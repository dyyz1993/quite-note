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
}


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
    private var revertTimer: Timer?
    private var lastSwitchAt: TimeInterval = 0
    private var isInteracting: Bool = false // 跟踪用户是否正在交互（拖拽、点击等）
    private var lastInteractionChange: TimeInterval = 0 // 记录上次交互状态变更时间
    private var userHidden: Bool = false // 用户主动隐藏标记，防止自动前置
    
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
        panel.isMovableByWindowBackground = !PreferencesManager.shared.windowLock
        panel.hasShadow = true // Ensure shadow is visible for borderless window
        
        // Hide system buttons
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        
        hosting = NSHostingView(rootView: FloatingRootView(store: store, heatmapVM: heatmapVM, bluetooth: bluetooth, focus: focusProvider, onHoverChanged: { [weak self] hovering in
            guard let self else { return }
            if hovering { self.requestRegularFocus(reason: "hover") } else { self.scheduleRevertToAccessory() }
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
        
        NotificationCenter.default.addObserver(self, selector: #selector(onWindowLock(_:)), name: .windowLockChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onAnimations(_:)), name: .animationsEnabledChanged, object: nil)
        
        // 监听窗口位置和大小变化
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidMove(_:)), name: NSWindow.didMoveNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResize(_:)), name: NSWindow.didResizeNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(onWindowKeyDidChange(_:)), name: NSWindow.didBecomeKeyNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(onWindowKeyDidChange(_:)), name: NSWindow.didResignKeyNotification, object: panel)
        
        // 监听浮球恢复通知
        NotificationCenter.default.addObserver(self, selector: #selector(onRestoreFromBall), name: Notification.Name("restoreFromBall"), object: nil)
        
        // 监听浮球位置更新通知
        NotificationCenter.default.addObserver(self, selector: #selector(onUpdateBallPosition(_:)), name: Notification.Name("updateBallPosition"), object: nil)
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
            guard let self = self else { return }
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
        // 标记为用户主动隐藏，并清理可能导致再次前置的定时器/状态
        userHidden = true
        hoverActive = false
        revertTimer?.invalidate(); revertTimer = nil
        launchEnsurer?.invalidate(); launchEnsurer = nil
        
        if animationsEnabled {
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
            panel.isMovableByWindowBackground = !lock
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
            
            // 如果不是正在执行恢复动画，则更新球体位置，以便下次缩小时能缩回到新位置
            if !focusProvider.isRestoring {
                focusProvider.ballPosition = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
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

        let now = CFAbsoluteTimeGetCurrent()
        // 增加节流时间到 1 秒，减少频繁的焦点切换
        if now - lastSwitchAt < 1.0 { return }
        // 如果已经是关键窗口，不需要再次请求焦点
        if panel.isKeyWindow { return }
        
        lastSwitchAt = now
        hoverActive = true
        print("[DEBUG] requestFocus(\(reason)) policy=\(NSApp.activationPolicy()) isKey=\(panel.isKeyWindow)")
        // 保持 Accessory，直接激活并前置
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeKeyAndOrderFront(nil)
            self.panel.orderFrontRegardless()
        }
    }

    /// 悬停离开后回退到 Accessory（防抖）
    func scheduleRevertToAccessory() {
        // 如果用户主动隐藏了窗口，则直接返回，不进行回退策略（避免前置）
        if userHidden { return }

        hoverActive = false
        revertTimer?.invalidate()
        // 增加延迟时间，减少频繁的状态切换
        revertTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            // 只有在非悬停且非交互状态下才回退到 Accessory
            // 增加额外检查：确保窗口不是关键窗口
            if !self.hoverActive && !self.isInteracting && !self.userHidden && !self.panel.isKeyWindow {
                NSApp.setActivationPolicy(.accessory)
                self.panel.orderFrontRegardless()
                print("[DEBUG] revertToAccessory policy=\(NSApp.activationPolicy()) isKey=\(self.panel.isKeyWindow)")
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
        NotificationCenter.default.post(name: .showSettings, object: nil)
    }

    /// 最小化到浮球
    func minimizeToBall() {
        guard focusProvider.mode == .expanded else { return }
        
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
        
        // 1. 启动窗口框架动画
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        }
        
        // 2. 稍微延迟模式切换，让窗口先动起来，产生“折叠”感
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.focusProvider.mode = .floatingBall
            }
        }
        
        // 更新浮球位置状态 (确保一致性)
        focusProvider.ballPosition = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        
        // 浮球状态下允许点击穿透背景
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = false // 浮球自带阴影效果
    }
    
    /// 从浮球恢复
    func restoreFromBall() {
        guard focusProvider.mode == .floatingBall else { return }
        
        let ballFrame = panel.frame
        let ballCenter = CGPoint(x: ballFrame.midX, y: ballFrame.midY)
        
        // 记录当前的球心，用于防止展开时的边界适配导致下次缩小位置偏移
        focusProvider.ballPosition = ballCenter
        focusProvider.isRestoring = true
        
        // 标准尺寸
        let defaultWidth: CGFloat = 520
        let defaultHeight: CGFloat = 640
        
        var targetWidth = defaultWidth
        var targetHeight = defaultHeight
        
        // 如果开启了记忆位置，尝试使用上次展开的尺寸
        if PreferencesManager.shared.rememberWindowPosition, let savedFrame = focusProvider.lastExpandedFrame {
            // 确保尺寸合理，防止出现尺寸过小的问题
            targetWidth = max(defaultWidth, savedFrame.width)
            targetHeight = max(defaultHeight, savedFrame.height)
        }
        
        // 核心逻辑：以当前浮球中心为原点，均匀展开
        var targetX = ballCenter.x - (targetWidth / 2)
        var targetY = ballCenter.y - (targetHeight / 2)
        
        // 屏幕边界适配
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        let padding: CGFloat = 16 // 距离屏幕边缘的最小留白
        
        // 检查并修正 X 轴位置
        if targetX < screenFrame.minX + padding {
            targetX = screenFrame.minX + padding
        } else if targetX + targetWidth > screenFrame.maxX - padding {
            targetX = screenFrame.maxX - targetWidth - padding
        }
        
        // 检查并修正 Y 轴位置
        if targetY < screenFrame.minY + padding {
            targetY = screenFrame.minY + padding
        } else if targetY + targetHeight > screenFrame.maxY - padding {
            targetY = screenFrame.maxY - targetHeight - padding
        }
        
        let targetFrame = NSRect(x: targetX, y: targetY, width: targetWidth, height: targetHeight)
        
        // 如果开启了记忆位置，更新记忆的位置为当前展开后的位置
        if PreferencesManager.shared.rememberWindowPosition {
            focusProvider.lastExpandedFrame = targetFrame
            PreferencesManager.shared.setWindowPosition(targetFrame)
        }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            focusProvider.mode = .expanded
        }
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak focusProvider] in
            // 动画结束后重置恢复状态
            focusProvider?.isRestoring = false
        }
        
        panel.backgroundColor = NSColor.clear.withAlphaComponent(0.9)
        panel.hasShadow = true
    }
}

