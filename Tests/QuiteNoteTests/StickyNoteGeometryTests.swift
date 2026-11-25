import XCTest
@testable import QuiteNote

/// 便利贴窗口几何（纯函数）
final class StickyNoteGeometryTests: XCTestCase {

    private let main = StickyNoteGeometry.Screen(
        frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: NSRect(x: 0, y: 25, width: 1440, height: 875)       // 顶部菜单栏
    )
    private let side = StickyNoteGeometry.Screen(
        frame: NSRect(x: 1440, y: -200, width: 1080, height: 1920),
        visibleFrame: NSRect(x: 1440, y: -175, width: 1080, height: 1895)
    )

    // MARK: - 新建

    func testNewNoteIsCenteredOnTheMouseAndStaysInsideTheScreen() {
        let frame = StickyNoteGeometry.newNoteFrame(mouseLocation: NSPoint(x: 700, y: 400), screens: [main])
        XCTAssertEqual(frame, NSRect(x: 550, y: 300, width: 300, height: 200))
    }

    func testNewNoteNearTheMenuBarIsPushedBelowIt() {
        let frame = StickyNoteGeometry.newNoteFrame(mouseLocation: NSPoint(x: 700, y: 890), screens: [main])
        XCTAssertEqual(frame.maxY, main.visibleFrame.maxY - StickyNoteGeometry.screenMargin)
    }

    func testNewNoteUsesTheScreenTheMouseIsOn() {
        let frame = StickyNoteGeometry.newNoteFrame(mouseLocation: NSPoint(x: 2000, y: 600), screens: [main, side])
        XCTAssertEqual(frame.midX, 2000, accuracy: 0.001)
        XCTAssertEqual(frame.midY, 600, accuracy: 0.001)
    }

    func testConsecutiveNotesDoNotLandExactlyOnTopOfEachOther() {
        let mouse = NSPoint(x: 700, y: 400)
        let first = StickyNoteGeometry.newNoteFrame(mouseLocation: mouse, screens: [main])
        let second = StickyNoteGeometry.newNoteFrame(mouseLocation: mouse, screens: [main], existingFrames: [first])
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(NSPointInRect(second.origin, main.visibleFrame), "错开之后仍在可见区内")
    }

    // MARK: - 恢复

    func testRestoredFrameOnAScreenIsKeptWhereItWas() {
        let saved = NSRect(x: 100, y: 100, width: 300, height: 200)
        XCTAssertEqual(StickyNoteGeometry.restoredFrame(saved, screens: [main, side], fallback: main.visibleFrame), saved)
    }

    /// 显示器拔掉后，保存在那块屏上的便利贴会整块落在屏外，而便利贴没有任何找回入口
    func testRestoredFrameOffEveryScreenMovesToTheFallbackScreen() {
        let saved = NSRect(x: 3000, y: 2500, width: 300, height: 200)
        let restored = StickyNoteGeometry.restoredFrame(saved, screens: [main], fallback: main.visibleFrame)
        XCTAssertTrue(main.visibleFrame.contains(restored), "应回到主屏可见区内，实际 \(restored)")
        XCTAssertEqual(restored.size, saved.size)
    }

    func testRestoredFrameHangingOffTheEdgeIsPulledBackIn() {
        let hanging = NSRect(x: -200, y: 300, width: 300, height: 200)      // 中心在屏内，左边出屏
        let restored = StickyNoteGeometry.restoredFrame(hanging, screens: [main], fallback: main.visibleFrame)
        XCTAssertTrue(main.visibleFrame.contains(restored), "实际 \(restored)")
    }

    func testRestoredFrameLargerThanTheScreenIsShrunkToIt() {
        let huge = NSRect(x: 100, y: 100, width: 4000, height: 3000)
        let restored = StickyNoteGeometry.restoredFrame(huge, screens: [main], fallback: main.visibleFrame)
        XCTAssertTrue(main.visibleFrame.contains(restored), "实际 \(restored)")
        XCTAssertGreaterThanOrEqual(restored.width, StickyNoteGeometry.minimumSize.width)
        XCTAssertGreaterThanOrEqual(restored.height, StickyNoteGeometry.minimumSize.height)
    }

    func testRestoredFrameSmallerThanTheMinimumIsBumpedUpToIt() {
        let tiny = NSRect(x: 100, y: 100, width: 20, height: 10)
        let restored = StickyNoteGeometry.restoredFrame(tiny, screens: [main], fallback: main.visibleFrame)
        XCTAssertEqual(restored.size, StickyNoteGeometry.minimumSize)
    }

    // MARK: - 钳制

    func testClampKeepsAWellPlacedFrameUntouched() {
        let frame = NSRect(x: 200, y: 200, width: 300, height: 200)
        XCTAssertEqual(StickyNoteGeometry.clamp(frame, to: main.visibleFrame), frame)
    }

    func testClampOnAScreenNarrowerThanTheMarginStillProducesAValidFrame() {
        let narrow = NSRect(x: 0, y: 0, width: 120, height: 90)
        let clamped = StickyNoteGeometry.clamp(NSRect(x: 500, y: 500, width: 300, height: 200), to: narrow)
        XCTAssertTrue(narrow.contains(clamped), "实际 \(clamped)")
        XCTAssertLessThanOrEqual(clamped.minX, clamped.maxX)
        XCTAssertLessThanOrEqual(clamped.minY, clamped.maxY)
    }
}
