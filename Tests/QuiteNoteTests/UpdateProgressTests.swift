import XCTest
import SwiftUI
@testable import QuiteNote

/// 顶栏更新按钮的圆环进度（2026-11-28）：
/// 进度与百分比是纯函数；转发壳用替身 driver 验证"每条回调都转发了、阶段抄送对了"；
/// 视图离屏渲染后采样像素——断言全过不等于看得见，所以圆环画到哪、中间有没有字都量出来。
/// 设置 QN_BADGE_RENDER_DIR=<目录> 时把各阶段的渲染图存成 PNG 供人眼复核。
@MainActor
final class UpdateProgressTests: XCTestCase {

    // MARK: - 进度 / 百分比 / 提示文字

    func testFractionAndPercentText() throws {
        XCTAssertNil(UpdateProgressMath.fraction(for: .idle), "idle 没有进度可画")
        XCTAssertNil(UpdateProgressMath.fraction(for: .downloading(received: 10, expected: 0)), "总长度未知时是不确定态")
        XCTAssertNil(UpdateProgressMath.percentText(for: .downloading(received: 10, expected: 0)), "不知道总量就不显示百分比")

        XCTAssertEqual(UpdateProgressMath.fraction(for: .downloading(received: 0, expected: 100)), 0)
        XCTAssertEqual(UpdateProgressMath.fraction(for: .downloading(received: 42, expected: 100)), 0.42)
        XCTAssertEqual(UpdateProgressMath.fraction(for: .extracting(progress: 0.7)), 1, "解压阶段圆环保持满环，不跟着解压进度回退")
        XCTAssertEqual(UpdateProgressMath.fraction(for: .extracting(progress: 0)), 1)
        XCTAssertEqual(UpdateProgressMath.fraction(for: .readyToInstall), 1)
        XCTAssertEqual(UpdateProgressMath.fraction(for: .installing), 1)

        // 收到的比预期多（多出来的尾部数据）不能画出超过一圈的环
        XCTAssertEqual(UpdateProgressMath.fraction(for: .downloading(received: 130, expected: 100)), 1)

        XCTAssertEqual(UpdateProgressMath.percentText(for: .downloading(received: 0, expected: 12_095_127)), "0%")
        XCTAssertEqual(UpdateProgressMath.percentText(for: .downloading(received: 5_120_000, expected: 12_095_127)), "42%")
        XCTAssertEqual(UpdateProgressMath.percentText(for: .downloading(received: 12_095_127, expected: 12_095_127)), "100%")
        XCTAssertNil(UpdateProgressMath.percentText(for: .extracting(progress: 0.5)), "解压阶段不显示百分比（中间转圈）")
        XCTAssertNil(UpdateProgressMath.percentText(for: .readyToInstall))
    }

    func testStatusTextAndActiveState() {
        XCTAssertEqual(UpdateProgressMath.statusText(for: .idle, version: "1.7.3"), "发现新版本 1.7.3，点击更新")
        XCTAssertEqual(UpdateProgressMath.statusText(for: .downloading(received: 42, expected: 100), version: nil), "正在下载更新 42%")
        XCTAssertEqual(UpdateProgressMath.statusText(for: .downloading(received: 0, expected: 0), version: nil), "正在下载更新…")
        XCTAssertEqual(UpdateProgressMath.statusText(for: .installing, version: nil), "正在安装更新…")

        XCTAssertFalse(UpdateDownloadPhase.idle.isActive, "idle 时按钮可以点")
        for phase in [UpdateDownloadPhase.downloading(received: 1, expected: 2), .extracting(progress: 0), .readyToInstall, .installing] {
            XCTAssertTrue(phase.isActive, "\(phase) 进行中按钮不再响应点击")
        }
    }

    // MARK: - 转发壳：阶段抄送 + 每条回调原样转发

