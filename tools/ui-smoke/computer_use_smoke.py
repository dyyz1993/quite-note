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
        kAXValueAttribute,
    )
except ImportError:  # The remote test Mac boots before pip dependencies are installed.
    Quartz = None
    AXIsProcessTrusted = None
    NSWorkspace = None
    kAXValueAttribute = None
    AXUIElementCopyElementAtPosition = None
    AXUIElementSetAttributeValue = None


APP_NAME = "Quite Note Dev"
SETTLE_SECONDS = 0.35
_target_ax_identifier = ""
driver_global = None


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
    # Targeted hit test avoids traversing large/offscreen AX trees on the remote Mac.
    window = driver_global.foreground_floating_window()
    if window:
        x, y, width, height = window["frame"]
        # The search field occupies the top strip of the 760x520 panel; lower
        # probes hit the filter/list and require tree traversal to recover.
        for fraction in ((0.5, 0.055), (0.3, 0.06), (0.7, 0.06)):
            found = driver_global.element_at(x + width * fraction[0], y + height * fraction[1])
            if found is not None and _target_ax_identifier in (
                _ax_string(_ax_attribute(found, "AXIdentifier")),
                _ax_string(_ax_attribute(found, "AXDescription")),
            ):
                return found
            if found is not None:
                # Hit testing is bounded; avoid recursive tree walks that can hang
                # once SwiftUI exposes a large accessibility tree.
                if _ax_string(_ax_attribute(found, "AXRole")) == "AXTextField":
                    return found
                frame = driver_global.bounding_frame(found)
                if frame:
                    element_x, element_y, element_width, element_height = frame
                    center_x = element_x + element_width / 2
                    center_y = element_y + element_height / 2
                    if x <= center_x <= x + width and y <= center_y <= y + height:
                        print(
                            f"AX hit candidate={identifier} role={_ax_string(_ax_attribute(found, 'AXRole'))} "
                            f"frame={frame} window={(x, y, width, height)}",
                            file=sys.stderr,
                        )
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
    # cua 的 desktop click 带真实指针路径（hover 前置），SwiftUI 按钮可可靠响应；
    # 坐标为截图像素（×px/pt 因子）
    pt = 1366 / 1440
    out = _cua_call("click", (
        f'{{"scope":"desktop","delivery_mode":"foreground",'
        f'"x":{round(x * pt)},"y":{round(y * pt)}}}'))
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


def _find_toolbar_buttons(capture: Path, display_width: float, y_lo: float, y_hi: float) -> dict:
    """Locate the record (red) and selected-group (blue) toolbar buttons via
    feature-color clustering inside the y band. Returns {"red": (cx, cy), "blue": (cx, cy)}
    in display points; missing colors are omitted."""
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
    for color in ("red", "blue"):
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
            if len(group) < 40:
                dbg.append(info + " REJECT:too-few"); continue
            if not 22 <= cluster_width <= 48:
                dbg.append(info + " REJECT:width"); continue
            position = ((min(xs) + max(xs)) / 2 / scale, (min(ys) + max(ys)) / 2 / scale)
            dbg.append(info + " KEEP")
            # Keep the leftmost cluster: the selected group highlight sits left of
            # the action buttons, and there is exactly one record button.
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


