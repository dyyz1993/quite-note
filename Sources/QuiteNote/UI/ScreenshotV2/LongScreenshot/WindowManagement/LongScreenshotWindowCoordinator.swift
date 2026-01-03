import Foundation
import AppKit
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.quitenote.app", category: "LongScreenshotWindow")

/// 长截图窗口协调器
/// 统一管理三个独立窗口：选区覆盖层、工具栏、预览面板
@MainActor
class LongScreenshotWindowCoordinator: ObservableObject {
    static let shared = LongScreenshotWindowCoordinator()

    // 三个独立窗口
    private var selectionOverlay: NSPanel?
    private var toolbarPanel: NSPanel?
    private var previewPanel: NSPanel?

    // ✨ 新增：视觉引导面板
    private var guidePanel: NSPanel?

    // 状态
    @Published var isActive: Bool = false
    private var currentScreen: NSScreen?
    private var currentSelection: CGRect?

    private init() {}

    // MARK: - 窗口管理

    /// 显示所有窗口
    func showAllWindows(selection: CGRect, screen: NSScreen) {
        closeAllWindows()  // 先关闭旧的

        self.currentSelection = selection
        self.currentScreen = screen

        // 1. 创建选区覆盖层（完全穿透）
        selectionOverlay = createSelectionOverlay(selection: selection, screen: screen)

        // 2. 创建工具栏面板（独立接收事件）
        toolbarPanel = createToolbarPanel(selection: selection, screen: screen)

        // 3. 显示窗口
        selectionOverlay?.orderFrontRegardless()
        toolbarPanel?.orderFrontRegardless()

        isActive = true
        print("✅ 长截图窗口已显示 - 选区覆盖层（穿透），工具栏（独立）")
    }

    /// 显示预览面板（在采集开始时）
    func showPreviewPanel() {
        guard let selection = currentSelection,
              let screen = currentScreen else {
            print("❌ 无法显示预览面板 - 选区或屏幕为空")
            return
        }

        previewPanel?.close()  // 关闭旧的
        previewPanel = createPreviewPanel(selection: selection, screen: screen)
        previewPanel?.orderFrontRegardless()

        print("✅ 预览面板已显示")
    }

    /// 更新工具栏位置（选区改变时）
    func updateToolbarPosition(selection: CGRect) {
        self.currentSelection = selection

        guard let screen = currentScreen else { return }

        // 重新创建工具栏（简单有效）
        toolbarPanel?.close()
        toolbarPanel = createToolbarPanel(selection: selection, screen: screen)
        toolbarPanel?.orderFrontRegardless()

        print("✅ 工具栏位置已更新")
    }

    /// 关闭所有窗口
    func closeAllWindows() {
        guidePanel?.close()  // ✅ 新增：关闭引导面板
        previewPanel?.close()
        toolbarPanel?.close()
        selectionOverlay?.close()

        guidePanel = nil  // ✅ 新增
        previewPanel = nil
        toolbarPanel = nil
        selectionOverlay = nil

        isActive = false
        currentSelection = nil
        currentScreen = nil

        print("✅ 所有长截图窗口已关闭")
    }

    // MARK: - 截图辅助方法

    /// ✅ 截图前隐藏 UI（防止被捕获进截图）
    /// 使用 orderOut 完全隐藏窗口，而不是透明度
    func hideUIForCapture() async {
        // 完全隐藏窗口，从窗口服务器显示列表中移除
        selectionOverlay?.orderOut(nil)
        toolbarPanel?.orderOut(nil)
        previewPanel?.orderOut(nil)  // 隐藏预览面板
        guidePanel?.orderOut(nil)  // ✅ 新增：隐藏引导面板

        logger.info("截图前已隐藏 UI（线框、工具栏、预览面板和引导面板）")

        // ⏰ 等待窗口服务器处理（32ms 更保险）
        try? await Task.sleep(nanoseconds: 32_000_000)
    }