    func testDriverReportsDownloadPhasesAndForwardsEverything() {
        let spy = SpyDriver()
        var phases: [UpdateDownloadPhase] = []
        let driver = UpdateProgressUserDriver(forwarding: spy) { phases.append($0) }

        driver.showUserInitiatedUpdateCheck(cancellation: {})
        driver.showUpdateFound(with: dummy(), state: dummy(), reply: { _ in })
        XCTAssertEqual(phases, [], "检查 / 发现新版阶段还没开始下载，不动进度")

        driver.showDownloadInitiated(cancellation: {})
        XCTAssertEqual(phases.last, .downloading(received: 0, expected: 0), "一开始不知道总长度")

        driver.showDownloadDidReceiveExpectedContentLength(1000)
        XCTAssertEqual(phases.last, .downloading(received: 0, expected: 1000))

        driver.showDownloadDidReceiveData(ofLength: 300)
        driver.showDownloadDidReceiveData(ofLength: 200)
        XCTAssertEqual(phases.last, .downloading(received: 500, expected: 1000), "按收到的字节累加")
        XCTAssertEqual(UpdateProgressMath.percentText(for: phases.last ?? .idle), "50%")

        driver.showDownloadDidStartExtractingUpdate()
        XCTAssertEqual(phases.last, .extracting(progress: 0))
        driver.showExtractionReceivedProgress(0.4)
        XCTAssertEqual(phases.last, .extracting(progress: 0.4))

        driver.showReady(toInstallAndRelaunch: { _ in })
        XCTAssertEqual(phases.last, .readyToInstall)
        driver.showInstallingUpdate(withApplicationTerminated: false, retryTerminatingApplication: {})
        XCTAssertEqual(phases.last, .installing)
        driver.showUpdateInstalledAndRelaunched(true, acknowledgement: {})
        XCTAssertEqual(phases.last, .idle, "装完回到 idle")

        // 下载途中出错 → 回到 idle，按钮恢复成可点的上箭头
        driver.showDownloadInitiated(cancellation: {})
        driver.showDownloadDidReceiveExpectedContentLength(50)
        driver.showUpdaterError(NSError(domain: "test", code: 1), acknowledgement: {})
        XCTAssertEqual(phases.last, .idle)

        // 关掉 Sparkle 的窗口同样回到 idle，并且下一轮下载从 0 重新计数
        driver.showDownloadInitiated(cancellation: {})
        driver.showDownloadDidReceiveData(ofLength: 5)
        driver.dismissUpdateInstallation()
        XCTAssertEqual(phases.last, .idle)
        driver.showDownloadInitiated(cancellation: {})
        XCTAssertEqual(phases.last, .downloading(received: 0, expected: 0), "新一轮下载不能带着上一轮的字节数")

        // 剩下的回调也要到标准界面那边（漏转一条 = 对应弹窗消失）
        driver.show(dummy(), reply: { _ in })
        driver.showUpdateReleaseNotes(with: dummy())
        driver.showUpdateReleaseNotesFailedToDownloadWithError(NSError(domain: "test", code: 2))
        driver.showUpdateNotFoundWithError(NSError(domain: "test", code: 3), acknowledgement: {})
        driver.showUpdateInFocus()
        // showUpdateInFocus 在 Sparkle 里是可选协议方法：Sparkle 用 ObjC 运行时问"响应不响应"，
        // 转发壳没写 @objc 时这里会是 false，更新窗口就不会被置顶
        XCTAssertTrue(driver.responds(to: NSSelectorFromString("showUpdateInFocus")), "可选协议方法必须暴露给 ObjC 运行时")
        XCTAssertEqual(spy.calls, [
            "check", "found",
            "downloadInitiated", "expected(1000)", "data(300)", "data(200)", "extracting", "extractProgress(0.4)",
            "ready", "installing(false)", "installed(true)",
            "downloadInitiated", "expected(50)", "error",
            "downloadInitiated", "data(5)", "dismiss", "downloadInitiated",
            "permission", "notes", "notesFailed", "notFound", "focus",
        ])
    }

    // MARK: - 看得见：离屏渲染后量像素

    private let scale: CGFloat = 8

