import AppKit
import XCTest
@testable import QuiteNote

/// 剪贴板面板按键必须先尊重正在编辑的搜索框。
@MainActor
final class ClipboardPanelKeyMappingTests: XCTestCase {
    private func arrowEvent(_ keyCode: UInt16) -> NSEvent {
        let symbol = keyCode == 123 ? "\u{2190}" : "\u{2192}"
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: symbol,
            charactersIgnoringModifiers: symbol,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    func testArrowKeysRemainSearchFieldEditingKeysWhileFocused() {
        XCTAssertNil(
            ClipboardHistoryPanelController.mapKey(
                arrowEvent(123),
                isSearchFieldEditing: true
            )
        )
        XCTAssertNil(
            ClipboardHistoryPanelController.mapKey(
                arrowEvent(124),
                isSearchFieldEditing: true
            )
        )
    }

    func testArrowKeysStillSwitchFiltersWhenSearchFieldIsNotEditing() {
        XCTAssertEqual(
            ClipboardHistoryPanelController.mapKey(
                arrowEvent(123),
                isSearchFieldEditing: false
            ),
            .switchFilterLeft
        )
        XCTAssertEqual(
            ClipboardHistoryPanelController.mapKey(
                arrowEvent(124),
                isSearchFieldEditing: false
            ),
            .switchFilterRight
        )
    }
}
