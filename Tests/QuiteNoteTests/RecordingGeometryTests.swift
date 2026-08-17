import XCTest
@testable import QuiteNote

/// 录屏几何换算纯函数测试
/// 坐标系口径：局部坐标 = 屏幕左上原点 y 向下（SwiftUI）；AppKit 全局 = 左下原点
final class RecordingGeometryTests: XCTestCase {

    // MARK: - sourceRect 钳制

    func testSelectionInsideScreenPassesThrough() {
        let rect = CGRect(x: 100, y: 200, width: 300, height: 150)
        let clamped = V2RecordingGeometry.clampedSourceRect(
            local: rect, screenPointSize: CGSize(width: 1000, height: 800))
        XCTAssertEqual(clamped, rect)
    }

    func testCrossScreenSelectionClampedToSingleScreen() {
        // 选区右缘超出屏幕 200pt（跨到副屏），应被钳制到本屏右边界
        let rect = CGRect(x: 800, y: 100, width: 400, height: 300) // maxX = 1200 > 1000
        let clamped = V2RecordingGeometry.clampedSourceRect(
            local: rect, screenPointSize: CGSize(width: 1000, height: 800))
        XCTAssertEqual(clamped.minX, 800)
        XCTAssertEqual(clamped.width, 200)
    }

    func testSelectionCompletelyOutsideReturnsZero() {
        let rect = CGRect(x: -500, y: 100, width: 300, height: 150)
        let clamped = V2RecordingGeometry.clampedSourceRect(
            local: rect, screenPointSize: CGSize(width: 1000, height: 800))
        XCTAssertEqual(clamped, .zero, "完全在屏外的选区应返回 .zero，由调用方放弃录制")
    }

    // MARK: - AppKit 全局坐标转换

    func testLocalToAppKitGlobalOnMainScreen() {
        // 主屏 frame (0,0,1000,800)；局部选区左上 (100,200)、尺寸 300×150
        // → 全局左下原点：x = 0+100 = 100；顶边 = 800-200 = 600；y = 600-150 = 450
        let local = CGRect(x: 100, y: 200, width: 300, height: 150)
        let global = V2RecordingGeometry.appKitGlobalRect(
            local: local, screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        XCTAssertEqual(global.minX, 100)
        XCTAssertEqual(global.minY, 450)
        XCTAssertEqual(global.width, 300)
        XCTAssertEqual(global.height, 150)
    }

    func testLocalToAppKitGlobalOnSecondaryScreen() {
        // 副屏全局 frame (1000,-200,1200,900)；局部选区 (50,100,400,200)
        // → x = 1000+50 = 1050；y = (-200+900) - (100+200) = 700-300 = 400
        let local = CGRect(x: 50, y: 100, width: 400, height: 200)
        let global = V2RecordingGeometry.appKitGlobalRect(
            local: local, screenFrame: CGRect(x: 1000, y: -200, width: 1200, height: 900))
        XCTAssertEqual(global.minX, 1050)
        XCTAssertEqual(global.minY, 400)
    }

    // MARK: - 输出像素尺寸（偶数）

    func testPixelSizeRetinaEvenRounding() {
        // 300.5 × 2 = 601 → 收敛到偶数 600
        let size = V2RecordingGeometry.pixelSize(
            for: CGSize(width: 300.5, height: 151), scale: 2.0)
        XCTAssertEqual(size.width, 600)
        XCTAssertEqual(size.height, 302)
    }

    func testPixelSizeOneXDisplay() {
        let size = V2RecordingGeometry.pixelSize(
            for: CGSize(width: 801, height: 603), scale: 1.0)
        XCTAssertEqual(size.width, 800)
        XCTAssertEqual(size.height, 602)
    }

    func testPixelSizeNeverBelowTwo() {
        let size = V2RecordingGeometry.pixelSize(
            for: CGSize(width: 1, height: 0.5), scale: 1.0)
        XCTAssertEqual(size.width, 2)
        XCTAssertEqual(size.height, 2)
    }

    // MARK: - 码率

    func testBitRate720p() {
        // 1280×720×30 × 0.22 ≈ 6.08 Mbps
        let rate = V2RecordingGeometry.recommendedBitRate(pixelWidth: 1280, pixelHeight: 720, fps: 30)
        XCTAssertEqual(rate, 6_082_560)
    }

    func testBitRateClampedToMinimum() {
        let rate = V2RecordingGeometry.recommendedBitRate(pixelWidth: 64, pixelHeight: 64, fps: 10)
        XCTAssertEqual(rate, 2_000_000)
    }

    func testBitRateClampedToMaximum() {
        // 6K 整屏会超过 H.264 硬编 4096×2304 上限——M1 靠选区尺寸天然规避，但码率钳制仍需兜底
        let rate = V2RecordingGeometry.recommendedBitRate(pixelWidth: 6016, pixelHeight: 3384, fps: 60)
        XCTAssertEqual(rate, 20_000_000)
    }
}
