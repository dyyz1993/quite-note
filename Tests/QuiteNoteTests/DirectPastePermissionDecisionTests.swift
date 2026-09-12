import XCTest
@testable import QuiteNote

final class DirectPastePermissionDecisionTests: XCTestCase {
    func testTrustedAccessibilityPastesDirectly() {
        XCTAssertEqual(
            ClipboardPasteService.permissionDecision(hasAccessibilityPermission: true),
            .pasteDirectly
        )
    }

    func testMissingAccessibilityCopiesBeforeOfferingPermission() {
        XCTAssertEqual(
            ClipboardPasteService.permissionDecision(hasAccessibilityPermission: false),
            .copyThenOfferAccessibility
        )
    }
}
