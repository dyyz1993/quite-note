import Foundation
import AppKit
import SwiftUI

/// 剪贴板历史面板窗口按键动作（窗口内快捷键，PRD 6）
enum ClipboardPanelKeyAction: Equatable {
    case moveUp
    case moveDown
    case switchFilterLeft   // ⇧Tab 切换筛选类型（反向）
    case switchFilterRight  // Tab 切换筛选类型（正向）
    case pasteSelected
    case pasteIndex(Int) // ⌘1–⌘9
    case saveToFlash     // ⌘S
    case togglePin       // ⌘P
    case deleteSelected
    case focusSearch     // ⌘F
    case escape          // Esc：有搜索词先清空，否则关闭面板
}

/// Carbon 全局兜底热键规格（面板打开期间注册，收起即注销）
///
/// 为什么需要：macOS 26 对 accessory 应用的激活拒绝让面板可见但非 key 的窗口期
/// （生产日志实锤：12/12 次打开 key✗，九连补拉全失败过半）local monitor 完全
/// 收不到按键——↑↓/回车/⌘1-9 全部漏进前一个应用（浏览器 ⌘1 = 切标签页）。
/// 修法同面板 ESC 拦截（id 5004）：可见期间注册 Carbon 全局热键，系统层截获，
/// 与激活状态无关。
enum ClipboardGlobalFallback {
    struct Spec: Equatable {
        let key: String
        let modifiers: NSEvent.ModifierFlags
        let id: UInt32
        let action: ClipboardPanelKeyAction
    }

    /// ⌘ 组合（面板可见期常驻）：输入法组词不会用到 ⌘ 组合键，无 IME 冲突。
    /// ⌘1–9 直贴 / ⌘S 闪记 / ⌘P 置顶 / ⌘F 聚焦搜索
    static let commandSpecs: [Spec] = {
        let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
        var specs = digits.enumerated().map { idx, key in
            Spec(key: key, modifiers: .command, id: UInt32(5110 + idx), action: .pasteIndex(idx + 1))
        }
        specs.append(Spec(key: "s", modifiers: .command, id: 5119, action: .saveToFlash))
        specs.append(Spec(key: "p", modifiers: .command, id: 5120, action: .togglePin))
        specs.append(Spec(key: "f", modifiers: .command, id: 5121, action: .focusSearch))
        return specs
    }()

    /// 裸导航键（仅面板**未成为 key** 期间注册，didBecomeKey 即注销）：
    /// 组词期 ↑↓/回车是输入法候选键，Carbon 注册即系统级消费、无法放行，
    /// 面板已 key 时必须还给 local monitor 路径（带组词守卫）。
    /// ←/→ 仅在搜索词为空时作为切筛选键注册（有输入内容时左右是光标编辑键，
    /// 消费会破坏编辑——arrowFilterGuard 拦）
    static let navigationSpecs: [Spec] = [
        Spec(key: "up", modifiers: [], id: 5122, action: .moveUp),
        Spec(key: "down", modifiers: [], id: 5123, action: .moveDown),
        Spec(key: "return", modifiers: [], id: 5124, action: .pasteSelected),
        Spec(key: "tab", modifiers: [], id: 5125, action: .switchFilterRight),
        Spec(key: "tab", modifiers: .shift, id: 5126, action: .switchFilterLeft),
        Spec(key: "left", modifiers: [], id: 5127, action: .switchFilterLeft),
        Spec(key: "right", modifiers: [], id: 5128, action: .switchFilterRight),
    ]

    /// 按面板 key 状态给出应注册的规格集合（单测钉住分层语义）
    static func specs(panelIsKey: Bool) -> [Spec] {
        panelIsKey ? commandSpecs : commandSpecs + navigationSpecs
    }

    static func allIDs() -> [UInt32] { Array(5110...5128) }
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

    /// ←/→ 可否当"切筛选"消费：搜索词为空才可（有输入内容时左右是光标编辑键，
    /// 消费会破坏编辑）。视图 onAppear/didShow 接入 vm.searchText 判定
    var arrowFilterGuard: () -> Bool = { true }

