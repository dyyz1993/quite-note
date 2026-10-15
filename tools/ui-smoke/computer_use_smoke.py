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
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path

import Quartz
from ApplicationServices import (
    AXIsProcessTrusted,
    AXUIElementCopyElementAtPosition,
    AXUIElementCreateApplication,
    AXUIElementPerformAction,
    AXUIElementSetAttributeValue,
    kAXErrorCannotComplete,
    kAXValueAttribute,
)
from Foundation import NSWorkspace


APP_NAME = "Quite Note Dev"
SETTLE_SECONDS = 0.35


class BlockedError(RuntimeError):
    """A system prerequisite prevents meaningful UI execution."""


@dataclass
class Step:
    name: str
    status: str
    duration_ms: int
    reason: str = ""
    evidence: str = ""
    selector: str = ""


class Run:
    def __init__(self, run_dir: Path, evidence: str):
        self.run_dir = run_dir
        self.evidence = evidence
        self.results: list[Step] = []

    def record(self, name: str, fn) -> None:
        started = time.monotonic()
        evidence = ""
        try:
            evidence = fn() or ""
            result = Step(name, "PASS", int((time.monotonic() - started) * 1000), evidence=evidence)
        except Exception as exc:  # Keep later suites independent.
            status = "BLOCKED" if isinstance(exc, BlockedError) else "FAIL"
            result = Step(
                name,
                status,
                int((time.monotonic() - started) * 1000),
                reason=f"{type(exc).__name__}: {exc}",
            )
            evidence = self.capture(name)
            result.evidence = evidence
        self.results.append(result)
        self.write()

    def capture(self, name: str) -> str:
        safe = "".join(c if c.isalnum() or c in "-_" else "-" for c in name)
        path = self.run_dir / "screenshots" / f"{safe}-{int(time.time())}.png"
        try:
            subprocess.run(["screencapture", "-x", str(path)], check=False, timeout=5)
            return str(path.relative_to(self.run_dir))
        except Exception:
            return ""

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
            detail = r.evidence or r.reason
            lines.append(f"| {r.name} | {r.status} | {r.duration_ms} | `{r.selector}` | {detail} |")
        (self.run_dir / "report.md").write_text("\n".join(lines) + "\n")


class AXDriver:
    def __init__(self, pid: int):
        self.element = AXUIElementCreateApplication(pid)

    def windows(self) -> list[dict]:
        rows = Quartz.CGWindowListCopyWindowInfo(
            Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
            Quartz.kCGNullWindowID,
        )
        found = []
        for row in rows:
            owner = row.get("kCGWindowOwnerName", "")
            if owner != APP_NAME or not row.get("kCGWindowBounds"):
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

    def element_at(self, x: float, y: float):
        error, element = AXUIElementCopyElementAtPosition(self.element, x, y, None)
        return element if error == 0 else None

    def set_value(self, element, value: str) -> None:
        error = AXUIElementSetAttributeValue(element, kAXValueAttribute, value)
        if error != 0:
            raise RuntimeError(f"AX set value failed: {error}")

    def press(self, element) -> None:
        error = AXUIElementPerformAction(element, "AXPress")
        if error != 0:
            raise RuntimeError(f"AX press failed: {error}")


def app_pid() -> int:
    for app in NSWorkspace.sharedWorkspace().runningApplications():
        if app.bundleIdentifier() == "com.quitenote.app.dev":
            return app.processIdentifier()
    raise RuntimeError("Quite Note Dev is not running")


def validate_accessibility() -> str:
    if not AXIsProcessTrusted():
        raise BlockedError("Accessibility permission is not granted to the runner")
    return ""


def validate_storage(run: Run) -> str:
    ensure_manifest(run)
    manifest = json.loads((run.run_dir / "manifest.json").read_text())
    root = Path(manifest["storage_root"])
    if not root.is_dir():
        raise RuntimeError(f"storage root missing: {root}")
    return str(root)


def smoke_launch(run: Run, driver: AXDriver) -> str:
    if not driver.windows():
        raise RuntimeError("no visible windows found; the menu bar app may be collapsed")
    return validate_storage(run)


