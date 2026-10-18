#!/usr/bin/env python3
"""Run one UI smoke inside the Screen Recording-authorized GUI app context."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import traceback
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path


def atomic_write(path: Path, value: dict) -> None:
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temp.replace(path)


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: gui_smoke_launcher.py REQUEST RESPONSE", file=sys.stderr)
        return 2

    request_path, response_path = (Path(value).resolve() for value in sys.argv[1:])
    request = json.loads(request_path.read_text())
    run_dir = Path(request["run_dir"])
    app_path = Path(request["app_path"])
    storage_root = Path(request["storage_root"])
    pid_path = run_dir / "app.pid"

    app = None
    code = 1
    error = ""
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
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
