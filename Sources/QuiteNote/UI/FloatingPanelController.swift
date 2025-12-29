import SwiftUI
import AppKit

// MARK: - Window Dragging Helper

struct DraggableArea<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content.background(WindowDragHandler())
    }
}

struct WindowDragHandler: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableNSView {
        return DraggableNSView()
    }

    func updateNSView(_ nsView: DraggableNSView, context: Context) {}
}

class DraggableNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

class CustomPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum WindowMode {
    case expanded
    case floatingBall
}

final class WindowFocusProvider: ObservableObject {
    @Published var isKeyWindow: Bool = false
    @Published var mode: WindowMode = .expanded
    @Published var ballPosition: CGPoint = .zero
    @Published var lastExpandedFrame: NSRect? = nil
    var isRestoring: Bool = false // 新增：标记是否正在从浮球恢复，用于防止坐标漂移
    var ballPositionLastSet: TimeInterval = 0 // 记录 ballPosition 最后设置的时间，用于防止 windowDidMove 覆盖
}

// MARK: - FloatingPanelController

/// 管理悬浮窗 NSPanel 展示、置顶与动效
final class FloatingPanelController {
    private var panel: CustomPanel!
    private let store: RecordStore
    private let heatmapVM: HeatmapViewModel
    private let bluetooth: BluetoothManager
    private var hosting: NSHostingView<FloatingRootView>!
    private var animationsEnabled: Bool = true
    private let focusProvider = WindowFocusProvider()
    private var launchEnsurer: Timer?
    private var hoverActive: Bool = false
    private var hoverFocusTimer: Timer?
    private var revertTimer: Timer?
    private var lastSwitchAt: TimeInterval = 0
    private var isInteracting: Bool = false // 跟踪用户是否正在交互（拖拽、点击等）
    private var lastInteractionChange: TimeInterval = 0 // 记录上次交互状态变更时间
    private var userHidden: Bool = false // 用户主动隐藏标记，防止自动前置
    private var previousApp: NSRunningApplication? // 记录焦点夺取前的活跃应用

    var isVisible: Bool { panel.isVisible }

    /// 析构函数，确保清理所有资源
    deinit {
        cleanup()
    }

    /// 清理所有资源，防止内存泄漏
    private func cleanup() {
        // 清理定时器
        launchEnsurer?.invalidate()
        launchEnsurer = nil
        hoverFocusTimer?.invalidate()
        hoverFocusTimer = nil
        revertTimer?.invalidate()
        revertTimer = nil

        // 移除通知观察者
        NotificationCenter.default.removeObserver(self)

        // 清理hosting view
        if hosting != nil {
            hosting.removeFromSuperview()
            hosting = nil
        }

        // 清理panel
        if panel != nil {
            panel.close()
            panel = nil
        }
    }

