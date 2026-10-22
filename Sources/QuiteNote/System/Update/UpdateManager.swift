import Foundation
import Sparkle
import Combine

/// 应用在线更新管理器（Sparkle 封装，单例）。
///
/// 三个消费方：状态栏菜单「检查更新…」、设置页「检查更新」按钮、
/// 主面板顶栏的蓝色更新按钮（有新版本时才出现）。
/// 更新清单 = https://dyyz1993.github.io/quite-note/appcast.xml（CI 发版时自动刷新）。
final class UpdateManager: NSObject, ObservableObject {
    static let shared = UpdateManager()

    /// Sparkle 核心驱动。懒创建：测试进程/单元测试上下文不触碰 updater。
    #if !APP_STORE
    private lazy var updater: SPUUpdater = {
        let driver = SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil)
        let updater = SPUUpdater(hostBundle: Bundle.main, applicationBundle: Bundle.main, userDriver: driver, delegate: self)
        try? updater.start()
        return updater
    }()
    #endif

    /// 是否检测到新版本（驱动主面板顶栏更新按钮的显隐）
    @Published private(set) var updateAvailable = false
    /// 待安装的新版本号（如 "1.5.0"，无则 nil）
    @Published private(set) var availableVersion: String?
    /// 手动检查进行中（按钮转圈）
    @Published private(set) var checkInProgress = false

    /// 当前版本号（与 Info.plist 同源）
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    /// 启动静默检查（App 启动完成后调用一次；Sparkle 自身按 SUAutomaticallyUpdate/周期调度）
    func startBackgroundChecks() {
        #if !APP_STORE
        _ = updater
        #endif
    }

    /// 手动检查更新（菜单/设置页/顶栏按钮）。无新版时 Sparkle 弹「已是最新」提示。
    /// App Store 沙盒版：Sparkle 不可用，直接弹「已是最新」不触发检查。
    func checkForUpdates() {
        #if APP_STORE
        let alert = NSAlert()
        alert.messageText = "已是最新版本"
        alert.informativeText = "当前版本 \(currentVersion)（App Store 版更新请前往 App Store）"
        alert.addButton(withTitle: "确定")
        alert.runModal()
        #else
        checkInProgress = true
        updater.checkForUpdates()
        #endif
    }

    fileprivate func updaterDidFindUpdate(_ version: String?) {
        availableVersion = version
        updateAvailable = version != nil
        checkInProgress = false
    }

    fileprivate func updaterDidFinishCheck() {
        checkInProgress = false
    }
}

extension UpdateManager: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updaterDidFindUpdate(item.displayVersionString.isEmpty ? item.versionString : item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        updaterDidFindUpdate(nil)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        updaterDidFinishCheck()
    }
}
