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

    /// 浮球模式下系统侧的窗口摆放（order front 位置约束、标题栏拖拽、空间切换等）
    /// 一律经 BallEdgeGeometry 钳回可视区域。此前窗口一旦被系统摆到部分出屏，
    /// 会被推回来再被拖拽逻辑摆回去，来回拉扯表现为边缘闪跳；覆写这里之后
    /// 系统不再有机会把 80pt 窗口放到出屏/贴边打架的位置。
    var isBallMode: Bool = false

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard isBallMode else { return super.constrainFrameRect(frameRect, to: screen) }
        var frame = super.constrainFrameRect(frameRect, to: screen)
        let screens = NSScreen.screens.map {
            BallEdgeGeometry.ScreenBounds(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        let clamped = BallEdgeGeometry.clampDrag(
            center: CGPoint(x: frame.midX, y: frame.midY),
            windowSize: frame.width,
            screens: screens
        )
        frame.origin.x = clamped.x - frame.width / 2
        frame.origin.y = clamped.y - frame.height / 2
        return frame
    }
}

enum WindowMode {
    case expanded
    case floatingBall
}

final class WindowFocusProvider: ObservableObject {
    /// 形变视觉状态：纯渲染 transform（scaleEffect/opacity），不改布局、不改
    /// 视图树结构，因此不会触发 NSHostingView 的窗口尺寸回写——这是球↔面板
    /// 形变唯一安全的方向性动效手段（transition/窗口逐帧动画都会闪退，见
    /// FloatingPanelController 形变注释）
    struct MorphVisual {
        var scale: CGFloat
        var opacity: Double
        var anchor: UnitPoint
        static let identity = MorphVisual(scale: 1, opacity: 1, anchor: .center)
    }

    @Published var isKeyWindow: Bool = false
    @Published var mode: WindowMode = .expanded
    @Published var ballPosition: CGPoint = .zero
    @Published var lastExpandedFrame: NSRect? = nil
    @Published var morph: MorphVisual = .identity
    var isRestoring: Bool = false // 新增：标记是否正在从浮球恢复，用于防止坐标漂移
    var ballPositionLastSet: TimeInterval = 0 // 记录 ballPosition 最后设置的时间，用于防止 windowDidMove 覆盖
}

// MARK: - FloatingPanelController

