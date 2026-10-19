#!/usr/bin/env python3
"""Require readable visual evidence for every passing full UI smoke step."""

import json
import os
import struct
import sys
from pathlib import Path

from PIL import Image


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as stream:
        header = stream.read(24)
    if len(header) != 24 or not header.startswith(b"\x89PNG\r\n\x1a\n") or header[12:16] != b"IHDR":
        raise ValueError(f"Invalid PNG: {path}")
    return struct.unpack(">II", header[16:24])


def validate(run_dir: Path) -> str:
    manifest = json.loads((run_dir / "manifest.json").read_text())
    report = json.loads((run_dir / "report.json").read_text())
    if manifest.get("app_bundle_id") != "com.quitenote.app.dev" or not manifest.get("finished_at"):
        raise ValueError("Dev app binding or run completion missing")
    if os.environ.get("GITHUB_SHA") and manifest.get("git_commit") != os.environ["GITHUB_SHA"]:
        raise ValueError("Evidence commit does not match CI checkout")
    if report.get("status") != "PASS":
        raise ValueError("UI report is not PASS")

    recording = run_dir / "recordings/ui-recording.mov"
    if recording.is_file() and recording.stat().st_size > 0:
        evidence = "recordings/ui-recording.mov"
        count = 0
    else:
        evidence = "recordings/frames.json"
        index = json.loads((run_dir / evidence).read_text())
        frames = index.get("frames", [])
        if len(frames) < 2:
            raise ValueError("Timestamped frame evidence is incomplete")
        for relative in frames:
            if not relative.startswith("recordings/frames/") or ".." in Path(relative).parts:
                raise ValueError(f"Unsafe frame path: {relative}")
            width, height = png_size(run_dir / relative)
            if width < 200 or height < 120:
                raise ValueError(f"Frame too small: {relative}")
        count = len(frames)
        timeline = run_dir / "recordings/ui-timeline.webp"
        with Image.open(timeline) as animation:
            if animation.format != "WEBP" or not animation.is_animated or animation.n_frames != count:
                raise ValueError("Animated WebP does not match screenshot frame index")
            for number in range(count):
                animation.seek(number)
                animation.load()

    if manifest.get("video_evidence") != evidence:
        raise ValueError("Manifest evidence path does not match actual artifact")
    for step in report.get("results", []):
        relative = step.get("evidence", "")
        if not relative or ".." in Path(relative).parts or not (run_dir / relative).is_file():
            raise ValueError(f"Missing step evidence: {step.get('name')}")
        if relative.endswith(".png"):
            width, height = png_size(run_dir / relative)
            if step.get("name") == "clipboard" and width / height < 1.2:
                raise ValueError("Clipboard frame does not show the wide panel")
            if step.get("name") == "launcher" and width / height < 1.1:
                raise ValueError("Launcher frame does not show the wide panel")
    return f"Validated {len(report['results'])} steps and {count} timestamped frames ({evidence})"


if __name__ == "__main__":
    try:
        print(validate(Path(sys.argv[1])))
    except (OSError, KeyError, ValueError, IndexError) as exc:
        raise SystemExit(f"Visual evidence invalid: {exc}")