    /// ✅ 截图后恢复 UI
    func showUIAfterCapture() {
        selectionOverlay?.orderFrontRegardless()
        toolbarPanel?.orderFrontRegardless()
        previewPanel?.orderFrontRegardless()  // 恢复预览面板

        // ✅ 新增：只在需要时恢复引导面板
        if V2PrimaryScreenStateManager.shared.isShowingScrollBackGuide {
            guidePanel?.orderFrontRegardless()
        }

        logger.info("截图后已恢复 UI（线框、工具栏和预览面板）")
    }

    // MARK: - ✨ 新增：视觉引导管理

    /// 显示滚回引导面板
    func showScrollBackGuide(
        frameIndex: Int,
        targetOffset: CGFloat,
        direction: ScrollDirection
    ) {
        guard let selection = currentSelection,
              let screen = currentScreen else {
            print("❌ 无法显示引导面板 - 选区或屏幕为空")
            return
        }

        guidePanel?.close()  // 关闭旧的

        let guideSize = NSSize(width: selection.width, height: selection.height)
        let position = calculateGuidePosition(
            selection: selection,
            screen: screen,
            direction: direction,
            panelSize: guideSize
        )

        let frame = NSRect(origin: position, size: guideSize)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // ⚠️ 关键配置：完全透明背景
        panel.level = NSWindow.Level.screenSaver
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.ignoresMouseEvents = false  // 允许点击关闭按钮
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        // ⚠️ 滚回引导功能已移除
        let alert = NSAlert()
        alert.messageText = "功能已移除"
        alert.informativeText = "滚回引导功能已被移除。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    /// 隐藏滚回引导面板（已移除）
    func hideScrollBackGuide() {
        // 功能已移除
    }

    /// 更新引导面板的距离显示（已移除）
    func updateGuideDistance(currentOffset: CGFloat) {
        // 功能已移除

        // 更新距离显示
        let targetOffset = V2PrimaryScreenStateManager.shared.guideTargetScrollOffset
        let distance = abs(targetOffset - currentOffset)

        // 通过更新状态管理器来触发视图更新
        // 注意：ScrollBackGuideView 需要使用 @ObservedObject 来监听距离变化
    }

    /// 计算引导面板位置
    private func calculateGuidePosition(
        selection: CGRect,
        screen: NSScreen,
        direction: ScrollDirection,
        panelSize: CGSize
    ) -> CGPoint {
        // 引导面板与选区重合，不需要额外偏移
        return CGPoint(
            x: selection.origin.x + screen.frame.origin.x,
            y: selection.origin.y + screen.frame.origin.y
        )
    }

    // MARK: - 窗口创建

    /// 创建选区覆盖层（完全穿透）
    private func createSelectionOverlay(selection: CGRect, screen: NSScreen) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // ⚠️ 关键配置：完全穿透
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true  // ✅ 完全穿透
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // 设置内容视图（只显示线框，不处理事件）
        let contentView = SelectionOverlayContentView(selection: selection, screen: screen)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        return panel
    }

