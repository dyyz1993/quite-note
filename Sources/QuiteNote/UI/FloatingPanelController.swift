import SwiftUI
import AppKit

// MARK: - Colors & Theme
// Note: Most colors are defined in Sources/QuiteNote/UI/Theme/Color+Theme.swift
// This extension only contains FloatingPanelController-specific colors

extension Color {
    // FloatingPanelController specific colors
    static let themeSidebar = Color(red: 31/255, green: 41/255, blue: 55/255)    // gray-800 (used for sidebar)
    // Note: note.jsx uses bg-black/20 for sidebar, but let's keep this for compatibility

    static let themeAccent = Color(red: 37/255, green: 99/255, blue: 235/255)    // blue-600
    static let themePurple = Color(red: 192/255, green: 132/255, blue: 252/255)  // purple-400
    static let themeGreen = Color(red: 74/255, green: 222/255, blue: 128/255)    // green-400
    static let themeRed = Color(red: 248/255, green: 113/255, blue: 113/255)     // red-400
    static let themeYellow = Color(red: 250/255, green: 204/255, blue: 21/255)   // yellow-400
}

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
    
    override func mouseDown(with event: NSEvent) {
        self.window?.performDrag(with: event)
    }
}

class CustomPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class WindowFocusProvider: ObservableObject {
    @Published var isKeyWindow: Bool = false
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
    private var userHidden: Bool = false // 用户主动隐藏标记，防止自动前置
    
    var isVisible: Bool { panel.isVisible }
    
