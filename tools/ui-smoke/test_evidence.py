import importlib.util
import base64
import json
import os
import sqlite3
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
seeder = load_module("seed_clipboard_history", "seed_clipboard_history.py")
composer = load_module("compose_timeline", "compose_timeline.py")
validator = load_module("validate_evidence", "validate_evidence.py")


class EvidenceTests(unittest.TestCase):
    def test_clipboard_fixture_is_isolated_and_stable(self):
        with tempfile.TemporaryDirectory() as temp:
            database = Path(temp) / "nested" / "ClipboardHistory-Debug.sqlite"
            self.assertEqual(seeder.seed(database), 4)
            self.assertEqual(seeder.seed(database), 4)
            connection = sqlite3.connect(database)
            try:
                rows = connection.execute(
                    "SELECT ZPLAINTEXT, ZTYPE, ZSOURCEAPP, ZCONTENTHASH FROM ZCDCLIPBOARDENTRY "
                    "ORDER BY ZCREATEDAT DESC"
                ).fetchall()
            finally:
                connection.close()
            self.assertEqual([row[0] for row in rows], [
                seeder.FIXTURES[0][0],
                seeder.FIXTURES[1][0],
                seeder.FIXTURES[2][0],
                seeder.FIXTURES[3][0],
            ])
            self.assertEqual([row[1] for row in rows], ["text", "text", "text", "link"])
            self.assertEqual({row[2] for row in rows}, {"UI Smoke"})
            self.assertEqual(len({row[3] for row in rows}), 4)
            self.assertTrue(seeder.CORE_DATA_TABLES <= set(self.table_names(database)))
            self.assertEqual(base64.b64decode(seeder.MODEL_CACHE_B64)[:8].hex(), "8d570b7414d519fe")

    def table_names(self, database):
        connection = sqlite3.connect(database)
        try:
            return [row[0] for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )]
        finally:
            connection.close()

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


def entry(role, **kwargs):
    return {"role": role, "title": kwargs.get("title", ""), "value": kwargs.get("value", ""),
            "desc": kwargs.get("desc", ""), "help": kwargs.get("help", ""),
            "frame": kwargs.get("frame"), "ref": kwargs.get("ref")}


# AX facts measured on xyz-mac 2026-11-28 (artifact a4911402, probe run
# probe-settings-084931): labels the settings overlay exposes and labels that
# exist in the notes view when settings is closed.
SETTINGS_OPEN_TREE = [
    entry("AXButton", desc="settings", frame=[1124.0, 63.0, 28.0, 38.0]),
    entry("AXButton", desc="chevron left", frame=[736.0, 127.0, 32.0, 32.0]),
    entry("AXButton", desc="AI", frame=[736.0, 189.0, 52.0, 27.0]),
    entry("AXButton", desc="记录", frame=[793.5, 188.5, 66.0, 28.0]),
    entry("AXButton", desc="剪贴板", frame=[864.5, 188.5, 78.0, 28.0]),
    entry("AXStaticText", value="偏好设置", frame=[909.2, 77.5, 65.5, 19.0]),
    entry("AXStaticText", value="AI 自动提炼, 当前使用：Magpie · 未选择模型"),
    entry("AXStaticText", value="连接方式"),
    entry("AXButton", desc="Magpie, 自动连接本机网关"),
    entry("AXStaticText", value="WEEK"),
]
SETTINGS_CLIPBOARD_TREE = [
    entry("AXButton", desc="chevron left"),
    entry("AXButton", desc="剪贴板", frame=[864.5, 189.0, 77.0, 27.0]),
    entry("AXButton", desc="AI"),
    entry("AXStaticText", value="偏好设置"),
    entry("AXStaticText", value="剪贴板历史"),
    entry("AXStaticText", value="启用剪贴板历史"),
    entry("AXStaticText", value="正在记录 · 当前 4 条"),
    entry("AXButton", desc="打开剪贴板历史"),
    entry("AXButton", desc="暂停 1 小时"),
]
NOTES_VIEW_TREE = [
    # settings closed: notes view filter buttons use English lucide descriptions
    # and the panel header title switches back to 闪记 — none of the settings
    # markers may match, otherwise a failed open would read as success.
    entry("AXButton", desc="type", help="筛选纯文本"),
    entry("AXButton", desc="clipboard", help="筛选便签"),
    entry("AXStaticText", value="闪记"),
    entry("AXStaticText", value="没有找到匹配的记录。"),
]


