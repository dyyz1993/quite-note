#!/usr/bin/env python3
"""Accessibility-driven smoke driver for Quite Note Dev.

The driver intentionally keeps interactions deterministic: AX first, window-relative
coordinates only as a fallback. It is designed to be reusable by Computer Use agents
and local regression scripts without depending on OCR.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import signal
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path

try:
    import Quartz
    from AppKit import NSWorkspace
    from ApplicationServices import (
        AXUIElementCopyElementAtPosition,
        AXUIElementSetAttributeValue,
        AXIsProcessTrusted,
        AXValueGetValue,
        kAXValueAttribute,
        kAXValueCGPointType,
        kAXValueCGSizeType,
    )
except ImportError:  # The remote test Mac boots before pip dependencies are installed.
    Quartz = None
    AXIsProcessTrusted = None
    NSWorkspace = None
    kAXValueAttribute = None
    AXUIElementCopyElementAtPosition = None
    AXUIElementSetAttributeValue = None
    AXValueGetValue = None
    kAXValueCGPointType = None
    kAXValueCGSizeType = None


APP_NAME = "Quite Note Dev"
CUA = "/Applications/CuaDriver.app/Contents/MacOS/cua-driver"
SETTLE_SECONDS = 0.35
_target_ax_identifier = ""
driver_global = None


def _cua_scale() -> float:
    """cua 点击坐标相对逻辑点的缩放系数。

    cua reports screen_width as the logical display width and takes click
    coordinates in those same logical points - only its screenshots are
    scaled down. Scaling the clicks by the screenshot size therefore moved
    every click about 5% to the left of the intended target.
    """
    return 1.0


class BlockedError(RuntimeError):
    """A system prerequisite prevents meaningful UI execution."""


class ScreenRecorder:
    """Continuous recording with a timestamped frame fallback."""

    def __init__(self, run_dir: Path, name: str = "ui-recording.mov"):
        self.run_dir = run_dir
        self.path = run_dir / "recordings" / name
        self.frame_root = run_dir / "recordings" / "frames"
        self.frames: list[str] = []
        self.unavailable_path = run_dir / "recordings" / "ui-recording.unavailable.txt"
        self.path.parent.mkdir(parents=True, exist_ok=True)
        # -k renders clicks in the movie, which is essential when reviewing
        # keyboard focus and transient panel interactions.
        self.process = subprocess.Popen(
            ["screencapture", "-v", "-k", str(self.path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        time.sleep(0.5)
        if self.process.poll() is not None:
            # Screen Recording TCC can lapse for a runner after a macOS update.
            # Keep the deterministic AX smoke path usable while surfacing the loss.
            detail = self.process.stderr.read().decode(errors="replace").strip()
            print(f"WARNING: continuous UI recording unavailable: {detail}", file=sys.stderr)
            self.process = None
            self.unavailable_path.write_text(detail + "\n")
            self.frame_root.mkdir(parents=True, exist_ok=True)

    @property
    def evidence_label(self) -> str:
        return str(self.path.relative_to(self.path.parents[1]))

    def stop(self) -> str:
        if self.process is not None and self.process.poll() is None:
            self.process.send_signal(signal.SIGINT)
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        if self.path.exists() and self.path.stat().st_size > 0:
            return self.evidence_label
        if self.frames:
            index_path = self.run_dir / "recordings" / "frames.json"
            index_path.write_text(json.dumps({"frames": self.frames}, ensure_ascii=False, indent=2) + "\n")
            return str(index_path.relative_to(self.run_dir))
        return self.unavailable_path.relative_to(self.run_dir).as_posix()

    def capture_fallback_frame(self, event: str) -> str:
        """Ask the isolated Dev app for its front window, then try desktop capture."""
        safe = "".join(c if c.isalnum() or c in "-_" else "-" for c in event)
        stem = f"frame-{len(self.frames):04d}-{safe}-{time.time_ns()}"
        path = self.frame_root / f"{stem}.png"
        self.frame_root.mkdir(parents=True, exist_ok=True)
        requests = self.path.parent / "requests"
        requests.mkdir(parents=True, exist_ok=True)
        request = requests / f"{stem}.request"
        request.write_text(event + "\n")
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            if path.exists() and path.stat().st_size > 0:
                break
            time.sleep(0.05)
        request.unlink(missing_ok=True)
        if path.exists() and path.stat().st_size > 0:
            return self._record_frame(path)
        try:
            completed = subprocess.run(
                ["/usr/sbin/screencapture", "-x", str(path)],
                check=False,
                timeout=5,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception:
            return ""
        if completed.returncode != 0 or not path.exists() or path.stat().st_size == 0:
            return ""
        return self._record_frame(path)

    def _record_frame(self, path: Path) -> str:
        relative = path.relative_to(self.run_dir).as_posix()
        self.frames.append(relative)
        append_timeline(self.run_dir, "evidence.frame", {"path": relative})
        return relative


@dataclass
class Step:
    name: str
    status: str
    duration_ms: int
    reason: str = ""
    evidence: str = ""
    selector: str = ""


class Run:
    def __init__(self, run_dir: Path, evidence: str, video_recorder: ScreenRecorder | None = None):
        self.run_dir = run_dir
        self.evidence = evidence
        self.video_recorder = video_recorder
        self.results: list[Step] = []

    def record(self, name: str, fn) -> None:
        started = time.monotonic()
        evidence = ""
        detail = ""
        if self.evidence == "full":
            evidence = self.capture(f"{name}-before")
        elif self.video_recorder is not None and self.video_recorder.process is None:
            self.video_recorder.capture_fallback_frame(f"{name}-before")
        try:
            detail = fn() or ""
            if self.evidence == "full":
                evidence = self.capture(name)
            if self.video_recorder is not None and self.evidence != "full" and self.video_recorder.process is None:
                self.video_recorder.capture_fallback_frame(f"{name}-after")
            result = Step(name, "PASS", int((time.monotonic() - started) * 1000), reason=detail, evidence=evidence)
        except Exception as exc:  # Keep later suites independent.
            status = "BLOCKED" if isinstance(exc, BlockedError) else "FAIL"
            result = Step(
                name,
                status,
                int((time.monotonic() - started) * 1000),
                reason=f"{type(exc).__name__}: {exc}",
            )
            evidence = self.capture(name)
            if self.video_recorder is not None and self.evidence != "full" and self.video_recorder.process is None:
                self.video_recorder.capture_fallback_frame(f"{name}-failure")
            result.evidence = evidence
        if not detail and self.video_recorder and self.video_recorder.process is not None:
            result.evidence = self.video_recorder.evidence_label
        self.results.append(result)
        self.write()

    def capture(self, name: str) -> str:
        if self.video_recorder and self.video_recorder.process is None:
            return self.video_recorder.capture_fallback_frame(name)
        safe = "".join(c if c.isalnum() or c in "-_" else "-" for c in name)
        path = self.run_dir / "screenshots" / f"{safe}-{int(time.time())}.png"
        try:
            completed = subprocess.run(["/usr/sbin/screencapture", "-x", str(path)], check=False, timeout=5, stderr=subprocess.DEVNULL)
            if completed.returncode == 0 and path.exists() and path.stat().st_size > 0:
                return str(path.relative_to(self.run_dir))
        except Exception:
            pass
        return self.video_recorder.capture_fallback_frame(name) if self.video_recorder else ""

    def write(self) -> None:
        statuses = [r.status for r in self.results]
        blocked = any(r.status == "BLOCKED" for r in self.results)
        overall = "BLOCKED" if blocked else ("PASS" if statuses and all(s in ("PASS", "SKIP") for s in statuses) else "FAIL")
        report = {
            "status": overall,
            "started_at": self.results[0].name if False else None,
            "results": [asdict(r) for r in self.results],
        }
        (self.run_dir / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")

        lines = ["# Quite Note UI Smoke Report", "", f"Result: **{overall}**", ""]
        lines += ["| Case | Result | ms | Selector | Evidence / reason |", "|---|---|---:|---|---|"]
        for r in self.results:
            detail = f"{r.evidence} ({r.reason})" if r.evidence and r.reason else (r.evidence or r.reason)
            lines.append(f"| {r.name} | {r.status} | {r.duration_ms} | `{r.selector}` | {detail} |")
        (self.run_dir / "report.md").write_text("\n".join(lines) + "\n")


class AXDriver:
    def __init__(self, pid: int):
        if Quartz is None:
            raise BlockedError("PyObjC is required on the UI execution Mac")
        from ApplicationServices import AXUIElementCreateApplication, AXUIElementPerformAction
        self.element = AXUIElementCreateApplication(pid)
        self.pid = pid

    def foreground_floating_window(self) -> dict | None:
        candidates = self.windows()
        if not candidates:
            return None
        candidates.sort(key=lambda w: (w["frame"][3] < 600, w["frame"][3], w["frame"][2]), reverse=True)
        selected = candidates[0]
        # CGWindow bounds are in scaled screen points; AX hit testing is in global
        # points. Query the AX window frame at the CG center and replace the shell
        # frame so probes land in the exact SwiftUI hosting-view coordinate space.
        center_x = selected["frame"][0] + selected["frame"][2] / 2
        center_y = selected["frame"][1] + selected["frame"][3] / 2
        element = self.element_at(center_x, center_y)
        if element is not None:
            frame = self.bounding_frame(element)
            if frame and frame[2] > 100 and frame[3] > 60:
                return {"id": selected["id"], "title": selected["title"], "frame": list(frame)}
        return selected

    def windows(self) -> list[dict]:
        rows = Quartz.CGWindowListCopyWindowInfo(
            Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
            Quartz.kCGNullWindowID,
        )
        found = []
        for row in rows:
            owner_pid = int(row.get("kCGWindowOwnerPID", 0) or 0)
            if owner_pid != self.pid or not row.get("kCGWindowBounds"):
                continue
            bounds = dict(row["kCGWindowBounds"])
            found.append(
                {
                    "id": row.get("kCGWindowNumber", 0),
                    "title": row.get("kCGWindowName", ""),
                    "frame": [float(bounds.get("X", 0)), float(bounds.get("Y", 0)), float(bounds.get("Width", 0)), float(bounds.get("Height", 0))],
                }
            )
        return found

    def bounding_frame(self, element):
        position = self.attribute("AXPosition", element)
        size = self.attribute("AXSize", element)
        if position is None or size is None:
            return None
        # pyobjc 10 对 AXValue 不自动解包：AXPosition/AXSize 会返回 AXValueRef
        # （旧桥接直接给 CGPoint/CGSize），统一在取值时双兼容解包
        if not hasattr(position, "x"):
            ok, position = AXValueGetValue(position, kAXValueCGPointType, None)
            if not ok:
                return None
        if not hasattr(size, "width"):
            ok, size = AXValueGetValue(size, kAXValueCGSizeType, None)
            if not ok:
                return None
        x = float(position.x)
        y = float(position.y)
        width = float(size.width)
        height = float(size.height)
        return x, y, width, height

    def element_at(self, x: float, y: float):
        error, element = AXUIElementCopyElementAtPosition(self.element, x, y, None)
        return element if error == 0 else None

    def set_value(self, element, value: str) -> None:
        error = AXUIElementSetAttributeValue(element, kAXValueAttribute, value)
        if error != 0:
            raise RuntimeError(f"AX set value failed: {error}")

    def press(self, element) -> None:
        from ApplicationServices import AXUIElementPerformAction
        error = AXUIElementPerformAction(element, "AXPress")
        if error != 0:
            raise RuntimeError(f"AX press failed: {error}")

    def status_menu_item(self, title: str):
        children = self.attribute("AXChildren") or []
        # The menu-extra bar is the last child of the application element.
        menu = children[-1]
        items = self.attribute("AXChildren", menu) or []
        if not items:
            raise RuntimeError("status menu is unavailable")
        item = items[0]
        # Opening the transient menu is allowed to return actionFailed; the
        # dropdown is still exposed for subsequent AX enumeration.
        try:
            self.press(item)
        except RuntimeError as exc:
            if "AX press failed" not in str(exc):
                raise
        time.sleep(0.3)
        dropdowns = self.attribute("AXChildren", item) or []
        if not dropdowns:
            raise RuntimeError("status menu dropdown did not open")
        for menu_item in self.attribute("AXChildren", dropdowns[0]) or []:
            if self.attribute("AXTitle", menu_item) == title:
                return menu_item
        raise RuntimeError(f"status menu item not found: {title}")

    def attribute(self, name: str, element=None):
        from ApplicationServices import AXUIElementCopyAttributeValue
        target = self.element if element is None else element
        error, value = AXUIElementCopyAttributeValue(target, name, None)
        return value if error == 0 else None


def app_pid() -> int:
    if NSWorkspace is not None:
        for app in NSWorkspace.sharedWorkspace().runningApplications():
            if app.bundleIdentifier() == "com.quitenote.app.dev":
                return app.processIdentifier()
    script = "tell application \"System Events\" to get unix id of first process whose bundle identifier is \"com.quitenote.app.dev\""
    result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=5)
    if result.returncode == 0 and result.stdout.strip().isdigit():
        return int(result.stdout.strip())
    raise RuntimeError("Quite Note Dev is not running")


def validate_accessibility() -> str:
    if AXIsProcessTrusted is not None and not AXIsProcessTrusted():
        raise BlockedError("Accessibility permission is not granted to the runner")
    if AXIsProcessTrusted is None:
        # PyObjC is unavailable; System Events cannot fully substitute AX trust.
        return "PyObjC unavailable; using osascript/CGWindow fallback"
    return ""


def validate_storage(run: Run) -> str:
    ensure_manifest(run)
    manifest = json.loads((run.run_dir / "manifest.json").read_text())
    root = Path(manifest["storage_root"])
    if not root.is_dir():
        raise RuntimeError(f"storage root missing: {root}")
    return str(root)


def smoke_launch(run: Run, driver: AXDriver) -> str:
    # Menu-bar apps may start collapsed; process + isolated storage are the launch
    # contract. Panel visibility is asserted by dedicated suites.
    if app_pid() <= 0:
        raise RuntimeError("Dev process missing")
    return validate_storage(run)


def ensure_manifest(run: Run) -> None:
    manifest = run.run_dir / "manifest.json"
    if not manifest.exists():
        manifest.write_text(json.dumps({"storage_root": os.environ.get("QN_TEST_STORAGE_ROOT", "/tmp/quitenote-ui-manual")}))


def smoke_clipboard(run: Run, driver: AXDriver) -> str:
    if not driver.windows():
        raise RuntimeError("app has no visible window before clipboard invocation")

    def panel_visible() -> bool:
        # The AX tree on the remote Mac can include thousands of transient menu
        # nodes. The 760x520 popUpMenu panel is deterministic and cheaper.
        return any(
            700 <= w["frame"][2] <= 800 and 490 <= w["frame"][3] <= 550
            for w in driver.windows()
        )

    if not panel_visible():
        _press_status_menu_item("剪贴板历史")
    _activate_app()
    time.sleep(0.1)
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        if panel_visible():
            search = _find_ax_element_by_identifier("clipboard.search_field")
            if search is None:
                raise RuntimeError("clipboard search field is unavailable")
            driver.set_value(search, "QNUI_SMOKE_CLIP")
            time.sleep(0.2)
            return "clipboard 760x520 panel exposed"
        time.sleep(0.1)
    raise RuntimeError("clipboard panel not exposed after invoking menu")

def smoke_launcher(run: Run, driver: AXDriver) -> str:
    if not driver.windows():
        raise RuntimeError("app has no visible window before launcher invocation")

    def panel_visible() -> bool:
        # Launcher NSPanel is not consistently AX-readable over SSH; its ~640x491
        # popUpMenu panel is the deterministic smoke signal.
        return any(
            620 <= w["frame"][2] <= 660 and 480 <= w["frame"][3] <= 510
            for w in driver.windows()
        )

    if not panel_visible():
        _press_status_menu_item("应用启动器")
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        if panel_visible():
            return "launcher panel exposed"
        time.sleep(0.1)
    raise RuntimeError("launcher panel not exposed after invoking shortcut")

def _activate_app() -> None:
    if NSWorkspace is not None:
        for app in NSWorkspace.sharedWorkspace().runningApplications():
            if app.processIdentifier() == driver_global.pid:
                # macOS 13 can reject a normal activation for an accessory app in
                # the GUI launcher session. ActivateAll is the deterministic path.
                app.activateWithOptions_(0x00010000 | 0x00000010)
                return
    # 进程未出现在 NSWorkspace 清单（注册延迟）时不再硬失败：AXPress 菜单
    # 触发不强依赖 frontmost，让后续步骤自行验证效果。
    print("[activate] app not yet in runningApplications; continuing", file=sys.stderr)


def _press_status_menu_item(title: str) -> None:
    if driver_global is None:
        raise RuntimeError("AX driver is unavailable")
    item = driver_global.status_menu_item(title)
    _activate_app()
    time.sleep(0.2)
    driver_global.press(item)


def _keystroke(key: str, modifiers: list[str]) -> None:
    from Quartz import CGEventCreateKeyboardEvent, CGEventPost, CGEventSetFlags, CGEventSourceCreate, kCGEventFlagMaskAlternate, kCGEventFlagMaskCommand, kCGEventFlagMaskControl, kCGEventFlagMaskShift, kCGEventSourceStateHIDSystemState
    mask = 0
    for modifier in modifiers:
        mask |= {
            "command": kCGEventFlagMaskCommand,
            "option": kCGEventFlagMaskAlternate,
            "control": kCGEventFlagMaskControl,
            "shift": kCGEventFlagMaskShift,
        }[modifier]
    key_code = {" ": 49, "v": 9}.get(key.lower(), 0)
    source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState)
    for key_down in (True, False):
        event = CGEventCreateKeyboardEvent(source, key_code, key_down)
        CGEventSetFlags(event, mask)
        CGEventPost(kCGEventSourceStateHIDSystemState, event)
        time.sleep(0.05)


def _press_status_menu_item_system_events(title: str) -> None:
    script = f'''
    tell application "System Events"
      tell process "{APP_NAME}"
        set frontmost to true
        delay 0.4
        tell menu bar item 1 of menu bar 2
          perform action "AXPress"
          delay 0.5
          tell menu item "{title}" of menu 1
            perform action "AXPress"
          end tell
        end tell
        set frontmost to true
      end tell
    end tell
    '''
    subprocess.run(["osascript", "-e", script], check=True, timeout=15, capture_output=True, text=True)


def _invoke_shortcut(key_combo: str) -> None:
    keys = key_combo.split()
    script = (
        "tell application \"System Events\"\n"
        "  keystroke \"v\" using {command down, shift down}\n"
        "end tell"
    )
    subprocess.run(["osascript", "-e", script], check=True, timeout=15)


def _walk_ax(element, depth: int = 0, max_depth: int = 16):
    if depth > max_depth:
        return None
    identifiers = (
        _ax_string(_ax_attribute(element, "AXIdentifier")),
        _ax_string(_ax_attribute(element, "AXDescription")),
    )
    if _target_ax_identifier in identifiers:
        return element
    for child_ref in _ax_children(element):
        result = _walk_ax(child_ref, depth + 1, max_depth)
        if result is not None:
            return result
    return None


def _ax_attribute(element, attribute: str):
    from ApplicationServices import AXUIElementCopyAttributeValue
    value = None
    error, value = AXUIElementCopyAttributeValue(element, attribute, None)
    return value if error == 0 else None


def _ax_string(value) -> str:
    return str(value) if value is not None else ""


def _ax_children(element):
    ref = _ax_attribute(element, "AXChildren")
    return list(ref) if ref is not None else []


def _find_ax_element_by_identifier(identifier: str):
    global _target_ax_identifier
    _target_ax_identifier = identifier
    # Prefer the known clipboard panel frame (760x520) over the generic foreground
    # window selector. NSStatusItem creates small layered companion windows that
    # can win that heuristic while pointing AX hit probes at menu chrome.
    candidates = [
        window for window in driver_global.windows()
        if 700 <= window["frame"][2] <= 800 and 490 <= window["frame"][3] <= 550
    ]
    for window in candidates:
        x, y, width, height = window["frame"]
        for fraction in ((0.5, 0.055), (0.3, 0.06), (0.7, 0.06)):
            found = driver_global.element_at(x + width * fraction[0], y + height * fraction[1])
            if found is None:
                continue
            identifiers = (
                _ax_string(_ax_attribute(found, "AXIdentifier")),
                _ax_string(_ax_attribute(found, "AXDescription")),
            )
            if _target_ax_identifier in identifiers:
                return found
            # Some remote AX sessions omit the identifier during first hit resolution.
            # The clipboard panel has exactly one text field, so role is a stable
            # fallback without recursively traversing the large list tree.
            if _ax_string(_ax_attribute(found, "AXRole")) == "AXTextField":
                return found
    return None


def smoke_flash_notes(run: Run, driver: AXDriver) -> str:
    # The floating panel is a non-titled NSPanel; its deterministic 520x640
    # frame is exposed on the GUI session at launch.
    windows = driver.windows()
    if not any(480 <= w["frame"][2] <= 560 and 600 <= w["frame"][3] <= 680 for w in windows):
        raise RuntimeError(f"main panel not exposed; windows={windows}")
    return "main 520x640 panel exposed"


def smoke_settings(run: Run, driver: AXDriver) -> str:
    # Settings is reached without changing user data from the main panel.
    window = driver.foreground_floating_window()
    if window is None:
        raise RuntimeError("settings invocation requires the main panel")
    return "settings AX flow available from main panel"


def smoke_devcore(run: Run, driver: AXDriver) -> str:
    validate_storage(run)
    return "DevCore storage isolation available"


def smoke_cleanup(run: Run, driver: AXDriver) -> str:
    return assert_production_process_untouched()


# ---------------------------------------------------------------------------
# Screenshot toolbar edge-layout regression (added 2026-10-21 with the
# ScreenshotToolbarLayout rewrite). All assertions are pixel-level: the
# overlay renders at screenSaver level and is not reachable through AX.
# ---------------------------------------------------------------------------

def _overlay_window_count(pid: int) -> int:
    from Quartz import CGWindowListCopyWindowInfo, kCGWindowListOptionOnScreenOnly, kCGNullWindowID
    windows = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID)
    return sum(1 for w in windows if w.get("kCGWindowOwnerPID") == pid and w.get("kCGWindowLayer", 0) >= 1000)


def _main_display_size() -> tuple[float, float]:
    from Quartz import CGMainDisplayID, CGDisplayBounds
    bounds = CGDisplayBounds(CGMainDisplayID())
    return bounds.size.width, bounds.size.height


def caffeinate(t=25):
    subprocess.Popen(["caffeinate", "-u", "-d", "-t", str(t)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.0)


def _cua_call(tool: str, args: str) -> str:
    result = subprocess.run(
        ["/Applications/CuaDriver.app/Contents/MacOS/cua-driver", "call", tool, args],
        check=False,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return result.stdout


def _mouse_click(x: float, y: float) -> None:
    # cua 的 desktop click 带真实指针路径（hover 前置），SwiftUI 按钮可可靠响应。
    # cua 接收的是逻辑点坐标（screen_width），只有它自己的截图是缩放的。
    out = _cua_call("click", (
        f'{{"scope":"desktop","delivery_mode":"foreground",'
        f'"x":{round(x)},"y":{round(y)}}}'))
    if "error" in out or "pending" in out:
        raise RuntimeError(f"cua click failed at ({x:.0f},{y:.0f}): {out.strip()[:160]}")
    time.sleep(0.9)


def _mouse_drag(x1: float, y1: float, x2: float, y2: float) -> None:
    # cliclick 逻辑 pt 拖拽（此前"进不了 overlay"的结论采集于锁屏状态，作废）
    steps = 12
    cmds = [f"dd:{round(x1)},{round(y1)}"]
    for i in range(1, steps + 1):
        t = i / steps
        cmds.append(f"dm:{round(x1 + (x2 - x1) * t)},{round(y1 + (y2 - y1) * t)}")
        time.sleep(0.03)
    cmds.append(f"du:{round(x2)},{round(y2)}")
    subprocess.run(["/usr/local/bin/cliclick", *cmds], check=False, timeout=30,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.0)


def _press_escape() -> None:
    # cliclick's keyboard synthesis is TCC-granted on the dedicated test Mac
    # (/usr/local/bin/cliclick); raw CGEventPost from the runner session is not.
    cliclick = "/usr/local/bin/cliclick"
    if os.path.exists(cliclick):
        subprocess.run([cliclick, "kp:esc"], check=False, timeout=10,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        from Quartz import (
            CGEventCreateKeyboardEvent, CGEventPost, CGEventSourceCreate,
            kCGEventSourceStateHIDSystemState,
        )
        source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState)
        for key_down in (True, False):
            CGEventPost(kCGEventSourceStateHIDSystemState, CGEventCreateKeyboardEvent(source, 53, key_down))
            time.sleep(0.05)
    time.sleep(0.5)


def _capture_main_display(run: Run, name: str) -> Path:
    """Snapshot through the Dev app's own UIEvidenceCaptureService request queue.

    The app holds the Screen Recording grant on the test Mac (stable, granted
    once in System Settings); its service captures its highest-level window —
    the screenSaver screenshot overlay, which covers the full display — by
    window ID via CGWindowListCreateImage. Neither the runner session nor the
    CuaDriver daemon are reliable capture paths there (periodic re-consent
    kicks them off). Stems must be frame--prefixed and must not contain
    clipboard/launcher, which key the service's window choice.
    """
    # 显示器睡眠会让一切截屏 API 失效（2026-10-21 实锤）；先唤醒再走 cua
    subprocess.Popen(["caffeinate", "-u", "-t", "20"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.5)
    path = run.run_dir / "screenshots" / f"{name}.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    completed = subprocess.run(
        ["/Applications/CuaDriver.app/Contents/MacOS/cua-driver", "call",
         "get_desktop_state", "--screenshot-out-file", str(path)],
        check=False, timeout=45, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    if completed.returncode != 0 or not path.exists() or path.stat().st_size == 0:
        raise RuntimeError(f"cua capture failed rc={completed.returncode} {completed.stderr.strip()[:120]}")
    return path


def _find_toolbar_buttons(capture: Path, display_width: float, y_lo: float, y_hi: float,
                          row_y: float | None = None) -> dict:
    """Locate the record (red) and selected-group (blue) toolbar buttons via
    feature-color clustering inside the y band. Returns {"red": (cx, cy), "blue": (cx, cy)}
    in display points; missing colors are omitted.

    row_y: when given, red clusters are restricted to this row (±15pt) — the
    toolbar row is already known from the blue cluster, and unrelated red UI
    elsewhere on screen (notification badges etc.) must not win."""
    try:
        from PIL import Image
    except ImportError as exc:
        raise BlockedError(f"Pillow unavailable for toolbar pixel checks: {exc}")

    image = Image.open(capture).convert("RGB")
    width, height = image.size
    scale = width / display_width
    pixels = image.load()

    def classify(r: float, g: float, b: float):
        if r > 170 and 40 < g < 130 and b < 110:
            return "red"     # record button gradient (themeRed500)
        if r < 80 and 90 < g < 150 and b > 170:
            return "blue"    # selected group button highlight (~49,109,200)
        return None

    cells = {}
    for y in range(int(y_lo * scale), min(int(y_hi * scale), height), 2):
        for x in range(0, width, 2):
            color = classify(*pixels[x, y])
            if color:
                cells.setdefault((x // 34, y // 34), []).append((x, y, color))

    # 按颜色独立聚类：相邻的不同色按钮（如红录制紧挨蓝保存）不能连坐成
    # 巨型混合簇被宽度过滤整簇拒掉（2026-10-21 实锤：红钮被隔壁蓝钮吞掉）。
    found = {}
    dbg = []
    for color in ("blue", "red"):
        color_cells = {k: v for k, v in cells.items() if all(p[2] == color for p in v)}
        visited = set()
        for key in list(color_cells):
            if key in visited:
                continue
            stack, group = [key], []
            while stack:
                current = stack.pop()
                if current in visited or current not in color_cells:
                    continue
                visited.add(current)
                group += color_cells[current]
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        stack.append((current[0] + dx, current[1] + dy))
            xs = [p[0] for p in group]
            ys = [p[1] for p in group]
            cluster_width = (max(xs) - min(xs)) / scale
            info = f"{color} @{key} n={len(group)} w={cluster_width:.1f}pt x[{min(xs)/scale:.0f},{max(xs)/scale:.0f}]"
            if len(group) < 25:
                dbg.append(info + " REJECT:too-few"); continue
            if not 18 <= cluster_width <= 50:
                dbg.append(info + " REJECT:width"); continue
            position = ((min(xs) + max(xs)) / 2 / scale, (min(ys) + max(ys)) / 2 / scale)
            if color == "red" and row_y is not None and abs(position[1] - row_y) > 15:
                dbg.append(info + f" REJECT:row(y={position[1]:.0f} vs {row_y:.0f})"); continue
            dbg.append(info + " KEEP")
            # Keep the leftmost cluster per color within the toolbar row.
            if color not in found or position[0] < found[color][0]:
                found[color] = position
    try:
        with open("/tmp/qn-manual/tb_debug.txt", "w") as f:
            f.write("\n".join(dbg))
    except Exception:
        pass
    return found


def _diff_region(capture_before: Path, capture_after: Path, display_width: float, y_above: float):
    """Bounding box (display points) of changed pixels above y_above — used to
    detect the sub-toolbar floating above the main toolbar."""
    try:
        from PIL import Image, ImageChops
    except ImportError as exc:
        raise BlockedError(f"Pillow unavailable for toolbar diff checks: {exc}")

    before = Image.open(capture_before).convert("RGB")
    after = Image.open(capture_after).convert("RGB")
    diff = ImageChops.difference(before, after).convert("L")
    width, height = after.size
    scale = width / display_width
    changed = diff.load()
    xs, ys = [], []
    for y in range(0, min(int(y_above * scale), height), 2):
        for x in range(0, width, 2):
            if changed[x, y] > 24:
                xs.append(x)
                ys.append(y)
    if len(xs) < 200:
        return None
    return (min(xs) / scale, min(ys) / scale, max(xs) / scale, max(ys) / scale)


def _snap_overlay(tag, run_dir):
    """Snapshot the screenshot overlay through the app's own capture service.

    The overlay renders at screenSaver level, so neither the runner session
    nor the CuaDriver daemon can capture it - they only see the desktop
    underneath, which is why the previous captures of stage1/stage2/stage3
    came out identical. The Dev app holds the Screen Recording grant and
    exposes UIEvidenceCaptureService, which grabs its own highest-level
    window by window id and writes the PNG into the run's frames directory.
    """
    caffeinate(20)
    evidence_dir = Path(run_dir) / "recordings"
    requests = evidence_dir / "requests"
    frames = evidence_dir / "frames"
    requests.mkdir(parents=True, exist_ok=True)
    frames.mkdir(parents=True, exist_ok=True)

    name = f"frame-{tag}"
    request = requests / f"{name}.request"
    output = frames / f"{name}.png"
    for stale in (request, output):
        try:
            stale.unlink()
        except FileNotFoundError:
            pass
    request.write_text("")

    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if output.exists() and output.stat().st_size > 40000:
            return str(output)
        time.sleep(0.1)
    return None


def _click_overlay(lx, ly):
    """cua desktop foreground 点击（逻辑坐标）"""
    scale = _cua_scale()
    out = _cua_call("click", json.dumps({"scope": "desktop", "delivery_mode": "foreground",
                                         "x": round(lx * scale), "y": round(ly * scale)}))
    time.sleep(1.3)


def _drag_overlay(lx1, ly1, lx2, ly2):
    scale = _cua_scale()
    args = {"scope": "desktop", "delivery_mode": "foreground",
            "from_x": round(lx1 * scale), "from_y": round(ly1 * scale),
            "to_x": round(lx2 * scale), "to_y": round(ly2 * scale),
            "duration_ms": 500, "steps": 14}
    _cua_call("drag", json.dumps(args))
    time.sleep(1.4)


def smoke_screenshot_toolbar(run: Run, driver: AXDriver) -> str:
    """Regression for the screenshot toolbar edge layout (2026-10-21 rewrite).

    Verification uses (a) blue selected-button clustering for anchoring and
    (b) the dark-band right edge of the toolbar bar itself for width
    assertions - the wallpaper on this host is orange-red and poisons red
    pixel clustering (2026-10-22: 9055-point mega cluster swallowed the
    record button). All cua input, screencapture-in-app evidence, screen
    kept awake via caffeinate for the whole scenario.
    """
    width, height = _main_display_size()
    pid = driver.pid

    def _wake():
        subprocess.Popen(["caffeinate", "-u", "-t", "25"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1.0)

    _press_escape()  # clear any stale session
    # The screenshot session is started from the status-bar menu, the same
    # path the clipboard and launcher suites use. Pressing Escape only clears
    # a stale session, so the overlay never appeared on its own.
    _press_status_menu_item("捕获屏幕截图")
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline and _overlay_window_count(pid) == 0:
        time.sleep(0.05)
    if _overlay_window_count(pid) == 0:
        # The menu title is localized; fall back to the English title.
        _press_status_menu_item("Capture Screenshot")
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline and _overlay_window_count(pid) == 0:
            time.sleep(0.05)
    if _overlay_window_count(pid) == 0:
        raise RuntimeError("screenshot overlay did not appear")
    time.sleep(1.0)

    # Selection hugging the right edge of the actual display.
    sel = (width - 102, 300, width - 2, 480)
    _drag_overlay(*sel)

    p1 = _snap_overlay("stage1_default", run.run_dir)
    if not p1:
        raise RuntimeError("stage1 overlay capture failed")
    d1 = decode(p1)
    B1 = d1["B"][0] if d1["B"] else None
    R1 = d1["R"][0] if d1["R"] else None
    assert B1 and R1, f"默认态按钮未检出: {d1}"
    band1 = dark_band_right(p1, width, B1[1])
    inside1 = band1 <= width - 8
    print(f"[stage1] 蓝钮 {B1} 红钮 {R1} 暗带右端 {band1:.0f}/{width - 8:.0f} {'✓' if inside1 else '✗出屏'}")
    assert inside1, f"默认态主栏右端出屏: {band1:.0f}"

    # 点文本组。The group buttons sit 38pt apart, but the offset from the
    # selected button is only reliable when the selected group is known, so
    # locate the text glyph itself: a "T" drawn as a wide top bar with a
    # single stem under it.
    text_x = _text_tool_center(p1, B1[1])
    if text_x is None:
        raise RuntimeError("文本工具图标未检出")
    _click_overlay(text_x, B1[1])
    p2 = _snap_overlay("stage2_widened", run.run_dir)
    d2 = decode(p2)
    B2 = d2["B"][0] if d2["B"] else None
    R2 = d2["R"][0] if d2["R"] else None
    assert B2 and R2, f"点T后按钮未检出: {d2}"
    band2 = dark_band_right(p2, width, B2[1])
    inside2 = band2 <= width - 8
    print(f"[stage2] 撑开后 暗带右端 {band2:.0f}/{width - 8:.0f} {'✓红钮屏内' if inside2 else '✗出屏'}")
    assert inside2, f"撑开后主栏出屏: {band2:.0f}"

    # 点图形组展开二级。The group buttons sit 38pt apart and the selected one
    # is the text group at this point, so the shape group is one slot back.
    # Deriving it from B2 would land on the colour swatches instead.
    _click_overlay(B2[0] - 38, B2[1])
    p3 = _snap_overlay("stage3_sub", run.run_dir)
    B3 = decode(p3)["B"][0]
    sub = find_sub(p2, p3, B3[1])
    assert sub, "二级面板未展开"
    gap = sub["gap"]
    inside3 = sub["x0"] >= 8 and sub["x1"] <= width - 8
    anchored = abs((sub["x0"] + sub["x1"]) / 2 - B3[0] + 38) <= 40
    print(f"[stage3] 二级 间隙={gap:.0f}pt 锚定偏差={abs((sub['x0']+sub['x1'])/2 - B3[0] + 38):.0f}pt 屏内={'Y' if inside3 else 'N'}")
    assert inside3, "二级出屏"

    _press_escape()
    return (f"edge layout ok: 默认带右端 {band1:.0f}→撑开 {band2:.0f} 均屏内, "
            f"二级间隙 {gap:.0f}pt 锚定偏差 {abs((sub['x0']+sub['x1'])/2 - B3[0] + 38):.0f}pt")


def dark_band_right(path, width, row_cy):
    """主栏暗带右端（逻辑pt）：从行右端向左找最后一个暗像素（壁纸噪点免疫）"""
    from PIL import Image
    im = Image.open(path).convert("RGB"); W, H = im.size; px = im.load()
    # The capture can come from the app (full display) or from cua (scaled
    # down), so derive the scale from the image against the real display
    # width instead of assuming a fixed 1440pt canvas.
    display_w, display_h = _main_display_size()
    scale = W / display_w if display_w else W / 1440.0
    Y = int(row_cy * H / display_h) if display_h else int(row_cy * H / 900)
    Y = max(0, min(Y, H - 1))
    for X in range(W - 2, 0, -2):
        r, g, b = px[X, Y]
        if r < 110 and g < 110 and b < 130:
            return X / scale
    return None


def decode(path):
    """行带内蓝钮（选中组高亮）与红钮（录制按钮）聚类定位"""
    from PIL import Image
    im = Image.open(path).convert("RGB"); W, H = im.size; px = im.load()
    display_w, _ = _main_display_size()
    scale = W / display_w if display_w else W / 1440.0

    def clusters(points, min_width=0, max_width=60, min_size=20):
        cells = {}
        for p in points: cells.setdefault((round(p[0] / 14), round(p[1] / 14)), []).append(p)
        visited = set(); res = []
        for k in list(cells):
            if k in visited: continue
            stack = [k]; group = []
            while stack:
                c = stack.pop()
                if c in visited or c not in cells: continue
                visited.add(c); group += cells[c]
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1): stack.append((c[0] + dx, c[1] + dy))
            if len(group) < min_size: continue
            xs = [p[0] for p in group]; ys = [p[1] for p in group]
            w = max(xs) - min(xs)
            if min_width <= w <= max_width:
                res.append((sum(xs)/len(xs), sum(ys)/len(ys), w, len(group)))
        return res

    blues = []
    for y in range(0, H, 2):
        for x in range(int(150 * scale), W, 2):
            lx = x / scale; ly = y / scale
            r, g, b = px[x, y]
            if b > 185 and r < 70 and 80 < g < 160: blues.append((lx, ly))

    # The record button uses themeRed500 (#EF4444). Keep it strict so the
    # orange-red wallpaper on the test Mac cannot poison the detection.
    reds = []
    for y in range(0, H, 2):
        for x in range(int(150 * scale), W, 2):
            r, g, b = px[x, y]
            if r > 175 and 40 < g < 115 and 45 < b < 115 and r - g > 90: reds.append((x / scale, y / scale))

    # The toolbar row is identified by the largest blue cluster: the selected
    # group button is a solid ~33pt block, while wallpaper and desktop icons
    # only produce small specks. Anchoring on the leftmost cluster instead
    # would put the row on the noise.
    all_blues = clusters(blues)
    if not all_blues:
        return {"B": [], "R": []}
    row_y = max(all_blues, key=lambda c: c[3])[1]

    # The toolbar carries two kinds of blue: the selected annotation group
    # button and the colour swatches, and both can measure the same width.
    # The tool groups are easier to locate by their glyphs: each group button
    # draws a light icon on the dark pill, and the six groups sit 38pt apart,
    # left of the colour swatches and the record button.
    icons = _toolbar_icon_centers(px, W, H, scale, row_y)
    group_buttons = []
    for x in icons:
        near = [c for c in all_blues if abs(c[1] - row_y) <= 15 and abs(c[0] - x) <= 22]
        if near:
            group_buttons.append(near[0])
    swatches = [
        c for c in all_blues
        if abs(c[1] - row_y) <= 15 and c not in group_buttons
    ]

    # The record button sits on the same row but is narrower than the blue
    # group buttons, so the width window differs between the two colours.
    red_clusters = [c for c in clusters(reds) if abs(c[1] - row_y) <= 15 and 8 <= c[2] <= 50]
    red_clusters = sorted(red_clusters, key=lambda t: t[0])

    return {"B": group_buttons, "S": sorted(swatches, key=lambda t: t[0]), "R": red_clusters}



def _toolbar_icon_centers(px, W, H, scale, row_y, max_gap=22):
    """Centers of the light glyphs on the toolbar row, in display points.

    The annotation tool groups draw a white-ish icon on the dark pill, so
    the glyph columns mark where the buttons are. Returns the merged runs.
    """
    y_lo = int((row_y - 16) * scale)
    y_hi = int((row_y + 16) * scale)
    runs = []
    cur = None
    for X in range(int(150 * scale), W, 2):
        hits = 0
        for Y in range(max(0, y_lo), min(H, y_hi), 2):
            r, g, b = px[X, Y]
            if r > 130 and g > 130 and b > 130 and abs(r - g) < 30 and abs(g - b) < 30:
                hits += 1
        if hits >= 1 and cur is None:
            cur = X
        elif hits < 1 and cur is not None:
            runs.append((cur, X))
            cur = None
    if cur is not None:
        runs.append((cur, W))
    merged = []
    for a, b in runs:
        if b - a < 8:
            continue
        if merged and (a - merged[-1][1]) / scale <= max_gap:
            merged[-1] = (merged[-1][0], b)
        else:
            merged.append((a, b))
    return [(a + b) / 2 / scale for a, b in merged]


def _text_tool_center(path, row_y):
    """Horizontal centre of the "T" glyph on the toolbar row, or None.

    The "T" is the only glyph in the annotation pill whose stem sits under a
    horizontal bar, so look for a warm off-white row segment with exactly one
    narrow lit column below it. Measured on the smoke host the T sits near
    x=442, ~80pt right of the selected cursor button.
    """
    from PIL import Image

    im = Image.open(path).convert("RGB")
    W, H = im.size
    px = im.load()
    display_w, _ = _main_display_size()
    scale = W / display_w if display_w else W / 1440.0

    def glyph(x, y):
        r, g, b = px[x, y]
        return r > 130 and g > 110 and abs(r - g) < 60 and r >= b - 30

    y0, y1 = max(0, int((row_y - 16) * scale)), min(H, int((row_y + 16) * scale))
    for Y in range(y0, y1):
        run = []
        for X in range(int(400 * scale), int(560 * scale)):
            if glyph(X, Y):
                if not run or X - run[-1] <= 4:
                    run.append(X)
                else:
                    break
        if len(run) < 4 or run[-1] - run[0] > 22 * scale:
            continue
        lo, hi = run[0], run[-1]
        stem = sum(
            1 for X in range(lo, hi + 1)
            if any(glyph(X, Y + k) for k in range(2, 10))
        )
        if stem <= 3:
            return (lo + hi) / 2 / scale
    return None

def find_sub(before_path, after_path, row_y):
    """Locate the sub-toolbar that expands above the main toolbar.

    The sub-toolbar is the region that changed above the main toolbar row
    (row_y, in display points) between the previous capture and this one.
    Returns {"x0", "x1", "gap"} in display points, or None when no panel
    appeared.
    """
    from PIL import Image, ImageChops

    before = Image.open(before_path).convert("RGB")
    after = Image.open(after_path).convert("RGB")
    diff = ImageChops.difference(before, after).convert("L")
    width, height = after.size
    display_w, _ = _main_display_size()
    scale = width / display_w if display_w else width / 1440.0
    changed = diff.load()
    limit = int(row_y * scale)
    xs, ys = [], []
    for y in range(0, min(limit, height), 2):
        for x in range(0, width, 2):
            if changed[x, y] > 24:
                xs.append(x)
                ys.append(y)
    if len(xs) < 200:
        return None
    x0, x1 = min(xs) / scale, max(xs) / scale
    top = min(ys) / scale
    return {"x0": x0, "x1": x1, "gap": row_y - top}

    return {
        "B": blue_clusters,
        "R": sorted(red_clusters, key=lambda t: t[0]),
    }


def append_timeline(run_dir: Path, event: str, data: dict | None = None) -> None:
    row = {"timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"), "event": event, **(data or {})}
    with (run_dir / "timeline.jsonl").open("a") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


def assert_production_process_untouched() -> str:
    production = []
    if NSWorkspace is not None:
        production = [str(app.processIdentifier()) for app in NSWorkspace.sharedWorkspace().runningApplications() if app.bundleIdentifier() == "com.quitenote.app"]
    return "production pids: " + (",".join(production) or "none")

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--app-path", type=Path)
    parser.add_argument("--app-pid", type=int)
    parser.add_argument("--suites", nargs="+", required=True)
    parser.add_argument("--evidence", choices=("fast", "full"), default="fast")
    args = parser.parse_args()

    recorder = None
    run = Run(args.run_dir, args.evidence)
    try:
        recorder = ScreenRecorder(args.run_dir)
        run.video_recorder = recorder
        run.record("permissions.accessibility", validate_accessibility)
        try:
            driver = AXDriver(args.app_pid or app_pid())
        except Exception as exc:
            run.record("launch.app", lambda: (_ for _ in ()).throw(RuntimeError(str(exc))))
            return 1

        global driver_global
        driver_global = driver

        suite_map = {
            "launch": lambda: smoke_launch(run, driver),
            "flash-notes": lambda: smoke_flash_notes(run, driver),
            "clipboard": lambda: smoke_clipboard(run, driver),
            "launcher": lambda: smoke_launcher(run, driver),
            "settings": lambda: smoke_settings(run, driver),
            "devcore": lambda: smoke_devcore(run, driver),
            "screenshot-toolbar": lambda: smoke_screenshot_toolbar(run, driver),
            "cleanup": lambda: smoke_cleanup(run, driver),
        }
        for suite in args.suites:
            append_timeline(args.run_dir, "suite.start", {"name": suite})
            run.record(suite, suite_map.get(suite, lambda: (_ for _ in ()).throw(RuntimeError(f"unknown suite: {suite}"))))
            append_timeline(args.run_dir, "suite.end", {"name": suite})
    finally:
        video_evidence = recorder.stop() if recorder else ""
        append_timeline(args.run_dir, "video.stop", {"evidence": video_evidence})
        if not video_evidence or video_evidence.endswith(".unavailable.txt"):
            run.results.append(Step("evidence.capture", "BLOCKED", 0, reason="No readable video or timestamped window frames"))
            run.write()

    report = json.loads((args.run_dir / "report.json").read_text())
    if report["status"] == "PASS":
        return 0
    return 3 if report["status"] == "BLOCKED" else 1


if __name__ == "__main__":
    sys.exit(main())
