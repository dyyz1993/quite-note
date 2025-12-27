import SwiftUI

/// 窗口识别视图 - 阶段0的主视图
struct WindowDetectionView: View {
    // 回调
    let onWindowSelected: (WindowInfo, CGRect) -> Void
    let onAreaSelected: (CGRect) -> Void
    let onFullscreen: () -> Void
    let onCancel: () -> Void

    // 状态
    @State private var windows: [WindowInfo] = []
    @State private var highlightedWindow: WindowInfo?
    @State private var mouseLocation: CGPoint = .zero
    @State private var isDragging = false
    @State private var dragStartPoint: CGPoint = .zero
    @State private var selectionRect: CGRect = .zero
    @State private var showExitConfirm = false
    @State private var exitConfirmTimer: Timer?
    @State private var windowFrame: CGRect = .zero  // 窗口的屏幕框架

    // 全局鼠标跟踪
    @State private var globalMonitor: Any?
    @State private var localMonitor: Any?

    // 服务
    private let windowService = WindowInfoService.shared

    init(
        onWindowSelected: @escaping (WindowInfo, CGRect) -> Void,
        onAreaSelected: @escaping (CGRect) -> Void,
        onFullscreen: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        print("[DEBUG WindowDetectionView] init 被调用")
        self.onWindowSelected = onWindowSelected
        self.onAreaSelected = onAreaSelected
        self.onFullscreen = onFullscreen
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            // ✅ 修复：始终显示半透明遮罩层，降低不透明度让效果更自然
            // 高亮窗口因为有叠加层，视觉上会比其他区域更亮
            Color.black.opacity(0.2)
                .ignoresSafeArea(.all)

            // 背景点击处理
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 1) {
                    handleBackgroundTap()
                }

            // 窗口高亮覆盖层
            WindowHighlightOverlay(window: highlightedWindow, windowFrame: windowFrame)
                .animation(.easeInOut(duration: 0.15), value: highlightedWindow?.bounds)

            // 框选拖拽层
            SelectionDragLayer(
                selectionRect: $selectionRect,
                isDragging: isDragging,
                animation: .easeInOut(duration: 0.1)
            )

            // 底部提示栏
            VStack {
                Spacer()

                VStack(spacing: 8) {
                    // 操作提示
                    hintPanel

                    // 窗口信息（如果有高亮窗口）
                    if let window = highlightedWindow {
                        windowInfoPanel(for: window)
                    }
                }
                .padding(.bottom, 40)
            }