/// 悬浮窗根视图
struct FloatingRootView: View {
    @ObservedObject var store: RecordStore
    @ObservedObject var heatmapVM: HeatmapViewModel
    @ObservedObject var bluetooth: BluetoothManager
    @ObservedObject var focus: WindowFocusProvider
    var onHoverChanged: ((Bool) -> Void)? = nil
    var onInteractionChanged: ((Bool) -> Void)? = nil
    var onClose: (() -> Void)? = nil
    var onMinimize: (() -> Void)? = nil
    @State private var showSettings = false
    @State private var settingsTab: String = "ai"
    @State private var expandedId: UUID? = nil
    @State private var searchTerm: String = ""
    @State private var searchResults: [Record] = [] // 缓存搜索结果
    @State private var isLoadingMore: Bool = false // 是否正在加载更多
    @State private var hasMoreRecords: Bool = true // 是否还有更多记录

    var body: some View {
        ZStack {
            if focus.mode == .floatingBall {
                FloatingBallView(store: store, focus: focus)
                    .transition(.opacity)
                    .zIndex(1)
            } else {
                baseContentView
                    .background(Color.themeBackground.opacity(0.9))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.themeBorder, lineWidth: 1).allowsHitTesting(false))
                    .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
                    .transition(.opacity)
                    .zIndex(0)
            }
        }
        .ignoresSafeArea()
        .onHover { hovering in onHoverChanged?(hovering) }
        .simultaneousGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onChanged { _ in onInteractionChanged?(true) }
                .onEnded { _ in onInteractionChanged?(false) }
        )
        .allowsHitTesting(true)
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            // 响应显示设置界面的通知
            showSettings = true
            settingsTab = "ai"
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("expandRecord"))) { notification in
            // 响应展开特定记录的通知
            if let recordId = notification.object as? UUID {
                expandedId = recordId
                showSettings = false // 确保不在设置界面
            }
        }
        .modifier(KeyboardHandlerModifier(
            expandedId: $expandedId,
            showSettings: $showSettings,
            onClose: onClose
        ))
    }
    
    // MARK: - 子视图组件
    
    /// 基础内容视图，包含主要的布局结构
    private var baseContentView: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                // Left Sidebar (Activity)
                sidebarView
                
                // Right Main Content
                mainContentView
            }
            
            // Toast Overlay (Elevated to top level)
            toastOverlayView
        }
    }
    
    /// Toast 覆盖层视图
    @ViewBuilder
    private var toastOverlayView: some View {
        if let toast = store.toast {
            ToastView(message: toast)
                .padding(.top, 32)
                .padding(.trailing, 32)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
        }
    }
    
    // MARK: - 辅助视图
    
    /// 左侧边栏视图
    private var sidebarView: some View {
        ZStack(alignment: .top) {
            Color.themePanel // 使用主题文件中的面板颜色
            WindowDragHandler() // Allow dragging on sidebar background
            
            HeatmapView(vm: heatmapVM)
        }
        .frame(width: ThemeSpacing.w16.rawValue) // 使用主题文件中的宽度定义
        .zIndex(10) // Fix Tooltip Z-Index (Ensure it renders above Main Content)
        .overlay(Rectangle().frame(width: ThemeSpacing.border1, height: nil, alignment: .trailing).foregroundColor(Color.themeBorder).allowsHitTesting(false), alignment: .trailing)
    }
    
    /// 右侧主内容视图
    private var mainContentView: some View {
        ZStack {
            Color.themeBackground.opacity(0.9) // bg-gray-900/90
            
            VStack(spacing: 0) {
                headerView
                contentView
            }
        }
    }
    
    /// 头部视图
    private var headerView: some View {
        HStack {
            // Window Controls (Custom Red Dot)
            HStack(spacing: ThemeSpacing.px2.rawValue) {
                // Close (Red)
                CloseButton(onClose: onClose)
                
                // Minimize (Yellow)
                ShrinkButton(onMinimize: onMinimize)
            }
            .padding(.leading, ThemeSpacing.px4.rawValue)
            
            Spacer()
            
            Text(showSettings ? "偏好设置" : "闪记")
                .font(.themeH2) // 使用主题文件中的字体定义
                .foregroundColor(.themeTextPrimary) // 使用主题文件中的文本颜色
            
            Spacer()
            
            // Bluetooth Icon (Lucide)
            bluetoothView
        }
        .frame(height: ThemeSpacing.h12.rawValue) // 使用主题文件中的高度定义
        .background(
            ZStack {
                Color.themeBackground.opacity(0.5) // bg-gray-900/50
                WindowDragHandler() // Allow dragging on header background
            }
        )
        .overlay(Rectangle().frame(width: nil, height: ThemeSpacing.border1, alignment: .bottom).foregroundColor(Color.themeBorder).allowsHitTesting(false), alignment: .bottom)
    }
    
    /// 蓝牙视图
    private var bluetoothView: some View {
        HStack(spacing: ThemeSpacing.px3.rawValue) {
            Group {
                if let name = bluetooth.connectedDeviceName {
                    LucideView(name: .bluetoothConnected, size: 14, color: .themeBlue400)
                        .help("已连接: \(name)")
                } else if bluetooth.state == .poweredOn {
                    LucideView(name: .bluetooth, size: 14, color: .themeYellow500)
                        .help("蓝牙已开启，未连接")
                } else {
                    LucideView(name: .bluetoothOff, size: 14, color: .themeTextTertiary)
                        .help("蓝牙未开启")
                }
            }
            .font(.themeBody)
            .frame(width: ThemeSpacing.px4.rawValue, height: ThemeSpacing.px4.rawValue) // Ensure it has size
            .contentShape(Rectangle()) // Make sure it's clickable/hoverable
            .onTapGesture {
                settingsTab = "bluetooth"
                withAnimation(.easeInOut(duration: ThemeDuration._300.rawValue)) { showSettings = true }
            }
            .pointingHandCursor()
            
            HoverButton(icon: .settings, size: 16, isActive: showSettings) {
                settingsTab = "ai"
                withAnimation(.easeInOut(duration: ThemeDuration._300.rawValue)) { showSettings.toggle() }
            }
        }
        .padding(.trailing, ThemeSpacing.px4.rawValue)
    }
    
    /// 内容视图
    @ViewBuilder
    private var contentView: some View {
        if showSettings {
            SettingsOverlayView(store: store, bluetooth: bluetooth, showSettings: $showSettings, initialTab: settingsTab)
                .transition(.slideRight) // 使用主题文件中的过渡动画
        } else {
            mainListView
        }
    }
    
    /// 主列表视图
    private var mainListView: some View {
        VStack(spacing: 0) {
            // Search Bar
            searchBarView
            
            // List Content
            listContentView
            
            // Bottom Status Bar
            statusBarView
        }
    }
    
    /// 搜索栏视图
    private var searchBarView: some View {
        EnhancedSearchBar(store: store, searchTerm: $searchTerm)
            .disabled(!focus.isKeyWindow)
    }
    
    /// 列表内容视图
    private var listContentView: some View {
        ScrollView {
            LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) { // 使用LazyVStack提高性能，并固定Header
                if searchTerm.isEmpty {
                    if store.records.isEmpty {
                        emptyStateView
                    } else {
                        let starred = store.records.filter { $0.starred }
                        let others = store.records.filter { !$0.starred }
                        
                        // 收藏部分
                        if !starred.isEmpty {
                            Section(header: starredSectionHeader(count: starred.count)) {
                                // 使用动画包裹收藏列表内容，根据收藏数量调整动画时间
                                animatedStarredListView(starred: starred)
                            }
                        }
                        
                        // 其他记录部分
                        if !others.isEmpty {
                            Section(header: !starred.isEmpty ? otherSectionHeader : nil) {
                                listViewContent(items: others)
                            }
                        }
                        
                        // 加载更多指示器
                        if hasMoreRecords {
                            loadMoreIndicatorView
                                .onAppear {
                                    loadMoreRecords()
                                }
                        }
                    }
                } else {
                    let items = Array(searchResults.prefix(50))
                    if items.isEmpty {
                        emptyStateView
                    } else {
                        listViewContent(items: items)
                    }
                }
            }
            .padding(16) // p-4
        }
        .onChange(of: searchTerm) { newValue in
            // 使用防抖搜索，避免频繁搜索
            store.debouncedSearch(newValue) { results in
                searchResults = results
                // 重置分页状态
                hasMoreRecords = results.count >= 50
            }
        }
        .onAppear {
            // 初始化时设置搜索结果
            if searchTerm.isEmpty {
                // 确保记录已加载
                if store.records.isEmpty {
                    store.loadFromStore(pageSize: 50, offset: 0)
                }
                // 检查是否还有更多记录
                hasMoreRecords = store.records.count >= 50
            } else {
                // 使用防抖搜索，避免频繁搜索
                store.debouncedSearch(searchTerm) { results in
                    searchResults = results
                    hasMoreRecords = results.count >= 50
                }
            }
        }
    }
    
    /// 收藏部分 Header
    private func starredSectionHeader(count: Int) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                store.isStarredCollapsed.toggle()
            }
        }) {
            HStack(spacing: 8) {
                LucideView(name: .star, size: 14, color: .themeYellow500)
                Text("已收藏 (\(count))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.themeTextPrimary)
                
                Spacer()
                
                LucideView(name: .chevronRight, size: 12, color: .themeGray400)
            .rotationEffect(.degrees(store.isStarredCollapsed ? 90 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.themeItem.opacity(0.8))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .padding(.bottom, 4)
    }
    
    /// 其他部分 Header
    private var otherSectionHeader: some View {
        HStack {
            Text("所有记录")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.themeGray400)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(Color.themeBackground)
    }
    
    /// 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .opacity(0.2)
            Text("没有找到匹配的记录。")
                .font(.system(size: 14)) // text-sm
                .foregroundColor(.themeTextSecondary)
        }
        .frame(height: 300)
    }
    
    /// 列表内容视图
    @ViewBuilder
    private func listViewContent(items: [Record]) -> some View {
        ForEach(items, id: \.id) { record in // 明确指定 id
            RecordCardView(
                record: record,
                expandedId: $expandedId,
                store: store
            )
            .equatable() // 使用 Equatable 减少重绘
        }
    }
    
    /// 为收藏列表提供动画效果的视图
    /// - Parameter starred: 收藏的记录数组
    /// - Returns: 带动画效果的收藏列表视图
    @ViewBuilder
    private func animatedStarredListView(starred: [Record]) -> some View {
        // 根据收藏数量动态调整动画时间
        let animationDuration = calculateAnimationDuration(for: starred.count)
        
        // 如果收藏数量很多（比如超过50条），只显示前50条，并提供"查看更多"的提示
        let displayCount = min(starred.count, 50)
        let displayRecords = Array(starred.prefix(displayCount))
        
        VStack(spacing: 0) {
            // 显示前50条记录
            ForEach(displayRecords) { record in
                RecordCardView(
                    record: record,
                    expandedId: $expandedId,
                    store: store
                )
                .equatable() // 使用 Equatable 减少重绘
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.8, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.8, anchor: .top))
                ))
            }
            
            // 如果还有更多记录，显示"查看更多"提示
            if starred.count > 50 {
                HStack {
                    Spacer()
                    Text("还有 \(starred.count - 50) 条收藏记录...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    // 可以在这里实现展开全部的逻辑，暂时先不做
                }
            }
        }
        .opacity(store.isStarredCollapsed ? 0 : 1)
        .scaleEffect(y: store.isStarredCollapsed ? 0.1 : 1.0, anchor: .top)
        .frame(height: store.isStarredCollapsed ? 0 : nil)
        .clipped()
        .animation(.easeInOut(duration: animationDuration), value: store.isStarredCollapsed)
    }
    
    /// 根据列表大小计算动画持续时间
    /// - Parameter count: 列表项数量
    /// - Returns: 动画持续时间（秒）
    private func calculateAnimationDuration(for count: Int) -> Double {
        if count <= 10 {
            return 0.15
        } else if count <= 20 {
            return 0.2
        } else if count <= 50 {
            return 0.25
        } else {
            return 0.3
        }
    }
    
    /// 加载更多记录的方法
    private func loadMoreRecords() {
        guard !isLoadingMore && hasMoreRecords else { return }
        
        isLoadingMore = true
        
        // 使用 RecordStore 的 loadMoreRecords 方法
        let previousCount = store.records.count
        store.loadMoreRecords()
        
        // 检查是否还有更多记录
        hasMoreRecords = store.records.count > previousCount && store.records.count >= 50
        isLoadingMore = false
    }
    
    /// 加载更多指示器视图
    private var loadMoreIndicatorView: some View {
        HStack {
            Spacer()
            if isLoadingMore {
                ProgressView()
                    .scaleEffect(0.8)
                Text("加载更多...")
                    .font(.system(size: 14))
                    .foregroundColor(.themeTextSecondary)
            } else {
                Text("向上滑动加载更多")
                    .font(.system(size: 14))
                    .foregroundColor(.themeTextSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    /// 状态栏视图
    private var statusBarView: some View {
        let base = heatmapVM.filteredRecords()
        // 使用缓存的搜索结果，避免重复搜索
        let items = searchTerm.isEmpty ? base : searchResults
        
        return HStack {
            Text("记录条数: \(store.records.count) 条 (已过滤: \(store.records.count - items.count))")
            Spacer()
            Text("AI: \(store.enableAI ? "ON (阈值 > \(store.summaryTrigger) 字符)" : "OFF")")
        }
        .font(.system(size: 10)) // text-[10px]
        .foregroundColor(.themeTextSecondary) // 使用主题文件中的文本颜色
        .padding(.horizontal, 16)
        .frame(height: 32) // h-8
        .background(Color.black.opacity(0.2)) // bg-black/20
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.themeBorder).allowsHitTesting(false), alignment: .top)
    }
}

struct HoverButton: View {
    let icon: IconName
    let size: CGFloat
    var isActive: Bool = false
    let action: () -> Void
    @State private var hovering = false
    
    var body: some View {
        Button(action: action) {
            LucideView(name: icon, size: size, color: isActive ? .white : (hovering ? .white : .themeGray400))
                .padding(6)
                .background(isActive ? Color.white.opacity(0.2) : (hovering ? Color.white.opacity(0.1) : Color.clear))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .pointingHandCursor()
    }
}

struct CloseButton: View {
    let onClose: (() -> Void)?
    @State private var hovering = false
    
    var body: some View {
        Circle()
            .fill(Color.themeRed500.opacity(hovering ? 1.0 : 0.8)) // bg-red-500/80
            .frame(width: 12, height: 12)
            .onTapGesture { onClose?() }
            .onHover { hovering = $0 }
            .pointingHandCursor()
            .help("关闭")
    }
}

struct ShrinkButton: View {
    let onMinimize: (() -> Void)?
    @State private var hovering = false
    
    var body: some View {
        Circle()
            .fill(Color.themeYellow500.opacity(hovering ? 1.0 : 0.8)) // bg-yellow-500/80
            .frame(width: 12, height: 12)
            .onTapGesture { onMinimize?() }
            .onHover { hovering = $0 }
            .pointingHandCursor()
            .help("缩小到浮球")
    }
}

/// AI 闪烁图标 (用户提供的 SVG 设计)
struct AISparkleIcon: View {
    var size: CGFloat = 30
    var color: Color = .white
    
    var body: some View {
        Canvas { context, size in
            let w = size.width
            
            // 比例系数
            let scale = w / 24.0
            
            var path = Path()
            
            // M12 3v1
            path.move(to: CGPoint(x: 12 * scale, y: 3 * scale))
            path.addLine(to: CGPoint(x: 12 * scale, y: 4 * scale))
            
            // m0 16v1
            path.move(to: CGPoint(x: 12 * scale, y: 20 * scale))
            path.addLine(to: CGPoint(x: 12 * scale, y: 21 * scale))
            
            // m9-9h-1
            path.move(to: CGPoint(x: 21 * scale, y: 12 * scale))
            path.addLine(to: CGPoint(x: 20 * scale, y: 12 * scale))
            
            // M4 12H3
            path.move(to: CGPoint(x: 4 * scale, y: 12 * scale))
            path.addLine(to: CGPoint(x: 3 * scale, y: 12 * scale))
            
            // m15.364-6.364l-.707.707
            path.move(to: CGPoint(x: 18.364 * scale, y: 5.636 * scale))
            path.addLine(to: CGPoint(x: 17.657 * scale, y: 6.343 * scale))
            
            // M6.343 17.657l-.707.707
            path.move(to: CGPoint(x: 6.343 * scale, y: 17.657 * scale))
            path.addLine(to: CGPoint(x: 5.636 * scale, y: 18.364 * scale))
            
            // m0-12.728l.707.707
            path.move(to: CGPoint(x: 5.636 * scale, y: 5.636 * scale))
            path.addLine(to: CGPoint(x: 6.343 * scale, y: 6.343 * scale))
            
            // m11.314 11.314l.707.707
            path.move(to: CGPoint(x: 17.657 * scale, y: 17.657 * scale))
            path.addLine(to: CGPoint(x: 18.364 * scale, y: 18.364 * scale))
            
            // M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z (中心圆)
            let circleRect = CGRect(x: 8 * scale, y: 8 * scale, width: 8 * scale, height: 8 * scale)
            path.addEllipse(in: circleRect)
            
            context.stroke(path, with: .color(color), lineWidth: 2 * scale)
        }
        .frame(width: size, height: size)
    }
}

struct FloatingBallView: View {
    @ObservedObject var store: RecordStore
    @ObservedObject var focus: WindowFocusProvider
    @State private var hovering = false
    @State private var pasteSuccess = false
    @State private var aiSuccess = false
    @State private var iconOffset: CGFloat = 0
    @State private var aiRotation: Double = 0
    @State private var initialPosition: CGPoint = .zero // 记录拖拽开始时的位置
    @State private var isDragging = false // 跟踪是否正在拖拽
    
    var body: some View {
        ZStack {
            // Glow Effect - tight edge glow
            if hovering || store.isAIProcessing || pasteSuccess || aiSuccess {
                Circle()
                    .stroke(statusColor.opacity(0.8), lineWidth: 3)
                    .frame(width: 58, height: 58)
                    .blur(radius: 3)
                    .transition(.opacity)
            }
            
            // Main Ball - refined size 56
            Circle()
                .fill(ballBackgroundColor.opacity(isIdle ? 0.8 : 1.0))
                .frame(width: 56, height: 56)
                .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
                .overlay(
                    Circle()
                        .stroke(statusColor.opacity(0.3), lineWidth: 1)
                )
            
            // Icon with Animation
            Group {
                if store.isAIProcessing {
                    AISparkleIcon(size: 30, color: .themePurple500)
                        .rotationEffect(.degrees(aiRotation))
                        .onAppear {
                            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                                aiRotation = 360
                            }
                        }
                } else if pasteSuccess || aiSuccess {
                    LucideView(name: .check, size: 30, color: .themeGreen500)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    AISparkleIcon(size: 30, color: statusColor)
                }
            }
            .offset(y: iconOffset)
        }
        .frame(width: 80, height: 80) // Container matches window size
        .contentShape(Circle())
        .onHover { h in 
            hovering = h 
            if h {
                // 跳动动画：向上移动然后轻微回弹
                withAnimation(.interpolatingSpring(stiffness: 300, damping: 15).repeatForever(autoreverses: true)) {
                    iconOffset = -6
                }
                NSCursor.pointingHand.set()
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    iconOffset = 0
                }
                NSCursor.arrow.set()
            }
        }
        .onAppear {
            print("[DEBUG] FloatingBallView appeared, mode: \(focus.mode), statusColor: \(statusColor)")
        }
        .onReceive(store.$lastAISuccessAt) { _ in
            // 使用 store 的方法来判断是否应该显示成功动画
            if store.shouldShowAISuccessAnimation() {
                triggerAISuccessAnimation()
            }
        }
        .onReceive(store.$lastPasteSuccessAt) { _ in
            // 使用 store 的方法来判断是否应该显示粘贴成功动画
            if store.shouldShowPasteSuccessAnimation() {
                triggerPasteSuccessAnimation()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global) // 使用全局坐标
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        NSCursor.closedHand.push()
                    }
                    // 直接使用鼠标的绝对屏幕坐标，这在多显示器环境下是最可靠的
                    let currentMouse = NSEvent.mouseLocation
                    NotificationCenter.default.post(name: Notification.Name("updateBallPosition"), object: currentMouse)
                }
                .onEnded { _ in
                    if isDragging {
                        isDragging = false
                        NSCursor.pop()
                        snapToEdge()
                    }
                }
        )
        .onTapGesture {
            // 只有在非拖拽状态下的点击才触发展开
            if !isDragging {
                handleRestore()
            }
        }
    }
    
    private var statusColor: Color {
        if store.isAIProcessing {
            return .themePurple500
        } else if pasteSuccess || aiSuccess {
            return .themeGreen500
        } else {
            // 用户要求：闲置时淡蓝色且带透明度
            return Color.themeBlue400.opacity(0.7)
        }
    }
    
    private var ballBackgroundColor: Color {
        // 浮球背景色始终使用要求的深蓝色 #0D111C
        return .themeDeepBlue
    }
    
    private var isIdle: Bool {
        !hovering && !store.isAIProcessing && !pasteSuccess && !aiSuccess
    }
    
    private func snapToEdge() {
        // 获取包含当前窗口中心点的屏幕
        let currentBallPos = focus.ballPosition
        let screens = NSScreen.screens
        let targetScreen = screens.first { NSMouseInRect(currentBallPos, $0.frame, false) } ?? NSScreen.main ?? screens.first!
        
        let screenFrame = targetScreen.visibleFrame
        let padding: CGFloat = 16
        let ballRadius: CGFloat = 28 // 56/2
        var finalPos = currentBallPos
        
        // 在当前所在的屏幕内进行边界吸附
        if finalPos.x < screenFrame.minX + padding + ballRadius {
            finalPos.x = screenFrame.minX + padding + ballRadius
        } else if finalPos.x > screenFrame.maxX - padding - ballRadius {
            finalPos.x = screenFrame.maxX - padding - ballRadius
        }
        
        if finalPos.y < screenFrame.minY + padding + ballRadius {
            finalPos.y = screenFrame.minY + padding + ballRadius
        } else if finalPos.y > screenFrame.maxY - padding - ballRadius {
            finalPos.y = screenFrame.maxY - padding - ballRadius
        }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            NotificationCenter.default.post(name: Notification.Name("updateBallPosition"), object: finalPos)
        }
    }
    
    private func handleRestore() {
        NotificationCenter.default.post(name: Notification.Name("restoreFromBall"), object: nil)
    }
    
    private func triggerAISuccessAnimation() {
        withAnimation(.spring()) {
            aiSuccess = true
        }
        HapticFeedbackManager.shared.success()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                aiSuccess = false
            }
        }
    }
    
    /// 触发粘贴成功动画
    private func triggerPasteSuccessAnimation() {
        withAnimation(.spring()) {
            pasteSuccess = true
        }
        HapticFeedbackManager.shared.lightImpact()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                pasteSuccess = false
            }
        }
    }
    
    
}

