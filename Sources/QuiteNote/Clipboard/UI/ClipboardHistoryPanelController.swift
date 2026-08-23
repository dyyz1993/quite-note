import Foundation
import AppKit
import SwiftUI

/// 剪贴板历史面板窗口按键动作（窗口内快捷键，PRD 6）
enum ClipboardPanelKeyAction {
    case moveUp
    case moveDown
    case switchFilterLeft   // ← 切换筛选类型
    case switchFilterRight  // → 切换筛选类型
    case pasteSelected
    case pasteIndex(Int) // ⌘1–⌘9
    case saveToFlash     // ⌘S
    case togglePin       // ⌘P
    case deleteSelected
    case focusSearch     // ⌘F
    case escape          // Esc：有搜索词先清空，否则关闭面板
}

/// 剪贴板历史快捷面板控制器（PRD 7.1：720×560，打开后搜索自动聚焦）
///
/// 单例 + 惰性建窗（参考 V2OCRResultPanelController 模式）。
/// 窗口内键盘操作通过 NSEvent localMonitor 拦截（比 SwiftUI onKeyPress 兼容 macOS 13）。
@MainActor
final class ClipboardHistoryPanelController {
    static let shared = ClipboardHistoryPanelController()

    private var panel: ClipboardHistoryPanel?
    private var keyMonitor: Any?
    /// SwiftUI 视图注册的按键处理器（视图 onAppear 注册、onDisappear 置空）
    var onKeyAction: ((ClipboardPanelKeyAction) -> Void)?
    /// 从剪贴板条目打开对应闪记（MainApp 接线：唤起主悬浮面板并展开记录）
    var onOpenFlashNote: ((UUID) -> Void)?

    private init() {}

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        // 打开前记住用户当前所在应用 = 粘贴目标（PRD 6：自动粘贴前保存当前前台 App）
        ClipboardPasteService.shared.rememberTargetApp()

        let panel = ensurePanel()
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // macOS 14+ 对 accessory 应用的 activate 不总是生效，makeKey 之后再补一次，
        // 尽量确保用户随后打字直接进搜索框（PRD 7.1：打开后搜索框自动获得焦点）
        NSApp.activate(ignoringOtherApps: true)

        installKeyMonitor()

        // 首次打开加载历史
        ClipboardHistoryStore.shared.loadIfNeeded()
        ClipboardMonitor.shared.syncWithPreferences()
        QuiteNoteNotification.post(.clipboardPanelDidShow)
        DiagnosticCenter.info("Clipboard", "历史面板打开")
    }

    func hide() {
        panel?.orderOut(nil)
        removeKeyMonitor()
        onKeyAction = nil
    }

    // MARK: - 失焦自动关闭（用户约定：点别处即退出，不留常驻窗口）

    private var resignObserver: NSObjectProtocol?

    private func installResignObserver() {
        guard resignObserver == nil, let panel else { return }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] note in
            guard let self, let window = note.object as? NSWindow, window === self.panel else { return }
            // 新 key window 不是本面板（点到了其他 app / 主悬浮面板 / 浮球）→ 自动收起；
            // hide() 幂等，粘贴流程主动 orderOut 触发的同名通知无害
            if NSApp.keyWindow !== window {
                self.hide()
            }
        }
    }

    // MARK: - 窗口

    private func ensurePanel() -> ClipboardHistoryPanel {
        if let panel { return panel }

        // 尺寸/外观按用户指定的 Alfred 参考样式复刻（浅色主题）；
        // 左列表 + 右预览双栏：760 宽（左 ~300 列表 + 右 ~440 详情）
        let rect = NSRect(x: 0, y: 0, width: 760, height: 520)
        let panel = ClipboardHistoryPanel(contentRect: rect, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .aqua)
        panel.backgroundColor = NSColor(red: 0.941, green: 0.949, blue: 0.961, alpha: 1.0) // #f0f2f5
        panel.minSize = NSSize(width: 640, height: 400)
        panel.maxSize = NSSize(width: 1000, height: 760)

        // 崩溃红线：NSHostingView 禁止反向驱动窗口尺寸
        let hosting = NSHostingView(rootView: ClipboardHistoryView(controller: self))
        hosting.sizingOptions = []
        panel.contentView = hosting

        self.panel = panel
        installResignObserver()
        return panel
    }

    // MARK: - 键盘监听（窗口内快捷键）

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = event.window, window === self.panel, window.isKeyWindow else { return event }
            guard let action = Self.mapKey(event) else { return event }
            self.onKeyAction?(action)
            return nil // 消费事件
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    /// 按键映射（仅窗口聚焦时生效；⌘1–9 不注册全局，PRD 6）
    private static func mapKey(_ event: NSEvent) -> ClipboardPanelKeyAction? {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let keyCode = event.keyCode

        // ⌘1–⌘9：直接粘贴第 N 项（keycode 18,19,20,21,23,22,26,28,25 → 1...9）
        if flags == .command {
            let digitKeys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
            if let idx = digitKeys.firstIndex(of: keyCode) {
                return .pasteIndex(idx + 1)
            }
            switch keyCode {
            case 1: return .saveToFlash     // ⌘S
            case 35: return .togglePin      // ⌘P
            case 3: return .focusSearch     // ⌘F
            default: break
            }
        }

        if flags.isEmpty {
            switch keyCode {
            case 125: return .moveDown      // ↓
            case 126: return .moveUp        // ↑
            case 123: return .switchFilterLeft  // ←
            case 124: return .switchFilterRight // →
            case 36, 76: return .pasteSelected // Return / 小键盘 Enter
            case 117: return .deleteSelected // fn+Delete（向前删除）
            case 53: return .escape         // Esc（焦点在搜索框时 field editor 会吞 cancelOperation，这里直接拦）
            default: break
            }
        }

        return nil
    }
}

/// 面板窗口：ESC 关闭（PRD 6）
final class ClipboardHistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        ClipboardHistoryPanelController.shared.hide()
    }
}