class VisibleAssertionTests(unittest.TestCase):
    """Bad-sample red proofs for the 1.4.0 launch/settings/toolbar assertions.

    Every new assertion must be shown to fail on a known-bad input before it
    is trusted on the test Mac (project rule: 修过的测试先证明它会红)."""

    def test_launch_window_assertion_rejects_windows_without_main_panel(self):
        # red: launch with only the status item / quick panels / ball visible
        for bad in ([], [[995.0, 0.0, 34.0, 24.0]], [[0.0, 0.0, 760.0, 520.0]],
                    [[0.0, 0.0, 640.0, 477.0]], [[0.0, 0.0, 80.0, 80.0]]):
            self.assertIsNone(smoke.find_panel_frame(bad), f"must reject {bad}")
        # green: the measured launch state (panel via AX at [648,63,520,640])
        frame = smoke.find_panel_frame([[995.0, 0.0, 34.0, 24.0], [648.0, 63.0, 520.0, 640.0]])
        self.assertEqual(frame, [648.0, 63.0, 520.0, 640.0])

    def test_main_panel_size_interval_boundaries(self):
        # inclusive interval; a wrong measurement (±1pt outside) must fail
        self.assertIsNotNone(smoke.find_panel_frame([[0, 0, 480, 600]]))
        self.assertIsNotNone(smoke.find_panel_frame([[0, 0, 560, 680]]))
        self.assertIsNone(smoke.find_panel_frame([[0, 0, 479, 640]]))
        self.assertIsNone(smoke.find_panel_frame([[0, 0, 561, 640]]))
        self.assertIsNone(smoke.find_panel_frame([[0, 0, 520, 599]]))
        self.assertIsNone(smoke.find_panel_frame([[0, 0, 520, 681]]))

    def test_settings_presence_requires_settings_only_labels(self):
        # red: if the settings overlay never opened, presence must be False
        self.assertFalse(smoke.settings_overlay_present(NOTES_VIEW_TREE))
        self.assertFalse(smoke.settings_overlay_present([]))
        # green: header text or any tab button proves the overlay is in the tree
        self.assertTrue(smoke.settings_overlay_present(SETTINGS_OPEN_TREE))
        self.assertTrue(smoke.settings_overlay_present(SETTINGS_CLIPBOARD_TREE))
        # partial render (only one tab so far) still counts as present
        self.assertTrue(smoke.settings_overlay_present([entry("AXButton", desc="AI")]))

    def test_settings_marker_matching_is_label_exact(self):
        # tab buttons are found by AXDescription exactly; the notes-view
        # English desc "clipboard" must not match the Chinese tab label
        self.assertIsNotNone(smoke.find_entry(SETTINGS_OPEN_TREE, role="AXButton", desc="剪贴板"))
        self.assertIsNone(smoke.find_entry(NOTES_VIEW_TREE, role="AXButton", desc="剪贴板"))
        # initial-tab marker is a prefix match (model suffix varies)
        self.assertIsNotNone(smoke.find_entry(SETTINGS_OPEN_TREE, role="AXStaticText",
                                              value_prefix=smoke.AI_TAB_MARKER_PREFIX))
        self.assertIsNone(smoke.find_entry(SETTINGS_CLIPBOARD_TREE, role="AXStaticText",
                                           value_prefix=smoke.AI_TAB_MARKER_PREFIX))
        # switched-tab marker exists only on the clipboard tab
        self.assertIsNotNone(smoke.find_entry(SETTINGS_CLIPBOARD_TREE, role="AXStaticText",
                                              value_equals=smoke.CLIPBOARD_TAB_MARKER))
        self.assertIsNone(smoke.find_entry(SETTINGS_OPEN_TREE, role="AXStaticText",
                                           value_equals=smoke.CLIPBOARD_TAB_MARKER))

    def test_require_entry_raises_on_missing_marker(self):
        # red proof: switching assertions must fail when the tab did not change
        with self.assertRaisesRegex(RuntimeError, "clipboard settings tab button"):
            smoke.require_entry(SETTINGS_OPEN_TREE, "clipboard settings tab button",
                                role="AXButton", desc="不存在的标签")
        with self.assertRaisesRegex(RuntimeError, "not found in AX tree"):
            smoke.require_entry(NOTES_VIEW_TREE, "header", role="AXStaticText",
                                value_equals=smoke.SETTINGS_OPEN_MARKER)

    def test_toolbar_frames_archive_into_screenshots(self):
        # _snap_overlay must leave the assertion frame in screenshots/ with a
        # stage-tagged name (previously frames only existed in /tmp/qn-manual
        # and the baseline never showed the toolbar)
        with tempfile.TemporaryDirectory() as temp:
            run_dir = Path(temp)
            frames = run_dir / "recordings/frames"
            run = smoke.Run(run_dir, "fast")

            def respond_like_app():
                # the Dev app polls recordings/requests and renders the frame;
                # the driver deletes any stale file before writing the request
                deadline = time.monotonic() + 6
                while time.monotonic() < deadline:
                    pending = list((run_dir / "recordings/requests").glob("*.request")) \
                        if (run_dir / "recordings/requests").exists() else []
                    if pending:
                        Image.effect_noise((1366, 854), 64).convert("RGB").save(frames / (pending[0].stem + ".png"))
                        return
                    time.sleep(0.02)

            worker = threading.Thread(target=respond_like_app)
            worker.start()
            with patch.object(smoke, "caffeinate", lambda t=25: None):
                archived = smoke._snap_overlay(run, "stage1_default")
            worker.join(timeout=6)
            self.assertTrue(archived.startswith(str(run_dir / "screenshots/screenshot-toolbar-frame-stage1_default-")))
            self.assertGreater(Path(archived).stat().st_size, 40000)
            with Image.open(archived) as im:
                self.assertEqual(im.size, (1366, 854))

    def test_toolbar_annotation_draws_boxes_and_tolerates_missing_file(self):
        with tempfile.TemporaryDirectory() as temp:
            frame = Path(temp) / "frame.png"
            Image.new("RGB", (1366, 854), (20, 20, 20)).save(frame)
            before = frame.read_bytes()
            smoke._annotate_toolbar_frame(frame, [
                ("hi 874,300", (874.0, 300.0), (0, 255, 255)),
                ("rec 1332,300", (1332.0, 300.0), (255, 60, 60)),
                ("click 950,300", (950.0, 300.0), (255, 220, 0)),
            ])
            self.assertNotEqual(frame.read_bytes(), before, "annotation must change the archived frame")
            with Image.open(frame) as im:
                self.assertEqual(im.size, (1366, 854))
                # cyan box border at the highlight position (26pt half width -> ~24px at 1366/1440 scale)
                self.assertEqual(im.getpixel((int(874 * 1366 / 1440) - 24, int(300 * 854 / 900))), (0, 255, 255))
            # a missing/unreadable frame must not raise: annotation is best effort
            smoke._annotate_toolbar_frame(Path(temp) / "missing.png", [("x", (10, 10), (0, 255, 255))])

    def test_suite_versions_are_consistent_across_harness_files(self):
        shell = (ROOT / "run_ui_smoke.sh").read_text()
        import re
        match = re.search(r'SUITE_VERSION="(\d+\.\d+\.\d+)"', shell)
        self.assertIsNotNone(match, "run_ui_smoke.sh must declare SUITE_VERSION")
        declared = match.group(1)
        self.assertEqual(declared, json.loads((ROOT / "selectors.json").read_text())["suite_version"])
        self.assertEqual(declared, json.loads((ROOT / "operations.json").read_text())["suite_version"])

    def test_settings_flow_operations_match_measured_labels(self):
        operations = json.loads((ROOT / "operations.json").read_text())
        selectors = json.loads((ROOT / "selectors.json").read_text())
        flow = operations["operations"]["settings"]
        pressed = [op.get("value") for op in flow if op.get("action") == "ax_press"]
        self.assertIn("偏好设置", pressed, "settings must open through the status menu item")
        self.assertIn("剪贴板", pressed, "settings must switch exactly one tab")
        self.assertIn("chevron left", pressed, "settings must close through the header back button")
        # read-only: no toggle/checkbox interaction in the flow
        self.assertNotIn("toggle", [op.get("action") for op in flow])
        self.assertEqual(selectors["fallback_labels"]["settings.clipboard_tab"], "剪贴板")


if __name__ == "__main__":
    unittest.main()