    /// 初始化悬浮窗并配置置顶与多桌面行为
    init(store: RecordStore, heatmapVM: HeatmapViewModel, bluetooth: BluetoothManager) {
        self.store = store
        self.heatmapVM = heatmapVM
        self.bluetooth = bluetooth
        
        // 计算屏幕中心位置
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
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
            self.isInteracting = interacting
            print("[DEBUG] 交互状态变更: \(interacting)")
        }, onClose: { [weak self] in
            self?.hide()
        }))
        panel.contentView = hosting
        
        NotificationCenter.default.addObserver(self, selector: #selector(onWindowLock(_:)), name: .windowLockChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onAnimations(_:)), name: .animationsEnabledChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onWindowKeyDidChange(_:)), name: NSWindow.didBecomeKeyNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(onWindowKeyDidChange(_:)), name: NSWindow.didResignKeyNotification, object: panel)
    }

    /// 显示悬浮窗，带淡入动效
    func show() {
        print("[DEBUG] show() called")
        userHidden = false

        // 1. 确保位置正确
        forceCenterWindow()

        // 2. 重置透明度，防止动画状态残留
        panel.alphaValue = 1
        // 确保层级为浮动层级（比普通窗口高）
        panel.level = .floating

        // 3. 显示窗口（保持Accessory模式，不切换ActivationPolicy）
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        // 4. 执行动画
        if animationsEnabled {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }

        // 5. 重置悬停状态，确保UI正常显示
        updateHoverState(hovering: false, animated: false)

        focusProvider.isKeyWindow = panel.isKeyWindow
        print("[DEBUG] show() 完成，isVisible: \(panel.isVisible), isKey: \(panel.isKeyWindow)")
    }

    /// 启动期强制确保悬浮窗可见并可在当前空间显示
    func ensureVisibleOnLaunch() {
        print("[DEBUG] ensureVisibleOnLaunch() called - Force showing window")
        userHidden = false

        // 停止之前的 Timer，避免冲突
        launchEnsurer?.invalidate()
        launchEnsurer = nil

        // 1. 基础属性重置
        panel.alphaValue = 1
        panel.isOpaque = false
        panel.level = .floating

        // 2. 强制居中
        forceCenterWindow()

        // 3. 强制显示策略 (保持Accessory模式，不切换ActivationPolicy)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        // 4. 延时强化（确保窗口显示）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            // 再次尝试前置
            self.panel.makeKeyAndOrderFront(nil)
            self.panel.orderFrontRegardless()
            let isKey = self.panel.isKeyWindow
            let isVisible = self.panel.isVisible
            print("[DEBUG] 强化后状态: visible=\(isVisible), key=\(isKey)")
        }
    }

    /// 隐藏悬浮窗，带淡出动效
    func hide() {
        // 标记为用户主动隐藏，并清理可能导致再次前置的定时器/状态
        userHidden = true
        hoverActive = false
        revertTimer?.invalidate(); revertTimer = nil
        launchEnsurer?.invalidate(); launchEnsurer = nil

        if animationsEnabled {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            } completionHandler: { [weak panel] in
                panel?.orderOut(nil)
                panel?.alphaValue = 1
            }
        } else {
            panel.orderOut(nil)
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

    /// 悬停时请求窗口前置（保持Accessory模式）
    func requestRegularFocus(reason: String) {
        // 如果用户主动隐藏了窗口，则不进行任何前置操作
        if userHidden { return }

        let now = CFAbsoluteTimeGetCurrent()
        if now - lastSwitchAt < 0.5 { return } // 节流 500ms
        lastSwitchAt = now
        hoverActive = true
        print("[DEBUG] requestFocus(\(reason)) isKey=\(panel.isKeyWindow)")
        // 保持 Accessory，直接激活并前置
        DispatchQueue.main.async {
            self.panel.makeKeyAndOrderFront(nil)
            self.panel.orderFrontRegardless()
            // 确保悬停时UI正常显示
            self.updateHoverState(hovering: true, animated: true)
        }
    }

    /// 悬停离开后让UI变淡（防抖）
    func scheduleRevertToAccessory() {
        // 如果用户主动隐藏了窗口，则直接返回，不进行回退策略（避免前置）
        if userHidden { return }

        hoverActive = false
        revertTimer?.invalidate()
        revertTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self else { return }
            // 只有在非悬停且非交互状态下才让UI变淡
            if !self.hoverActive && !self.isInteracting && !self.userHidden {
                self.updateHoverState(hovering: false, animated: true)
                print("[DEBUG] UI 变淡")
            }
        }
    }
    
    /// 强制窗口居中显示（调试用）
    func forceCenterWindow() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
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

    /// 更新悬停状态（控制UI透明度）
    /// hovering: true = 正常显示, false = 变淡显示
    /// animated: 是否使用动画过渡
    func updateHoverState(hovering: Bool, animated: Bool) {
        let targetAlpha: CGFloat = hovering ? 1.0 : 0.85

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.allowsImplicitAnimation = true
                panel.animator().alphaValue = targetAlpha
            }
        } else {
            panel.alphaValue = targetAlpha
        }

        print("[DEBUG] updateHoverState: hovering=\(hovering), alpha=\(targetAlpha)")
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
    @State private var showSettings = false
    @State private var settingsTab: String = "ai"
    @State private var expandedId: UUID? = nil
    @State private var searchTerm: String = ""
    @State private var isHovering = false

    // Sidebar View
    private var sidebarView: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.2) // bg-black/20
            WindowDragHandler() // Allow dragging on sidebar background

            HeatmapView(vm: heatmapVM)
        }
        .frame(width: 64) // w-16
        .zIndex(10) // Fix Tooltip Z-Index (Ensure it renders above Main Content)
        .overlay(Rectangle().frame(width: 1, height: nil, alignment: .trailing).foregroundColor(Color.themeBorder), alignment: .trailing)
        .opacity(isHovering ? 1.0 : 0.7)
    }

    // Header View
    private var headerView: some View {
        HStack {
            // Window Controls (Custom Red Dot)
            HStack(spacing: 8) {
                // Close (Red)
                CloseButton(onClose: onClose)
            }
            .padding(.leading, 16)

            Spacer()

            Text(showSettings ? "偏好设置" : "剪切板历史")
                .font(.system(size: 14, weight: .semibold)) // text-sm font-semibold
                .foregroundColor(.themeGray200) // text-gray-200

            Spacer()

            // Bluetooth Icon (Lucide)
            HStack(spacing: 12) {
                Group {
                    if let name = bluetooth.connectedDeviceName {
                        LucideView(name: .bluetoothConnected, size: 14, color: .themeBlue400)
                            .help("已连接: \(name)")
                    } else if bluetooth.state == .poweredOn {
                        LucideView(name: .bluetooth, size: 14, color: .themeYellow)
                            .help("蓝牙已开启，未连接")
                    } else {
                        LucideView(name: .bluetoothOff, size: 14, color: .themeGray500)
                            .help("蓝牙未开启")
                    }
                }
                .font(.system(size: 14))
                .frame(width: 16, height: 16) // Ensure it has size
                .contentShape(Rectangle()) // Make sure it's clickable/hoverable
                .onTapGesture {
                    settingsTab = "bluetooth"
                    withAnimation(.easeInOut(duration: 0.3)) { showSettings = true }
                }
                .pointingHandCursor()

                HoverButton(icon: .settings, size: 16, isActive: showSettings) {
                    settingsTab = "ai"
                    withAnimation(.easeInOut(duration: 0.3)) { showSettings.toggle() }
                }
            }
            .padding(.trailing, 16)
        }
        .frame(height: 48) // h-12
        .background(
            ZStack {
                Color.themeBackground.opacity(0.5) // bg-gray-900/50
                WindowDragHandler() // Allow dragging on header background
            }
        )
        .overlay(Rectangle().frame(width: nil, height: 1, alignment: .bottom).foregroundColor(Color.themeBorder), alignment: .bottom)
        .opacity(isHovering ? 1.0 : 0.7)
    }

    // Main Content View
    private var mainContentView: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                LucideView(name: .search, size: 16, color: .themeGray500)
                TextField("搜索标题或内容...", text: $searchTerm)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14)) // text-sm
                    .foregroundColor(.themeGray100) // text-gray-100
                    .disabled(!focus.isKeyWindow)
            }
            .padding(12) // p-3
            .background(Color.black.opacity(0.1)) // bg-black/10
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.themeBorder), alignment: .bottom)

            let base = heatmapVM.filteredRecords()
            let items = searchTerm.isEmpty ? base : base.filter { r in
                (r.title ?? "").lowercased().contains(searchTerm.lowercased()) || r.content.lowercased().contains(searchTerm.lowercased())
            }

            ScrollView {
                VStack(spacing: 12) {
                    if items.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 48))
                                .opacity(0.2)
                            Text("没有找到匹配的记录。")
                                .font(.system(size: 14)) // text-sm
                                .foregroundColor(.themeGray500)
                        }
                        .frame(height: 300)
                    } else {
                        ForEach(items.prefix(100)) { record in
                            RecordCardView(record: record, expandedId: $expandedId, store: store)
                        }
                    }
                }
                .padding(16) // p-4
            }

            // Bottom Status Bar
            HStack {
                Text("记录条数: \(store.records.count) 条 (已过滤: \(store.records.count - items.count))")
                Spacer()
                Text("AI: \(store.enableAI ? "ON (阈值 > \(store.summaryTrigger) 字符)" : "OFF")")
            }
            .font(.system(size: 10)) // text-[10px]
            .foregroundColor(.themeGray500) // text-gray-500
            .padding(.horizontal, 16)
            .frame(height: 32) // h-8
            .background(Color.black.opacity(0.2)) // bg-black/20
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.themeBorder), alignment: .top)
            .opacity(isHovering ? 1.0 : 0.8)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar (Activity)
            sidebarView

            // Right Content Area (Header + Main Content)
            ZStack {
                // Background and styling for the entire right area
                Color.themeBackground.opacity(0.9)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.themeBorder, lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
                    .ignoresSafeArea()

                // Content Stack
                VStack(spacing: 0) {
                    // Header
                    headerView

                    // Main Content
                    ZStack {
                        Color.themeBackground.opacity(0.9) // bg-gray-900/90

                        if showSettings {
                            SettingsOverlayView(store: store, bluetooth: bluetooth, showSettings: $showSettings, initialTab: settingsTab)
                                .transition(.move(edge: .trailing))
                        } else {
                            mainContentView
                        }
                    }
                }

                // Toast Overlay (top-right of right content area)
                if let toast = store.toast {
                    ToastView(message: toast)
                        .padding(.top, 32)
                        .padding(.trailing, 32)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(100)
                }
            }
        }
        .onHover { hovering in
            isHovering = hovering
            onHoverChanged?(hovering)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onInteractionChanged?(true) }
                .onEnded { _ in onInteractionChanged?(false) }
        )
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
        .focusable(false) // Fix outline issue
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

