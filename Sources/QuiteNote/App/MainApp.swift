import SwiftUI
import AppKit

@main
struct MainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var floatingPanelController: FloatingPanelController?
    private var clipboard: ClipboardService?
    private var shortcuts: KeyboardShortcutManager?

    /// 应用启动回调：初始化状态栏与悬浮窗
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[DEBUG] 应用启动中...")
        
        let store = RecordStore()
        clipboard = ClipboardService(store: store)
        let bluetooth = BluetoothManager()
        let heatmapVM = HeatmapViewModel(store: store)
        let ai = AIService()
        store.attachAI(service: ai)

        print("[DEBUG] 创建状态栏控制器...")
        statusBarController = StatusBarController(store: store, bluetooth: bluetooth, toggleAction: { [weak self] in
            self?.toggleFloating()
        })

        print("[DEBUG] 创建悬浮窗控制器...")
        floatingPanelController = FloatingPanelController(store: store, heatmapVM: heatmapVM, bluetooth: bluetooth)
        
        print("[DEBUG] 自动显示悬浮窗...")
        floatingPanelController?.show()
        
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
        shortcuts?.start()
        
        print("[DEBUG] 应用启动完成")
    }

    /// 切换悬浮窗显示/隐藏，包含动效
    private func toggleFloating() {
        guard let floating = floatingPanelController else { return }
        if floating.isVisible {
            floating.hide()
        } else {
            floating.show()
        }
    }

    /// 蓝牙“唤起历史”事件处理：展开或收起悬浮窗
    @objc private func onToggleHistory(_ note: Notification) {
        toggleFloating()
    }
}
