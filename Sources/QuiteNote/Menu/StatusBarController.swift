import AppKit
import SwiftUI
import Combine

/// 菜单栏图标与菜单管理，含快捷入口与状态指示
final class StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store: RecordStore
    private let bluetooth: BluetoothManager
    private let toggleAction: () -> Void
    private let forceShowAction: () -> Void
    private var cancellables = Set<AnyCancellable>()

    /// 初始化状态栏与菜单结构
    init(store: RecordStore, bluetooth: BluetoothManager, toggleAction: @escaping () -> Void, forceShowAction: @escaping () -> Void) {
        self.store = store
        self.bluetooth = bluetooth
        self.toggleAction = toggleAction
        self.forceShowAction = forceShowAction
        setupMenu()
        
        store.$enableAI
            .sink { [weak self] _ in self?.setupMenu() }
            .store(in: &cancellables)
        
        // 监听记录变化，更新菜单
        store.$records
            .sink { [weak self] _ in self?.setupMenu() }
            .store(in: &cancellables)
    }

    /// 构建菜单与状态更新
    private func setupMenu() {
        // 尝试从多个来源加载图标
        let icon: NSImage? = {
            // 1. 优先尝试加载生成的 PNG
            if let path = Bundle.main.path(forResource: "StatusBarIcon", ofType: "png"),
               let image = NSImage(contentsOfFile: path) {
                image.isTemplate = true
                return image
            }
            // 2. 尝试命名加载
            if let image = NSImage(named: "StatusBarIcon") {
                image.isTemplate = true
                return image
            }
            // 3. 备选方案：系统图标
            let sparkles = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Quite Note")
            sparkles?.isTemplate = true
            return sparkles
        }()

        if let icon = icon {
            // 状态栏标准高度通常为 22pt，图标建议 16x16 或 18x18
            icon.size = NSSize(width: 18, height: 18)
            statusItem.button?.image = icon
            statusItem.button?.imagePosition = .imageLeft
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        // 蓝牙状态信息
        let btTitle = bluetooth.connectedDeviceName != nil ? "蓝牙：已连接 \(bluetooth.connectedDeviceName!)" : "蓝牙：未连接"
        let btInfo = NSMenuItem(title: btTitle, action: nil, keyEquivalent: "")
        btInfo.isEnabled = false
        menu.addItem(btInfo)
        
        // 记录统计信息
        let today = Calendar.current.startOfDay(for: Date())
        let todayRecords = store.records.filter { $0.createdAt >= today }
        let statsTitle = "记录：共 \(store.records.count) 条，今日 \(todayRecords.count) 条"
        let statsInfo = NSMenuItem(title: statsTitle, action: nil, keyEquivalent: "")
        statsInfo.isEnabled = false
        menu.addItem(statsInfo)
        
        menu.addItem(NSMenuItem.separator())
        let toggle = NSMenuItem(title: "显示/隐藏悬浮窗", action: #selector(onToggle), keyEquivalent: "r")
        toggle.keyEquivalentModifierMask = [.option, .command]
        toggle.target = self
        toggle.isEnabled = true
        menu.addItem(toggle)
        
        let force = NSMenuItem(title: "强制显示并居中 (Reset)", action: #selector(onForceShow), keyEquivalent: "R")
        force.keyEquivalentModifierMask = [.option, .command, .shift]
        force.target = self
        force.isEnabled = true
        menu.addItem(force)
        
        let capture = NSMenuItem(title: "采集当前剪贴板", action: #selector(onCapture), keyEquivalent: "c")
        capture.keyEquivalentModifierMask = [.option, .command]
        capture.target = self
        capture.isEnabled = true
        menu.addItem(capture)

        let screenshot = NSMenuItem(title: "捕获屏幕截图", action: #selector(onScreenshot), keyEquivalent: "s")
        screenshot.keyEquivalentModifierMask = [.command, .shift]
        screenshot.target = self
        screenshot.isEnabled = true
        menu.addItem(screenshot)

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
        
        // 最近记录快速访问
        let recentRecords = Array(store.records.sorted(by: { $0.createdAt > $1.createdAt }).prefix(5))
        if !recentRecords.isEmpty {
            let recentHeader = NSMenuItem(title: "最近记录", action: nil, keyEquivalent: "")
            recentHeader.isEnabled = false
            menu.addItem(recentHeader)
            
            for (index, record) in recentRecords.enumerated() {
                let preview = String(record.content.prefix(30))
                let title = (record.summary?.isEmpty ?? true) ? preview : "\(record.summary?.prefix(30) ?? "")"
                let menuItem = NSMenuItem(title: "\(index + 1). \(title)", action: #selector(onOpenRecentRecord(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.tag = index // 使用tag存储记录索引
                menuItem.toolTip = record.content
                menu.addItem(menuItem)
            }
            menu.addItem(NSMenuItem.separator())
        }
        
        // 高级功能
        let clearAll = NSMenuItem(title: "清空所有记录", action: #selector(onClearAll), keyEquivalent: "")
        clearAll.target = self
        clearAll.isEnabled = !store.records.isEmpty
        menu.addItem(clearAll)
        
        menu.addItem(NSMenuItem.separator())
        let prefs = NSMenuItem(title: "偏好设置", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        prefs.isEnabled = true
        menu.addItem(prefs)
        let about = NSMenuItem(title: "关于 QuiteNote", action: #selector(onAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "退出应用", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.isEnabled = true
        menu.addItem(quit)
        statusItem.menu = menu
    }

    /// 菜单：显示/隐藏悬浮窗
    @objc private func onToggle() {
        print("[DEBUG] 状态栏菜单点击：显示/隐藏悬浮窗")
        toggleAction()
    }

    /// 菜单：强制显示
    @objc private func onForceShow() {
        print("[DEBUG] 状态栏菜单点击：强制显示并居中")
        forceShowAction()
    }

    /// 菜单：打开设置
    @objc private func openSettings() {
        QuiteNoteNotification.post(.showSettings)
    }

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
    @objc private func onCapture() { QuiteNoteNotification.post(.bluetoothCaptureClipboard) }

    @objc private func onToggleAI() {
        store.enableAI.toggle()
        store.savePreferences()
        store.postToast(store.enableAI ? "AI 已开启" : "AI 已关闭")
        setupMenu()
    }

    @objc private func onScreenshot() {
        // 通过 NotificationCenter 发送截图通知，让 MainApp 处理
        NotificationCenter.default.post(name: NSNotification.Name("qn.screenshot.trigger"), object: nil)
    }
    
    @objc private func onOpenRecentRecord(_ sender: NSMenuItem) {
        let recentRecords = Array(store.records.sorted(by: { $0.createdAt > $1.createdAt }).prefix(5))
        guard sender.tag < recentRecords.count else { return }
        
        let record = recentRecords[sender.tag]
        
        // 显示悬浮窗并展开特定记录
        forceShowAction()
        
        // 通过通知展开特定记录
        QuiteNoteNotification.post(.expandRecord, object: record.id)
    }
    
    /// 菜单：清空所有记录
    @objc private func onClearAll() {
        let alert = NSAlert()
        alert.messageText = "确认清空所有记录"
        alert.informativeText = "此操作不可撤销，将永久删除所有记录。"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "清空")
        
        if alert.runModal() == .alertSecondButtonReturn {
            store.clearAll()
            setupMenu() // 更新菜单状态
        }
    }
    
    /// 菜单：关于应用
    @objc private func onAbout() {
        let alert = NSAlert()
        alert.messageText = "QuiteNote"
        alert.informativeText = "版本 1.0.0\n\n一个简洁的剪切板历史记录和AI提炼工具\n\n© 2025 QuiteNote Team"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}
