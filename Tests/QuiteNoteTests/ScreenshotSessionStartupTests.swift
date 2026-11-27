import XCTest
import AppKit
@testable import QuiteNote

/// 截图会话启动链路的纯逻辑（2026-11-27）：截屏挪到后台并行后，
/// 就绪进度、key 面板判定、鼠标所在屏、底图生成都不依赖真屏幕 / 真截屏。
/// 不调用 show()——它会在真屏幕上铺全屏面板。
@MainActor
final class ScreenshotSessionStartupTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TestStorageIsolation.activate
    }

    // MARK: - 截屏就绪进度

    /// 双屏：第一块就绪不算全部就绪；首屏时刻不被后来的屏覆盖
    func testProgressIsCompleteOnlyWhenEveryScreenIsReady() {
        var progress = V2ScreenshotController.CaptureProgress(total: 2)
        XCTAssertFalse(progress.isComplete)

        XCTAssertFalse(progress.markReady(at: 0.08), "第一块屏就绪不算全部就绪")
        XCTAssertEqual(progress.ready, 1)
        XCTAssertEqual(progress.firstReadyAt, 0.08)

        XCTAssertTrue(progress.markReady(at: 0.31), "最后一块屏就绪才算全部就绪")
        XCTAssertTrue(progress.isComplete)
        XCTAssertEqual(progress.firstReadyAt, 0.08)
    }

    /// 单屏：第一块就绪即全部就绪
    func testSingleScreenIsCompleteOnFirstReady() {
        var progress = V2ScreenshotController.CaptureProgress(total: 1)
        XCTAssertTrue(progress.markReady(at: 0.12))
        XCTAssertTrue(progress.isComplete)
    }

    // MARK: - 距会话开始的毫秒数（"遮罩首帧 / 上屏"日志用）

    func testMillisecondsSinceSessionStartIsNegativeWithoutSession() {
        XCTAssertNil(V2ScreenshotController.sessionStartedAt)
        XCTAssertEqual(V2ScreenshotController.msSinceSessionStart(), -1, "没有进行中的会话应返回 -1")
    }

    func testMillisecondsSinceSessionStartCountsFromSessionStart() {
        let started = DispatchTime.now() - DispatchTimeInterval.milliseconds(1500)
        V2ScreenshotController.sessionStartedAtForTesting = started
        defer { V2ScreenshotController.sessionStartedAtForTesting = nil }

        let later = started + DispatchTimeInterval.milliseconds(830)
        XCTAssertEqual(V2ScreenshotController.msSinceSessionStart(now: later), 830)
        XCTAssertEqual(V2ScreenshotController.msSinceSessionStart(now: started), 0)
    }

    // MARK: - 看门狗激活限频（系统拒绝激活时 activate 会同步阻塞，不能每秒盲敲）

    func testWatchdogRetriesActivationOnlyAfterInterval() {
        let first = DispatchTime.now()
        XCTAssertTrue(V2ScreenshotController.shouldRetryActivation(now: first, last: nil), "还没试过：要试")
        XCTAssertFalse(V2ScreenshotController.shouldRetryActivation(now: first, last: first), "刚试过：不试")

        let justBefore = first + DispatchTimeInterval.milliseconds(Int(V2ScreenshotController.watchdogActivationInterval * 1000) - 50)
        XCTAssertFalse(V2ScreenshotController.shouldRetryActivation(now: justBefore, last: first), "间隔没满：不试")

        let due = first + DispatchTimeInterval.seconds(Int(V2ScreenshotController.watchdogActivationInterval))
        XCTAssertTrue(V2ScreenshotController.shouldRetryActivation(now: due, last: first), "满间隔：再试")
    }

    // MARK: - key 面板判定（看门狗只在"没有会话面板是 key"时才补 key）

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    func testNoKeyWindowMeansSessionHasNoKeyPanel() {
        XCTAssertFalse(V2ScreenshotController.sessionPanelIsKey(nil, in: [makeWindow()]))
    }

    /// key 窗口是别的窗口（比如用户切去了别的应用）：需要补 key
    func testKeyWindowOutsideSessionNeedsRefocus() {
        let other = makeWindow()
        XCTAssertFalse(V2ScreenshotController.sessionPanelIsKey(other, in: [makeWindow()]))
    }

    /// 已有会话面板是 key（例如文字工具正在输入的面板）：不能再动它
    func testSessionPanelAlreadyKeyIsLeftAlone() {
        let first = makeWindow()
        let second = makeWindow()
        XCTAssertTrue(V2ScreenshotController.sessionPanelIsKey(second, in: [first, second]))
        XCTAssertTrue(V2ScreenshotController.sessionPanelIsKey(first, in: [first, second]))
        XCTAssertFalse(V2ScreenshotController.sessionPanelIsKey(first, in: []))
    }

    // MARK: - 鼠标所在屏

    func testScreenIndexContainingPoint() {
        let frames = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: 1512, y: 748, width: 1920, height: 1080),
        ]
        XCTAssertEqual(V2ScreenshotController.screenIndex(containing: CGPoint(x: 100, y: 100), frames: frames), 0)
        XCTAssertEqual(V2ScreenshotController.screenIndex(containing: CGPoint(x: 2000, y: 1500), frames: frames), 1)
        // 外接屏比内建屏靠下：两屏纵向重叠的坐标区归 x 所在的那块
        XCTAssertEqual(V2ScreenshotController.screenIndex(containing: CGPoint(x: 1600, y: 800), frames: frames), 1)
        XCTAssertNil(V2ScreenshotController.screenIndex(containing: CGPoint(x: -50, y: -50), frames: frames))
        XCTAssertNil(V2ScreenshotController.screenIndex(containing: .zero, frames: []))
    }

    // MARK: - 底图

    private func makeCGImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Retina 不糊的前提：逻辑尺寸 = 屏幕点尺寸，像素 = 截屏的实际像素
    func testSnapshotImageKeepsLogicalSizeAndPixelDimensions() throws {
        let image = V2ScreenshotController.snapshotImage(from: makeCGImage(width: 100, height: 50),
                                                         logicalSize: CGSize(width: 50, height: 25))
        XCTAssertEqual(image.size, CGSize(width: 50, height: 25))
        let rendered = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(rendered.width, 100)
        XCTAssertEqual(rendered.height, 50)
    }

    /// 截屏失败（nil）也要给一张同尺寸的底图，界面不能崩
    func testSnapshotImageFallsBackToSolidImageWhenCaptureFailed() {
        let image = V2ScreenshotController.snapshotImage(from: nil, logicalSize: CGSize(width: 300, height: 200))
        XCTAssertEqual(image.size, CGSize(width: 300, height: 200))
        XCTAssertNotNil(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }
}
