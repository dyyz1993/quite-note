import XCTest
@testable import QuiteNote

final class AnnotationToolbarGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)
    private let toolbarSize = CGSize(width: 500, height: 48)
    private let secondarySize = CGSize(width: 220, height: 42)

    func testSecondaryToolbarKeepsLeftEdgeInsideScreenWhenSelectionIsNearLeft() {
        let center = V2AnnotationToolbarGeometry.mainToolbarCenter(
            in: screen,
            selection: CGRect(x: 0, y: 200, width: 80, height: 50),
            toolbarSize: toolbarSize,
            expandedContentRect: CGRect(x: -100, y: -60, width: 220, height: 42),
            spacing: 12,
            margin: 8
        )

        // The subtoolbar starts 100 points left of the main toolbar.
        XCTAssertEqual(center.x, 358)
    }

    func testSecondaryToolbarKeepsTopEdgeInsideScreenWhenFallbackIsAtBottom() {
        // A subtoolbar 60 points above the main toolbar expands the combined
        // bounds upward; the bottom fallback must account for that extension.
        let center = V2AnnotationToolbarGeometry.mainToolbarCenter(
            in: CGRect(x: 0, y: 0, width: 1000, height: 100),
            selection: CGRect(x: 0, y: 0, width: 1000, height: 100),
            toolbarSize: toolbarSize,
            expandedContentRect: CGRect(x: 0, y: -60, width: secondarySize.width, height: secondarySize.height),
            spacing: 12,
            margin: 8
        )

        XCTAssertEqual(center.y, 92)
    }

    func testAudioPopoverKeepsRightAndBottomEdgesInsideScreen() {
        let center = V2AnnotationToolbarGeometry.mainToolbarCenter(
            in: screen,
            selection: CGRect(x: 600, y: 650, width: 390, height: 45),
            toolbarSize: toolbarSize,
            expandedContentRect: CGRect(x: 300, y: 54, width: 200, height: 170),
            spacing: 12,
            margin: 8
        )

        XCTAssertEqual(center.x, 742)
        XCTAssertEqual(center.y, 492)
    }
}
