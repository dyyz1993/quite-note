import AppKit
import SwiftUI
import Combine

/// 菜单栏图标与菜单管理，含快捷入口与状态指示
final class StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store: RecordStore
    private let bluetooth: BluetoothManager
    private let toggleAction: () -> Void
    private var cancellables = Set<AnyCancellable>()

    /// 初始化状态栏与菜单结构
    init(store: RecordStore, bluetooth: BluetoothManager, toggleAction: @escaping () -> Void) {
        self.store = store
        self.bluetooth = bluetooth
        self.toggleAction = toggleAction
        setupMenu()
        
        store.$enableAI
            .sink { [weak self] _ in self?.setupMenu() }
            .store(in: &cancellables)
    }

    /// 构建菜单与状态更新
    private func setupMenu() {
        statusItem.button?.title = "📝"
        let menu = NSMenu()
        menu.autoenablesItems = false
        let btTitle = bluetooth.connectedDeviceName != nil ? "蓝牙：已连接 \(bluetooth.connectedDeviceName!)" : "蓝牙：未连接"
        let info = NSMenuItem(title: btTitle, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        let toggle = NSMenuItem(title: "显示/隐藏悬浮窗", action: #selector(onToggle), keyEquivalent: "r")
        toggle.keyEquivalentModifierMask = [.option, .command]
        toggle.target = self
        toggle.isEnabled = true
        menu.addItem(toggle)
        let capture = NSMenuItem(title: "采集当前剪贴板", action: #selector(onCapture), keyEquivalent: "c")
        capture.keyEquivalentModifierMask = [.option, .command]
        capture.target = self
        capture.isEnabled = true
        menu.addItem(capture)
        let bulk = NSMenuItem(title: "批量重新提炼（3条）", action: #selector(onBulkSummarize), keyEquivalent: "a")
        bulk.keyEquivalentModifierMask = [.option, .command]
        bulk.target = self
        bulk.isEnabled = true
        menu.addItem(bulk)
        let aiToggle = NSMenuItem(title: store.enableAI ? "AI 自动提炼：开启" : "AI 自动提炼：关闭", action: #selector(onToggleAI), keyEquivalent: "a")
        aiToggle.keyEquivalentModifierMask = [.shift, .option, .command]
        aiToggle.target = self
        aiToggle.isEnabled = true
        menu.addItem(aiToggle)
        let export = NSMenuItem(title: "导出所有记录为 Markdown", action: #selector(onExport), keyEquivalent: "e")
        export.keyEquivalentModifierMask = [.option, .command]
        export.target = self
        export.isEnabled = true
        menu.addItem(export)
        menu.addItem(NSMenuItem.separator())
        let prefs = NSMenuItem(title: "偏好设置", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        prefs.isEnabled = true
        menu.addItem(prefs)
        let quit = NSMenuItem(title: "退出应用", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.isEnabled = true
        menu.addItem(quit)
        statusItem.menu = menu
    }

    /// 菜单：显示/隐藏悬浮窗
    @objc private func onToggle() { toggleAction() }

    /// 菜单：打开设置
    @objc private func openSettings() { NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) }

    /// 菜单：退出应用
    @objc private func quit() { NSApp.terminate(nil) }

    /// 菜单：批量重新提炼
    @objc private func onBulkSummarize() { store.bulkResummarize() }

    /// 菜单：导出所有记录为 Markdown 到桌面
    @objc private func onExport() {
        let md = store.exportMarkdown()
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let url = desktop.appendingPathComponent("QuiteNote_Export.md")
        try? md.write(to: url, atomically: true, encoding: .utf8)
        store.postLightHint("已导出到桌面：QuiteNote_Export.md")
    }

    /// 菜单：采集剪贴板（触发与硬件按钮一致的逻辑）
    @objc private func onCapture() { NotificationCenter.default.post(name: .bluetoothCaptureClipboard, object: nil) }

    @objc private func onToggleAI() {
        store.enableAI.toggle()
        store.savePreferences()
        store.postToast(store.enableAI ? "AI 已开启" : "AI 已关闭")
        setupMenu()
    }
}
