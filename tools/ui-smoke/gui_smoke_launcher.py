#!/usr/bin/env python3
"""Queue-driven GUI smoke launcher.

The process is intentionally long-lived: it inherits the interactive login
session's TCC context, so every run performs AX and screen capture under the
same trusted identity. GitHub's runner never becomes the responsible process.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import traceback
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path


QUEUE_ROOT = Path("/tmp/quitenote-ui-smoke-launcher")
REQUEST_ROOT = QUEUE_ROOT / "requests"
RESPONSE_ROOT = QUEUE_ROOT / "responses"
LOG_ROOT = QUEUE_ROOT / "logs"


def atomic_write(path: Path, value: dict) -> None:
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temp.replace(path)


def ensure_layout() -> None:
    for directory in (REQUEST_ROOT, RESPONSE_ROOT, LOG_ROOT):
        directory.mkdir(parents=True, exist_ok=True)


def claim_request() -> Path | None:
    for request_path in sorted(REQUEST_ROOT.glob("*.request.json")):
        # Reserve the claim by renaming before processing. A launcher restart
        # can safely replay unclaimed files; claimed files are cleaned by age.
        try:
            claim_path = request_path.with_suffix(".claim")
            request_path.rename(claim_path)
            return claim_path
        except FileNotFoundError:
            continue
    return None


def run_once(claim_path: Path) -> None:
    request = json.loads(claim_path.read_text())
    response_path = RESPONSE_ROOT / f"{claim_path.stem}.response.json"
    run_dir = Path(request["run_dir"])
    app_path = Path(request["app_path"])
    storage_root = Path(request["storage_root"])
    pid_path = run_dir / "app.pid"

    app = None
    code = 1
    error = ""

    run_dir.mkdir(parents=True, exist_ok=True)
    storage_root.mkdir(parents=True, exist_ok=True)
    try:
        environment = os.environ.copy()
        environment["QN_TEST_STORAGE_ROOT"] = str(storage_root)
        app = subprocess.Popen(
            [
                str(app_path / "Contents/MacOS/QuiteNoteDev"),
                "--ui-smoke-run",
                request["run_id"],
            ],
            stdout=(run_dir / "app.stdout.log").open("w"),
            stderr=(run_dir / "app.stderr.log").open("w"),
            env=environment,
        )
        pid_path.write_text(str(app.pid) + "\n")

        tools_dir = Path(__file__).resolve().parent
        sys.path.insert(0, str(tools_dir))
        from computer_use_smoke import main as smoke_main

        sys.argv = [
            "computer_use_smoke.py",
            "--run-dir", str(run_dir),
            "--app-path", str(app_path),
            "--app-pid", str(app.pid),
            "--suites", *request["suites"],
            "--evidence", request["evidence"],
        ]
        with (run_dir / "driver.stdout.log").open("w") as stdout, (
            run_dir / "driver.stderr.log"
        ).open("w") as stderr:
            with redirect_stdout(stdout), redirect_stderr(stderr):
                code = smoke_main()
    except BaseException:
        error = traceback.format_exc()
        (run_dir / "launcher.stderr.log").write_text(error)
        code = 1
    finally:
        if app is not None and app.poll() is None:
            app.terminate()
            try:
                app.wait(timeout=5)
            except subprocess.TimeoutExpired:
                app.kill()
                app.wait(timeout=5)

    atomic_write(response_path, {"returncode": code, "error": error})
    claim_path.unlink(missing_ok=True)


def prune_claims() -> None:
    cutoff = time.time() - 24 * 60 * 60
    for path in REQUEST_ROOT.glob("*.claim"):
        try:
            if path.stat().st_mtime < cutoff:
                path.unlink()
        except FileNotFoundError:
            pass


def main() -> int:
    ensure_layout()
    while True:
        request = claim_request()
        if request is None:
            time.sleep(0.5)
            continue
        run_once(request)
        prune_claims()


def compatibility_main() -> int:
    if len(sys.argv) != 3:
        print("Usage: gui_smoke_launcher.py REQUEST RESPONSE", file=sys.stderr)
        return 2
    ensure_layout()
    request_path = Path(sys.argv[1]).resolve()
    response_path = Path(sys.argv[2]).resolve()
    claim_path = REQUEST_ROOT / f"manual-{time.time_ns()}.claim"
    claim_path.write_text(request_path.read_text())
    run_once(claim_path)
    atomic_write(response_path, json.loads((RESPONSE_ROOT / f"{claim_path.stem}.response.json").read_text()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main() if len(sys.argv) == 1 else compatibility_main())
