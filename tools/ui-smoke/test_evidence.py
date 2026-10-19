import importlib.util
import json
import os
import tempfile
import threading
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

from PIL import Image


ROOT = Path(__file__).resolve().parent


def load_module(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / filename)
    module = importlib.util.module_from_spec(spec)
    import sys
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


launcher = load_module("gui_smoke_launcher", "gui_smoke_launcher.py")
smoke = load_module("computer_use_smoke", "computer_use_smoke.py")
composer = load_module("compose_timeline", "compose_timeline.py")
validator = load_module("validate_evidence", "validate_evidence.py")


class EvidenceTests(unittest.TestCase):
    def test_visual_gate_rejects_main_window_for_clipboard(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            frames = root / "recordings/frames"
            frames.mkdir(parents=True)
            names = ["recordings/frames/before.png", "recordings/frames/clipboard.png"]
            (root / "recordings/frames.json").write_text(json.dumps({"frames": names}))
            (root / "manifest.json").write_text(json.dumps({
                "app_bundle_id": "com.quitenote.app.dev",
                "finished_at": "2026-10-19T00:00:00Z",
                "video_evidence": "recordings/frames.json",
            }))
            (root / "report.json").write_text(json.dumps({
                "status": "PASS", "results": [{"name": "clipboard", "evidence": names[1]}],
            }))

            Image.new("RGB", (1040, 1280), "#223344").save(root / names[0])
            Image.new("RGB", (1040, 1280), "#445566").save(root / names[1])
            output = composer.compose(root)
            with patch.dict(os.environ, {"GITHUB_SHA": ""}):
                with self.assertRaisesRegex(ValueError, "wide panel"):
                    validator.validate(root)
                Image.new("RGB", (1520, 1040), "#667788").save(root / names[1])
                composer.compose(root)
                self.assertIn("2 timestamped frames", validator.validate(root))
                output.unlink()
                with self.assertRaises(FileNotFoundError):
                    validator.validate(root)

    def test_animated_webp_preserves_order_and_mixed_frame_sizes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            frame_dir = root / "recordings/frames"
            frame_dir.mkdir(parents=True)
            names = [f"recordings/frames/frame-{number:04d}-step-{number}.png" for number in range(3)]
            for number, name in enumerate(names):
                Image.new("RGB", (300 + number * 40, 240 + number * 20), (number * 90, 0, 0)).save(root / name)
            (root / "recordings/frames.json").write_text(json.dumps({"frames": names}))
            output = composer.compose(root)
            self.assertTrue(all((root / name).is_file() for name in names))
            with Image.open(output) as animation:
                self.assertEqual(animation.format, "WEBP")
                self.assertEqual(animation.n_frames, 3)
                self.assertEqual(animation.size, (444, 384))
                for number in range(3):
                    animation.seek(number)
                    self.assertEqual(animation.convert("RGB").getpixel((222, 172)), (number * 90, 0, 0))

    def test_fallback_does_not_call_screencapture_before_app_frame(self):
        with tempfile.TemporaryDirectory() as temp:
            recorder = SimpleNamespace(process=None, capture_fallback_frame=Mock(return_value="recordings/frames/window.png"))
            run = smoke.Run(Path(temp), "full", recorder)
            with patch.object(smoke.subprocess, "run", side_effect=AssertionError("screencapture called")):
                self.assertEqual(run.capture("clipboard"), "recordings/frames/window.png")
            recorder.capture_fallback_frame.assert_called_once_with("clipboard")

    def test_window_assertions_only_see_current_process_onscreen(self):
        options = []
        quartz = SimpleNamespace(
            kCGWindowListOptionOnScreenOnly=1,
            kCGWindowListExcludeDesktopElements=2,
            kCGNullWindowID=0,
            CGWindowListCopyWindowInfo=lambda option, _: options.append(option) or [
                {"kCGWindowOwnerName": "Quite Note Dev", "kCGWindowOwnerPID": 456, "kCGWindowBounds": {"Width": 760, "Height": 520}},
                {"kCGWindowOwnerName": "Quite Note Dev", "kCGWindowOwnerPID": 123, "kCGWindowBounds": {"Width": 520, "Height": 640}},
            ],
        )
        driver = object.__new__(smoke.AXDriver)
        driver.pid = 123
        with patch.object(smoke, "Quartz", quartz):
            self.assertEqual([window["frame"][2:] for window in driver.windows()], [[520.0, 640.0]])
        self.assertEqual(options, [3])

    def test_launcher_loads_driver_from_checkout(self):
        self.assertTrue(callable(launcher.load_smoke_main(ROOT / "computer_use_smoke.py")))

    def test_claim_response_matches_runner_wait_path(self):
        with tempfile.TemporaryDirectory() as temp:
            with patch.object(launcher, "RESPONSE_ROOT", Path(temp)):
                claim = Path(temp) / "ui-20261019-102008-68982b84.request.claim"
                self.assertEqual(
                    launcher.response_for_claim(claim),
                    Path(temp) / "ui-20261019-102008-68982b84.response.json",
                )

    def test_app_window_frame_is_recorded_with_timeline(self):
        with tempfile.TemporaryDirectory() as temp:
            run_dir = Path(temp)
            recorder = object.__new__(smoke.ScreenRecorder)
            recorder.run_dir = run_dir
            recorder.path = run_dir / "recordings/ui-recording.mov"
            recorder.frame_root = run_dir / "recordings/frames"
            recorder.frames = []
            recorder.process = None
            recorder.unavailable_path = run_dir / "recordings/ui-recording.unavailable.txt"
            recorder.unavailable_path.parent.mkdir(parents=True)
            recorder.unavailable_path.write_text("video unavailable\n")

            def render_request():
                requests = run_dir / "recordings/requests"
                deadline = time.monotonic() + 2
                while time.monotonic() < deadline:
                    files = list(requests.glob("*.request")) if requests.exists() else []
                    if files:
                        recorder.frame_root.mkdir(parents=True, exist_ok=True)
                        (recorder.frame_root / (files[0].stem + ".png")).write_bytes(b"valid-frame")
                        return
                    time.sleep(0.01)

            worker = threading.Thread(target=render_request)
            worker.start()
            evidence = recorder.capture_fallback_frame("clipboard-after")
            worker.join(timeout=2)
            self.assertTrue(evidence.startswith("recordings/frames/frame-"))
            self.assertEqual(recorder.stop(), "recordings/frames.json")
            self.assertEqual(json.loads((run_dir / "recordings/frames.json").read_text())["frames"], [evidence])
            self.assertIn("evidence.frame", (run_dir / "timeline.jsonl").read_text())


if __name__ == "__main__":
    unittest.main()
