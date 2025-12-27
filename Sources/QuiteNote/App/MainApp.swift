import SwiftUI
import AppKit
import UserNotifications

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
    private var screenshotCount = 0
    private var screenshotPreviewController: ScreenshotPreviewController?

    // 公开的 store 和 bluetooth 属性供 PreferencesView 使用
    var recordStore: RecordStore!
    var bluetoothManager: BluetoothManager!

    /// 应用启动回调：初始化状态栏与悬浮窗
    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundlePath = Bundle.main.bundlePath
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        print("[DEBUG] 应用启动中...")
        print("[DEBUG] 运行路径: \(bundlePath)")
        print("[DEBUG] Bundle ID: \(bundleID)")

        NSApp.setActivationPolicy(.accessory)

        let store = RecordStore()
        let bluetooth = BluetoothManager()

        clipboard = ClipboardService(store: store)
        self.recordStore = store
        self.bluetoothManager = bluetooth

        let heatmapVM = HeatmapViewModel(store: store)
        let ai = AIService()
        store.attachAI(service: ai)

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
        NotificationCenter.default.addObserver(self, selector: #selector(onScreenshotTriggered), name: NSNotification.Name("qn.screenshot.trigger"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onTestScreenshotTriggered), name: NSNotification.Name("qn.screenshot.test"), object: nil)

        shortcuts = KeyboardShortcutManager()
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
        shortcuts?.onScreenshot = { [weak self] in
            self?.handleScreenshot()
        }
        shortcuts?.start()
        
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
        // 检查当前焦点是否在文本输入框中
        if let focusedView = NSApp.keyWindow?.firstResponder,
           focusedView is NSTextView || focusedView is NSTextField {
            // 如果焦点在文本输入框中，不处理，让系统默认粘贴行为生效
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
        recordStore.addRecord(content: text, hash: hash, sourceApp: sourceApp, sourceUrl: sourceUrl)
        
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

    /// 蓝牙“唤起历史”事件处理：展开或收起悬浮窗
    @objc private func onToggleHistory(_ note: Notification) {
        toggleFloating()
    }

    @objc private func onScreenshotTriggered() {
        handleScreenshot()
    }

    @objc private func onTestScreenshotTriggered() {
        print("[DEBUG] 触发测试截图预览")
        // 调用真正的截图功能
        handleScreenshot()
    }

    /// 处理截图快捷键触发
    private func handleScreenshot() {
        print("[DEBUG] 快捷键回调：handleScreenshot 被调用")
        ScreenshotService.shared.capture { [weak self] image in
            if image == nil {
                print("[DEBUG] 截图失败或被取消：image 为 nil")
            }
            guard let self = self, let image = image else { return }
            
            DispatchQueue.main.async {
                self.showPreview(image: image)
            }
        }
    }
    
    private func showPreview(image: NSImage) {
        // 创建预览窗口
        self.screenshotPreviewController = ScreenshotPreviewController(
            image: image,
            onSave: { [weak self] in
                guard let self = self else { return }
                self.saveScreenshotRecord(image: image)
            },
            onCancel: { [weak self] in
                print("[DEBUG] 用户放弃了截图")
                self?.screenshotPreviewController = nil
            }
        )
        self.screenshotPreviewController?.show()
    }
    
    /// 保存截图到记录中
    private func saveScreenshotRecord(image: NSImage) {
        self.screenshotCount += 1
        let timestamp = Int(Date().timeIntervalSince1970)
        let message = "截图 \(self.screenshotCount)"
        let hash = "screenshot_\(timestamp)_\(self.screenshotCount)"
        
        // 1. 发送轻提示
        self.recordStore.postLightHint(message)
        
        // 2. 创建真正的记录
        self.recordStore.addRecord(
            content: message,
            hash: hash,
            sourceApp: "Screen Capture",
            type: .screenshot,
            skipAI: true
        )
        
        print("[DEBUG] \(message) 已保存并创建记录")
        self.screenshotPreviewController = nil
    }
}