            // 退出确认提示
            if showExitConfirm {
                exitConfirmView
            }
        }
        // ⚠️ 关键修复 4：强制 SwiftUI 视图填充整个窗口
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.all)  // 忽略安全区域，确保全屏
        .onAppear {
            print("[DEBUG WindowDetectionView] onAppear 被调用")
            setupWindowDetection()
            setupCursor()  // ⚠️ 设置瞄准镜光标
            setupGlobalMouseTracking()  // ⚠️ 使用全局鼠标跟踪
            captureWindowFrame()  // 获取窗口的屏幕框架
            print("[DEBUG WindowDetectionView] onAppear 完成，找到 \(windows.count) 个窗口")
        }
        .onDisappear {
            print("[DEBUG WindowDetectionView] onDisappear 被调用")
            cleanupCursor()
            removeGlobalMouseTracking()  // ⚠️ 清理全局鼠标跟踪
        }
        // ⚠️ 修复：使用 minimumDistance: 5 避免与 onTapGesture 冲突
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    handleDragChanged(value)
                }
                .onEnded { value in
                    handleDragEnded(value)
                }
        )
        .overlay {
            // 键盘事件处理
            keyboardHandler
        }
    }

    // MARK: - 子视图

    @ViewBuilder
    private var hintPanel: some View {
        Text("💡 拖拽框选 | 点击窗口选中 | Enter 全屏 | ESC 退出")
            .font(.system(size: 14))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.8))
            )
    }

    @ViewBuilder
    private func windowInfoPanel(for window: WindowInfo) -> some View {
        VStack(spacing: 4) {
            Text(window.displayTitle)
                .font(.system(size: 13, weight: .medium))

            Text("\(window.sizeDescription) | \(window.positionDescription)")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.8))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.8))
        )
    }

    @ViewBuilder
    private var exitConfirmView: some View {
        VStack {
            Spacer()

            Text("再按一次 ESC 退出截图")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.7)))
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var keyboardHandler: some View {
        Color.clear
            .onAppear {
                NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    handleKeyEvent(event)
                }
            }
    }

    // MARK: - 设置

    private func setupWindowDetection() {
        print("[DEBUG WindowDetectionView] setupWindowDetection 开始")
        switch windowService.fetchAllWindows() {
        case .success(let windowList):
            windows = windowList
            print("[DEBUG WindowDetectionView] 成功获取 \(windowList.count) 个窗口")
        case .failure(let error):
            print("[WindowDetection] Failed to fetch windows: \(error.localizedDescription)")
        }
    }

    private func setupCursor() {
        CrosshairCursor.shared.set()
    }

    private func cleanupCursor() {
        CrosshairCursor.shared.reset()
    }

    // ⚠️ 使用 NSEvent.addGlobalMonitorForEvents 进行全局鼠标跟踪
    private func setupGlobalMouseTracking() {
        print("[DEBUG WindowDetectionView] setupGlobalMouseTracking 被调用")

        // 移除旧的监听器
        removeGlobalMouseTracking()

        // 全局监听 - 捕获所有鼠标移动事件
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { event in
            self.handleGlobalMouseMove(event)
        }

        // 本地监听 - 捕获应用内的鼠标移动事件
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            self.handleLocalMouseMove(event)
            return event
        }

        print("[DEBUG WindowDetectionView] 全局鼠标监听已设置")
    }

    private func removeGlobalMouseTracking() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleGlobalMouseMove(_ event: NSEvent) {
        // ✅ 使用统一的坐标系统处理鼠标事件
        guard let screen = NSScreen.main else { return }

        // 1. 获取鼠标在屏幕上的位置（AppKit 坐标系）
        let mouseLocation = NSEvent.mouseLocation

        // 2. 转换为 CoreGraphics 坐标系
        let mouseCG = CoordinateSystem.appKitToCoreGraphics(mouseLocation, screenHeight: screen.frame.height)

        // 3. 转换为窗口局部坐标（SwiftUI 坐标系）
        let localPoint = CoordinateSystem.screenToLocal(mouseCG, windowFrame: windowFrame, screen: screen)

        print("[DEBUG WindowDetectionView] 全局鼠标移动: AppKit(\(mouseLocation)) -> CG(\(mouseCG)) -> Local(\(localPoint))")

        DispatchQueue.main.async {
            self.mouseLocation = localPoint
            if !self.isDragging {
                self.updateHighlightedWindow(at: localPoint)
            }
        }
    }

    private func handleLocalMouseMove(_ event: NSEvent) {
        // ✅ 本地事件也使用统一坐标系统
        guard let screen = NSScreen.main else { return }

        let location = event.locationInWindow
        let mouseCG = CoordinateSystem.appKitToCoreGraphics(location, screenHeight: screen.frame.height)
        let localPoint = CoordinateSystem.screenToLocal(mouseCG, windowFrame: windowFrame, screen: screen)

        print("[DEBUG WindowDetectionView] 本地鼠标移动: AppKit(\(location)) -> CG(\(mouseCG)) -> Local(\(localPoint))")

        DispatchQueue.main.async {
            self.mouseLocation = localPoint
            if !self.isDragging {
                self.updateHighlightedWindow(at: localPoint)
            }
        }
    }

    // MARK: - 事件处理

    private func handleHover(_ phase: HoverPhase) {
        switch phase {
        case .active(let location):
            mouseLocation = location

            // 如果正在拖拽，不更新窗口高亮
            if !isDragging {
                updateHighlightedWindow(at: location)
            }

        case .ended:
            break
        }
    }

    private func updateHighlightedWindow(at point: CGPoint) {
        print("[DEBUG WindowDetectionView] 鼠标位置（窗口局部坐标）: \(point)")

        guard let screen = NSScreen.main else {
            print("[DEBUG WindowDetectionView] ⚠️ 无法获取屏幕")
            return
        }

        // ✅ 将窗口局部坐标（SwiftUI）转换为屏幕坐标（CoreGraphics）
        let screenPoint = CoordinateSystem.localToScreen(point, windowFrame: windowFrame, screen: screen)
        print("[DEBUG WindowDetectionView] 鼠标位置（屏幕坐标 CG）: \(screenPoint)")

        // ✅ 新增：打印所有屏幕的信息
        print("[DEBUG WindowDetectionView] 所有屏幕信息：")
        for (index, s) in NSScreen.screens.enumerated() {
            print("[DEBUG]   屏幕 \(index): \(s.localizedName), frame: \(s.frame)")
        }

        let found = windowService.findWindow(at: screenPoint, in: windows)
        print("[DEBUG WindowDetectionView] 找到窗口: \(found?.displayTitle ?? "nil"), bounds: \(found?.bounds ?? .zero)")
        highlightedWindow = found
        print("[DEBUG WindowDetectionView] highlightedWindow 已更新: \(highlightedWindow?.displayTitle ?? "nil")")
    }

    /// 捕获窗口的屏幕框架
    private func captureWindowFrame() {
        // ⚠️ 关键修复：不能使用 NSApp.keyWindow，因为它可能返回其他窗口（如状态栏）
        // 需要通过其他方式获取窗口框架
        // 对于全屏覆盖窗口，窗口框架就是屏幕框架
        if let screen = NSScreen.main {
            windowFrame = screen.frame
            print("[DEBUG WindowDetectionView] 使用屏幕框架: \(windowFrame)")
        } else {
            print("[DEBUG WindowDetectionView] ⚠️ 无法获取屏幕")
        }
    }

    private func handleBackgroundTap() {
        // 点击背景时，如果有高亮窗口则选中
        if let window = highlightedWindow {
            onWindowSelected(window, window.bounds)
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        if !isDragging {
            // 开始拖拽
            isDragging = true
            dragStartPoint = value.startLocation
            selectionRect = CGRect(origin: value.startLocation, size: .zero)
            highlightedWindow = nil  // 清除窗口高亮
        }

        // 更新选择区域
        let currentPoint = value.location
        selectionRect = CGRect(
            x: min(dragStartPoint.x, currentPoint.x),
            y: min(dragStartPoint.y, currentPoint.y),
            width: abs(currentPoint.x - dragStartPoint.x),
            height: abs(currentPoint.y - dragStartPoint.y)
        )
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        isDragging = false

        // 如果选择区域太小（可能是点击），则尝试选择窗口
        if selectionRect.width < 10 && selectionRect.height < 10 {
            if let window = highlightedWindow {
                onWindowSelected(window, window.bounds)
            }
        } else {
            // 框选完成
            onAreaSelected(selectionRect)
        }

        // 重置选择区域
        selectionRect = .zero
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 { // ESC
            handleEscape()
            return nil
        }

        if event.keyCode == 36 { // Enter
            onFullscreen()
            return nil
        }

        return event
    }

    private func handleEscape() {
        if showExitConfirm {
            // 第2次 ESC: 退出
            exitConfirmTimer?.invalidate()
            showExitConfirm = false
            onCancel()
        } else {
            // 第1次 ESC: 显示提示
            withAnimation {
                showExitConfirm = true
            }
            exitConfirmTimer?.invalidate()
            exitConfirmTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                withAnimation {
                    showExitConfirm = false
                }
            }
        }
    }
}

