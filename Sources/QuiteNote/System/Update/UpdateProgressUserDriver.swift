//
//  UpdateProgressUserDriver.swift
//  QuiteNote
//
//  顶栏更新按钮的圆环进度从哪来：包在 Sparkle 标准界面外面的一层转发壳。
//

import Foundation
import Sparkle

/// 更新下载 / 安装进行到哪一步。驱动主面板顶栏更新按钮的样子（圆环 + 百分比）。
/// 纯数据，不依赖 Sparkle（App Store 沙盒版也能用这个类型）。
enum UpdateDownloadPhase: Equatable {
    case idle
    /// 下载中；`expected <= 0` 表示还不知道总长度（画不确定态）
    case downloading(received: Int64, expected: Int64)
    /// 下载完、解压中（0…1）
    case extracting(progress: Double)
    /// 解压完，等用户在 Sparkle 的窗口里点「安装并重新启动」
    case readyToInstall
    /// 正在安装（应用即将退出重启）
    case installing

    /// 下载/安装流程是否还在进行（进行中按钮不再响应点击）
    var isActive: Bool { self != .idle }
}

/// 圆环和百分比的计算，纯函数，便于单测。
enum UpdateProgressMath {
    /// 圆环画到哪（0…1）。总长度未知时为 nil。
    static func fraction(for phase: UpdateDownloadPhase) -> Double? {
        switch phase {
        case .idle:
            return nil
        case .downloading(let received, let expected):
            guard expected > 0 else { return nil }
            return clamp01(Double(received) / Double(expected))
        case .extracting:
            // 下载已走满一圈；解压阶段圆环保持满环（中间转圈），不要从 100% 跳回去再走一遍
            return 1
        case .readyToInstall, .installing:
            return 1
        }
    }

    /// 圆环中间的文字：下载中且知道总长度时是百分比（"42%"），其余情况 nil（调用方画别的）。
    static func percentText(for phase: UpdateDownloadPhase) -> String? {
        guard case .downloading = phase, let fraction = fraction(for: phase) else { return nil }
        return "\(Int((fraction * 100).rounded()))%"
    }

    /// 悬停提示 / 无障碍标签
    static func statusText(for phase: UpdateDownloadPhase, version: String?) -> String {
        switch phase {
        case .idle:
            return "发现新版本 \(version ?? "")，点击更新"
        case .downloading:
            if let percent = percentText(for: phase) {
                return "正在下载更新 \(percent)"
            }
            return "正在下载更新…"
        case .extracting:
            return "更新已下载，正在解压…"
        case .readyToInstall:
            return "更新已就绪，请在更新窗口里点「安装并重新启动」"
        case .installing:
            return "正在安装更新…"
        }
    }

    private static func clamp01(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 0, 0), 1)
    }
}

#if !APP_STORE

/// 转发壳：`SPUUpdater` 的 user driver 换成它，它把每一条回调原样转给 Sparkle 的标准界面
/// （弹窗、安装确认都还是 Sparkle 的），只把下载进度抄送一份给 App。
///
/// Sparkle 的协议约定所有回调都在主线程。
@MainActor
final class UpdateProgressUserDriver: NSObject, SPUUserDriver {
    private let forwarding: any SPUUserDriver
    private let onPhaseChange: (UpdateDownloadPhase) -> Void
    private var expectedLength: Int64 = 0
    private var receivedLength: Int64 = 0

    /// - Parameters:
    ///   - forwarding: 真正干活的界面（生产 = `SPUStandardUserDriver`，单测 = 记录调用的替身）
    ///   - onPhaseChange: 阶段变化时调用（主线程）
    init(forwarding: any SPUUserDriver, onPhaseChange: @escaping (UpdateDownloadPhase) -> Void) {
        self.forwarding = forwarding
        self.onPhaseChange = onPhaseChange
        super.init()
    }

    /// 生产用：转发给 Sparkle 标准界面。
    convenience init(hostBundle: Bundle,
                     delegate: (any SPUStandardUserDriverDelegate)?,
                     onPhaseChange: @escaping (UpdateDownloadPhase) -> Void) {
        self.init(forwarding: SPUStandardUserDriver(hostBundle: hostBundle, delegate: delegate),
                  onPhaseChange: onPhaseChange)
    }

    private var downloadPhase: UpdateDownloadPhase {
        .downloading(received: receivedLength, expected: expectedLength)
    }

    // MARK: - 下载 / 安装进度：抄送一份，再原样转发

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedLength = 0
        receivedLength = 0
        onPhaseChange(downloadPhase)
        forwarding.showDownloadInitiated(cancellation: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = Int64(min(expectedContentLength, UInt64(Int64.max)))
        onPhaseChange(downloadPhase)
        forwarding.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        let (sum, overflow) = receivedLength.addingReportingOverflow(Int64(min(length, UInt64(Int64.max))))
        receivedLength = overflow ? Int64.max : sum
        onPhaseChange(downloadPhase)
        forwarding.showDownloadDidReceiveData(ofLength: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        onPhaseChange(.extracting(progress: 0))
        forwarding.showDownloadDidStartExtractingUpdate()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        onPhaseChange(.extracting(progress: progress))
        forwarding.showExtractionReceivedProgress(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        onPhaseChange(.readyToInstall)
        forwarding.showReady(toInstallAndRelaunch: reply)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        onPhaseChange(.installing)
        forwarding.showInstallingUpdate(withApplicationTerminated: applicationTerminated,
                                        retryTerminatingApplication: retryTerminatingApplication)
    }

    // MARK: - 流程结束 / 出错 / 被关掉：回到 idle

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        onPhaseChange(.idle)
        forwarding.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }

    func dismissUpdateInstallation() {
        onPhaseChange(.idle)
        forwarding.dismissUpdateInstallation()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        onPhaseChange(.idle)
        forwarding.showUpdaterError(error, acknowledgement: acknowledgement)
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        onPhaseChange(.idle)
        forwarding.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
    }

    // MARK: - 其余回调：原样转发

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        forwarding.show(request, reply: reply)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        forwarding.showUserInitiatedUpdateCheck(cancellation: cancellation)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        forwarding.showUpdateFound(with: appcastItem, state: state, reply: reply)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        forwarding.showUpdateReleaseNotes(with: downloadData)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        forwarding.showUpdateReleaseNotesFailedToDownloadWithError(error)
    }

    // Sparkle 把这一条列为可选方法（@optional）：必须显式 @objc 才会通过 ObjC 运行时被调到，
    // 否则用户点 Dock / 状态栏图标时更新窗口不会置顶
    @objc func showUpdateInFocus() {
        forwarding.showUpdateInFocus?()
    }
}

#endif