/// 单条记录行
struct RecordCardView: View, Equatable {
    let record: Record
    @Binding var expandedId: UUID?
    let store: RecordStore
    @State private var hovering = false
    @State private var showOriginalContent = false
    @State private var showContent = false // 控制内容延迟显示
    @State private var showFullContent = false // 控制是否显示完整内容
    @State private var displayedContent = "" // 当前显示的内容
    
    // 删除撤回逻辑
    @State private var deleteCountdown = 0
    @State private var deleteTimer: Timer? = nil
    
    // 缓存计算结果，避免重复计算
    private var isExpanded: Bool {
        expandedId == record.id
    }
    
    // 使用@ViewBuilder优化条件渲染
    @ViewBuilder
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            
            if isExpanded {
                cardExpandedContent
            }
        }
        // 简化背景和边框，减少重绘
        .background(Color.themeItem)
        .cornerRadius(8) // rounded-lg
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isExpanded ? Color.themeBlue500.opacity(0.3) : Color.clear, lineWidth: 1)
                .allowsHitTesting(false)
        )
        // 只在展开状态时应用阴影，减少性能开销
        .shadow(color: isExpanded ? Color.black.opacity(0.3) : .clear, radius: 10, x: 0, y: 2)
        .animation(.easeOut(duration: 0.2), value: isExpanded) // 减少动画时长
        .onChange(of: isExpanded) { expanded in
            // 当折叠时，重置内容显示状态，优化性能
            if !expanded {
                showContent = false
                showFullContent = false
                // 重新初始化显示内容
                if record.content.count > 1000 {
                    displayedContent = String(record.content.prefix(1000)) + "..."
                } else {
                    displayedContent = record.content
                    showFullContent = true
                }
            }
        }
        .onHover { hovering = $0 }
        .pointingHandCursor()
    }
    
    private var cardHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            LucideView(name: statusIconLucide, size: 16, color: statusColor)
                .frame(width: 20, height: 20)
                .padding(.top, 4) // mt-1 (4px)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(displayTitle)
                    .font(.system(size: 14, weight: .medium)) // text-sm font-medium
                    .foregroundColor(record.aiStatus == "pending" ? Color.themePurple500.opacity(0.7) : Color.themeTextPrimary)
                    .lineLimit(1)
                
                // Meta Info
                HStack(spacing: 8) {
                    Text(formattedDate)
                    Rectangle().fill(Color.themeGray700).frame(width: 2, height: 10) // w-0.5 h-2.5 bg-gray-700
                    Text("\(record.content.count) 字符")
                    Rectangle().fill(Color.themeGray700).frame(width: 2, height: 10)
                    
                    // Status Badge
                    HStack(spacing: 2) {
                        LucideView(name: statusIconLucide, size: 10, color: statusColor)
                        Text(statusText)
                    }
                    .foregroundColor(statusColor)
                }
                .font(.system(size: 10, design: .monospaced)) // text-[10px] font-mono
                .foregroundColor(.themeGray500) // text-gray-500
            }
            
            Spacer()
            
            // Actions - 始终显示按钮，提高可用性
            HStack(spacing: 6) {
                IconButton(icon: record.starred ? .star : .starOff, color: record.starred ? .themeYellow500 : .themeTextSecondary) {
                    store.toggleStar(record)
                }
                // 单独总结按钮 - 根据状态显示不同样式
                Button(action: {
                    generateIndividualSummary()
                }) {
                    Group {
                        if record.aiStatus == "fail" {
                            // 失败状态：显示警告图标
                            LucideView(name: .alertTriangle, size: 14, color: .themeRed500)
                                .frame(width: 24, height: 24)
                                .background(Color.themeRed500.opacity(0.1))
                                .clipShape(Circle())
                        } else {
                            // 正常或处理中状态
                            LucideView(name: .sparkles, size: 14, color: record.aiStatus == "pending" ? .themePurple500.opacity(0.7) : .themeBlue500)
                                .frame(width: 24, height: 24)
                                .background(Color.white.opacity(0.05))
                                .clipShape(Circle())
                        }
                    }
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .focusable(false)
                .help(record.aiStatus == "fail" ? "总结失败，点击重试" : "单独总结此消息")
                
                if deleteCountdown > 0 {
                    Button(action: {
                        cancelDelete()
                    }) {
                        HStack(spacing: 4) {
                            LucideView(name: .rotateCcw, size: 14, color: .themeGray400)
                            Text("\(deleteCountdown)s")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                        }
                        .frame(width: 48, height: 24)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .help("撤回删除")
                } else {
                    IconButton(icon: .trash2, color: .themeTextSecondary) {
                        startDeleteTimer()
                    }
                    .help("删除此消息")
                }
                
                // 展开/收起按钮始终显示
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedId = nil
                        } else {
                            expandedId = record.id
                        }
                    }
                }) {
                    LucideView(name: .chevronRight, size: 14, color: .themeTextSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            .opacity(hovering || isExpanded ? 1.0 : 0.8) // 减少透明度变化
            .scaleEffect(hovering || isExpanded ? 1.0 : 0.95) // 减少缩放幅度
            .animation(.easeOut(duration: 0.15), value: hovering) // 减少动画时长
        }
        .padding(12) // p-3
        .contentShape(Rectangle())
        .onTapGesture {
            // 使用更快的动画减少卡顿
            withAnimation(.easeInOut(duration: 0.25)) {
                expandedId = isExpanded ? nil : record.id
            }
        }
    }
    
    private var cardExpandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Expanded Content Area
            VStack(alignment: .leading, spacing: 12) {
                // 延迟加载内容，提升展开性能
                if showContent {
                
                // AI Summary Section - 优先显示
                if record.summary != nil || record.aiStatus == "fail" {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 4) {
                                LucideView(name: .sparkles, size: 10, color: record.aiStatus == "fail" ? .themeRed500 : .themePurple500)
                                Text("AI 智能总结")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(record.aiStatus == "fail" ? .themeRed500 : .themePurple500)
                            .textCase(.uppercase)
                            Spacer()
                            if let s = record.summary {
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(s, forType: .string)
                                    HapticFeedbackManager.shared.lightImpact()
                                    store.postToast("已复制总结", type: "success")
                                }) {
                                    HStack(spacing: 4) {
                                        LucideView(name: .copy, size: 10, color: .themePurple500)
                                        Text("复制总结")
                                    }
                                    .font(.system(size: 10))
                                    .foregroundColor(.themePurple500)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.themePurple500.opacity(0.1))
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                            } else if record.aiStatus == "fail" {
                                Button(action: {
                                    store.resummarize(record: record)
                                }) {
                                    HStack(spacing: 4) {
                                        LucideView(name: .refreshCw, size: 10, color: .themeRed500)
                                        Text("重试")
                                    }
                                    .font(.system(size: 10))
                                    .foregroundColor(.themeRed500)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.themeRed500.opacity(0.1))
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                            }
                        }
                        
                        Text(record.summary ?? "提炼失败")
                            .font(.system(size: 12))
                            .foregroundColor(Color.themePurple400.opacity(0.8)) // text-purple-200
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.themePurple500.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themePurple500.opacity(0.2), lineWidth: 1).allowsHitTesting(false))
                    }
                }
                
                // Raw Content Section - 如果有总结则默认折叠
                if record.summary == nil || showOriginalContent {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 4) {
                                LucideView(name: .rss, size: 10, color: .themeGray500)
                                Text("原文内容")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.themeGray500)
                            .textCase(.uppercase) // uppercase tracking-wider
                            Spacer()
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(record.content, forType: .string)
                                HapticFeedbackManager.shared.lightImpact()
                                store.postToast("已复制原文", type: "success")
                            }) {
                                HStack(spacing: 4) {
                                    LucideView(name: .copy, size: 10, color: .themeGray400)
                                    Text("复制原文")
                                }
                                .font(.system(size: 10))
                                .foregroundColor(.themeGray400)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                        }
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(displayedContent)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.themeGray300) // text-gray-300
                                    .padding(12) // p-3
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxHeight: 300) // 限制最大高度，避免过长内容导致性能问题
                        .background(Color.black.opacity(0.2)) // bg-black/20
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.themeBorder, lineWidth: 1).allowsHitTesting(false))
                    }
                }
                
                // 如果有总结，添加显示/隐藏原文的切换按钮
                if record.summary != nil {
                    HStack {
                        Spacer()
                        Button(action: {
                            // 使用更快的动画减少卡顿
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showOriginalContent.toggle()
                            }
                        }) {
                            HStack(spacing: 4) {
                                LucideView(name: showOriginalContent ? .eyeOff : .eye, size: 10, color: .themeGray400)
                                Text(showOriginalContent ? "隐藏原文" : "显示原文")
                            }
                            .font(.system(size: 10))
                            .foregroundColor(.themeGray400)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                    }
                }
                } // 延迟加载内容的结束括号
            }
            .padding(12) // p-3
            .padding(.top, 0)
        }
        .onAppear {
            // 如果有总结，默认折叠原文
            if record.summary != nil {
                showOriginalContent = false
            }
            
            // 初始化显示内容
            if record.content.count > 1000 {
                displayedContent = String(record.content.prefix(1000)) + "..."
                // 延迟1秒后自动显示完整内容
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFullContent = true
                        displayedContent = record.content
                    }
                }
            } else {
                displayedContent = record.content
                showFullContent = true
            }
            
            // 延迟加载内容，提升展开性能
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showContent = true
                }
            }
        }
        .transition(.opacity)
    }
    
    /// 实现Equatable协议，减少不必要的重绘
    static func == (lhs: RecordCardView, rhs: RecordCardView) -> Bool {
        return lhs.record.id == rhs.record.id &&
               lhs.record.content == rhs.record.content &&
               lhs.record.title == rhs.record.title &&
               lhs.record.summary == rhs.record.summary &&
               lhs.record.starred == rhs.record.starred &&
               lhs.record.aiStatus == rhs.record.aiStatus &&
               lhs.isExpanded == rhs.isExpanded
    }
}

