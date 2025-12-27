import AppKit
import SwiftUI

/// 窗口高亮控制器 - 独立的原型版本（不需要屏幕权限）
///
/// 功能：
/// - 鼠标移动到哪个窗口，哪个窗口就显示蓝色虚线框
/// - 所有屏幕同时显示覆盖层
/// - 不需要屏幕录制权限
class WindowHighlightController: ObservableObject {
    // MARK: - Published State

    /// 所有窗口信息
    @Published var windows: [WindowInfo] = []

    /// 当前高亮的窗口
    @Published var highlightedWindow: WindowInfo?

    /// 是否启用高亮
    @Published var isEnabled: Bool = false

    /// 选中的窗口（点击确认）
    @Published var selectedWindow: WindowInfo?

    // MARK: - Private Properties

    /// 每个屏幕的面板
    private var screenPanels: [NSPanel] = []

    /// 全局鼠标监听器
    private var globalMouseMonitor: Any?

    /// 本地鼠标监听器
    private var localMouseMonitor: Any?

    /// 键盘监听器（用于 ESC 退出）
    private var keyboardMonitor: Any?

    /// 鼠标点击监听器
    private var mouseClickMonitor: Any?

    /// 窗口信息服务
    private let windowService = WindowInfoService.shared

    /// 权限状态
    @Published var hasScreenCapturePermission: Bool = false
    @Published var hasAccessibilityPermission: Bool = false

    // MARK: - Singleton

    static let shared = WindowHighlightController()

    private init() {
        // 不需要通知监听器了
    }

    // MARK: - Public Methods

    /// 启动窗口高亮
    func startHighlight() {
        guard !isEnabled else { return }

        // 🔍 检测权限状态
        hasScreenCapturePermission = CGPreflightScreenCaptureAccess()
        hasAccessibilityPermission = AXIsProcessTrusted()

        print("[DEBUG WindowHighlight] ========== 权限检测 ==========")
        print("[DEBUG WindowHighlight] 屏幕录制权限: \(hasScreenCapturePermission ? "✅ 已授权" : "❌ 未授权")")
        print("[DEBUG WindowHighlight] 辅助功能权限: \(hasAccessibilityPermission ? "✅ 已授权" : "❌ 未授权")")

        // 如果缺少权限，先请求权限
        if !hasScreenCapturePermission {
            print("[TIP] 正在请求屏幕录制权限...")
            CGRequestScreenCaptureAccess()
            // 等待用户授权
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.hasScreenCapturePermission = CGPreflightScreenCaptureAccess()
                if self.hasScreenCapturePermission {
                    print("[DEBUG WindowHighlight] ✅ 屏幕录制权限已授权")
                    self.tryStartHighlight()
                } else {
                    print("[ERROR WindowHighlight] ❌ 屏幕录制权限被拒绝")
                    self.showPermissionAlert()
                }
            }
            return
        }

        if !hasAccessibilityPermission {
            print("[TIP] 正在请求辅助功能权限...")
            // 辅助功能权限需要手动在系统设置中开启
            showPermissionAlert()
            return
        }

