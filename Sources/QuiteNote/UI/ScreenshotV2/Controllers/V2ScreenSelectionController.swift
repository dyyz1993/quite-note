import AppKit
import SwiftUI

/// V2 屏幕选择控制器 - 为每个屏幕创建独立面板
@MainActor
class V2ScreenSelectionController: NSObject {
    private var state: V2CaptureState
    private var onSelectScreen: ((NSScreen) -> Void)?
    private var onSelectWindow: ((WindowInfo) -> Void)?
    private var onSelectArea: ((CGRect, NSScreen) -> Void)?
    private var onCancel: (() -> Void)?

    // 所有屏幕的面板
    private var screenPanels: [NSPanel] = []

    // 所有窗口信息（全局）
    private var allWindows: [WindowInfo] = []

    // ⚠️ 关键修复: 鼠标所在的屏幕 (targetScreen) - 支持动态切换
    private var targetScreen: NSScreen!

    // 全局鼠标追踪，用于动态切换主屏幕
    private var globalEventMonitor: Any?

    // 本地鼠标追踪（后备方案）
    private var localEventMonitor: Any?

    // 防抖：减少屏幕切换更新的频率
    private var screenUpdateWorkItem: DispatchWorkItem?

    private override init() {
        self.state = V2CaptureState()
        super.init()
    }

    /// 创建控制器
    static func create(
        onSelectScreen: @escaping (NSScreen) -> Void,
        onSelectWindow: @escaping (WindowInfo) -> Void,
        onSelectArea: @escaping (CGRect, NSScreen) -> Void,
        onCancel: @escaping @Sendable () -> Void
    ) -> V2ScreenSelectionController {
        let controller = V2ScreenSelectionController()

        controller.onSelectScreen = onSelectScreen
        controller.onSelectWindow = onSelectWindow
        controller.onSelectArea = onSelectArea
        controller.onCancel = onCancel

        controller.setup()
        return controller
    }

    private func setup() {
        // 获取鼠标所在的屏幕,而不是主屏幕
        targetScreen = NSScreen.screens.first { screen in
            screen.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens.first!

        // ⚠️ 在创建面板之前设置 primaryScreen，避免透明度闪烁
        V2PrimaryScreenStateManager.shared.updatePrimaryScreen(targetScreen)

        // 1. 捕获所有屏幕
        state.screenSnapshots = V2ScreenCaptureService.shared.captureAllScreens()

        if state.screenSnapshots.isEmpty {
            return
        }

        // 2. 获取所有窗口信息（使用现有的 WindowInfoService）
        switch WindowInfoService.shared.fetchAllWindows() {
        case .success(let windows):
            allWindows = windows
        case .failure:
            allWindows = []
        }

        // 3. 为每个屏幕创建独立的面板
        createPanelsForAllScreens()

        // 4. 启动全局鼠标追踪
        startMouseTracking()
    }

    /// 启动全局鼠标追踪，动态切换主屏幕
    private func startMouseTracking() {
        print("[V2ScreenSelectionController] 启动鼠标追踪...")

        // 1. 尝试监听全局鼠标移动事件（需要辅助功能权限）
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseMoved(event)
        }

        if globalEventMonitor != nil {
            print("[V2ScreenSelectionController] ✅ 全局鼠标追踪已启动")
        } else {
            print("[V2ScreenSelectionController] ⚠️ 全局鼠标追踪启动失败（可能无辅助功能权限）")
        }

        // 2. 始终启用本地追踪作为后备（不需要权限）
        // ⚠️ 关键修复：无论全局追踪是否成功，都启用本地追踪
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseMoved(event)
            return event
        }

