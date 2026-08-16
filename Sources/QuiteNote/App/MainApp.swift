import SwiftUI
import AppKit
import UserNotifications
import Combine

@main
struct MainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            if let store = appDelegate.recordStore, let bluetooth = appDelegate.bluetoothManager {
                PreferencesView(store: store, bluetooth: bluetooth)
            } else {
                // 如果还没有初始化完成，显示一个占位符
                EmptyView()
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var floatingPanelController: FloatingPanelController?
    private var clipboard: ClipboardService?
    private var shortcuts: KeyboardShortcutManager?
    private var cancellables = Set<AnyCancellable>()

    // 公开的 store 和 bluetooth 属性供 PreferencesView 使用
    var recordStore: RecordStore!
    var bluetoothManager: BluetoothManager!

    /// 应用启动回调：初始化状态栏与悬浮窗
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 诊断中心最先启动：检测上次异常退出 + 崩溃捕获 + 卡死看门狗 + 文件日志
        DiagnosticCenter.shared.start()

        // 任一权限缺失时：自动打开对应设置页 + 在设置窗口底部弹出迷你拖拽引导条
        // （轻量横条：虚线框呼吸图标，用户直接从那里拖进上方列表；大面板留给截图触发的场景）
        let screenOK = ScreenshotService.shared.checkScreenCapturePermission()
        let accessibilityOK = ScreenshotService.shared.checkAccessibilityPermission()
        if !screenOK || !accessibilityOK {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let target = !accessibilityOK ? "Privacy_Accessibility" : "Privacy_ScreenCapture"
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(target)") {
                    NSWorkspace.shared.open(url)
                }
                MiniPermissionBarController.shared.show()
                DiagnosticCenter.info("Permission", "启动时检测到权限缺失（辅助功能:\(accessibilityOK ? "✓" : "✗") 录屏:\(screenOK ? "✓" : "✗")），已打开设置页并弹出迷你引导条")
            }
        }

        // 初始化贴纸管理器
        _ = StickyNoteManager.shared

        // ⭐ 预加载符号配置，避免首次点击延迟
        print("[DEBUG] 预加载符号配置...")
        _ = SymbolConfigManager.shared

        let bundlePath = Bundle.main.bundlePath
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        print("[DEBUG] 应用启动中...")
        print("[DEBUG] 运行路径: \(bundlePath)")
        print("[DEBUG] Bundle ID: \(bundleID)")

        NSApp.setActivationPolicy(.accessory)

        let store = RecordStore()
        let bluetooth = BluetoothManager()

        // 清理僵尸便签（关联到已删除记录的便签）
        StickyNoteManager.shared.cleanupZombieNotes { recordId in
            // 检查记录是否还存在
            return store.records.contains(where: { $0.id == recordId })
        }

        clipboard = ClipboardService(store: store)
        self.recordStore = store
        self.bluetoothManager = bluetooth

        let heatmapVM = HeatmapViewModel(store: store)
        let ai = AIService()
        store.attachAI(service: ai)

        // 将 RecordStore 注入到 ScreenshotService
        ScreenshotService.shared.attachRecordStore(store)
        
        // ⚠️ 配置截图时的窗口隐藏逻辑
        ScreenshotService.shared.onWillStartScreenshot = { [weak self] in
            print("[DEBUG AppDelegate] 截图即将开始，隐藏悬浮窗")
            self?.floatingPanelController?.hideImmediately()
        }
        ScreenshotService.shared.onDidFinishScreenshot = { [weak self] in
            print("[DEBUG AppDelegate] 截图已结束，恢复悬浮窗")
            self?.floatingPanelController?.show()
        }

        // 在 LucideDiagnostics.run() 之前，尝试显式加载 LucideIcons 框架的 bundle
        // 使用 Bundle.main.bundleURL 直接构建到 Contents/Frameworks 的路径
        let lucideBundleURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/LucideIcons_LucideIcons.bundle")
        if let lucideBundle = Bundle(url: lucideBundleURL) {
            lucideBundle.load()
            print("[DEBUG] LucideIcons bundle loaded explicitly from Contents/Frameworks.")
        } else {
            print("[DEBUG] Failed to explicitly load LucideIcons bundle from Contents/Frameworks.")
        }

        // Lucide 图标可用性诊断（启动时一次性输出）
        LucideDiagnostics.run()

        print("[DEBUG] 创建状态栏控制器...")
        statusBarController = StatusBarController(store: store, bluetooth: bluetooth, toggleAction: { [weak self] in
            self?.toggleFloating()
        }, forceShowAction: { [weak self] in
            print("[DEBUG] 状态栏触发：强制显示")
            self?.floatingPanelController?.ensureVisibleOnLaunch()
        })

        print("[DEBUG] 创建悬浮窗控制器...")
        floatingPanelController = FloatingPanelController(store: store, heatmapVM: heatmapVM, bluetooth: bluetooth)
        if floatingPanelController == nil {
            print("[DEBUG] FATAL: FloatingPanelController init failed (nil)")
        } else {
            print("[DEBUG] FloatingPanelController created successfully")
        }
        
        print("[DEBUG] 自动显示悬浮窗...")
        DispatchQueue.main.async {
            if let controller = self.floatingPanelController {
                print("[DEBUG] Calling ensureVisibleOnLaunch from startup")
                controller.ensureVisibleOnLaunch()
            } else {
                print("[DEBUG] FATAL: Cannot show window, controller is nil")
            }
        }
        
        // 发送系统通知（仅在 app bundle 中运行时）
        // swift run 时没有 bundle，访问 UNUserNotificationCenter 会崩溃
        if Bundle.main.bundlePath.contains(".app") {
            print("[DEBUG] 发送系统通知...")
            let content = UNMutableNotificationContent()
            content.title = "QuiteNote 应用已启动"
            content.body = "如果您看到这个通知，说明应用正在运行。"
            content.sound = .default

            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("[DEBUG] Failed to deliver notification: \(error)")
                }
            }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(onToggleHistory(_:)), name: QuiteNoteNotification.bluetoothToggleHistory.name, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onBluetoothScreenshot), name: QuiteNoteNotification.bluetoothCaptureScreenshot.name, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onScreenshotTriggered), name: NSNotification.Name("qn.screenshot.trigger"), object: nil)
        // P2.2: 监听图标缓存清除请求
        NotificationCenter.default.addObserver(self, selector: #selector(onClearIconCache), name: NSNotification.Name("ClearIconCache"), object: nil)

        shortcuts = KeyboardShortcutManager()
        shortcuts?.recordStore = store
        shortcuts?.onTogglePanel = { [weak self] in self?.toggleFloating() }
        shortcuts?.onToggleAI = { store.enableAI.toggle(); store.savePreferences(); store.postToast(store.enableAI ? "AI 已开启" : "AI 已关闭", type: "info") }
        shortcuts?.onForceCenter = { [weak self] in 
            self?.floatingPanelController?.forceCenterWindow()
            print("[DEBUG] 已触发强制窗口居中快捷键")
        }
        shortcuts?.onCaptureClipboard = {
            QuiteNoteNotification.post(.bluetoothCaptureClipboard)
        }
        shortcuts?.onBulkSummarize = { 
            store.bulkResummarize()
        }
        shortcuts?.onExport = { 
            let md = store.exportMarkdown()
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            let url = desktop.appendingPathComponent("QuiteNote_Export.md")
            try? md.write(to: url, atomically: true, encoding: .utf8)
            store.postLightHint("已导出到桌面：QuiteNote_Export.md")
        }
        shortcuts?.onOpenSettings = { [weak self] in
            self?.floatingPanelController?.showSettings()
        }
        shortcuts?.onQuit = {
            NSApp.terminate(nil)
        }
        shortcuts?.onGlobalPaste = { [weak self] in
            self?.handleGlobalPaste()
        }
        shortcuts?.onScreenshot = {
            // 使用统一截图入口
            ScreenshotService.shared.startScreenshot()
        }
        shortcuts?.start()
        
        // 观察配置变化，更新快捷键缓存
        PreferencesManager.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // 延迟一小段时间等待 UserDefaults 更新完成
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.shortcuts?.refresh()
                }
            }
            .store(in: &cancellables)
        
        // 检查辅助功能权限（静默检查，不触发弹窗）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !ScreenshotService.shared.checkAccessibilityPermission(prompt: false) {
                print("[DEBUG] 警告：缺少辅助功能权限，全局快捷键可能无效")
            }
        }
        
        print("[DEBUG] 应用启动完成")
    }

    /// 处理粘贴事件（无输入框聚焦时）
    private func handleGlobalPaste() {
        // 1. 检查当前焦点是否在文本输入框中
        if let focusedView = NSApp.keyWindow?.firstResponder,
           focusedView is NSTextView || focusedView is NSTextField {
            // 如果焦点在文本输入框中，不处理，让系统默认粘贴行为生效
            return
        }
        
        // 2. 只有当鼠标悬停在悬浮窗或浮球上时，才允许全局粘贴自动采集
        // 这是为了防止用户在其他应用中正常粘贴时，也被 Quite Note 误抓取
        guard let floatingPanel = floatingPanelController, floatingPanel.isMouseOverPanel() else {
            return
        }
        
        // 获取剪贴板内容
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        // 创建新记录
        let (sourceApp, sourceUrl) = ClipboardService.getSourceInfo()
        let hash = ClipboardService.sha1(text)
        // 判断是否为纯URL，如果是则设置为.url类型
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let recordType: RecordType = ClipboardService.isPureURL(trimmedText) ? .url : .text
        recordStore.addRecord(content: text, hash: hash, sourceApp: sourceApp, sourceUrl: sourceUrl, type: recordType)
        
        // 显示悬浮窗（如果当前未显示）
        DispatchQueue.main.async { [weak self] in
            // 如果已经在展开模式，不需要重新调用 ensureVisibleOnLaunch(forceCenter: true)
            // 只需要确保窗口可见即可
            self?.floatingPanelController?.showWithoutCentering()
        }
    }
    
    /// 切换悬浮窗显示/隐藏，包含动效
    private func toggleFloating() {
        print("[DEBUG] toggleFloating called")
        guard let floating = floatingPanelController else {
            print("[DEBUG] ERROR: floatingPanelController is nil")
            return 
        }
        print("[DEBUG] 状态栏触发：切换悬浮窗")
        if floating.isVisible {
            print("[DEBUG] 当前可见，执行隐藏")
            floating.hide()
        } else {
            print("[DEBUG] 当前不可见，执行确保可见并居中")
            floating.ensureVisibleOnLaunch()
        }
    }

    /// 蓝牙"唤起历史"事件处理：展开或收起悬浮窗
    @objc private func onToggleHistory(_ note: Notification) {
        toggleFloating()
    }

    /// 蓝牙按钮截图事件处理：触发截图功能
    @objc private func onBluetoothScreenshot() {
        print("[DEBUG] 蓝牙按钮触发截图")
        // 使用统一截图入口
        ScreenshotService.shared.startScreenshot()
    }

    @objc private func onScreenshotTriggered() {
        print("[DEBUG] 快捷键/菜单栏触发截图")
        // 使用统一截图入口
        ScreenshotService.shared.startScreenshot()
    }

    // P2.2: 清除图标缓存
    @objc private func onClearIconCache() {
        print("[DEBUG] 清除图标缓存")
        LucideView.clearCache()
        recordStore?.postToast("图标缓存已清除", type: "success")
    }

    deinit {
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
    }
}