    /// 创建工具栏面板（独立窗口）
    private func createToolbarPanel(selection: CGRect, screen: NSScreen) -> NSPanel {
        let toolbarSize = NSSize(width: 450, height: 60)
        let position = WindowPositionCalculator.calculateToolbarPosition(
            selection: selection,
            screen: screen,
            windowSize: toolbarSize
        )

        print("🔍 工具栏位置计算:")
        print("   selection(局部): \(selection)")
        print("   position(局部): \(position)")
        print("   screen.frame: \(screen.frame)")

        // ⚠️ position 是局部坐标，需要转换为全局坐标
        let localOrigin = CGPoint(
            x: position.x - toolbarSize.width / 2,
            y: position.y - toolbarSize.height / 2
        )

        // ✅ 转换为全局坐标
        let globalOrigin = CGPoint(
            x: localOrigin.x + screen.frame.origin.x,
            y: localOrigin.y + screen.frame.origin.y
        )

        print("   localOrigin: \(localOrigin)")
        print("   globalOrigin: \(globalOrigin)")

        let frame = NSRect(origin: globalOrigin, size: toolbarSize)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .hudWindow],
            backing: .buffered,
            defer: false
        )

        // ⚠️ 关键配置：独立接收事件
        panel.level = .floating
        panel.ignoresMouseEvents = false  // ✅ 接收事件
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        // 设置内容视图
        let contentView = LongScreenshotToolbarContentView(
            selection: selection,
            screen: screen,
            coordinator: self
        )
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        return panel
    }

    /// 创建预览面板（独立窗口）
    private func createPreviewPanel(selection: CGRect, screen: NSScreen) -> NSPanel {
        // ✅ 修改：增加预览面板尺寸以容纳更大的预览图（400x260）
        let previewSize = NSSize(width: 400, height: 260)
        let position = WindowPositionCalculator.calculatePreviewPosition(
            selection: selection,
            screen: screen,
            windowSize: previewSize
        )

        // ⚠️ position 是局部坐标，需要转换为全局坐标
        let globalOrigin = CGPoint(
            x: position.x + screen.frame.origin.x,
            y: position.y + screen.frame.origin.y
        )

        let frame = NSRect(origin: globalOrigin, size: previewSize)

        logger.info("创建预览面板，frame: \(frame.debugDescription)")

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // ⚠️ 关键配置：独立显示
        panel.level = .floating
        panel.ignoresMouseEvents = false
        panel.isMovable = true
        panel.isReleasedWhenClosed = false

        // 设置内容视图
        let contentView = LongScreenshotPreviewPanelView(
            selection: selection,
            screen: screen
        )
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        logger.info("预览面板已创建，窗口ID: \(panel.windowNumber)")

        return panel
    }
}

// MARK: - 位置计算器

struct WindowPositionCalculator {
    /// 计算工具栏位置
    /// ⚠️ selection 是屏幕局部坐标（AppKit 坐标系，左下角原点）
    static func calculateToolbarPosition(
        selection: CGRect,
        screen: NSScreen,
        windowSize: CGSize
    ) -> CGPoint {
        let screenFrame = screen.frame
        let spacing: CGFloat = 12

        // ⚠️ selection 已经是局部坐标，直接使用
        let localSelection = selection

        // ✅ 局部坐标系中的屏幕边界（原点在 (0, 0)）
        let localScreenBounds = CGRect(
            x: 0,
            y: 0,
            width: screenFrame.width,
            height: screenFrame.height
        )

        // AppKit 坐标系：左下角是原点，Y 向上为正
        // 所以 minY 是底部（视觉上的下方），maxY 是顶部（视觉上的上方）
        let candidates: [CGPoint] = [
            // 1. 选区下方（视觉上的下方 = Y 值更小）
            CGPoint(x: localSelection.midX, y: localSelection.minY - windowSize.height/2 - spacing),
            // 2. 选区上方（视觉上的上方 = Y 值更大）
            CGPoint(x: localSelection.midX, y: localSelection.maxY + windowSize.height/2 + spacing),
            // 3. 选区内部底部
            CGPoint(x: localSelection.midX, y: localSelection.minY + windowSize.height/2 + spacing)
        ]

        // 检查位置是否在屏幕内且有足够空间
        for candidate in candidates {
            let frame = NSRect(
                origin: CGPoint(
                    x: candidate.x - windowSize.width/2,
                    y: candidate.y - windowSize.height/2
                ),
                size: windowSize
            )

            // ✅ 使用局部坐标检查
            if localScreenBounds.contains(frame) {
                return candidate
            }
        }

        // 默认：屏幕中心（局部坐标）
        return CGPoint(x: localScreenBounds.midX, y: localScreenBounds.midY)
    }