struct IconButton: View {
    let icon: IconName
    let color: Color
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            LucideView(name: icon, size: 14, color: color)
                .frame(width: 24, height: 24)
                .background(isHovering ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .focusable(false)
        .onHover { isHovering = $0 }
        .scaleEffect(isHovering ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

private extension RecordCardView {
    /// 为当前记录生成单独的AI总结
    func generateIndividualSummary() {
        // 如果已经在处理中，不重复请求
        guard record.aiStatus != "pending" else { return }
        
        // 更新状态为处理中
        store.updateRecordAI(
            id: record.id,
            title: "AI 正在分析内容...",
            summary: nil,
            confidence: 0,
            aiStatus: "pending"
        )
        
        // 调用AI服务生成总结
        store.ai?.summarizeSingle(record.content) { [weak store] (result: Result<SummaryResult, Error>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let summaryResult):
                    let title = summaryResult.title
                    let summary = summaryResult.summary
                    let confidence = summaryResult.confidence
                    store?.updateRecordAI(
                        id: record.id,
                        title: title,
                        summary: summary,
                        confidence: confidence,
                        aiStatus: "success"
                    )
                    store?.postToast("总结已生成", type: "success")
                case .failure(let error):
                    store?.updateRecordAI(
                        id: record.id,
                        title: "提炼失败",
                        summary: nil,
                        confidence: 0,
                        aiStatus: "fail"
                    )
                    store?.postToast("总结生成失败: \(error.localizedDescription)", type: "error")
                }
            }
        }
    }
    
    /// 开始删除倒计时
    func startDeleteTimer() {
        deleteCountdown = 3
        deleteTimer?.invalidate()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if deleteCountdown > 1 {
                deleteCountdown -= 1
            } else {
                deleteTimer?.invalidate()
                deleteTimer = nil
                deleteCountdown = 0
                store.delete(record)
            }
        }
    }
    
