import AppKit
import SwiftUI

/// 应用启动器面板按键动作（窗口内快捷键）
enum AppLauncherKeyAction {
    case moveUp
    case moveDown
    case launchSelected   // Return / 小键盘 Enter
    case copyCalcFull     // ⌘↵：复制「算式 = 结果」整式（算式模式下）
    case launchIndex(Int) // ⌘1–⌘9
    case escape           // Esc：有搜索词先清空，否则关闭面板
}

/// 应用启动器面板控制器（Alfred 式：⌥空格唤起 → 搜索 → 回车启动）
///
/// 完整复用 ClipboardHistoryPanelController 验证过的骨架：
/// 单例 + 惰性建窗、NSEvent localMonitor 键盘拦截、失焦自动收起、
/// 鼠标所在屏居中、NSHostingView sizingOptions=[]（崩溃红线）。
/// 外观走深色主题（区别于剪贴板面板的浅色 Alfred 风，按 2026-09-11 确认的原型）。
@MainActor
final class AppLauncherPanelController {
    static let shared = AppLauncherPanelController()

    private var panel: AppLauncherPanel?
    private var keyMonitor: Any?
    /// SwiftUI 视图注册的按键处理器（onAppear + 每次面板 didShow 重接——
    /// hosted view 不会随面板隐藏销毁，onAppear 只触发一次）
    var onKeyAction: ((AppLauncherKeyAction) -> Void)?

    private init() {}

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        let panel = ensurePanel()
        // 居中到鼠标所在的屏幕（panel.center() 多屏时会甩到副屏）
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let screen {
            lastScreen = screen
            let x = screen.visibleFrame.midX - panel.frame.width / 2
            // 顶边锚定在屏幕上中部（Alfred 式下挂），高度自适应内容时顶边不动
            let top = screen.visibleFrame.maxY - screen.visibleFrame.height * 0.18
            let y = top - panel.frame.height
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // macOS 14+ 对 accessory 应用的 activate 不总是生效，补一次确保搜索框可输入
        NSApp.activate(ignoringOtherApps: true)

        // 面板互斥：唤启动器时收起剪贴板面板（两个浮板同时可见会引发 key 转移竞态，
        // 实测 key 停在 nil、面板键盘全废；互斥同时消除干扰源）
        if ClipboardHistoryPanelController.shared.isVisible {
            ClipboardHistoryPanelController.shared.hide()
        }

        // key 就位补拉：makeKey 是异步的。用浮球验证过的激进方式（orderFrontRegardless
        // + makeKey 直调），按固定间隔补拉直到就位
        for delay in [0.15, 0.4, 0.9] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let panel = self.panel, panel.isVisible, !panel.isKeyWindow else { return }
                NSApp.activate(ignoringOtherApps: true)
                panel.orderFrontRegardless()
                panel.makeKey()
            }
        }

        installKeyMonitor()

        // ESC 注册为 Carbon 热键（面板打开期间）：搜狗在「搜索框聚焦+中文模式」下
        // 会在 app 之前吞掉裸 ESC（实测单/双击都到不了 NSEvent 监听器），Carbon 层
        // 拦截可绕过输入法。面板隐藏即注销（失焦自动收起保证了暴露窗口极小）
        GlobalHotkeyManager.shared.register(key: "esc", modifiers: [], id: 5003) { [weak self] in
            self?.hide()
        }

        // 首次打开扫描应用目录；距上次超过 5 分钟后台重扫（新装/卸载）
        AppCatalogStore.shared.loadIfNeeded()
        QuiteNoteNotification.post(.appLauncherPanelDidShow)
        let keyInfo = panel.isKeyWindow ? "key✓" : "key✗（当前 key: \(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "nil")）"
        DiagnosticCenter.info("Launcher", "启动器面板打开（\(keyInfo)）")
    }

    func hide() {
        panel?.orderOut(nil)
        removeKeyMonitor()
        GlobalHotkeyManager.shared.unregister(id: 5003)
        onKeyAction = nil
    }

    private var lastScreen: NSScreen?

    /// 高度自适应内容（视图在结果数/模式变化时调用）：顶边锚定不动、只改高度，
    /// 静态 setFrame（无逐帧动画，避开 NSHostingView 与窗口 resize 并发的崩溃红线）
    func applyContentHeight(_ contentHeight: CGFloat) {
        guard let panel, panel.isVisible, let screen = lastScreen ?? panel.screen ?? NSScreen.main else { return }
        let maxH = screen.visibleFrame.height * 0.6
        let target = min(max(220, contentHeight), maxH)
        var frame = panel.frame
        guard abs(frame.height - target) > 0.5 else { return }
        let top = frame.maxY
        frame.size.height = target
        frame.origin.y = top - target
        panel.setFrame(frame, display: true)
    }

    // MARK: - 失焦自动关闭（点别处即退出，不留常驻窗口）

    private var resignObserver: NSObjectProtocol?

    private func installResignObserver() {
        guard resignObserver == nil, let panel else { return }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.panel else { return }
                if NSApp.keyWindow !== panel {
                    self.hide()
                }
            }
        }
    }

    // MARK: - 窗口（640×460 单栏，深色）

    private func ensurePanel() -> AppLauncherPanel {
        if let panel { return panel }

        let rect = NSRect(x: 0, y: 0, width: 640, height: 460)
        let panel = AppLauncherPanel(contentRect: rect, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        // 层级 popUpMenu（101）：高于剪贴板/悬浮窗面板（.floating=3）与浮球（mainMenu+2=26），
        // 保证唤起时始终置顶（Alfred 式）；低于截图遮罩（screenSaver=1000）。
        // ⚠️ 必须在 isFloatingPanel 之后设置——该属性 setter 会把 level 重置回 .floating
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
        // 深色主题（UI 规范 2026-08-17）：darkAqua 外观 + 深色窗口底
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0)
        // 高度自适应内容（applyContentHeight 动态 setFrame），宽度固定
        panel.minSize = NSSize(width: 640, height: 220)
        panel.maxSize = NSSize(width: 640, height: 1600)

        // 崩溃红线：NSHostingView 禁止反向驱动窗口尺寸
        let hosting = NSHostingView(rootView: AppLauncherView(controller: self))
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
            if event.keyCode == 53 {
                let target = event.window.map { String(describing: type(of: $0)) } ?? "nil"
                let keyNow = NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "nil"
                DiagnosticCenter.info("Launcher", "ESC 到达 app（事件窗口: \(target)，当前 key: \(keyNow)）")
            }
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

    /// 按键映射：↑↓ / Return / Esc / ⌘1–9 / ⌘W
    private static func mapKey(_ event: NSEvent) -> AppLauncherKeyAction? {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let keyCode = event.keyCode

        if flags == .command {
            let digitKeys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
            if let idx = digitKeys.firstIndex(of: keyCode) {
                return .launchIndex(idx + 1)
            }
            if keyCode == 13 { return .escape }  // ⌘W：ESC 兜底（中文输入法会吞裸 ESC）
            if keyCode == 36 || keyCode == 76 { return .copyCalcFull }  // ⌘↵
        }

        if flags.isEmpty {
            switch keyCode {
            case 125: return .moveDown
            case 126: return .moveUp
            case 36, 76: return .launchSelected
            case 53: return .escape
            default: break
            }
        }

        return nil
    }
}

/// 面板窗口：ESC 关闭（焦点在搜索框时 field editor 会吞 cancelOperation，窗口层兜底）
final class AppLauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        AppLauncherPanelController.shared.hide()
    }
}