    /// 初始化悬浮窗并配置置顶与多桌面行为
    init(store: RecordStore, heatmapVM: HeatmapViewModel, bluetooth: BluetoothManager) {
        self.store = store
        self.heatmapVM = heatmapVM
        self.bluetooth = bluetooth

        // 计算屏幕中心位置
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        // 使用主题文件中的尺寸定义
        let windowWidth: CGFloat = 520
        let windowHeight: CGFloat = 640
        let centerX = screenFrame.midX - (windowWidth / 2)
        let centerY = screenFrame.midY - (windowHeight / 2)

        // Updated size to match design (wider)
        // Use borderless to remove title bar completely, add fullSizeContentView to allow content to fill window
        // Remove .nonactivatingPanel to allow TextField input and key events
        panel = CustomPanel(contentRect: NSRect(x: centerX, y: centerY, width: windowWidth, height: windowHeight),
                       styleMask: [.titled, .fullSizeContentView],
                       backing: .buffered, defer: false)

        panel.isOpaque = false
        panel.level = .floating
        // 恢复关键行为：允许在所有桌面显示，允许在全屏应用之上显示
        // 去掉了 .moveToActiveSpace 以防止初始化卡死
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden  // 隐藏标题栏
        panel.titlebarAppearsTransparent = true  // 标题栏透明
        panel.backgroundColor = NSColor.clear.withAlphaComponent(0.9) // 设置为透明背景，让SwiftUI内容显示
        // 禁用全局窗口拖拽，只允许 WindowDragHandler 区域拖拽
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true // Ensure shadow is visible for borderless window

        // Hide system buttons
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        hosting = NSHostingView(rootView: FloatingRootView(store: store, heatmapVM: heatmapVM, bluetooth: bluetooth, focus: focusProvider, onHoverChanged: { [weak self] hovering in
            guard let self else { return }
            print("[DEBUG] onHoverChanged: \(hovering), mode: \(self.focusProvider.mode)")
            if hovering {
                self.hoverActive = true
                // 开启 300 毫秒延时聚焦定时器
                self.hoverFocusTimer?.invalidate()
                // 开启 300 毫秒延时聚焦定时器
                print("[DEBUG] 启动 300ms 聚焦计时器 (模式: \(self.focusProvider.mode))")
                let timer = Timer(timeInterval: 0.3, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    print("[DEBUG] 计时器触发, hoverActive: \(self.hoverActive)")
                    if self.hoverActive {
                        self.requestRegularFocus(reason: "hover_delayed")
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                self.hoverFocusTimer = timer
            } else {
                self.hoverActive = false
                // 鼠标离开，取消延时聚焦定时器
                self.hoverFocusTimer?.invalidate()
                self.hoverFocusTimer = nil
                self.scheduleRevertToAccessory()
            }
        }, onInteractionChanged: { [weak self] interacting in
            guard let self else { return }
            // 添加防抖机制，避免频繁的状态变更
            let now = CFAbsoluteTimeGetCurrent()
            // 增加防抖时间到 0.5 秒，减少状态更新频率
            if now - self.lastInteractionChange < 0.5 && self.isInteracting == interacting { return }

            self.lastInteractionChange = now
            self.isInteracting = interacting
            // 减少日志输出，只在状态真正改变时打印
            if self.isInteracting != interacting {
                print("[DEBUG] 交互状态变更: \(interacting)")
            }
        }, onClose: { [weak self] in
            self?.hide()
        }, onMinimize: { [weak self] in
            self?.minimizeToBall()
        }))
        panel.contentView = hosting

        NotificationCenter.default.addObserver(self, selector: #selector(onWindowLock(_:)), name: QuiteNoteNotification.windowLockChanged.name, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onAnimations(_:)), name: QuiteNoteNotification.animationsEnabledChanged.name, object: nil)

        // 监听窗口位置和大小变化
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidMove(_:)), name: NSWindow.didMoveNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResize(_:)), name: NSWindow.didResizeNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(onWindowKeyDidChange(_:)), name: NSWindow.didBecomeKeyNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(onWindowKeyDidChange(_:)), name: NSWindow.didResignKeyNotification, object: panel)

        // 监听浮球恢复通知
        NotificationCenter.default.addObserver(self, selector: #selector(onRestoreFromBall), name: QuiteNoteNotification.restoreFromBall.name, object: nil)

        // 监听浮球位置更新通知
        NotificationCenter.default.addObserver(self, selector: #selector(onUpdateBallPosition(_:)), name: QuiteNoteNotification.updateBallPosition.name, object: nil)
    }

    @objc private func onRestoreFromBall() {
        restoreFromBall()
    }

    @objc private func onUpdateBallPosition(_ notification: Notification) {
        guard let pos = notification.object as? CGPoint else { return }
        let size = panel.frame.size
        let newFrame = NSRect(x: pos.x - size.width/2, y: pos.y - size.height/2, width: size.width, height: size.height)
        panel.setFrame(newFrame, display: true)

        // 更新球的位置状态
        focusProvider.ballPosition = pos
    }

    /// 显示悬浮窗，不强制居中（用于静默采集等场景）
    func showWithoutCentering() {
        userHidden = false
        panel.level = .floating
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    /// 显示悬浮窗，带缩放+淡入动效
    func show() {
        print("[DEBUG] show() called")
        userHidden = false

        // 1. 确保位置正确
        forceCenterWindow()

        // 2. 重置透明度，防止动画状态残留
        panel.alphaValue = 1
        // 确保层级为浮动层级（比普通窗口高）
        panel.level = .floating

        // 3. 激活应用和窗口
        // 对于 Accessory app，顺序很重要：先激活 App，再 OrderFront
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        // 4. 执行动画
        if animationsEnabled {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = ThemeDuration._300.rawValue
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }

        focusProvider.isKeyWindow = panel.isKeyWindow
        print("[DEBUG] show() 完成，isVisible: \(panel.isVisible), isKey: \(panel.isKeyWindow)")
    }

    /// 启动期强制确保悬浮窗可见并可在当前空间显示
    /// 使用更稳健的策略：先尝试直接显示，如果失败则切换 Activation Policy
    func ensureVisibleOnLaunch(forceCenter: Bool = false) {
        print("[DEBUG] ensureVisibleOnLaunch() called - Force showing window, forceCenter: \(forceCenter)")
        userHidden = false

        // 停止之前的 Timer，避免冲突
        launchEnsurer?.invalidate()
        launchEnsurer = nil

        // 1. 基础属性重置
        panel.alphaValue = 1
        panel.isOpaque = false
        panel.level = .floating

        // 2. 设置窗口位置 - 如果不是强制居中且不在浮球状态，才恢复保存的位置
        if PreferencesManager.shared.rememberWindowPosition && !forceCenter && focusProvider.mode == .expanded {
            // 尝试恢复上次保存的窗口位置
            if let savedFrame = PreferencesManager.shared.getWindowPosition() {
                var targetScreen: NSScreen?

                // 首先尝试获取保存的屏幕
                if let screenId = PreferencesManager.shared.getWindowScreenId() {
                    targetScreen = PreferencesManager.shared.getScreenById(screenId)
                    print("[DEBUG] 尝试恢复到屏幕: \(screenId)")
                }

                // 如果找不到保存的屏幕，使用主屏幕
                if targetScreen == nil {
                    targetScreen = NSScreen.main
                    print("[DEBUG] 使用主屏幕")
                }

                // 确保窗口在屏幕范围内
                if let screen = targetScreen {
                    let screenFrame = screen.visibleFrame
                    var adjustedFrame = savedFrame

                    // 确保窗口不完全超出屏幕范围
                    if adjustedFrame.maxX < screenFrame.minX + 100 {
                        adjustedFrame.origin.x = screenFrame.minX + 100
                    }
                    if adjustedFrame.minX > screenFrame.maxX - 100 {
                        adjustedFrame.origin.x = screenFrame.maxX - adjustedFrame.width - 100
                    }
                    if adjustedFrame.maxY < screenFrame.minY + 100 {
                        adjustedFrame.origin.y = screenFrame.minY + 100
                    }
                    if adjustedFrame.minY > screenFrame.maxY - 100 {
                        adjustedFrame.origin.y = screenFrame.maxY - adjustedFrame.height - 100
                    }

                    panel.setFrame(adjustedFrame, display: true)
                    let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                    print("[DEBUG] 恢复窗口位置: \(adjustedFrame), 屏幕: \(screenNumber?.stringValue ?? "unknown")")
                }
            } else {
                // 没有保存的位置，且当前不在浮球状态，才居中
                if focusProvider.mode == .expanded {
                    forceCenterWindow()
                }
            }
        } else if !forceCenter && focusProvider.mode == .floatingBall {
            // 如果在浮球状态且不是强制居中，不改变位置，只确保显示
            print("[DEBUG] 浮球状态，不改变位置")
        } else {
            // 强制居中或其他情况
            forceCenterWindow()
        }

        // 3. 强制显示策略 (Accessory App 核心显示逻辑)
        // 步骤 A: 常规显示尝试
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        // 步骤 B: 延时强化 (保持 Accessory，不切换到 Regular，避免 Dock 显示)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            // 再次尝试激活并前置
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeKeyAndOrderFront(nil)
            self.panel.orderFrontRegardless()
            let isKey = self.panel.isKeyWindow
            let isVisible = self.panel.isVisible
            print("[DEBUG] 强化后状态: visible=\(isVisible), key=\(isKey), policy=\(NSApp.activationPolicy())")
        }
    }

    /// 隐藏悬浮窗，带缩放+淡出动效
    func hide() {
        // 标记为用户主动隐藏
        userHidden = true
        hideInternal(withAnimation: animationsEnabled)
    }

    /// 立即隐藏悬浮窗，无动画（用于截图等场景）
    func hideImmediately() {
        hideInternal(withAnimation: false)
    }

    private func hideInternal(withAnimation: Bool) {
        hoverActive = false
        revertTimer?.invalidate(); revertTimer = nil
        launchEnsurer?.invalidate(); launchEnsurer = nil

        if withAnimation {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = ThemeDuration._500.rawValue
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.6, 1.0)
                panel.animator().alphaValue = 0
            } completionHandler: { [weak panel] in
                panel?.orderOut(nil)
                panel?.alphaValue = 1
                NSApp.setActivationPolicy(.accessory)
            }
        } else {
            panel.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
        }
        focusProvider.isKeyWindow = false
    }