/// 单条记录行
struct RecordCardView: View {
    let record: Record
    @Binding var expandedId: UUID?
    let store: RecordStore
    @State private var hovering = false

    var body: some View {
        let isExpanded = expandedId == record.id
        
        VStack(alignment: .leading, spacing: 0) {
            cardHeader(isExpanded: isExpanded)
            
            if isExpanded {
                cardExpandedContent
            }
        }
        // bg-white/5 hover:bg-white/10
        .background(isExpanded ? Color.themeHover : (hovering ? Color.themeHover : Color.themeItem))
        .cornerRadius(8) // rounded-lg
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isExpanded ? Color.themeBlue500.opacity(0.3) : Color.themeBorderSubtle, lineWidth: 1)
        )
        .shadow(color: isExpanded ? Color.black.opacity(0.5) : .clear, radius: 30, x: 0, y: 8)
        .animation(.easeOut(duration: 0.2), value: hovering)
        .onHover { hovering = $0 }
        .pointingHandCursor()
    }
    
    private func cardHeader(isExpanded: Bool) -> some View {
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
                    .foregroundColor(record.aiStatus == "pending" ? Color.themePurple.opacity(0.7) : Color.themeGray200)
                    .lineLimit(1)
                
                // Meta Info
                HStack(spacing: 8) {
                    Text(record.createdAt.formatted(date: .omitted, time: .shortened))
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
            
            // Actions
            if hovering || isExpanded {
                HStack(spacing: 6) {
                    IconButton(icon: .star, color: record.starred ? .themeYellow : .themeGray500) {
                        store.toggleStar(record)
                    }
                    IconButton(icon: .trash2, color: .themeGray500) {
                        store.delete(record)
                    }
                    LucideView(name: .chevronRight, size: 14, color: .themeGray500)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .transition(.opacity)
            }
        }
        .padding(12) // p-3
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                expandedId = isExpanded ? nil : record.id
            }
        }
    }
    
    private var cardExpandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Expanded Content Area
            VStack(alignment: .leading, spacing: 12) {
                
                // Raw Content Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 4) {
                            LucideView(name: .alignLeft, size: 10, color: .themeGray500)
                            Text("原文内容")
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.themeGray500)
                        .textCase(.uppercase) // uppercase tracking-wider
                        Spacer()
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(record.content, forType: .string)
                            store.postLightHint("已复制原文")
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
                    
                    Text(record.content)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.themeGray300) // text-gray-300
                        .padding(12) // p-3
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.2)) // bg-black/20
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.themeBorder, lineWidth: 1))
                }
                
                // AI Summary Section
                if record.summary != nil || record.aiStatus == "fail" {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 4) {
                                LucideView(name: .sparkles, size: 10, color: record.aiStatus == "fail" ? .themeRed : .themePurple)
                                Text("AI 智能总结")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(record.aiStatus == "fail" ? .themeRed : .themePurple)
                            .textCase(.uppercase)
                            Spacer()
                            if let s = record.summary {
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(s, forType: .string)
                                    store.postLightHint("已复制总结")
                                }) {
                                    HStack(spacing: 4) {
                                        LucideView(name: .copy, size: 10, color: .themePurple)
                                        Text("复制总结")
                                    }
                                    .font(.system(size: 10))
                                    .foregroundColor(.themePurple)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.themePurple.opacity(0.1))
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                            }
                        }
                        
                        Text(record.summary ?? "提炼失败")
                            .font(.system(size: 12))
                            .foregroundColor(Color.themePurple.opacity(0.8)) // text-purple-200
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.themePurple.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themePurple.opacity(0.2), lineWidth: 1))
                    }
                }
            }
            .padding(12) // p-3
            .padding(.top, 0)
        }
        .transition(.opacity)
    }
}