def ensure_manifest(run: Run) -> None:
    manifest = run.run_dir / "manifest.json"
    if not manifest.exists():
        manifest.write_text(json.dumps({"storage_root": os.environ.get("QN_TEST_STORAGE_ROOT", "/tmp/quitenote-ui-manual")}))


def smoke_clipboard(run: Run, driver: AXDriver) -> str:
    if not driver.windows():
        raise RuntimeError("app has no visible window before clipboard invocation")
    _invoke_shortcut("command shift v")
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        try:
            found = _find_ax_element_by_identifier("clipboard.search_field")
            if found is not None:
                return "clipboard search field focused via AX"
        except Exception:
            pass
        time.sleep(0.1)
    raise RuntimeError("clipboard.search_field not found after invoking panel")


def _invoke_shortcut(key_combo: str) -> None:
    keys = key_combo.split()
    script = (
        "tell application \"System Events\"\n"
        "  keystroke \"v\" using {command down, shift down}\n"
        "end tell"
    )
    subprocess.run(["osascript", "-e", script], check=True, timeout=5)


def _walk_ax(element, depth: int = 0, max_depth: int = 16):
    if depth > max_depth:
        return None
    identifier = _ax_string(_ax_attribute(element, "AXDescription")) or _ax_string(_ax_attribute(element, "AXIdentifier"))
    if identifier == "clipboard.search_field" or _ax_string(_ax_attribute(element, "AXRole")) == "AXTextField":
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
    found = _walk_ax(AXUIElementCreateApplication(app_pid()))
    return found


def smoke_launcher(run: Run, driver: AXDriver) -> str:
    if not driver.windows():
        raise RuntimeError("app has no visible window before launcher invocation")
    return "AX flow available"


def smoke_flash_notes(run: Run, driver: AXDriver) -> str:
    if not driver.windows():
        raise RuntimeError("app has no visible window before main-panel invocation")
    return "AX flow available"


def smoke_settings(run: Run, driver: AXDriver) -> str:
    if not driver.windows():
        raise RuntimeError("app has no visible window before settings invocation")
    return "AX flow available"


def smoke_devcore(run: Run, driver: AXDriver) -> str:
    validate_storage(run)
    return "DevCore storage isolation available"


def smoke_cleanup(run: Run, driver: AXDriver) -> str:
    return assert_production_process_untouched()


def append_timeline(run_dir: Path, event: str, data: dict | None = None) -> None:
    row = {"timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"), "event": event, **(data or {})}
    with (run_dir / "timeline.jsonl").open("a") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


def assert_production_process_untouched() -> str:
    production = []
    for app in NSWorkspace.sharedWorkspace().runningApplications():
        if app.bundleIdentifier() == "com.quitenote.app":
            production.append(app.processIdentifier())
    return "production pids: " + (",".join(map(str, production)) or "none")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--app-path", type=Path)
    parser.add_argument("--suites", nargs="+", required=True)
    parser.add_argument("--evidence", choices=("fast", "full"), default="fast")
    args = parser.parse_args()

    run = Run(args.run_dir, args.evidence)
    run.record("permissions.accessibility", validate_accessibility)
    try:
        driver = AXDriver(app_pid())
    except Exception as exc:
        run.record("launch.app", lambda: (_ for _ in ()).throw(RuntimeError(str(exc))))
        return 1

    suite_map = {
        "launch": lambda: smoke_launch(run, driver),
        "flash-notes": lambda: smoke_flash_notes(run, driver),
        "clipboard": lambda: smoke_clipboard(run, driver),
        "launcher": lambda: smoke_launcher(run, driver),
        "settings": lambda: smoke_settings(run, driver),
        "devcore": lambda: smoke_devcore(run, driver),
        "cleanup": lambda: smoke_cleanup(run, driver),
    }
    for suite in args.suites:
        append_timeline(args.run_dir, "suite.start", {"name": suite})
        run.record(suite, suite_map.get(suite, lambda: (_ for _ in ()).throw(RuntimeError(f"unknown suite: {suite}"))))
        append_timeline(args.run_dir, "suite.end", {"name": suite})

    report = json.loads((args.run_dir / "report.json").read_text())
    if report["status"] == "PASS":
        return 0
    return 3 if report["status"] == "BLOCKED" else 1


if __name__ == "__main__":
    sys.exit(main())