        if localEventMonitor != nil {
            print("[V2ScreenSelectionController] ✅ 本地鼠标追踪已启动")
        } else {
            print("[V2ScreenSelectionController] ❌ 本地鼠标追踪启动失败")
        }
    }

    /// 处理鼠标移动，动态切换主屏幕
    private func handleMouseMoved(_ event: NSEvent) {
        let mouseLocation = NSEvent.mouseLocation

        // 找到鼠标所在的屏幕
        let newTargetScreen = NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }

        // 如果鼠标移动到了不同屏幕，更新主屏幕
        if let newScreen = newTargetScreen, newScreen != targetScreen {
            // 取消之前的更新任务
            screenUpdateWorkItem?.cancel()

            // 创建新的更新任务（防抖：50ms 延迟）
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                print("[V2ScreenSelectionController] 鼠标切换到屏幕: \(newScreen.localizedName)")
                self.targetScreen = newScreen
                self.updatePanelsForScreenChange()
            }
            screenUpdateWorkItem = workItem

            // 立即更新（不延迟），但通过取消机制来防抖
            DispatchQueue.main.async(execute: workItem)
        }
    }

    /// 当主屏幕切换时，更新所有面板的状态
    private func updatePanelsForScreenChange() {
        // 更新全局状态管理器（视图层会自动响应变化）
        V2PrimaryScreenStateManager.shared.updatePrimaryScreen(targetScreen)

        // 更新面板的层级（主面板成为 key window）
        for panel in screenPanels {
            // 通过 frame 反查屏幕
            guard let screen = NSScreen.screens.first(where: { $0.frame == panel.frame }) else {
                continue
            }

            let isPrimary = (screen == targetScreen)
            if isPrimary {
                panel.makeKeyAndOrderFront(nil)
            } else {
                // ✨ 修复：确保非主屏幕面板也保持显示，避免背景消失
                panel.orderFront(nil)
            }
        }
    }

    /// 为每个屏幕创建独立的面板
    private func createPanelsForAllScreens() {

        for screen in NSScreen.screens {
            // 即使截图失败,也创建面板 (使用空白背景)
            let snapshot = state.screenSnapshots[screen] ?? createEmptySnapshot(for: screen)

            let panel = createPanelForScreen(screen, snapshot: snapshot)
            screenPanels.append(panel)
        }
    }

    /// 辅助方法: 创建空白截图 (用于截图失败时的降级)
    private func createEmptySnapshot(for screen: NSScreen) -> NSImage {
        let size = screen.frame.size
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.set()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    /// 为单个屏幕创建面板
    private func createPanelForScreen(_ screen: NSScreen, snapshot: NSImage) -> NSPanel {
        // 使用 screen.frame (AppKit坐标)
        let screenFrame = screen.frame
        let isPrimary = (screen == targetScreen)

        let panel = NSPanel(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // 面板配置
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // ⚠️ 修复：所有屏幕都接收鼠标事件，在视图层判断是否是主屏幕
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]

        // 强制设置面板 frame (显示前)
        panel.setFrame(screenFrame, display: false)

        // 创建视图
        let view = V2WindowHighlightView(
            screen: screen,
            snapshot: snapshot,
            allWindows: allWindows,  // 传递所有窗口,由视图过滤
            isPrimary: isPrimary,    // 传递是否为主屏幕标志
            onHoverWindow: { _ in },
            onSelectWindow: { [weak self] window in
                self?.handleWindowSelected(window)
            },
            onSelectArea: { [weak self] rect, screen in
                self?.handleAreaSelected(rect, screen: screen)
            },
            onCancel: { [weak self] in
                self?.handleCancel()
            }
        )

        let hostingController = NSHostingController(rootView: view)

        // 使用绝对坐标,不是相对坐标
        hostingController.view.frame = screenFrame
        hostingController.view.autoresizingMask = []  // 移除autoresizingMask,避免冲突

        panel.contentViewController = hostingController

        return panel
    }

    private func handleScreenSelected(_ screen: NSScreen) {
        close()
        onSelectScreen?(screen)
    }

    private func handleWindowSelected(_ window: WindowInfo) {
        close()
        // 调用窗口选择回调
        onSelectWindow?(window)
    }

    private func handleAreaSelected(_ rect: CGRect, screen: NSScreen) {
        close()

        // 调用区域选择回调
        onSelectArea?(rect, screen)
    }

    private func handleCancel() {
        close()
        onCancel?()
    }

    func show() {
        // 找到主面板 (鼠标所在的屏幕)
        let mainPanel = screenPanels.first { panel in
            // 通过frame匹配找到主面板
            panel.frame == targetScreen.frame
        } ?? screenPanels.first

        // 显示所有面板
        for panel in screenPanels {
            panel.orderFrontRegardless()
        }

        NSApp.activate(ignoringOtherApps: true)

        // 主面板成为 key window
        mainPanel?.makeKeyAndOrderFront(nil)

        // 延迟验证frame (防止SwiftUI修改)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for panel in self.screenPanels {
                // 通过frame反查屏幕
                let screen = NSScreen.screens.first { s in
                    s.frame == panel.frame
                }

                if let screen = screen {
                    let screenFrame = screen.frame
                    if panel.frame != screenFrame {
                        panel.setFrame(screenFrame, display: true)
                    }
                }
            }

            mainPanel?.makeKey()
        }
    }

    func close() {
        // 停止鼠标追踪
        stopMouseTracking()

        for panel in screenPanels {
            panel.close()
        }
        screenPanels.removeAll()
    }

    /// 停止鼠标追踪
    private func stopMouseTracking() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }

    deinit {
        // 清理全局和本地事件监控（如果 close() 没有被调用）
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