    /// 撤回删除
    func cancelDelete() {
        deleteTimer?.invalidate()
        deleteTimer = nil
        deleteCountdown = 0
    }
    
    // 缓存计算结果，避免重复计算
    var displayTitle: String {
        // 使用更高效的条件判断顺序
        switch record.aiStatus {
        case "fail":
            return "提炼失败"
        case "pending":
            return "AI 正在分析内容..."
        default:
            if let t = record.title, !t.isEmpty { return t }
            return record.content.count > 30 ? String(record.content.prefix(30)) + "..." : record.content
        }
    }

    /// 格式化日期显示
    /// - 24小时内：显示时间
    /// - 24小时-30天：显示 n天前
    /// - 30天以上：显示 yyyy-MM-dd
    var formattedDate: String {
        let calendar = Calendar.current
        let now = Date()
        
        // 计算天数差异（使用 startOfDay 确保精确到天）
        let startOfNow = calendar.startOfDay(for: now)
        let startOfCreated = calendar.startOfDay(for: record.createdAt)
        let dayComponents = calendar.dateComponents([.day], from: startOfCreated, to: startOfNow)
        let days = dayComponents.day ?? 0
        
        // 计算小时差异
        let hourComponents = calendar.dateComponents([.hour], from: record.createdAt, to: now)
        let hours = hourComponents.hour ?? 0
        
        if hours < 24 {
            // 24小时内显示时间
            return record.createdAt.formatted(date: .omitted, time: .shortened)
        } else if days < 30 {
            // 24小时以上且30天以内
            return "\(days)天前"
        } else {
            // 30天以上显示具体日期
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: record.createdAt)
        }
    }
    
    var statusIconLucide: IconName {
        // 使用更高效的条件判断顺序
        if record.summary != nil { return .sparkles }
        switch record.aiStatus {
        case "pending": return .zap
        case "fail": return .x
        default:
            return record.title != nil ? .bot : .clock
        }
    }
    
    var statusColor: Color {
        // 使用更高效的条件判断顺序
        if record.summary != nil { return .themePurple500 }
        switch record.aiStatus {
        case "pending": return .themeYellow500
        case "fail": return .themeRed500
        default:
            return record.title != nil ? .themeBlue600 : .gray
        }
    }
    
    var statusText: String {
        // 使用更高效的条件判断顺序
        if record.summary != nil { return "已总结" }
        switch record.aiStatus {
        case "pending": return "提炼中..."
        case "fail": return "提炼失败"
        default:
            return record.title != nil ? "仅标题" : "原始记录"
        }
    }
}

extension View {
    func pointingHandCursor() -> some View {
        self.onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - 键盘事件处理修饰符

/// 键盘事件处理修饰符，处理不同 macOS 版本的兼容性
struct KeyboardHandlerModifier: ViewModifier {
    @Binding var expandedId: UUID?
    @Binding var showSettings: Bool
    var onClose: (() -> Void)?
    
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .onKeyPress(.escape) {
                    // ESC键关闭面板或取消展开
                    if expandedId != nil {
                        expandedId = nil
                        return .handled
                    } else if showSettings {
                        showSettings = false
                        return .handled
                    } else {
                        onClose?()
                        return .handled
                    }
                }
        } else {
            // 对于旧版本 macOS，暂时不提供键盘快捷键支持
            content
        }
    }
}