// MARK: - Mouse Tracking View

/// 使用 NSViewRepresentable 创建能跟踪鼠标移动的视图
struct MouseTrackingView: NSViewRepresentable {
    var onMouseMove: (CGPoint) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        view.onMouseMove = onMouseMove
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

class TrackingView: NSView {
    var onMouseMove: ((CGPoint) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTracking()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTracking()
    }

    private func setupTracking() {
        print("[DEBUG TrackingView] setupTracking 被调用，bounds: \(bounds)")
        // 添加跟踪区域，监听鼠标移动
        let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseMoved, .inVisibleRect]
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        print("[DEBUG TrackingView] NSTrackingArea 已添加")
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let location = convert(event.locationInWindow, from: nil)
        // 转换坐标：从左下角原点转换为左上角原点
        let flippedLocation = CGPoint(x: location.x, y: bounds.height - location.y)
        print("[DEBUG TrackingView] 原始位置: \(location), 转换后: \(flippedLocation), bounds: \(bounds)")
        onMouseMove?(flippedLocation)
    }
}

// MARK: - Preview

#Preview {
    WindowDetectionView(
        onWindowSelected: { window, rect in
            print("Selected: \(window.displayTitle)")
        },
        onAreaSelected: { rect in
            print("Area: \(rect)")
        },
        onFullscreen: {
            print("Fullscreen")
        },
        onCancel: {
            print("Cancel")
        }
    )
    .frame(width: 800, height: 600)
}
