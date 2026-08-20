import XCTest
@testable import QuiteNote

/// 浮球边缘几何单测：钉死「拖拽全程不出屏」与「吸附后离边 ≥ 24pt 视觉间距」两条约束。
/// 背景 bug：拖拽无钳制时鼠标可进菜单栏/Dock，80×80 窗口部分出屏后被系统推回，
/// 与拖拽 setFrame 互相拉扯，表现为浮球在屏幕边缘一闪一闪。
final class BallEdgeGeometryTests: XCTestCase {
    /// 主屏 1920×1080，菜单栏 25pt + Dock 80pt：visibleFrame = (0, 80, 1920, 975)
    private let mainScreen = BallEdgeGeometry.ScreenBounds(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 80, width: 1920, height: 975)
    )

    private let ballRadius: CGFloat = 28 // 可见球体 56pt 直径
    private let windowSize: CGFloat = 80 // 承载窗口边长

    // MARK: - 松手吸附

    func testSnapPullsCenterToMarginOnAllFourEdges() {
        let margin = ballRadius + BallEdgeGeometry.snapVisualGap // 28 + 24
        let visible = mainScreen.visibleFrame

        // 左边缘
        var snapped = BallEdgeGeometry.snapCenter(CGPoint(x: 10, y: 500), visualRadius: ballRadius, screens: [mainScreen])
        XCTAssertEqual(snapped.x, visible.minX + margin, accuracy: 0.01)
        XCTAssertEqual(snapped.y, 500, accuracy: 0.01)

        // 右边缘
        snapped = BallEdgeGeometry.snapCenter(CGPoint(x: 1910, y: 500), visualRadius: ballRadius, screens: [mainScreen])
        XCTAssertEqual(snapped.x, visible.maxX - margin, accuracy: 0.01)

        // 顶边缘（菜单栏下方）
        snapped = BallEdgeGeometry.snapCenter(CGPoint(x: 960, y: 1040), visualRadius: ballRadius, screens: [mainScreen])
        XCTAssertEqual(snapped.y, visible.maxY - margin, accuracy: 0.01)
        XCTAssertEqual(snapped.x, 960, accuracy: 0.01)

        // 底边缘（Dock 上方）
        snapped = BallEdgeGeometry.snapCenter(CGPoint(x: 960, y: 20), visualRadius: ballRadius, screens: [mainScreen])
        XCTAssertEqual(snapped.y, visible.minY + margin, accuracy: 0.01)
    }

    func testSnapLeavesInteriorPositionUnchanged() {
        let interior = CGPoint(x: 960, y: 500)
        let snapped = BallEdgeGeometry.snapCenter(interior, visualRadius: ballRadius, screens: [mainScreen])
        XCTAssertEqual(snapped.x, interior.x, accuracy: 0.01)
        XCTAssertEqual(snapped.y, interior.y, accuracy: 0.01)
    }

    func testSnapKeepsAtLeastVisualGapFromEveryEdge() {
        // 把球丢到四个角落，吸附后可见球缘（中心 ±28）必须离 visibleFrame 各边 ≥ 24pt
        let corners = [CGPoint(x: -20, y: -20), CGPoint(x: 1940, y: -20),
                       CGPoint(x: -20, y: 1100), CGPoint(x: 1940, y: 1100)]
        let visible = mainScreen.visibleFrame
        let gap = BallEdgeGeometry.snapVisualGap

        for corner in corners {
            let snapped = BallEdgeGeometry.snapCenter(corner, visualRadius: ballRadius, screens: [mainScreen])
            XCTAssertGreaterThanOrEqual(snapped.x - ballRadius, visible.minX + gap - 0.01)
            XCTAssertLessThanOrEqual(snapped.x + ballRadius, visible.maxX - gap + 0.01)
            XCTAssertGreaterThanOrEqual(snapped.y - ballRadius, visible.minY + gap - 0.01)
            XCTAssertLessThanOrEqual(snapped.y + ballRadius, visible.maxY - gap + 0.01)
        }
    }

    // MARK: - 拖拽实时钳制

    func testClampDragKeepsWholeWindowInsideVisibleFrame() {
        let visible = mainScreen.visibleFrame

        // 右上角（鼠标顶进菜单栏 + 屏幕右缘）
        var clamped = BallEdgeGeometry.clampDrag(center: CGPoint(x: 1910, y: 1070), windowSize: windowSize, screens: [mainScreen])
        var window = CGRect(x: clamped.x - 40, y: clamped.y - 40, width: 80, height: 80)
        XCTAssertTrue(visible.contains(window), "右上角：窗口必须完整在 visibleFrame 内，实际 \(window)")

        // 左下角（鼠标压进 Dock + 屏幕左缘）
        clamped = BallEdgeGeometry.clampDrag(center: CGPoint(x: 5, y: 5), windowSize: windowSize, screens: [mainScreen])
        window = CGRect(x: clamped.x - 40, y: clamped.y - 40, width: 80, height: 80)
        XCTAssertTrue(visible.contains(window), "左下角：窗口必须完整在 visibleFrame 内，实际 \(window)")

        // 钳制后窗口边缘离 visibleFrame 至少留 dragWindowMargin
        XCTAssertEqual(clamped.x - 40, visible.minX + BallEdgeGeometry.dragWindowMargin, accuracy: 0.01)
        XCTAssertEqual(clamped.y - 40, visible.minY + BallEdgeGeometry.dragWindowMargin, accuracy: 0.01)
    }

    func testClampDragLeavesInteriorUnchanged() {
        let interior = CGPoint(x: 960, y: 500)
        let clamped = BallEdgeGeometry.clampDrag(center: interior, windowSize: windowSize, screens: [mainScreen])
        XCTAssertEqual(clamped.x, interior.x, accuracy: 0.01)
        XCTAssertEqual(clamped.y, interior.y, accuracy: 0.01)
    }

    // MARK: - 多屏选屏

    func testScreenSelectionUsesContainingScreenThenNearest() {
        // 副屏在主屏右侧
        let sideScreen = BallEdgeGeometry.ScreenBounds(
            frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1920, y: 80, width: 1920, height: 975)
        )
        let screens = [mainScreen, sideScreen]

        // 点在副屏内 → 按副屏钳制
        let inSide = BallEdgeGeometry.clampDrag(center: CGPoint(x: 1930, y: 500), windowSize: windowSize, screens: screens)
        XCTAssertEqual(inSide.x, 1920 + 40 + BallEdgeGeometry.dragWindowMargin, accuracy: 0.01)

        // 点在两屏之外（主屏左侧 50pt）→ 回落到最近的主屏
        let outside = BallEdgeGeometry.clampDrag(center: CGPoint(x: -50, y: 540), windowSize: windowSize, screens: screens)
        XCTAssertEqual(outside.x, 40 + BallEdgeGeometry.dragWindowMargin, accuracy: 0.01)
    }
}