    private func render(_ phase: UpdateDownloadPhase) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: UpdateProgressBadge(phase: phase))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: UpdateProgressBadge.ringDiameter, height: UpdateProgressBadge.ringDiameter)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        if let dir = ProcessInfo.processInfo.environment["QN_BADGE_RENDER_DIR"] {
            let strip = ImageRenderer(content: HStack(spacing: 14) {
                UpdateProgressBadge(phase: .idle)
                UpdateProgressBadge(phase: phase)
                Text(UpdateProgressMath.statusText(for: phase, version: "9.9.9"))
                    .font(.themeCaption)
                    .foregroundColor(.themeTextPrimary)
                    .padding(.trailing, 12)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(red: 0.12, green: 0.12, blue: 0.12)))
            strip.scale = 4
            if let image = strip.nsImage, let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                let name = String(describing: phase).replacingOccurrences(of: "(", with: "-").replacingOccurrences(of: ")", with: "")
                    .replacingOccurrences(of: ", ", with: "_").replacingOccurrences(of: " ", with: "_")
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try? png.write(to: URL(fileURLWithPath: "\(dir)/preview-\(name).png"))
            }
            let name = String(describing: phase).replacingOccurrences(of: "(", with: "-").replacingOccurrences(of: ")", with: "")
                .replacingOccurrences(of: ", ", with: "_").replacingOccurrences(of: " ", with: "_")
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/badge-\(name).png"))
        }
        return rep
    }

    /// 以左上角为原点的逻辑坐标（pt）处像素：(alpha, min(r,b), max(r,b))；不关心通道顺序
    private func pixel(x: CGFloat, y: CGFloat, in rep: NSBitmapImageRep) -> (alpha: CGFloat, low: CGFloat, high: CGFloat) {
        let px = Int((x * scale).rounded(.down)), py = Int((y * scale).rounded(.down))
        guard let c = rep.colorAt(x: px, y: py) else { return (0, -1, -1) }
        let r = c.redComponent * 255, b = c.blueComponent * 255
        return (c.alphaComponent, min(r, b), max(r, b))
    }

    /// 圆环上的点：角度从 12 点方向顺时针量
    private func ringPoint(degrees: Double) -> (x: CGFloat, y: CGFloat) {
        let c = UpdateProgressBadge.ringDiameter / 2
        let radius = c - 1.25   // 圆环描边的中心线
        let a = degrees * .pi / 180
        return (c + radius * CGFloat(sin(a)), c - radius * CGFloat(cos(a)))
    }

    private func opaquePixelCount(insideRadius radius: CGFloat, in rep: NSBitmapImageRep) -> Int {
        let c = UpdateProgressBadge.ringDiameter / 2
        var count = 0
        var y: CGFloat = 0
        while y <= UpdateProgressBadge.ringDiameter {
            var x: CGFloat = 0
            while x <= UpdateProgressBadge.ringDiameter {
                if hypot(x + 0.5 / scale - c, y + 0.5 / scale - c) < radius, pixel(x: x, y: y, in: rep).alpha > 0.5 { count += 1 }
                x += 1 / scale
            }
            y += 1 / scale
        }
        return count
    }

    /// 进度弧的颜色：蓝色、不透明（浅色轨道是 10% 白，不算）
    private func isProgressArc(_ p: (alpha: CGFloat, low: CGFloat, high: CGFloat)) -> Bool {
        p.alpha > 0.3 && p.low < 110 && p.high > 150
    }

    /// 内圆（半径 radius 以内）里不透明像素的占比
    private func opaqueRatio(insideRadius radius: CGFloat, in rep: NSBitmapImageRep) -> Double {
        let c = UpdateProgressBadge.ringDiameter / 2
        var opaque = 0, total = 0
        var y: CGFloat = 0
        while y <= UpdateProgressBadge.ringDiameter {
            var x: CGFloat = 0
            while x <= UpdateProgressBadge.ringDiameter {
                if hypot(x + 0.5 / scale - c, y + 0.5 / scale - c) < radius {
                    total += 1
                    if pixel(x: x, y: y, in: rep).alpha > 0.5 { opaque += 1 }
                }
                x += 1 / scale
            }
            y += 1 / scale
        }
        return total == 0 ? 0 : Double(opaque) / Double(total)
    }

    /// 圆环上从 12 点方向顺时针扫过 sweep 度的若干个采样点里，属于进度弧的占比
    private func arcCoverage(sweepDegrees sweep: Double, in rep: NSBitmapImageRep) -> Double {
        let samples = stride(from: 2.0, to: sweep - 2, by: 2.0)
        var hit = 0, total = 0
        for degrees in samples {
            let p = ringPoint(degrees: degrees)
            total += 1
            if isProgressArc(pixel(x: p.x, y: p.y, in: rep)) { hit += 1 }
        }
        return total == 0 ? 0 : Double(hit) / Double(total)
    }

    func testIdleBadgeIsTheFilledBlueArrowButtonWithoutRing() throws {
        let rep = try XCTUnwrap(render(.idle))
        // 实心圆钮：圆心附近大半像素都是蓝色（箭头是白的，所以不要求 100%）
        let c = UpdateProgressBadge.ringDiameter / 2
        XCTAssertTrue(isProgressArc(pixel(x: c, y: c - 8, in: rep)), "箭头上方仍是蓝底")
        XCTAssertGreaterThan(opaqueRatio(insideRadius: 9, in: rep), 0.95, "待机态是实心圆钮")
        // 26pt 的边上是圆环的位置；待机态圆钮只有 22pt，这里必须什么都没有
        let ring = ringPoint(degrees: 90)
        XCTAssertEqual(pixel(x: ring.x, y: ring.y, in: rep).alpha, 0, "没开始下载时没有圆环，连轨道也不画")
    }

    func testRingGrowsWithProgressAndCenterShowsPercent() throws {
        let half = try XCTUnwrap(render(.downloading(received: 1, expected: 2)))
        XCTAssertGreaterThan(arcCoverage(sweepDegrees: 80, in: half), 0.9, "50%：12 点到 3 点这一段都是进度弧")
        XCTAssertEqual(arcCoverage(sweepDegrees: 0, in: half), 0)
        for degrees in [200.0, 270, 350] {
            let p = ringPoint(degrees: degrees)
            XCTAssertFalse(isProgressArc(pixel(x: p.x, y: p.y, in: half)), "50%：\(degrees)° 还没画到（只剩浅色轨道）")
        }
        XCTAssertLessThan(opaqueRatio(insideRadius: 8, in: half), 0.5, "下载中圆钮不再实心填充，内圆里只有百分比数字")

        let quarter = try XCTUnwrap(render(.downloading(received: 1, expected: 4)))
        XCTAssertGreaterThan(arcCoverage(sweepDegrees: 80, in: quarter), 0.9, "25%：弧到 3 点为止")
        for degrees in [100.0, 170, 270] {
            let p = ringPoint(degrees: degrees)
            XCTAssertFalse(isProgressArc(pixel(x: p.x, y: p.y, in: quarter)), "25%：\(degrees)° 还没画到")
        }
        XCTAssertGreaterThan(opaqueRatio(insideRadius: 8, in: quarter), 0.08, "圆环中间画了百分比数字（不是空的）")

        // 刚开始和临近结束的极端：弧很短 / 几乎满圈，数字仍要画出来
        let start = try XCTUnwrap(render(.downloading(received: 1, expected: 10_000)))
        XCTAssertFalse(isProgressArc(pixel(x: ringPoint(degrees: 60).x, y: ringPoint(degrees: 60).y, in: start)))
        XCTAssertGreaterThan(opaqueRatio(insideRadius: 8, in: start), 0.08, "0% 也要有数字")
        let full = try XCTUnwrap(render(.downloading(received: 9_999, expected: 10_000)))
        XCTAssertGreaterThan(arcCoverage(sweepDegrees: 350, in: full), 0.9, "99%：几乎满圈")
        XCTAssertGreaterThan(opaqueRatio(insideRadius: 8, in: full), 0.08, "99% 的数字放得下")

        // 总长度未知：轨道空着，中间转圈（没有任何百分比数字）
        let unknown = try XCTUnwrap(render(.downloading(received: 0, expected: 0)))
        XCTAssertEqual(arcCoverage(sweepDegrees: 350, in: unknown), 0)
        let spinnerRatio = opaqueRatio(insideRadius: 8, in: unknown)
        XCTAssertGreaterThan(spinnerRatio, 0.02, "中间有转圈指示")
        XCTAssertLessThan(spinnerRatio, 0.3, "转圈只是一个小弧，不该铺满内圆")
    }

    func testLaterStagesKeepTheRingFullAndDropThePercent() throws {
        for phase in [UpdateDownloadPhase.extracting(progress: 0.3), .installing] {
            let rep = try XCTUnwrap(render(phase))
            XCTAssertGreaterThan(arcCoverage(sweepDegrees: 356, in: rep), 0.9, "\(phase)：圆环保持满环")
            let spinnerRatio = opaqueRatio(insideRadius: 8, in: rep)
            XCTAssertGreaterThan(spinnerRatio, 0.02, "\(phase)：中间有转圈指示")
            XCTAssertLessThan(spinnerRatio, 0.3, "\(phase)：转圈只是一个小弧")
            XCTAssertNil(UpdateProgressMath.percentText(for: phase))
        }
        // 就绪待安装：满环 + 回到箭头（提示去 Sparkle 窗口点安装并重启）
        let ready = try XCTUnwrap(render(.readyToInstall))
        XCTAssertGreaterThan(arcCoverage(sweepDegrees: 356, in: ready), 0.9)
        XCTAssertFalse(isProgressArc(pixel(x: 13, y: 13, in: ready)), "箭头不是蓝的，中间留给箭头")
        XCTAssertGreaterThan(opaqueRatio(insideRadius: 8, in: ready), 0.08, "中间画了箭头")
    }
}

