import AppKit
import XCTest
@testable import QuiteNote

/// 剪贴板面板按键映射（2026-10-24 方案 B：←/→ 永远是输入框光标键，
/// 分类切换走 Tab/⇧Tab——搜索框常驻聚焦下旧"未聚焦才切筛选"永不生效）
@MainActor
final class ClipboardPanelKeyMappingTests: XCTestCase {
    private func keyEvent(_ keyCode: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    func testTabSwitchesFilterForward() {
        XCTAssertEqual(
            ClipboardHistoryPanelController.mapKey(keyEvent(48)),
            .switchFilterRight
        )
    }

    func testShiftTabSwitchesFilterBackward() {
        XCTAssertEqual(
            ClipboardHistoryPanelController.mapKey(keyEvent(48, flags: .shift)),
            .switchFilterLeft
        )
    }

    func testArrowKeysAreNeverFilterSwitches() {
        // 方案 B：←/→ 不再映射筛选切换（永远交给输入框 field editor 移光标）
        XCTAssertNil(ClipboardHistoryPanelController.mapKey(keyEvent(123)))
        XCTAssertNil(ClipboardHistoryPanelController.mapKey(keyEvent(124)))
    }
}