    /// 确定性聚焦：面板已 key 则直接生效；未 key 则由 key 补拉/成为 key 后调用
    func focusSearchFieldNow() {
        guard let panel, panel.isVisible, let field = searchFieldHandle else { return }
        // 已聚焦且编辑中（含输入法 marked text 组词态）→ 必须跳过：
        // 再调 makeFirstResponder 会重启 field editor 会话，未上屏的组词内容被
        // 整段丢弃（唤起后 0.05–0.7s 补焦重试期间用户已开始打字 = 首个单词被删的元凶）
        if let editor = field.currentEditor(), panel.firstResponder === editor {
            return
        }
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

        abortKeyLadder = false
        // key 就位补拉：前密后疏（0.05~0.7s，深度审计建议——长间隔重试落在
        // 激活归因窗口之外全部无效）。每次重试后**无条件**补焦一拍。
        // 逐步计时 + 自适应熔断（2026-11-20 用户真机实锤：第二次唤起遭激活拒绝时
        // 主线程冻 15.1s、0.35s 重锤都排不上队——嫌疑是 activate/makeKey 在被拒
        // 状态下同步阻塞；某步 >0.8s 即停跳等重锤，别把主线程堵满）
        for delay in [0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.4, 0.55, 0.7] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let panel = self.panel, panel.isVisible, !panel.isKeyWindow else { return }
                if self.abortKeyLadder { return }
                let t0 = DispatchTime.now()
                NSApp.activate(ignoringOtherApps: true)
                panel.orderFrontRegardless()
                panel.makeKey()
                let ms = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
                if ms > 80 {
                    DiagnosticCenter.warning("Clipboard", String(format: "key 补拉一步耗时 %.0fms（activate/makeKey 疑似阻塞）", ms))
                }
                if ms > 800 {
                    self.abortKeyLadder = true
                    DiagnosticCenter.warning("Clipboard", String(format: "key 补拉熔断（该步 %.0fms，交由重锤接管）", ms))
                }
                DispatchQueue.main.async {
                    self.focusSearchFieldNow()
                }
            }
        }
        // 激活重锤（Steinberger 2025 / macOS 26 文档方案）：补拉失败说明
        // accessory 激活被系统拒绝——临时切 .regular（有 Dock 图标的应用激活可靠），
        // 面板收起时切回。代价是 Dock 图标闪现 <1 秒。
        // 0.35s（生产日志定标）：用户唤起后 0.2~0.5s 就开始打字/导航，0.8s 才重锤
        // 意味着打字全漏；导航键已有 Carbon 兜底兜住，重锤只管打字进搜索框，越早越好
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible, !panel.isKeyWindow else { return }
            DiagnosticCenter.warning("Clipboard", "激活被拒（accessory 策略），启用 .regular 重锤")
            self.policyDanced = true
            let h0 = DispatchTime.now()
            NSApp.setActivationPolicy(.regular)
            let policyMs = Double(DispatchTime.now().uptimeNanoseconds - h0.uptimeNanoseconds) / 1_000_000
            if policyMs > 80 {
                DiagnosticCenter.warning("Clipboard", String(format: "重锤 setActivationPolicy 耗时 %.0fms", policyMs))
            }
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
        installClickOutsideMonitor()
        installGlobalKeyFallbacks()
        beginWakeAssertion()

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

    // MARK: App Nap 防护（2026-11-20 采样定罪）
    // 激活被拒 → 应用跌回后台 → macOS 26 对后台 accessory 应用激进 App Nap：
    // 主线程空闲挂起、主队列定时唤醒延迟 15s 量级（hang-sample 实锤：主线程
    // mach_msg 空转、零计算零锁，用户面板冻结、心跳饿死）。面板可见期间持有
    // userInitiated 活动断言，禁止系统 nap。
    private var wakeAssertion: NSObjectProtocol?

    private func beginWakeAssertion() {
        guard wakeAssertion == nil else { return }
        wakeAssertion = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "clipboard-panel-visible"
        )
        DiagnosticCenter.info("Clipboard", "App Nap 断言已持有（面板可见期间）")
    }

    private func endWakeAssertion() {
        if let token = wakeAssertion {
            ProcessInfo.processInfo.endActivity(token)
            wakeAssertion = nil
            DiagnosticCenter.info("Clipboard", "App Nap 断言已释放")
        }
    }
    /// key 补拉熔断标志（show() 时复位；某步 activate/makeKey 阻塞 >0.8s 置位）
    private var abortKeyLadder = false

    func hide() {
        if policyDanced {
            NSApp.setActivationPolicy(.accessory)
            policyDanced = false
        }
        DiagnosticCenter.info("Clipboard", "面板收起（当前 key: \(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "nil")）")
        panel?.orderOut(nil)
        endWakeAssertion()
        removeKeyMonitor()
        removeClickOutsideMonitor()
        removeGlobalKeyFallbacks()
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
                guard let self else { return }
                self.focusSearchFieldNow()
                // 已 key：导航键兜底交接给 local monitor（组词守卫在那一层）
                self.removeNavigationKeyFallbacks()
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
        // SwiftUI inside NSHostingView can otherwise remain opaque to AX unless a
        // child explicitly becomes accessible; the isolated app process needs this
        // for deterministic UI automation.
        hosting.setAccessibilityEnabled(true)
        panel.contentView = hosting

        self.panel = panel
        installResignObserver()
        installBecomeKeyFocusObserver()
        return panel
    }

    // MARK: - 点击外部关闭（Alfred 式兜底）

    /// 全局鼠标按下监听（面板打开期间）。didResignKey 只覆盖"面板曾拿到 key 后
    /// 失焦"；面板从未成为 key（accessory 激活被拒的竞态）时点击别处不触发
    /// resign 通知，面板会一直悬在屏上——全局监听点面板外任意处即收起，补上缺口
    private var clickOutsideMonitor: Any?

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                if !NSMouseInRect(location, panel.frame, false) {
                    self.hide()
                }
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    // MARK: - Carbon 全局兜底（面板可见期间的键盘可靠性，见 ClipboardGlobalFallback）

    private func installGlobalKeyFallbacks() {
        let manager = GlobalHotkeyManager.shared
        for spec in ClipboardGlobalFallback.specs(panelIsKey: panel?.isKeyWindow ?? false) {
            manager.register(key: spec.key, modifiers: spec.modifiers, id: spec.id) { [weak self] in
                self?.dispatchGlobalFallback(spec.action)
            }
        }
    }

    /// 面板成为 key 后注销裸导航键兜底：此后按键走 local monitor（带输入法组词守卫——
    /// 组词期 ↑↓/回车是候选键必须放行；Carbon 注册即系统级消费，不注销会拦死组词）
    private func removeNavigationKeyFallbacks() {
        guard let panel, panel.isKeyWindow else { return }
        ClipboardGlobalFallback.navigationSpecs.forEach {
            GlobalHotkeyManager.shared.unregister(id: $0.id)
        }
    }

    private func removeGlobalKeyFallbacks() {
        ClipboardGlobalFallback.allIDs().forEach {
            GlobalHotkeyManager.shared.unregister(id: $0)
        }
    }

    private func dispatchGlobalFallback(_ action: ClipboardPanelKeyAction) {
        guard let panel, panel.isVisible else { return }
        // 与 local monitor 同款组词守卫（防御 didBecomeKey 注销竞态期的残留注册）
        if let client = panel.firstResponder as? NSTextInputClient, client.hasMarkedText() { return }
        // 切筛选类（含 ←/→）：搜索词非空时丢弃，防止碳通道消费掉本应属于
        // 文本编辑的按键（keyless 窗口期 resetInput 已清词，常态下恒过）
        switch action {
        case .switchFilterLeft, .switchFilterRight:
            guard arrowFilterGuard() else { return }
        default:
            break
        }
        DiagnosticCenter.info("Clipboard", "Carbon 兜底按键：\(action)")
        onKeyAction?(action)
    }

    // MARK: - 键盘监听（窗口内快捷键）

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = event.window, window === self.panel, window.isKeyWindow else { return event }
            // 输入法组词期间（marked text）不拦截：Enter/↑↓ 此刻是候选确认键，
            // 拦掉会把组词打断（表现同"首单词被删"），事件原样还给第一响应者
            if let client = window.firstResponder as? NSTextInputClient, client.hasMarkedText() {
                return event
            }
            guard let action = Self.mapKey(event) else {
                // ←/→ 特殊分流：搜索词为空时是切筛选键（用户约定 2026-11-20），
                // 有输入内容时必须还给 field editor 当光标编辑键——mapKey 是静态
                // 无状态表，带状态的拦截在这里做
                let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
                if flags.isEmpty, event.keyCode == 123 || event.keyCode == 124, self.arrowFilterGuard() {
                    let action: ClipboardPanelKeyAction = event.keyCode == 123 ? .switchFilterLeft : .switchFilterRight
                    self.onKeyAction?(action)
                    return nil
                }
                return event
            }
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
    static func mapKey(
        _ event: NSEvent
    ) -> ClipboardPanelKeyAction? {
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

        // ⇧Tab / Tab：切换分类筛选（输入框聚焦与否均生效——面板内 Tab 无其他用途）
        // （2026-10-24 交互改版：←/→ 永远是输入框光标键（搜索框常驻聚焦），分类
        // 切换移到 Tab——旧"←→ 未聚焦时切筛选"与常驻聚焦设计自相矛盾，实测切不动）
        if flags == .shift, keyCode == 48 {
            return .switchFilterLeft
        }
        if flags.isEmpty, keyCode == 48 {
            return .switchFilterRight
        }

        if flags.isEmpty {
            switch keyCode {
            case 125: return .moveDown      // ↓
            case 126: return .moveUp        // ↑
            // ←/→ 永远是输入框光标编辑键（搜索框常驻聚焦，方案 B：输入框/分类分工明确）
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