#if !APP_STORE
import Sparkle

/// Sparkle 的这几个类没有公开构造器；替身只记录调用、不读参数，拿一个 NSObject 顶替即可
@MainActor
private func dummy<T: NSObject>() -> T { unsafeBitCast(NSObject(), to: T.self) }

/// 记录调用的 SPUUserDriver 替身
@MainActor
private final class SpyDriver: NSObject, SPUUserDriver {
    var calls: [String] = []

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) { calls.append("permission") }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { calls.append("check") }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) { calls.append("found") }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) { calls.append("notes") }
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) { calls.append("notesFailed") }
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { calls.append("notFound") }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { calls.append("error") }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { calls.append("downloadInitiated") }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { calls.append("expected(\(expectedContentLength))") }
    func showDownloadDidReceiveData(ofLength length: UInt64) { calls.append("data(\(length))") }
    func showDownloadDidStartExtractingUpdate() { calls.append("extracting") }
    func showExtractionReceivedProgress(_ progress: Double) { calls.append("extractProgress(\(progress))") }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { calls.append("ready") }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) { calls.append("installing(\(applicationTerminated))") }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { calls.append("installed(\(relaunched))") }
    func dismissUpdateInstallation() { calls.append("dismiss") }
    @objc func showUpdateInFocus() { calls.append("focus") }
}
#endif