struct IconButton: View {
    let icon: IconName
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            LucideView(name: icon, size: 14, color: color)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.05))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

private extension RecordCardView {
    var displayTitle: String {
        if let t = record.title, !t.isEmpty { return t }
        // 标题显示逻辑：优先使用 AI 标题，其次是去重/提炼失败/原始
        if record.aiStatus == "fail" { return "提炼失败" }
        if record.aiStatus == "pending" { return "AI 正在分析内容..." }
        return String(record.content.prefix(30)) + (record.content.count > 30 ? "..." : "")
    }
    
    var statusIconLucide: IconName {
        if record.summary != nil { return .sparkles }
        if record.aiStatus == "pending" { return .zap }
        if record.aiStatus == "fail" { return .x }
        if record.title != nil { return .bot }
        return .clock
    }
    
    var statusColor: Color {
        if record.summary != nil { return .themePurple }
        if record.aiStatus == "pending" { return .themeYellow }
        if record.aiStatus == "fail" { return .themeRed }
        if record.title != nil { return .themeAccent } // Blue
        return .gray
    }
    
    var statusText: String {
        if record.summary != nil { return "已总结" }
        if record.aiStatus == "pending" { return "提炼中..." }
        if record.aiStatus == "fail" { return "提炼失败" }
        if record.title != nil { return "仅标题" }
        return "原始记录"
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