    /// 计算预览面板位置
    /// ⚠️ selection 是屏幕局部坐标（相对于传入的 screen）
    static func calculatePreviewPosition(
        selection: CGRect,
        screen: NSScreen,
        windowSize: CGSize
    ) -> CGPoint {
        let screenFrame = screen.frame
        let spacing: CGFloat = 20

        // ✅ 局部坐标系中的屏幕边界（原点在 (0, 0)）
        let localScreenBounds = CGRect(
            x: 0,
            y: 0,
            width: screenFrame.width,
            height: screenFrame.height
        )

        // ⚠️ selection 已经是局部坐标，直接使用
        let localSelection = selection

        // 优先显示在选区右侧
        let rightX = localSelection.maxX + windowSize.width/2 + spacing
        if rightX + windowSize.width/2 < localScreenBounds.maxX {
            return CGPoint(x: rightX, y: localSelection.midY)
        }

        // 否则显示在左侧
        let leftX = localSelection.minX - windowSize.width/2 - spacing
        if leftX - windowSize.width/2 > localScreenBounds.minX {
            return CGPoint(x: leftX, y: localSelection.midY)
        }

        // 默认：屏幕右侧
        return CGPoint(
            x: localScreenBounds.maxX - windowSize.width/2 - spacing,
            y: localScreenBounds.midY
        )
    }
}

// MARK: - SwiftUI 视图

/// 选区覆盖层内容视图（只显示线框，不处理事件）
struct SelectionOverlayContentView: View {
    let selection: CGRect  // ⚠️ 屏幕局部坐标（相对于传入的 screen）
    let screen: NSScreen

    var body: some View {
        ZStack {
            // 完全透明背景
            Color.clear

            // 选区边框（黄色线框）
            // ⚠️ selection 已经是局部坐标，直接使用
            YellowWireframe(
                rect: selection,
                label: "长截图区域",
                isDashed: false,
                showBackground: true,
                isEditing: false,
                isLongScreenshotMode: true,
                opacity: 0.8
            )
            .allowsHitTesting(false)  // ⚠️ 确保不拦截事件
        }
        .frame(width: screen.frame.width, height: screen.frame.height)
    }
}

/// 长截图工具栏内容视图
struct LongScreenshotToolbarContentView: View {
    let selection: CGRect
    let screen: NSScreen
    let coordinator: LongScreenshotWindowCoordinator

    @ObservedObject var stateManager = V2PrimaryScreenStateManager.shared

    var body: some View {
        HStack(spacing: 16) {
            // 长图模式标识
            Text("长图采集模式")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.green)

            Divider()
                .frame(width: 1, height: 24)
                .background(Color.white.opacity(0.2))

            // 开始/暂停 切换按钮
            if stateManager.isCapturing {
                // 暂停按钮
                ToolbarButton(icon: "pause.circle.fill", color: .orange, label: "暂停") {
                    Task {
                        await LongScreenshotFlowController.shared.stopCapture()
                    }
                }
            } else {
                // 开始滚动按钮
                ToolbarButton(icon: "record.circle", color: .red, label: "开始滚动") {
                    Task { @MainActor in
                        await LongScreenshotFlowController.shared.startCapture(
                            selection: selection,
                            screen: screen,
                            config: .default
                        ) { result in
                            switch result {
                            case .success(let image):
                                print("长截图拼接成功，尺寸: \(image.size)")
                                coordinator.closeAllWindows()
                            case .failure(let error):
                                print("长截图失败: \(error.localizedDescription)")
                            }
                        }

                        // ✅ 修复：不再在这里显示预览面板
                        // 预览面板会在第一帧捕获成功后自动显示
                    }
                }
            }

            // 完成按钮（只在采集时显示）
            if stateManager.isCapturing {
                ToolbarButton(icon: "checkmark.circle.fill", color: .green, label: "完成") {
                    Task {
                        await LongScreenshotFlowController.shared.stopCapture()
                    }
                }
            }

            ToolbarButton(icon: "xmark.circle", color: .white, label: "取消") {
                Task {
                    if stateManager.isCapturing {
                        await LongScreenshotFlowController.shared.cancelCapture()
                    }
                    coordinator.closeAllWindows()
                    V2PrimaryScreenStateManager.shared.setLongScreenshotMode(false)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.4))
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(0.5), radius: 15, x: 0, y: 8)
    }
}