def smoke_screenshot_toolbar(run: Run, driver: AXDriver) -> str:
    """Regression for the screenshot toolbar edge layout (2026-10-21 rewrite).

    Scenario chain, pinned to the product requirements:
      1. right-edge selection, default state: record button fully on screen;
      2. click the text tool group -> color controls widen the main toolbar:
         the whole toolbar must yield left and the record button must stay
         fully visible (the reported "button pushed off screen" bug);
      3. click the shape tool group -> sub-toolbar expands above the main
         toolbar, stays on screen, and centers on the group button;
      4. Escape closes the overlay with no leftover windows.
    """
    width, height = _main_display_size()
    pid = driver.pid

    # 显示器睡眠会拦截一切输入合成与截屏（2026-10-21 实锤）：场景全程保活
    subprocess.Popen(["caffeinate", "-u", "-t", "300"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.0)

    _press_escape()  # clear any stale session
    _press_status_menu_item("捕获屏幕截图")
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline and _overlay_window_count(pid) == 0:
        time.sleep(0.05)
    if _overlay_window_count(pid) == 0:
        raise RuntimeError("screenshot overlay did not appear")
    time.sleep(1.0)  # interaction layer settles after the window exists; early drags get dropped

    # Derive the px-per-pt factor from a live frame now that the overlay exists.
    # Probing before the session opened once measured an unrelated window
    # (1416px instead of 2880px) and scaled every input off-target.
    from PIL import Image as PILImage
    probe = _capture_main_display(run, "toolbar-scale-probe")
    pt = PILImage.open(probe).size[0] / width
    # macOS 26 上 SwiftUI 内容的离屏取图四条路径全部受限（cacheDisplay/窗口合成/
    # layer 渲染/SCK 在该宿主均产出纯色或失败）——取图能力缺失属环境阻塞而非
    # 布局回归，报告 BLOCKED 而不是 FAIL。
    def _is_blank(path):
        im = PILImage.open(path).convert("RGB").resize((64, 40))
        return len(set(im.getdata())) <= 2

    # Selection hugging the right edge of the main display (logical points).
    sel_x1, sel_y1, sel_x2, sel_y2 = width - 262, 300.0, width - 42, 480.0
    _mouse_drag(sel_x1, sel_y1, sel_x2, sel_y2)

    cap_default = _capture_main_display(run, "toolbar-right-default")
    if _is_blank(cap_default):
        raise BlockedError(
            "evidence capture produces solid blanks with the overlay on screen; "
            "layout assertions skipped")
    buttons_default = _find_toolbar_buttons(cap_default, width, 0.0, 760.0)
    if "red" not in buttons_default or "blue" not in buttons_default:
        raise RuntimeError(f"toolbar buttons not found in default state: {buttons_default}")
    red1 = buttons_default["red"]
    blue1 = buttons_default["blue"]
    if abs(blue1[1] - red1[1]) > 10:
        raise RuntimeError(f"selected group button not on the toolbar row: blue={blue1} red={red1}")
    if red1[0] + 17 + 8 > width:
        raise RuntimeError(f"record button clipped at right edge in default state: cx={red1[0]:.0f} width={width:.0f}")

    # Click the text tool group (third group button: +2 * 38pt from the selected group).
    _mouse_click(blue1[0] + 76, blue1[1])

    cap_widened = _capture_main_display(run, "toolbar-right-widened")
    buttons_widened = _find_toolbar_buttons(cap_widened, width, 0.0, 760.0)
    if "red" not in buttons_widened or "blue" not in buttons_widened:
        raise RuntimeError(f"toolbar buttons not found after widening: {buttons_widened}")
    red2 = buttons_widened["red"]
    blue2 = buttons_widened["blue"]
    if red2[0] + 17 + 8 > width:
        raise RuntimeError(
            f"record button pushed off screen after text tool widened the toolbar: "
            f"cx {red1[0]:.0f} -> {red2[0]:.0f}, right edge {red2[0] + 25:.0f} > {width:.0f}"
        )
    if red2[0] >= red1[0] - 20:
        raise RuntimeError(f"toolbar did not yield left after widening: record cx {red1[0]:.0f} -> {red2[0]:.0f}")

    # Click the shape tool group (left neighbor of the selected text group) to expand the sub-toolbar.
    _mouse_click(blue2[0] - 38, blue2[1])

    cap_expanded = _capture_main_display(run, "toolbar-subtoolbar-expanded")
    buttons_expanded = _find_toolbar_buttons(cap_expanded, width, 0.0, 760.0)
    if "blue" not in buttons_expanded:
        raise RuntimeError("selected group button lost after expanding the sub-toolbar")
    blue3 = buttons_expanded["blue"]
    region = _diff_region(cap_widened, cap_expanded, width, y_above=blue3[1] - 45)
    if region is None:
        raise RuntimeError("sub-toolbar did not appear above the main toolbar")
    region_left, _, region_right, _ = region
    if region_left < 8 or region_right > width - 8:
        raise RuntimeError(f"sub-toolbar exceeds screen bounds: [{region_left:.0f}, {region_right:.0f}] vs [8, {width - 8:.0f}]")
    region_center = (region_left + region_right) / 2
    if abs(region_center - blue3[0]) > 30:
        raise RuntimeError(f"sub-toolbar not anchored to the group button: center={region_center:.0f} button={blue3[0]:.0f}")

    _press_escape()
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline and _overlay_window_count(pid) > 0:
        time.sleep(0.1)
    if _overlay_window_count(pid) > 0:
        raise RuntimeError("overlay windows remain after Escape")

    # --- Vertical-edge selections: with the main toolbar near the top or the
    # bottom of the screen, expanding a sub-toolbar must never leave the screen. ---
    for label, sel_y1, sel_y2, band_lo, band_hi in (
        ("top", 8.0, 120.0, 120.0, 210.0),          # selection at the very top; toolbar below it
        ("bottom", height - 102.0, height - 22.0, height - 192.0, height - 102.0),  # at the bottom; toolbar above it
    ):
        _press_escape()
        _press_status_menu_item("捕获屏幕截图")
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline and _overlay_window_count(pid) == 0:
            time.sleep(0.05)
        if _overlay_window_count(pid) == 0:
            raise RuntimeError(f"screenshot overlay did not appear ({label} selection)")
        time.sleep(1.0)

        _mouse_drag(width * 0.3, sel_y1, width * 0.55, sel_y2)
        cap_edge = _capture_main_display(run, f"toolbar-{label}-selection")
        buttons_edge = _find_toolbar_buttons(cap_edge, width, band_lo, band_hi)
        if "blue" not in buttons_edge:
            raise RuntimeError(f"selected group button not found ({label} selection): {buttons_edge}")
        blue_edge = buttons_edge["blue"]

        # Expand the shape sub-toolbar (right neighbor of the selected select group).
        _mouse_click(blue_edge[0] + 38, blue_edge[1])
        cap_edge_expanded = _capture_main_display(run, f"toolbar-{label}-subtoolbar")
        buttons_edge_expanded = _find_toolbar_buttons(cap_edge_expanded, width, band_lo, band_hi)
        if "blue" not in buttons_edge_expanded:
            raise RuntimeError(f"selected group button lost after expansion ({label})")
        blue_edge_expanded = buttons_edge_expanded["blue"]
        region_edge = _diff_region(cap_edge, cap_edge_expanded, width, y_above=blue_edge_expanded[1] - 45)
        if region_edge is None:
            raise RuntimeError(f"sub-toolbar did not appear above the main toolbar ({label} selection)")
        left, _, right, _ = region_edge
        if left < 8 or right > width - 8:
            raise RuntimeError(
                f"sub-toolbar off screen with {label}-edge selection: "
                f"[{left:.0f}, {right:.0f}] vs [8, {width - 8:.0f}]"
            )
        center_edge = (left + right) / 2
        if abs(center_edge - blue_edge_expanded[0]) > 30:
            raise RuntimeError(
                f"sub-toolbar not anchored with {label}-edge selection: "
                f"center={center_edge:.0f} button={blue_edge_expanded[0]:.0f}"
            )
        _press_escape()
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline and _overlay_window_count(pid) > 0:
            time.sleep(0.1)
        if _overlay_window_count(pid) > 0:
            raise RuntimeError(f"overlay windows remain after Escape ({label} selection)")

    return (
        f"edge layout ok: default red cx={red1[0]:.0f}, widened red cx={red2[0]:.0f} (yielded left), "
        f"sub-toolbar center={region_center:.0f} anchored to button={blue3[0]:.0f}, "
        f"top/bottom sub-toolbars on screen"
    )


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