    @objc private func onWindowLock(_ note: Notification) {
        if let lock = note.object as? Bool {
            panel.isMovable = !lock
            // 保持 isMovableByWindowBackground 为 false，只允许 WindowDragHandler 区域拖拽
            // panel.isMovableByWindowBackground = !lock  // 注释掉，不使用全局窗口拖拽
        }
    }

    @objc private func onAnimations(_ note: Notification) {
        if let enabled = note.object as? Bool { animationsEnabled = enabled }
    }

    @objc private func onWindowKeyDidChange(_ note: Notification) {
        focusProvider.isKeyWindow = panel.isKeyWindow
    }

    @objc private func windowDidMove(_ note: Notification) {
        // 窗口移动时保存位置和屏幕信息，仅在展开模式下保存，防止保存缩放过程中的中间状态或浮球位置
        if PreferencesManager.shared.rememberWindowPosition && focusProvider.mode == .expanded {
            PreferencesManager.shared.setWindowPosition(panel.frame)

            // 如果不是正在执行恢复动画，且距离上次设置 ballPosition 超过 1 秒，则更新球体位置
            // 这是为了防止恢复动画完成后的 windowDidMove 通知覆盖正确的 ballPosition
            let now = CFAbsoluteTimeGetCurrent()
            if !focusProvider.isRestoring && (now - focusProvider.ballPositionLastSet) > 1.0 {
                focusProvider.ballPosition = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
                print("[DEBUG] windowDidMove 更新 ballPosition: \(panel.frame.midX), \(panel.frame.midY)")
            }

            // 保存当前屏幕的ID
            if let screen = panel.screen,
               let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                PreferencesManager.shared.setWindowScreenId(screenNumber.stringValue)
                print("[DEBUG] 保存窗口位置: \(panel.frame), 屏幕: \(screenNumber.stringValue)")
            }
        }
    }

    @objc private func windowDidResize(_ note: Notification) {
        // 窗口调整大小时保存位置和屏幕信息，仅在展开模式下保存
        if PreferencesManager.shared.rememberWindowPosition && focusProvider.mode == .expanded {
            PreferencesManager.shared.setWindowPosition(panel.frame)

            // 保存当前屏幕的ID
            if let screen = panel.screen,
               let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                PreferencesManager.shared.setWindowScreenId(screenNumber.stringValue)
                print("[DEBUG] 保存窗口位置(调整大小): \(panel.frame), 屏幕: \(screenNumber.stringValue)")
            }
        }
    }

    /// 悬停请求切换到 Regular 获取 KeyWindow
    func requestRegularFocus(reason: String) {
        // 如果用户主动隐藏了窗口，则不进行任何前置操作
        if userHidden { return }

        // 如果已经是关键窗口，不需要再次请求焦点
        if panel.isKeyWindow { return }

        // 记录当前活跃的应用，以便稍后还原 (仅在浮球模式且当前活跃应用不是我们自己时记录)
        if focusProvider.mode == .floatingBall {
            if let frontmost = NSWorkspace.shared.frontmostApplication,
               frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
                self.previousApp = frontmost
                print("[DEBUG] requestFocus: 记录上一个活跃应用: \(frontmost.localizedName ?? "unknown")")
            }
        }

        hoverActive = true
        print("[DEBUG] requestFocus(\(reason)) policy=\(NSApp.activationPolicy()) isKey=\(panel.isKeyWindow)")

        // 强制激活应用并置顶
        DispatchQueue.main.async {
            // 对于某些 macOS 版本，需要先设置为 regular 才能可靠获取焦点
            // 但为了不显示 Dock 图标，我们尽量保持 accessory 并使用更强力的激活方法
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeKeyAndOrderFront(nil)
            self.panel.orderFrontRegardless()
            self.panel.makeKey() // 显式请求成为关键窗口

            // 验证是否成功
            print("[DEBUG] 激活请求已发出，当前 key 状态: \(self.panel.isKeyWindow)")
        }
    }

    /// 悬停离开后回退到 Accessory（防抖）
    func scheduleRevertToAccessory() {
        // 如果用户主动隐藏了窗口，则直接返回，不进行回退策略（避免前置）
        if userHidden { return }

        hoverActive = false
        // 取消可能的聚焦定时器
        hoverFocusTimer?.invalidate()
        hoverFocusTimer = nil

        revertTimer?.invalidate()
        // 缩短延迟时间到 0.3 秒，让离开后的响应更灵敏，同时保留基础防抖
        revertTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self else { return }
            // 只有在非悬停且非交互状态下才回退到 Accessory
            if !self.hoverActive && !self.isInteracting && !self.userHidden {

                // 还原焦点到上一个应用 (仅在浮球模式且有记录时)
                if self.focusProvider.mode == .floatingBall, let prevApp = self.previousApp {
                    if !prevApp.isTerminated {
                        print("[DEBUG] scheduleRevertToAccessory: 尝试还原焦点到: \(prevApp.localizedName ?? "unknown")")
                        // 只有当我们仍然是活跃应用时才还原，避免干扰用户手动切换到其他应用
                        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
                            prevApp.activate(options: .activateIgnoringOtherApps)
                        }
                    }
                    self.previousApp = nil
                }

                // 如果窗口不是关键窗口，或者我们主动要交还焦点 (浮球模式下移走即还)，则切回 accessory 模式
                if !self.panel.isKeyWindow || self.focusProvider.mode == .floatingBall {
                    NSApp.setActivationPolicy(.accessory)
                    self.panel.orderFrontRegardless()
                    print("[DEBUG] revertToAccessory policy=\(NSApp.activationPolicy()) isKey=\(self.panel.isKeyWindow)")
                }
            }
        }
    }

    /// 强制窗口居中显示（调试用）
    func forceCenterWindow() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        // 使用主题文件中的尺寸定义
        let windowWidth: CGFloat = 520
        let windowHeight: CGFloat = 640
        let centerX = screenFrame.midX - (windowWidth / 2)
        let centerY = screenFrame.midY - (windowHeight / 2)

        let newFrame = NSRect(x: centerX, y: centerY, width: windowWidth, height: windowHeight)
        panel.setFrame(newFrame, display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        print("[DEBUG] 强制窗口居中，新位置: \(newFrame)")
    }

    /// 显示设置界面
    func showSettings() {
        // 通过 NotificationCenter 通知 FloatingRootView 显示设置界面
        QuiteNoteNotification.post(.showSettings)
    }

    /// 最小化到浮球
    func minimizeToBall() {
        print("[DEBUG] minimizeToBall called, mode: \(focusProvider.mode)")
        guard focusProvider.mode == .expanded else {
            print("[DEBUG] minimizeToBall guard failed, not in expanded mode")
            return
        }

        let currentFrame = panel.frame
        focusProvider.lastExpandedFrame = currentFrame

        // 如果开启了记忆位置，也同步到持久化存储
        if PreferencesManager.shared.rememberWindowPosition {
            PreferencesManager.shared.setWindowPosition(currentFrame)
        }

        // 减小窗口尺寸以保持精致感 (80x80)，球体本身为 56x56
        let ballWindowSize: CGFloat = 80

        // 核心修复：优先使用之前保存的 ballPosition，防止边缘漂移
        let targetCenter = focusProvider.ballPosition != .zero ? focusProvider.ballPosition : CGPoint(x: currentFrame.midX, y: currentFrame.midY)

        let targetFrame = NSRect(x: targetCenter.x - ballWindowSize/2,
                               y: targetCenter.y - ballWindowSize/2,
                               width: ballWindowSize,
                               height: ballWindowSize)

        // 1. 同步执行模式切换和窗口框架动画
        // 使用相同的时长和曲线，确保视觉同步
        let duration: TimeInterval = 0.35

        // 先切换背景和阴影，避免动画过程中出现黑边或奇怪的阴影
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = false

        // 先切换模式（SwiftUI 动画）
        withAnimation(.easeInOut(duration: duration)) {
            self.focusProvider.mode = .floatingBall
        }

        // 延迟一小段时间后开始窗口动画，确保 SwiftUI 动画已经启动
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                self.panel.animator().setFrame(targetFrame, display: true)
            } completionHandler: {
                // 动画完成后，使用 targetFrame（理论值）而不是 panel.frame（实际值）
                // 因为 macOS 窗口系统可能会有微小的位置调整，导致实际值不准确
                let targetCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)

                // 延迟检查实际位置，用于调试
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    let actualFrame = self.panel.frame
                    let actualCenter = CGPoint(x: actualFrame.midX, y: actualFrame.midY)

                    if abs(actualCenter.x - targetCenter.x) > 1 || abs(actualCenter.y - targetCenter.y) > 1 {
                        print("[DEBUG] ⚠️ minimizeToBall 位置偏差！预期(使用): \(targetCenter.x), \(targetCenter.y) | 实际(忽略): \(actualCenter.x), \(actualCenter.y)")
                    }

                    // 使用目标位置而不是实际位置
                    self.focusProvider.ballPosition = targetCenter
                    self.focusProvider.ballPositionLastSet = CFAbsoluteTimeGetCurrent()
                    print("[DEBUG] minimizeToBall 完成，ballPosition(使用目标值): \(targetCenter.x), \(targetCenter.y)")
                }
            }
        }
    }

    /// 从浮球恢复
    func restoreFromBall() {
        guard focusProvider.mode == .floatingBall else { return }

        let ballFrame = panel.frame
        let actualBallCenter = CGPoint(x: ballFrame.midX, y: ballFrame.midY)

        // 关键修复：使用已保存的 ballPosition 而不是 panel.frame
        // 因为 panel.frame 可能被 macOS 窗口系统调整过，导致位置漂移
        let ballCenter = focusProvider.ballPosition != .zero ? focusProvider.ballPosition : actualBallCenter

        print("[DEBUG] restoreFromBall 开始，实际浮球中心: \(actualBallCenter.x), \(actualBallCenter.y)")
        print("[DEBUG] restoreFromBall 使用保存的 ballPosition: \(ballCenter.x), \(ballCenter.y)")

        focusProvider.ballPositionLastSet = CFAbsoluteTimeGetCurrent()
        focusProvider.isRestoring = true

        // 标准尺寸
        let defaultWidth: CGFloat = 520
        let defaultHeight: CGFloat = 640

        var targetWidth = defaultWidth
        var targetHeight = defaultHeight

        // 如果开启了记忆位置，尝试使用上次展开的尺寸
        if PreferencesManager.shared.rememberWindowPosition, let savedFrame = focusProvider.lastExpandedFrame {
            targetWidth = max(defaultWidth, savedFrame.width)
            targetHeight = max(defaultHeight, savedFrame.height)
        }

        // 核心逻辑：以当前浮球中心为原点，均匀展开
        var targetX = ballCenter.x - (targetWidth / 2)
        var targetY = ballCenter.y - (targetHeight / 2)

        // 屏幕边界适配
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        let padding: CGFloat = 16

        let originalTargetY = targetY
        if targetX < screenFrame.minX + padding { targetX = screenFrame.minX + padding }
        else if targetX + targetWidth > screenFrame.maxX - padding { targetX = screenFrame.maxX - targetWidth - padding }

        if targetY < screenFrame.minY + padding { targetY = screenFrame.minY + padding }
        else if targetY + targetHeight > screenFrame.maxY - padding { targetY = screenFrame.maxY - targetHeight - padding }

        if targetY != originalTargetY {
            print("[DEBUG] restoreFromBall Y 被调整: \(originalTargetY) -> \(targetY)")
        }

        let targetFrame = NSRect(x: targetX, y: targetY, width: targetWidth, height: targetHeight)

        // 如果开启了记忆位置，更新记忆的位置
        if PreferencesManager.shared.rememberWindowPosition {
            focusProvider.lastExpandedFrame = targetFrame
            PreferencesManager.shared.setWindowPosition(targetFrame)
        }

        let duration: TimeInterval = 0.4

        // 同步开始模式切换和框架动画
        withAnimation(.spring(response: duration, dampingFraction: 0.8)) {
            focusProvider.mode = .expanded
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self, weak focusProvider, weak panel] in
            guard let self = self else { return }
            // 动画结束后，延迟处理
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                // 恢复背景
                panel?.backgroundColor = NSColor.clear.withAlphaComponent(0.9)
                panel?.hasShadow = true

                // 读取实际窗口位置用于调试
                let actualFrame = panel?.frame ?? targetFrame
                let actualCenter = CGPoint(x: actualFrame.midX, y: actualFrame.midY)
                let expectedCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)

                if abs(actualCenter.x - expectedCenter.x) > 1 || abs(actualCenter.y - expectedCenter.y) > 1 {
                    print("[DEBUG] ⚠️ restoreFromBall 窗口位置偏差！预期: \(expectedCenter.x), \(expectedCenter.y) | 实际: \(actualCenter.x), \(actualCenter.y)")
                }

                // 关键：始终使用原始保存的 ballCenter，保持浮球位置不变
                focusProvider?.ballPosition = ballCenter
                focusProvider?.ballPositionLastSet = CFAbsoluteTimeGetCurrent()
                focusProvider?.isRestoring = false

                print("[DEBUG] restoreFromBall 完成，ballPosition 保持为: \(ballCenter.x), \(ballCenter.y)")

                // 恢复后强制获取一次焦点，确保搜索框等组件可用
                self.requestRegularFocus(reason: "restore")
            }
        }
    }
}
