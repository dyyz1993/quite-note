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

    /// 面板 NSPanel（可见时）
    var panelIfVisible: NSPanel? {
        panel?.isVisible == true ? panel : nil
    }

    /// 搜索框的 AppKit 句柄（ClipSearchField 注册；makeFirstResponder 用）
    weak var searchFieldHandle: NSTextField?

    /// 确定性聚焦：面板已 key 则直接生效；未 key 则由 key 补拉/成为 key 后调用
    func focusSearchFieldNow() {
        guard let panel, panel.isVisible, let field = searchFieldHandle else { return }
        if panel.isKeyWindow {
            let ok = panel.makeFirstResponder(field)
            if ok {
                DiagnosticCenter.info("Clipboard", "聚焦成功：makeFirstResponder → true")
            } else {
                DiagnosticCenter.warning("Clipboard", "聚焦失败：makeFirstResponder 返回 false")
            }
        }
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        // 打开前记住用户当前所在应用 = 粘贴目标（PRD 6：自动粘贴前保存当前前台 App）
        ClipboardPasteService.shared.rememberTargetApp()

        let panel = ensurePanel()
        // 居中到鼠标所在的屏幕（panel.center() 会用窗口当前所在屏，多屏时可能跑到副屏）
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let screen {
            let x = screen.visibleFrame.midX - panel.frame.width / 2
            let y = screen.visibleFrame.midY - panel.frame.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // macOS 14+ 对 accessory 应用的 activate 不总是生效，makeKey 之后再补一次，
        // 尽量确保用户随后打字直接进搜索框（PRD 7.1：打开后搜索框自动获得焦点）
        NSApp.activate(ignoringOtherApps: true)
        focusSearchFieldNow()

        // 面板互斥：唤起剪贴板时收起启动器（两个浮板同屏会 key 转移竞态）
        if AppLauncherPanelController.shared.isVisible {
            AppLauncherPanelController.shared.hide()
        }

        // key 就位补拉：前密后疏（0.05~0.7s，深度审计建议——长间隔重试落在
        // 激活归因窗口之外全部无效）。每次重试后**无条件**补焦一拍（旧行为只在
        // 本轮 makeKey 成功才补焦，系统异步完成 key 时无人聚焦 = "key✓ 但打不了字"）
        for delay in [0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.4, 0.55, 0.7] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                if !panel.isKeyWindow {
                    NSApp.activate(ignoringOtherApps: true)
                    panel.orderFrontRegardless()
                    panel.makeKey()
                }
                DispatchQueue.main.async {
                    self.focusSearchFieldNow()
                }
            }
        }
        // 激活重锤（Steinberger 2025 / macOS 26 文档方案）：全部重试失败说明
        // accessory 激活被系统拒绝——临时切 .regular（有 Dock 图标的应用激活可靠），
        // 面板收起时切回。代价是 Dock 图标闪现 <1 秒
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible, !panel.isKeyWindow else { return }
            DiagnosticCenter.warning("Clipboard", "激活被拒（accessory 策略），启用 .regular 重锤")
            self.policyDanced = true
            NSApp.setActivationPolicy(.regular)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
                DispatchQueue.main.async {
                    self.focusSearchFieldNow()
                    // 聚焦完成后立刻切回（缩短 Dock 图标闪现）
                    if panel.isKeyWindow, self.policyDanced {
                        NSApp.setActivationPolicy(.accessory)
                        self.policyDanced = false
                    }
                }
            }
        }

        installKeyMonitor()

        // ESC Carbon 拦截（面板打开期间）：搜狗中文模式会吞裸 ESC，同启动器面板
        GlobalHotkeyManager.shared.register(key: "esc", modifiers: [], id: 5004) { [weak self] in
            self?.hide()
        }

        // 首次打开加载历史
        ClipboardHistoryStore.shared.loadIfNeeded()
        ClipboardMonitor.shared.syncWithPreferences()
        QuiteNoteNotification.post(.clipboardPanelDidShow)
        let keyInfo = panel.isKeyWindow ? "key✓" : "key✗（当前 key: \(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "nil")）"
        DiagnosticCenter.info("Clipboard", "历史面板打开（\(keyInfo)）")
    }

    private var policyDanced = false

    func hide() {
        if policyDanced {
            NSApp.setActivationPolicy(.accessory)
            policyDanced = false
        }
        DiagnosticCenter.info("Clipboard", "面板收起（当前 key: \(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "nil")）")
        panel?.orderOut(nil)
        removeKeyMonitor()
        GlobalHotkeyManager.shared.unregister(id: 5004)
        onKeyAction = nil
    }

    // MARK: - 失焦自动关闭（用户约定：点别处即退出，不留常驻窗口）

    private var resignObserver: NSObjectProtocol?

    /// 面板成为 key window → 确定性补焦（系统异步完成激活/key 时的兜底——
    /// 深度审计 R2：重试循环的 early-return 会让"晚到的 key"无人聚焦）
    private var becomeKeyFocusObserver: NSObjectProtocol?

    private func installBecomeKeyFocusObserver() {
        guard becomeKeyFocusObserver == nil, let panel else { return }
        becomeKeyFocusObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.focusSearchFieldNow()
            }
        }
    }

    private func installResignObserver() {
        guard resignObserver == nil, let panel else { return }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.panel else { return }
                // 新 key window 不是本面板（点到了其他 app / 主悬浮面板 / 浮球）→ 自动收起；
                // hide() 幂等，粘贴流程主动 orderOut 触发的同名通知无害
                if NSApp.keyWindow !== panel {
                    self.hide()
                }
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
        panel.isFloatingPanel = true
        // 层级 popUpMenu（101）：热键唤起的速查面板必须压在一切常规窗口之上
        //（高于闪记主面板 26，与启动器面板同层——两者互斥不会同屏）。
        // ⚠️ 必须先设 isFloatingPanel 再设 level，该属性 setter 会把 level 重置回 .floating
        panel.level = .popUpMenu
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
        installBecomeKeyFocusObserver()
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