private typealias MorphVisual = WindowFocusProvider.MorphVisual

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
    private var windowLocked: Bool = false // 窗口锁定状态（展开模式下决定 isMovable）
    private var isProgrammaticallyMovingBall: Bool = false // 区分我们的 setFrame 与系统侧移动，用于外部移动日志
    private var isAnimatingWindowFrame: Bool = false // 窗口 frame 动画进行中（展开形变），期间 windowDidMove/Resize 不逐帧写 UserDefaults

    var isVisible: Bool { panel.isVisible }
    
    /// 检查鼠标是否在面板或浮球上
    func isMouseOverPanel() -> Bool {
        guard panel.isVisible else { return false }
        let mouseLocation = NSEvent.mouseLocation
        return panel.frame.contains(mouseLocation)
    }

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
        panel.level = .mainMenu + 2  // 高于便签窗口的 .mainMenu + 1
        // 恢复关键行为：允许在所有桌面显示，允许在全屏应用之上显示
        // 去掉了 .moveToActiveSpace 以防止初始化卡死
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden  // 隐藏标题栏
        panel.titlebarAppearsTransparent = true  // 标题栏透明
        panel.backgroundColor = NSColor.clear.withAlphaComponent(0.9) // 设置为透明背景，让SwiftUI内容显示
        // 强制深色外观（与 OCR 结果面板一致）：系统浅色外观下，TextField 输入文字/占位符等
        // 依赖系统默认色的文本会解析成黑色，打在深色主题背景上不可见
        panel.appearance = NSAppearance(named: .darkAqua)
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
        // ⚠️ 关键修复（2026-08-17 两次闪退根因）：禁止 SwiftUI 驱动窗口尺寸。
        // NSHostingView 默认会按内容理想尺寸反向调整窗口大小，与手动 setFrame
        // 相互触发形成布局死循环 → NSGenericException "Update Constraints in
        // Window passes" → 闪退。窗口尺寸一律由本控制器手动管理（展开/浮球/恢复）。
        hosting.sizingOptions = []
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

        // 监听浮球松手吸附通知（控制器以 panel.frame 为准计算，视图侧不再持有位置真值）
        NotificationCenter.default.addObserver(self, selector: #selector(onSnapBallToEdge), name: QuiteNoteNotification.snapBallToEdge.name, object: nil)

        // 屏幕参数变化（接线/分辨率/Dock 大小变动）时刷新缓存
        NotificationCenter.default.addObserver(self, selector: #selector(onScreenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func onRestoreFromBall() {
        restoreFromBall()
    }

    @objc private func onSnapBallToEdge() {
        guard focusProvider.mode == .floatingBall else { return }
        let size = panel.frame.size
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let snapped = BallEdgeGeometry.snapCenter(center, visualRadius: 28, screens: currentScreenBounds())
        let newFrame = NSRect(x: snapped.x - size.width/2, y: snapped.y - size.height/2, width: size.width, height: size.height)
        isProgrammaticallyMovingBall = true
        panel.setFrame(newFrame, display: true)
        DispatchQueue.main.async { [weak self] in self?.isProgrammaticallyMovingBall = false }
        // 拖动过程中不发布中间位置，松手吸附时一次性更新（见 onUpdateBallPosition 注释）
        focusProvider.ballPosition = snapped
    }

    @objc private func onScreenParametersChanged() {
        screenBoundsCache = nil
    }

    @objc private func onUpdateBallPosition(_ notification: Notification) {
        guard let pos = notification.object as? CGPoint else { return }
        let size = panel.frame.size
        // 拖拽时鼠标可进入菜单栏/Dock/屏幕边缘，先把球心钳回可视区域内：
        // 窗口一旦部分出屏，macOS 置前时会把它推回来，与拖拽的 setFrame
        // 互相拉扯，表现为浮球在屏幕边缘来回闪跳
        let clamped = BallEdgeGeometry.clampDrag(
            center: pos,
            windowSize: size.width,
            screens: currentScreenBounds()
        )
        let newFrame = NSRect(x: clamped.x - size.width/2, y: clamped.y - size.height/2, width: size.width, height: size.height)
        isProgrammaticallyMovingBall = true
        panel.setFrame(newFrame, display: true)
        DispatchQueue.main.async { [weak self] in self?.isProgrammaticallyMovingBall = false }

        // 注意：拖动过程中故意不发布 ballPosition——@Published 逐帧更新会让
        // 整棵 SwiftUI 视图树跟着每个鼠标事件重算，拖动明显不跟手；
        // 位置真值在窗口 frame 上，松手吸附（onSnapBallToEdge）/恢复时才发布
    }

    /// 屏幕信息缓存：NSScreen.screens 是窗口服务器往返查询，拖动时逐事件
    /// 调用会拖慢跟手度；缓存 + 2 秒 TTL 兜住 Dock 移动等不发通知的变化
    private var screenBoundsCache: [BallEdgeGeometry.ScreenBounds]?
    private var screenBoundsCachedAt: TimeInterval = 0

    private func currentScreenBounds() -> [BallEdgeGeometry.ScreenBounds] {
        let now = CFAbsoluteTimeGetCurrent()
        if let cache = screenBoundsCache, now - screenBoundsCachedAt < 2.0 {
            return cache
        }
        let bounds = NSScreen.screens.map {
            BallEdgeGeometry.ScreenBounds(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        screenBoundsCache = bounds
        screenBoundsCachedAt = now
        return bounds
    }

    /// 显示悬浮窗，不强制居中（用于静默采集等场景）
    func showWithoutCentering() {
        userHidden = false
        panel.level = .mainMenu + 2  // 高于便签窗口的 .mainMenu + 1
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
        focusProvider.morph = .identity // 防御：中断的形变不得把面板卡在缩小/透明态
        // 确保层级高于便签窗口
        panel.level = .mainMenu + 2  // 高于便签窗口的 .mainMenu + 1

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
        focusProvider.morph = .identity // 防御：中断的形变不得把面板卡在缩小/透明态
        panel.isOpaque = false
        panel.level = .mainMenu + 2  // 高于便签窗口的 .mainMenu + 1

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
        // P2.4: 添加日志追踪
        print("[FloatingPanel] hide() called - stack trace:")
        Thread.callStackSymbols.forEach { print("  \($0)") }

        // 标记为用户主动隐藏
        userHidden = true
        hideInternal(withAnimation: animationsEnabled)
    }

    /// 立即隐藏悬浮窗，无动画（用于截图等场景）
    func hideImmediately() {
        print("[FloatingPanel] hideImmediately() called - stack trace:")
        Thread.callStackSymbols.forEach { print("  \($0)") }
        hideInternal(withAnimation: false)
    }

    private func hideInternal(withAnimation: Bool) {
        print("[FloatingPanel] hideInternal(withAnimation: \(withAnimation))")
        hoverActive = false
        revertTimer?.invalidate(); revertTimer = nil
        launchEnsurer?.invalidate(); launchEnsurer = nil

        if withAnimation {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = ThemeDuration._500.rawValue
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.6, 1.0)
                panel.animator().alphaValue = 0
            } completionHandler: { [weak panel] in
                print("[FloatingPanel] hideInternal - orderOut completed")
                panel?.orderOut(nil)
                panel?.alphaValue = 1
                NSApp.setActivationPolicy(.accessory)
            }
        } else {
            print("[FloatingPanel] hideInternal - immediate orderOut")
            panel.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
        }
        focusProvider.isKeyWindow = false
    }

    @objc private func onWindowLock(_ note: Notification) {
        if let lock = note.object as? Bool {
            windowLocked = lock
            // 浮球模式下窗口一律不可系统拖拽（球有自己的拖拽手势），
            // 展开模式按用户的锁定状态来
            panel.isMovable = focusProvider.mode == .expanded ? !lock : false
        }
    }

    @objc private func onAnimations(_ note: Notification) {
        if let enabled = note.object as? Bool { animationsEnabled = enabled }
    }

    @objc private func onWindowKeyDidChange(_ note: Notification) {
        focusProvider.isKeyWindow = panel.isKeyWindow
    }

    @objc private func windowDidMove(_ note: Notification) {
        // 浮球模式下出现「非我们 setFrame」的移动，说明有系统侧力量在动窗口
        // （order front 约束 / 标题栏拖拽 / 空间切换）——这是边缘闪跳的元凶特征，
        // 落盘留证便于定位
        if focusProvider.mode == .floatingBall && !isProgrammaticallyMovingBall {
            DiagnosticCenter.warning("Panel", "浮球窗口被外部移动: frame=\(panel.frame)")
        }

        // 窗口移动时保存位置和屏幕信息，仅在展开模式下保存，防止保存缩放过程中的中间状态或浮球位置；
        // 形变动画期间逐帧保存是卡顿源，结束后一次性保存
        if PreferencesManager.shared.rememberWindowPosition && focusProvider.mode == .expanded && !isAnimatingWindowFrame {
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
        // 窗口调整大小时保存位置和屏幕信息，仅在展开模式下保存；形变动画期间跳过（结束后一次性保存）
        if PreferencesManager.shared.rememberWindowPosition && focusProvider.mode == .expanded && !isAnimatingWindowFrame {
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

        // 拖拽中不抢焦点：中途 makeKeyAndOrderFront 会触发系统对出屏窗口的
        // 位置约束，与拖拽的 setFrame 拉扯造成边缘闪跳，还可能打断拖拽手势
        if isInteracting { return }

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
        // P2.4: 添加详细的堆栈追踪日志
        print("[FloatingPanel] minimizeToBall() called - stack trace:")
        Thread.callStackSymbols.forEach { print("  \($0)") }
        print("[FloatingPanel] minimizeToBall - mode: \(focusProvider.mode), frame: \(panel.frame)")

        guard focusProvider.mode == .expanded else {
            print("[FloatingPanel] minimizeToBall guard failed, not in expanded mode")
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

        // ⚠️ 形变安全配方（08-21 五连闪退实锤后的结论，最新 crash-1787251170）：
        // macOS 26 上 NSHostingView 会在内容切换/SwiftUI 过渡（transition）期间经
        // updateAnimatedWindowSize 把窗口回写成内容的过渡期理想尺寸
        // （sizingOptions=[] 拦不住），与布局互相触发约束循环 → NSGenericException。
        // 因此：① 不做窗口 frame 逐帧动画；② 内容切换不包 withAnimation/transition，
        // 只在窗口内容不可见时瞬时换；③ 方向性动效只走 morph（scaleEffect/opacity
        // 纯渲染 transform，不改布局不改树）。
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = false
        panel.isBallMode = true
        panel.isMovable = false

        // 收缩形变：面板内容向球所在位置缩小并淡出
        withAnimation(.easeIn(duration: 0.28)) {
            focusProvider.morph = MorphVisual(
                scale: 0.02,
                opacity: 0,
                anchor: morphAnchor(ballCenter: targetCenter, in: currentFrame)
            )
        }

        // 收缩动画结束后（内容已透明不可见）：瞬时落位换内容，球从小放大出现
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.31) { [weak self] in
            guard let self, self.focusProvider.mode == .expanded else { return }
            self.panel.setFrame(targetFrame, display: false)
            self.focusProvider.mode = .floatingBall
            self.focusProvider.ballPosition = targetCenter
            self.focusProvider.ballPositionLastSet = CFAbsoluteTimeGetCurrent()
            // 球淡入（transform 动画；窗口 alpha 保持 1，透明窗口无残影）
            self.focusProvider.morph = MorphVisual(scale: 0.6, opacity: 0, anchor: .center)
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                    self.focusProvider.morph = .identity
                }
            }
        }
    }

    /// 球心在给定窗口 frame 内的 SwiftUI 锚点（顶左原点，AppKit 全局坐标是底左原点）
    private func morphAnchor(ballCenter: CGPoint, in frame: NSRect) -> UnitPoint {
        UnitPoint(
            x: (ballCenter.x - frame.minX) / max(frame.width, 1),
            y: (frame.maxY - ballCenter.y) / max(frame.height, 1)
        )
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

        // 还原为原版动画机制：窗口 frame 从球大小逐帧长到面板大小（0.4s
        // easeInEaseOut，与原版完全一致），内容以真实尺寸逐帧布局——这就是
        // 「慢慢放大」观感的来源。与原版的唯一差别（也是闪退的修复）：
        // 内容切换为瞬时、不包 withAnimation——约束闪退链的触发条件是
        // 「内容过渡动画」与「窗口逐帧 resize」并发（NSHostingView 会把
        // 过渡期理想尺寸回写窗口），纯窗口缩放 + 静态内容树是安全的
        // （正常 app 的窗口缩放从不触发）。
        focusProvider.isRestoring = true
        isAnimatingWindowFrame = true

        panel.backgroundColor = NSColor.clear.withAlphaComponent(0.9)
        panel.isBallMode = false
        panel.isMovable = !windowLocked
        focusProvider.mode = .expanded // 瞬时换内容（无过渡动画）

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                self.isAnimatingWindowFrame = false
                self.panel.hasShadow = true
                // 结束后一次性保存位置（动画期间逐帧写 UserDefaults 是卡顿源）
                if PreferencesManager.shared.rememberWindowPosition {
                    PreferencesManager.shared.setWindowPosition(self.panel.frame)
                    if let screen = self.panel.screen,
                       let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                        PreferencesManager.shared.setWindowScreenId(screenNumber.stringValue)
                    }
                }
                // 关键：始终使用原始保存的 ballCenter，保持浮球位置不变
                self.focusProvider.ballPosition = ballCenter
                self.focusProvider.ballPositionLastSet = CFAbsoluteTimeGetCurrent()
                self.focusProvider.isRestoring = false
                // 恢复后强制获取一次焦点，确保搜索框等组件可用
                self.requestRegularFocus(reason: "restore")
            }
        }
    }
}