        tryStartHighlight()
    }

    /// 尝试启动高亮（权限已满足）
    private func tryStartHighlight() {
        guard hasScreenCapturePermission && hasAccessibilityPermission else {
            print("[ERROR WindowHighlight] 权限不足，无法启动")
            return
        }

        isEnabled = true

        // 1. 获取所有窗口
        fetchAllWindows()

        // 2. 为每个屏幕创建覆盖面板
        createPanelsForAllScreens()

        // 3. 设置全局鼠标监听
        setupGlobalMouseTracking()
    }

    /// 显示权限提示对话框
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "需要系统权限"
        alert.informativeText = """
        窗口高亮功能需要以下权限：

        1. 屏幕录制权限 - 用于获取窗口列表
        2. 辅助功能权限 - 用于监听鼠标移动

        请在「系统设置 > 隐私与安全性」中授权
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 打开系统设置的隐私页面
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// 停止窗口高亮
    func stopHighlight() {
        isEnabled = false

        // 移除鼠标监听
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }

        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }

        // 移除键盘监听
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }

        // 关闭所有面板
        screenPanels.forEach { $0.close() }
        screenPanels.removeAll()

        highlightedWindow = nil
        selectedWindow = nil
    }

    /// 确认选择当前高亮的窗口
    func confirmSelection() {
        selectedWindow = highlightedWindow
        print("[DEBUG WindowHighlight] 确认选择窗口: \(selectedWindow?.displayTitle ?? "nil")")
        stopHighlight()
    }

    /// 切换窗口高亮状态
    func toggleHighlight() {
        if isEnabled {
            stopHighlight()
        } else {
            startHighlight()
        }
    }

    // MARK: - Private Methods

    private func fetchAllWindows() {
        switch windowService.fetchAllWindows() {
        case .success(let windowList):
            windows = windowList
        case .failure(let error):
            print("[ERROR WindowHighlight] 获取窗口失败: \(error)")
            windows = []
        }
    }

    private func createPanelsForAllScreens() {
        let screens = NSScreen.screens

        for screen in screens {
            let panel = createPanel(for: screen)
            screenPanels.append(panel)
            panel.orderFrontRegardless()
        }
    }

    private func createPanel(for screen: NSScreen) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // 面板配置
        panel.level = .screenSaver  // 最高级别，覆盖所有窗口
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = false  // 拦截鼠标事件
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]

        // 设置窗口 frame
        panel.setFrame(screen.frame, display: true)

        // 创建 SwiftUI 视图
        let view = WindowHighlightOverlayView(
            screen: screen,
            controller: self
        )

        let hostingController = NSHostingController(rootView: view)
        hostingController.view.frame = screen.frame
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        // ⚠️ 同步设置 contentViewController，确保视图已加载
        panel.contentViewController = hostingController

        return panel
    }

    private func setupGlobalMouseTracking() {
        // 全局监听 - 捕获所有鼠标移动
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMoved(event)
        }

        // 本地监听 - 捕获应用内鼠标移动
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMoved(event)
            return event
        }

        // 全局鼠标点击监听 - 点击确认选择
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleMouseClick(event)
        }

        // 本地鼠标点击监听
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleMouseClick(event)
            return event
        }

        // 全局键盘监听 - ESC 退出，Enter 确认
        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.stopHighlight()
            } else if event.keyCode == 36 { // Enter
                self?.confirmSelection()
            }
        }

        // 本地键盘监听 - ESC 退出（备用）
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.stopHighlight()
                return nil
            } else if event.keyCode == 36 { // Enter
                self?.confirmSelection()
                return nil
            }
            return event
        }
    }

    private func handleMouseClick(_ event: NSEvent) {
        guard isEnabled else { return }

        // 如果有高亮的窗口，确认选择
        if highlightedWindow != nil {
            confirmSelection()
        }
    }

    private func handleMouseMoved(_ event: NSEvent) {
        guard isEnabled else { return }

        // 获取鼠标位置（AppKit 坐标系）
        let mouseLocation = NSEvent.mouseLocation

        // 找到鼠标所在的屏幕
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) else {
            return
        }

        // 转换为 CoreGraphics 坐标系
        let screenHeight = screen.frame.height
        let cgPoint = CGPoint(x: mouseLocation.x, y: screenHeight - mouseLocation.y)

        // 查找鼠标下的窗口
        let window = windowService.findWindow(at: cgPoint, in: windows)

        // 更新高亮窗口
        if highlightedWindow != window {
            highlightedWindow = window
        }
    }

    /// 判断窗口是否应该在指定屏幕上显示高亮
    func shouldShowHighlight(for window: WindowInfo, in screen: NSScreen) -> Bool {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }

        let screenBounds = CGDisplayBounds(displayID)
        return window.bounds.intersects(screenBounds)
    }
}

/// 窗口高亮覆盖视图（多屏幕版本）
struct WindowHighlightOverlayView: View {
    let screen: NSScreen
    @ObservedObject var controller: WindowHighlightController

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 半透明背景
                Color.black.opacity(0.2)

                // 窗口高亮框
                if let window = controller.highlightedWindow,
                   controller.shouldShowHighlight(for: window, in: screen) {
                    let localBounds = convertToLocalBounds(window.bounds)

                    ZStack {
                        // 蓝色虚线边框
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                Color.blue,
                                style: StrokeStyle(lineWidth: 4, dash: [10, 6])
                            )

                        // 白色内边框（增加对比度）
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white, lineWidth: 2)
                    }
                    .frame(width: localBounds.width, height: localBounds.height)
                    .position(x: localBounds.midX, y: localBounds.midY)

                    // 窗口信息卡片
                    VStack(alignment: .leading, spacing: 4) {
                        Text(window.displayTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)

                        HStack(spacing: 8) {
                            Text("✓ 点击确认")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.8))

                            Text("ESC 取消")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.75))
                    )
                    .position(x: localBounds.midX, y: localBounds.minY - 30)
                    .onAppear {
                        print("[DEBUG UI] 高亮窗口: \(window.displayTitle)")
                        print("[DEBUG UI] 位置: \(localBounds)")
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(width: screen.frame.width, height: screen.frame.height)
        .ignoresSafeArea(.all)
    }

    /// 将全局坐标（CoreGraphics）转换为当前屏幕的局部坐标（SwiftUI）
    private func convertToLocalBounds(_ globalRect: CGRect) -> CGRect {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return .zero
        }

        let screenBounds = CGDisplayBounds(displayID)

        return CGRect(
            x: globalRect.origin.x - screenBounds.origin.x,
            y: globalRect.origin.y - screenBounds.origin.y,
            width: globalRect.size.width,
            height: globalRect.size.height
        )
    }
}
