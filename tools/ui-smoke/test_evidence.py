import importlib.util
import json
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch


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


class EvidenceTests(unittest.TestCase):
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
