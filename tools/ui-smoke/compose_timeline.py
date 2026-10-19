#!/usr/bin/env python3
"""Compose the UI checkpoint screenshots into a reviewable animated WebP."""

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, features


OUTPUT = Path("recordings/ui-timeline.webp")


def frame_paths(run_dir: Path) -> list[Path]:
    index = json.loads((run_dir / "recordings/frames.json").read_text())
    paths = []
    for relative in index["frames"]:
        path = Path(relative)
        if not relative.startswith("recordings/frames/") or ".." in path.parts or path.suffix != ".png":
            raise ValueError(f"Unsafe frame path: {relative}")
        paths.append(run_dir / path)
    if len(paths) < 2:
        raise ValueError("At least two screenshot frames are required")
    return paths


def compose(run_dir: Path) -> Path:
    if not features.check("webp"):
        raise RuntimeError("Pillow WebP support is required")
    paths = frame_paths(run_dir)
    screenshots = []
    for path in paths:
        with Image.open(path) as source:
            source.load()
            if source.format != "PNG" or source.width < 200 or source.height < 120:
                raise ValueError(f"Invalid screenshot frame: {path}")
            screenshots.append(source.convert("RGB"))

    padding, header = 32, 72
    width = max(image.width for image in screenshots) + 2 * padding
    height = max(image.height for image in screenshots) + header + padding
    font_path = Path("/System/Library/Fonts/Menlo.ttc")
    font = ImageFont.truetype(str(font_path), 21) if font_path.exists() else ImageFont.load_default()
    frames = []
    durations = []
    for number, (path, screenshot) in enumerate(zip(paths, screenshots), start=1):
        frame = Image.new("RGB", (width, height), (22, 26, 32))
        label = path.stem.split("-", 2)[-1].rsplit("-", 1)[0]
        ImageDraw.Draw(frame).text(
            (padding, 24), f"UI checkpoints   {number:02d}/{len(paths):02d}   {label}",
            font=font, fill=(235, 240, 245),
        )
        frame.paste(screenshot, ((width - screenshot.width) // 2, header))
        frames.append(frame)
        durations.append(550 if "-before-" in path.name else 1050)

    output = run_dir / OUTPUT
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(".webp.tmp")
    try:
        frames[0].save(
            temporary, format="WEBP", save_all=True, append_images=frames[1:],
            duration=durations, loop=0, lossless=True, method=4,
        )
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    return output


if __name__ == "__main__":
    try:
        print(compose(Path(sys.argv[1])))
    except (OSError, KeyError, ValueError, RuntimeError, IndexError) as exc:
        raise SystemExit(f"Timeline composition failed: {exc}")
