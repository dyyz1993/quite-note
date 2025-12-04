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
        let store = RecordStore()
        clipboard = ClipboardService(store: store)
        let bluetooth = BluetoothManager()
        let heatmapVM = HeatmapViewModel(store: store)
        let ai = AIService()
        store.attachAI(service: ai)

        statusBarController = StatusBarController(store: store, bluetooth: bluetooth, toggleAction: { [weak self] in
            self?.toggleFloating()
        })

        floatingPanelController = FloatingPanelController(store: store, heatmapVM: heatmapVM, bluetooth: bluetooth)

        NotificationCenter.default.addObserver(self, selector: #selector(onToggleHistory(_:)), name: .bluetoothToggleHistory, object: nil)

        shortcuts = KeyboardShortcutManager()
        shortcuts?.onTogglePanel = { [weak self] in self?.toggleFloating() }
        shortcuts?.onToggleAI = { store.enableAI.toggle(); store.savePreferences(); store.postToast(store.enableAI ? "AI 已开启" : "AI 已关闭", type: "info") }
        shortcuts?.start()
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
