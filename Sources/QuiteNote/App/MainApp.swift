import SwiftUI
import AppKit

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

    // 公开的 store 和 bluetooth 属性供 PreferencesView 使用
    var recordStore: RecordStore!
    var bluetoothManager: BluetoothManager!

    /// 应用启动回调：初始化状态栏与悬浮窗
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[DEBUG] 应用启动中...")

        NSApp.setActivationPolicy(.accessory)

        let store = RecordStore()
        let bluetooth = BluetoothManager()

        clipboard = ClipboardService(store: store)
        self.recordStore = store
        self.bluetoothManager = bluetooth

        let heatmapVM = HeatmapViewModel(store: store)
        let ai = AIService()
        store.attachAI(service: ai)

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
        
        // 发送系统通知
        print("[DEBUG] 发送系统通知...")
        let notification = NSUserNotification()
        notification.title = "QuiteNote 应用已启动"
        notification.informativeText = "如果您看到这个通知，说明应用正在运行。"
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)

        NotificationCenter.default.addObserver(self, selector: #selector(onToggleHistory(_:)), name: .bluetoothToggleHistory, object: nil)

        shortcuts = KeyboardShortcutManager()
        shortcuts?.onTogglePanel = { [weak self] in self?.toggleFloating() }
        shortcuts?.onToggleAI = { store.enableAI.toggle(); store.savePreferences(); store.postToast(store.enableAI ? "AI 已开启" : "AI 已关闭", type: "info") }
        shortcuts?.onForceCenter = { [weak self] in 
            self?.floatingPanelController?.forceCenterWindow()
            print("[DEBUG] 已触发强制窗口居中快捷键")
        }
        shortcuts?.onCaptureClipboard = { 
            NotificationCenter.default.post(name: .bluetoothCaptureClipboard, object: nil)
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
        shortcuts?.start()
        
        print("[DEBUG] 应用启动完成")
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
}
