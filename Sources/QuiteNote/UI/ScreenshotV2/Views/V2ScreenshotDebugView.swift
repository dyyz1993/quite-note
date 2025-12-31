import SwiftUI
import AppKit
import os.log

private let v2Logger = Logger(subsystem: "com.quitenote.app", category: "ScreenshotV2")

/// V2 截图调试验证视图
/// 用于验证在获取到屏幕画面后，各层级的布局和交互情况。
struct V2ScreenshotDebugView: View {
    let screen: NSScreen
    let snapshot: NSImage
    let screenIndex: Int
    let allWindows: [WindowInfo] // 接收真实的窗口列表
    
    @State private var dragStartPoint: CGPoint?
    @State private var dragCurrentPoint: CGPoint?
    
    // ✨ 标注元素交互状态
    @State private var isDraggingElement: Bool = false
    @State private var initialElementPoints: [CGPoint] = []
    @State private var initialMagnifierOffset: CGSize = .zero
    @State private var magnifierDragTarget: MagnifierDragTarget? = nil

    enum MagnifierDragTarget {
        case circle
        case sourceDot
    }
    
    // 选区调整相关状态用于选区移动的临时状态
    @State private var initialSelectionForMove: CGRect?
    @State private var isMovingSelection: Bool = false
    @State private var activeHandle: SelectionHandle? = nil
    @State private var currentCursor: NSCursor = .arrow

    @State private var logEntries: [String] = ["Debug View Initialized"]
    @State private var currentLayerName: String = "None"
    @State private var currentLayerLevel: Int = 0
    @State private var mouseLocation: CGPoint = .zero
    @State private var hasMouseMoved: Bool = false // 记录鼠标是否移动过
    
    /// 订阅主屏幕状态变化
    @StateObject private var primaryScreenManager = V2PrimaryScreenStateManager.shared

    /// ✨ 文本编辑焦点状态（必须在同一视图内）
    @FocusState private var isTextEditingFocused: Bool
    
    /// 动态计算是否是主屏幕（响应鼠标移动）
    private var isCurrentlyPrimary: Bool {
        primaryScreenManager.isPrimary(screen)
    }
    
    /// 屏幕尺寸
    private var screenSize: CGSize {
        screen.frame.size
    }
    
    /// 获取全局选区（如果选区在当前屏幕）
    private var localSelectedArea: CGRect? {
        primaryScreenManager.selectionScreen == screen ? primaryScreenManager.selectedArea : nil
    }
    
    /// 是否有任何屏幕存在选区
    private var hasAnySelection: Bool {
        primaryScreenManager.selectedArea != nil
    }
    
    /// 是否应该完全释放（没有任何覆盖物，显示纯净画面）
    /// - 阶段 0（无选区）：所有屏幕都不释放
    /// - 阶段 1+（有选区）：只有当前操作屏幕不释放，其他屏幕释放
    private var isReleased: Bool {
        // 无选区时，所有屏幕都显示背景
        guard hasAnySelection else { return false }
        // 有选区时，只有当前操作屏幕显示背景
        return !isCurrentlyPrimary
    }
    
    // 供外部使用的静态日志入口
    static var onLog: ((String) -> Void)?

    private func addLog(_ message: String) {
        let timestamp = Date().formatted(.dateTime.hour().minute().second())
        let entry = "[\(timestamp)] \(message)"
        logEntries.insert(entry, at: 0)
        if logEntries.count > 10 { logEntries.removeLast() }
        v2Logger.debug("Screen \(screenIndex): \(message, privacy: .public)")
        V2ScreenshotDebugView.onLog = { self.addLog($0) }
    }
    
    // 获取当前屏幕上的可见窗口列表（不执行遮挡过滤，由悬停逻辑处理）
    private var windowsOnScreen: [WindowInfo] {
        guard let screenBounds = V2ScreenCaptureService.shared.getScreenBounds(screen) else {
            return []
        }
        
        // 过滤并转换当前屏幕上的窗口
        return allWindows.filter { window in
            // 1. 必须与当前屏幕相交
            guard window.bounds.intersects(screenBounds) else { return false }
            
            // 2. 排除过小的窗口 (小于 100x100)
            let rect = getLocalRect(for: window)
            if rect.width < 100 || rect.height < 100 {
                return false
            }
            
            // 3. 排除系统背景 (如 Window Server, Dock)
            // 不再排除全屏窗口，允许吸附到全屏窗口
            return !isSystemBackground(window)
        }
    }
    
    // 动态更新悬停状态：寻找鼠标位置下最顶层的窗口
    private func updateHoverState(at location: CGPoint) {
        // 1. 坐标转换：将局部坐标转换为全局屏幕坐标
        guard let globalPoint = V2CoordinateMapper.localToScreen(point: location, on: screen) else { return }
        
        // 2. 在所有窗口中寻找包含该点的最顶层窗口（allWindows 已按 Z-order 排序）
        let found = windowsOnScreen.first { window in
            window.bounds.contains(globalPoint)
        }
        
        if let window = found {
            let rect = getLocalRect(for: window)
            let label = "\(window.ownerName)\(window.windowName != nil ? ": \(window.windowName!)" : "")"
            primaryScreenManager.updateHover(rect, label: label, on: screen)
        } else {
            // 没找到窗口，吸附到全屏
            let screenRect = CGRect(origin: .zero, size: screen.frame.size)
            primaryScreenManager.updateHover(screenRect, label: "Full Screen", on: screen)
        }
    }
    
    private func isSystemBackground(_ window: WindowInfo) -> Bool {
        let name = window.ownerName
        return name == "Window Server" || name == "Dock" || (name == "Finder" && window.windowName == nil)
    }
    
    // 获取窗口在当前屏幕下的局部坐标
    private func getLocalRect(for window: WindowInfo) -> CGRect {
        // 使用标准的坐标映射服务
        return V2CoordinateMapper.screenToLocal(rect: window.bounds, on: screen) ?? .zero
    }
    
    // 获取指定位置下的手柄
    private func getHandle(at point: CGPoint, in rect: CGRect) -> SelectionHandle? {
        let handleSize: CGFloat = 20 // 扩大判定范围
        for handle in SelectionHandle.allCases {
            let pos = handle.position(in: rect)
            let handleRect = CGRect(x: rect.minX + pos.x - handleSize/2, 
                                    y: rect.minY + pos.y - handleSize/2, 
                                    width: handleSize, height: handleSize)
            if handleRect.contains(point) {
                return handle
            }
        }
        return nil
    }
    
    // 执行调整大小
    private func applyResize(to rect: CGRect, handle: SelectionHandle, dx: CGFloat, dy: CGFloat) -> CGRect {
        var newRect = rect
        switch handle {
        case .topLeft:
            newRect.origin.x += dx
            newRect.origin.y += dy
            newRect.size.width -= dx
            newRect.size.height -= dy
        case .top:
            newRect.origin.y += dy
            newRect.size.height -= dy
        case .topRight:
            newRect.size.width += dx
            newRect.origin.y += dy
            newRect.size.height -= dy
        case .right:
            newRect.size.width += dx
        case .bottomRight:
            newRect.size.width += dx
            newRect.size.height += dy
        case .bottom:
            newRect.size.height += dy
        case .bottomLeft:
            newRect.origin.x += dx
            newRect.size.width -= dx
            newRect.size.height += dy
        case .left:
            newRect.origin.x += dx
            newRect.size.width -= dx
        }
        
        // 修正负数宽高
        if newRect.width < 0 {
            newRect.origin.x += newRect.width
            newRect.size.width = abs(newRect.width)
        }
        if newRect.height < 0 {
            newRect.origin.y += newRect.height
            newRect.size.height = abs(newRect.height)
        }
        
        return newRect
    }

    // MARK: - 辅助渲染

    private func renderMagnifierForSave(element: DrawingElement, points: [CGPoint], in context: CGContext, baseImage: NSImage, rect: CGRect) {
        // ✨ 真正的放大镜效果：截取并放大图像
        guard points.count >= 1 else { return }
        let start = points[0] // 视觉源点（已转换坐标）
        let contentSource = element.magnifierSourcePoint ?? element.points[0] // 实际内容源点（原始坐标）
        
        // 计算放大镜中心位置（考虑偏移）
        let radius = element.fontSize * 2.5
        let padding: CGFloat = 20
        let zoomScale: CGFloat = 2.0
        
        // ✨ 计算放大镜的最终显示位置 (需要和 elementBoundingRect 逻辑一致)
        // 注意：ConvertedPoints 已经是相对于 rect 的了
        let baseX: CGFloat = rect.width
        let baseY: CGFloat = rect.height
        
        // 默认位置：右上角
        let defaultEndX = baseX - radius - padding
        let defaultEndY = baseY - radius - padding
        
        let rawEndX = defaultEndX + element.magnifierOffset.width
        let rawEndY = defaultEndY - element.magnifierOffset.height // NSGraphicsContext Y轴向上，所以减去偏移高度
        
        // 边界约束
        let minX = radius
        let maxX = rect.width - radius
        let minY = radius
        let maxY = rect.height - radius
        
        let magnifierCenter = CGPoint(
            x: max(minX, min(maxX, rawEndX)),
            y: max(minY, min(maxY, rawEndY))
        )
        
        let magnifierRect = CGRect(x: magnifierCenter.x - radius, y: magnifierCenter.y - radius, width: radius * 2, height: radius * 2)

        // 0. 绘制连接虚线
        let distance = hypot(magnifierCenter.x - start.x, magnifierCenter.y - start.y)
        if distance > radius * 0.8 {
            // ✨ 计算连线到圆外径的交点
            let dx = magnifierCenter.x - start.x
            let dy = magnifierCenter.y - start.y
            
            // 交点 = 中心点 - 单位向量 * 半径
            let edgePoint = CGPoint(
                x: magnifierCenter.x - (dx / distance) * radius,
                y: magnifierCenter.y - (dy / distance) * radius
            )
            
            context.saveGState()
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [4, 2])
            context.move(to: start)
            context.addLine(to: edgePoint)
            context.strokePath()
            context.restoreGState()
            
            // 绘制源点小圆圈
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: CGRect(x: start.x - 3, y: start.y - 3, width: 6, height: 6))
        }

        // 1. 绘制放大镜外框（白色粗圆圈）
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(4)
        context.strokeEllipse(in: magnifierRect)

        // 2. 创建裁剪区域（限制在圆内）
        context.saveGState()
        context.addEllipse(in: magnifierRect)
        context.clip()

        // 3. 绘制放大的图像
        // ⚠️ 转换回原始截图坐标进行裁剪
        guard let cgImage = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            context.restoreGState()
            return
        }

        let sourceRadius = radius / zoomScale
        let sourceRect = CGRect(
            x: contentSource.x - sourceRadius,
            y: contentSource.y - sourceRadius,
            width: sourceRadius * 2,
            height: sourceRadius * 2
        )

        if let croppedImage = cgImage.cropping(to: sourceRect) {
            context.draw(croppedImage, in: magnifierRect)
        }

        context.restoreGState()
    }

    // 保存到剪贴板并关闭
    private func saveToClipboard(rect: CGRect) {
        addLog("Saving selection to clipboard...")
        
        // ⚠️ 获取屏幕的缩放因子 (Retina 屏通常是 2.0)
        let scale = screen.backingScaleFactor
        
        // 1. 计算像素坐标下的裁剪区域 (CGImage 使用 Top-Left 坐标系)
        let pixelRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        
        // 2. 直接使用初始化时预取的 snapshot (它是纯净的，不包含调试 UI)
        guard let fullCGImage = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let croppedCGImage = fullCGImage.cropping(to: pixelRect) else {
            addLog("Error: Failed to crop snapshot image")
            return
        }
        
        // 3. 创建基础图片
        let finalImage = NSImage(cgImage: croppedCGImage, size: rect.size)

        // 4. ✨ 渲染标注系统（图层叠加法 - 所见即所得）
        if !primaryScreenManager.elements.isEmpty {
            // 创建导出用的画布视图 (不带辅助 UI)
            let exportCanvas = V2AnnotationCanvas(
                stateManager: primaryScreenManager,
                canvasSize: screenSize,
                baseImage: snapshot,
                isExporting: true
            )
            .frame(width: screenSize.width, height: screenSize.height)

            // 使用 ImageRenderer 渲染标注层为透明图片
            let renderer = ImageRenderer(content: exportCanvas)
            renderer.scale = scale
            
            if let annotationImage = renderer.nsImage {
                // 裁剪标注图层到选区大小
                // ⚠️ 注意：ImageRenderer 出来的 NSImage 坐标系和 CGImage 裁剪可能需要对应
                if let fullAnnotationCGImage = annotationImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
                   let croppedAnnotationCGImage = fullAnnotationCGImage.cropping(to: pixelRect) {
                    
                    let croppedAnnotationImage = NSImage(cgImage: croppedAnnotationCGImage, size: rect.size)
                    
                    // 将透明标注图层叠加到底图上
                    finalImage.lockFocus()
                    croppedAnnotationImage.draw(in: CGRect(origin: .zero, size: rect.size), from: .zero, operation: .sourceOver, fraction: 1.0)
                    finalImage.unlockFocus()
                }
            }
        }

        // 5. 写入剪贴板
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([finalImage])
        
        addLog("Saved to clipboard (Scale: \(scale))! Closing...")
        
        // 6. 关闭所有调试窗口
        V2ScreenshotDebugController.close()
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // ⚠️ 彻底释放逻辑：如果屏幕已释放，只保留最底层的透明背景，连图片都不渲染
            if isReleased {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 1. 底层：原始截图 (始终显示)
                Image(nsImage: snapshot)
                    .resizable()
                    .scaledToFill()
                    .frame(width: screen.frame.width, height: screen.frame.height)
                
                // 2. 蒙层层：用于实现挖孔效果 (长图模式下隐藏)
                if !primaryScreenManager.isLongScreenshotMode {
                    buildMaskOverlay()
                }
                
                // 3. 交互层：处理悬停和点击
                buildInteractionLayer()
                    .allowsHitTesting(!primaryScreenManager.isLongScreenshotMode)
                    .onChange(of: primaryScreenManager.isLongScreenshotMode) { isLongMode in
                        // 长图模式下，如果是当前屏幕有选区，则需要根据选区动态设置是否忽略鼠标事件
                        if let panel = V2ScreenshotDebugController.debugPanels.first(where: { $0.frame == screen.frame }) {
                            if isLongMode {
                                // ⚠️ 核心修复：降到最低层级，且不抢占焦点
                                panel.level = .normal
                                // ⚠️ 重要：初始状态不忽略鼠标事件，由 HostingView 的 hitTest 动态控制
                                panel.ignoresMouseEvents = false
                                addLog("Long Screenshot Mode Active - Window level: .normal")
                            } else {
                                panel.level = .screenSaver + 1
                                panel.ignoresMouseEvents = false
                                addLog("Long Screenshot Mode Inactive - Restored level")
                            }
                        }
                    }
                
                // 4. 框选层：显示正在拖拽的区域
                buildDragOverlay()
                
                // 4.5. 标注层：显示绘图内容 (长图模式下隐藏标注)
                if !primaryScreenManager.isLongScreenshotMode {
                    buildAnnotationLayer()
                }
                
                // 5. 调试信息层 (最顶层)
                if !primaryScreenManager.isCapturing {
                    buildDebugOverlay()
                }
                
                // 新增：长图滚动预览 (仅在长图模式下显示，且非采集过程中)
                if primaryScreenManager.isLongScreenshotMode, let selection = localSelectedArea, !primaryScreenManager.isCapturing {
                    V2LongScreenshotPreview(selection: selection, screen: screen)
                }
                
                // 新增：截图工具栏 (仅在有选区时显示，且非采集过程中)
                if let selection = localSelectedArea, !primaryScreenManager.isCapturing {
                    V2FloatingToolbar(selection: selection, screen: screen)
                        .zIndex(1000) // ✨ 确保工具栏在最顶层，不被标注预览遮挡
                }
                
                // 新增：长图采集过程中的悬浮停止按钮
                // 此时按钮已经在独立的 V2LongScreenshotControlPanel 中显示
                // 这里只需保留空逻辑或移除旧的内置 Toolbar
                if primaryScreenManager.isCapturing {
                    // 空实现，UI 已经由独立窗口承载
                }
                
                // 层级标签汇总 (放在最右下角，纵向排列)
                if !primaryScreenManager.isCapturing {
                    VStack(alignment: .trailing, spacing: 4) {
                        LayerLabel(name: "Layer 5: Debug & Info Layer", color: .green)
                        LayerLabel(name: "Layer 4: Drag/Selection Layer", color: .blue)
                        LayerLabel(name: "Layer 3: Window Interaction", color: .red)
                        LayerLabel(name: "Layer 2: Mask Overlay", color: .black)
                        LayerLabel(name: "Layer 1: Background Layer", color: .gray)
                    }
                    .padding(10)
                }
                
                // 鼠标跟随层级标签
                if currentLayerLevel > 0 && !primaryScreenManager.isCapturing {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Level \(currentLayerLevel)")
                            .font(.system(size: 10, weight: .bold))
                        Text(currentLayerName)
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.8))
                    .foregroundColor(.yellow)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.yellow.opacity(0.5), lineWidth: 1)
                    )
                    .position(
                        x: mouseLocation.x + (mouseLocation.x > screen.frame.width - 150 ? -80 : 60),
                        y: mouseLocation.y + (mouseLocation.y > screen.frame.height - 100 ? -40 : 30)
                    )
                }
                
                // ⚠️ 放大镜预览 (隶属于 Layer 5)
                // 约束规则：
                // 1. 仅在鼠标当前所在的屏幕显示 (isCurrentlyPrimary)
                // 2. 仅在尚未完成选区 (Phase 0) 且 未开始拖拽 时显示
                // 3. 必须监测到鼠标移动过 (hasMouseMoved)
                if isCurrentlyPrimary && !hasAnySelection && dragStartPoint == nil && hasMouseMoved && !primaryScreenManager.isCapturing {
                    MagnifierView(snapshot: snapshot, location: mouseLocation, screen: screen)
                        .position(
                            x: mouseLocation.x + (mouseLocation.x > screen.frame.width - 150 ? -100 : 100),
                            y: mouseLocation.y + (mouseLocation.y > screen.frame.height - 150 ? -100 : 100)
                        )
                }
            }
        }
        .frame(width: screen.frame.width, height: screen.frame.height)
        .background(isReleased ? Color.clear : Color.black)  // 释放时透明，否则黑色
        .onAppear {
            addLog("Debug window appeared on Screen \(screenIndex)")
            // 监听保存通知
            NotificationCenter.default.addObserver(forName: NSNotification.Name("SaveScreenshot"), object: nil, queue: .main) { _ in
                if let selection = localSelectedArea {
                    saveToClipboard(rect: selection)
                }
            }
        }
        .onChange(of: isReleased) { released in
            // 当屏幕被释放时，允许鼠标穿透，这样用户就能感觉到"释放"了
            // 直接从控制器中寻找对应的面板
            if let panel = V2ScreenshotDebugController.debugPanels.first(where: { $0.frame == screen.frame }) {
                panel.ignoresMouseEvents = released
                if released {
                    addLog("Screen \(screenIndex) released - Mouse events ignored")
                } else {
                    panel.ignoresMouseEvents = false
                    addLog("Screen \(screenIndex) reclaimed - Mouse events captured")
                }
            }
        }
        .onExitCommand {
            if hasAnySelection || primaryScreenManager.globalHoveredRect != nil {
                addLog("ESC pressed - Resetting to Phase 0")
                primaryScreenManager.updateSelection(nil, on: nil)
                primaryScreenManager.updateHover(nil, label: nil, on: nil)
            } else {
                addLog("ESC pressed - Closing All Panels")
                V2ScreenshotDebugController.close()
            }
        }
    }

    /// 构建调试层：显示鼠标位置、层级名等
    @ViewBuilder
    private func buildDebugOverlay() -> some View {
        if isReleased {
            EmptyView()
        } else {
            // 1. 屏幕中心提示 (放在底层，且禁止交互)
            Text("SCREEN \(screenIndex)")
                .font(.system(size: 100, weight: .bold))
                .foregroundColor(.white.opacity(0.05))
                .allowsHitTesting(false)
            
            // 2. UI 控制面板
            VStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "display")
                        Text("SCREEN \(screenIndex)")
                            .font(.system(size: 18, weight: .black))
                        
                        Spacer()
                        
                        // 活动状态指示器
                        HStack(spacing: 4) {
                            Circle()
                                .fill(isCurrentlyPrimary ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(isCurrentlyPrimary ? "ACTIVE" : "INACTIVE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(isCurrentlyPrimary ? .green : .gray)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(4)
                    }
                    .foregroundColor(.yellow)
                    
                    Text("Bounds: \(Int(screen.frame.width))x\(Int(screen.frame.height)) at (\(Int(screen.frame.minX)),\(Int(screen.frame.minY)))")
                        .font(.caption)
                    
                    Divider().background(Color.white.opacity(0.3))
                    
                    Text("Recent Logs:")
                        .font(.caption).bold()
                    ForEach(logEntries, id: \.self) { log in
                        Text(log)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                    }
                    
                    // ⚠️ 新增：列出当前屏幕上的所有可选窗口（用于验证过滤逻辑）
                    Divider().background(Color.white.opacity(0.3))
                    Text("Selectable Windows (\(windowsOnScreen.count)):")
                        .font(.caption).bold()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(windowsOnScreen.prefix(5), id: \.id) { win in
                                Text("• \(win.ownerName)")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    .frame(height: 60)
                }
                .padding()
                .frame(width: 280)
                .background(Color.black.opacity(0.8))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.yellow.opacity(0.5), lineWidth: 1)
                )
                .foregroundColor(.white)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(_):
                        // 更新主屏幕状态
                        if !isCurrentlyPrimary {
                            primaryScreenManager.updatePrimaryScreen(screen)
                        }
                        
                        self.currentLayerName = "Debug Info Panel"
                        self.currentLayerLevel = 5
                    case .ended:
                        self.currentLayerLevel = 0
                    }
                }
                
                Spacer()
                
                Button(action: {
                    if primaryScreenManager.isEditing {
                        // ✨ 如果正在编辑文本，先完成编辑
                        primaryScreenManager.finishTextEdit()
                        // 如果在编辑模式，ESC 返回选区模式
                        primaryScreenManager.setEditing(false)
                        addLog("ESC - Back to Selection Mode")
                    } else {
                        // 否则关闭截图
                        V2ScreenshotDebugController.close()
                    }
                }) {
                    Text(primaryScreenManager.isEditing ? "Back (ESC)" : "Close (ESC)")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(primaryScreenManager.isEditing ? .orange : .red)
                .keyboardShortcut(.escape, modifiers: [])
                .onContinuousHover { phase in
                    switch phase {
                    case .active(_):
                        // 更新主屏幕状态
                        if !isCurrentlyPrimary {
                            primaryScreenManager.updatePrimaryScreen(screen)
                        }
                        
                        self.currentLayerName = "Close Button"
                        self.currentLayerLevel = 5
                    case .ended:
                        self.currentLayerLevel = 0
                    }
                }
            }
            .padding(40)
        }
    }

    /// 构建交互层：处理鼠标悬停、点击、拖拽等
    // 计算当前应该显示的唯一吸附线框
    private var snappedWireframeRect: CGRect? {
        // ⚠️ 统一使用全局悬停矩形
        if let rect = primaryScreenManager.globalHoveredRect, primaryScreenManager.hoverScreen == screen {
            // 如果是全屏，则缩一点
            let screenRect = CGRect(origin: .zero, size: screen.frame.size)
            if abs(rect.width - screenRect.width) < 1 && abs(rect.height - screenRect.height) < 1 {
                return rect.insetBy(dx: 2, dy: 2)
            }
            return rect
        }
        return nil
    }

    // 计算元素边界框 (复用逻辑)
    private func elementBoundingRect(_ element: DrawingElement) -> CGRect {
        if element.tool == .magnifier {
            let radius = element.fontSize * 2.5
            let padding: CGFloat = 20
            let baseX: CGFloat
            let baseY: CGFloat
            let bounds: CGRect
            if let selection = localSelectedArea {
                baseX = selection.maxX
                baseY = selection.minY
                bounds = selection
            } else {
                baseX = screenSize.width
                baseY = 0
                bounds = CGRect(origin: .zero, size: screenSize)
            }
            
            let defaultEnd = CGPoint(x: baseX - radius - padding, y: baseY + radius + padding)
            let rawEnd = CGPoint(
                x: defaultEnd.x + element.magnifierOffset.width,
                y: defaultEnd.y + element.magnifierOffset.height
            )
            
            // 应用边界约束
            let minX = bounds.minX + radius
            let maxX = bounds.maxX - radius
            let minY = bounds.minY + radius
            let maxY = bounds.maxY - radius
            
            let end = CGPoint(
                x: max(minX, min(maxX, rawEnd.x)),
                y: max(minY, min(maxY, rawEnd.y))
            )
            
            let circleRect = CGRect(x: end.x - radius, y: end.y - radius, width: radius * 2, height: radius * 2)
            
            // 包含源点小圆圈的热区
            if let start = element.points.first {
                let dotRect = CGRect(x: start.x - 15, y: start.y - 15, width: 30, height: 30) // 增大热区从 20x20 到 30x30
                return circleRect.union(dotRect)
            }
            
            return circleRect
        }
        
        if element.tool == .text {
            let point = element.points.first ?? .zero
            // ✨ 修复：匹配 TextEditor 的实际显示位置
            // TextEditor 使用 .position(x: point.x + 150, y: point.y + 25) (中心点定位)
            // 而 elementBoundingRect 需要返回左上角坐标
            // TextEditor 尺寸是 300x50，所以中心点补偿后左上角是 (point.x, point.y)
            let textEditorWidth: CGFloat = 300
            let textEditorHeight: CGFloat = 50
            // .position(x: point.x + 150, y: point.y + 25) 表示中心在 (point.x + 150, point.y + 25)
            // 所以左上角是 (point.x, point.y)
            // 但我们需要返回整个区域的 CGRect 用于点击检测
            // 考虑到 insetBy(dx: -10, dy: -10) 的热区扩展，我们返回一个稍大的区域
            return CGRect(
                x: point.x,
                y: point.y,
                width: textEditorWidth,
                height: textEditorHeight
            )
        }
        
        let points = element.points
        guard !points.isEmpty else { return .zero }
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        let minX = xs.min()!
        let minY = ys.min()!
        return CGRect(x: minX, y: minY, width: max(2, xs.max()! - minX), height: max(2, ys.max()! - minY))
    }

    @ViewBuilder
    private func buildInteractionLayer() -> some View {
        ZStack {
            // ⚠️ 统一监听层：整个屏幕都是热区
            Color.white.opacity(0.0001)
                .contentShape(InvertedRectangle(hole: primaryScreenManager.isLongScreenshotMode ? localSelectedArea : nil), eoFill: true)
                .onContinuousHover { phase in
                    // ✨ 修复：如果鼠标在 UI 上，则完全不处理 InteractionLayer 的悬停逻辑
                    // 这样可以确保：
                    // 1. 放大镜不会在 UI 悬停时显示（因为 mouseLocation 不会更新到 UI 位置）
                    // 2. 窗口吸附线框（Wireframe）不会在 UI 悬停时显示
                    // 3. updateHoverState 不会被触发，防止干扰 UI 交互
                    if primaryScreenManager.isMouseOverUI {
                        return
                    }

                    // ✨ 编辑文本时只更新位置，不处理放大镜等其他逻辑
                    if primaryScreenManager.editingTextId != nil {
                        switch phase {
                        case .active(let location):
                            mouseLocation = location
                        default:
                            break
                        }
                        return
                    }

                    if isReleased { return }
                    
                    switch phase {
                    case .active(let location):
                        // 1. 记录已移动，允许显示放大镜
                        if !hasMouseMoved {
                            hasMouseMoved = true
                        }

                        // 2. 更新主屏幕状态
                        if !isCurrentlyPrimary {
                            primaryScreenManager.updatePrimaryScreen(screen)
                        }

                        // 3. 更新鼠标位置
                        self.mouseLocation = location

                        // 4. ✨ 更新放大镜预览位置（如果选中了放大镜工具且在编辑模式）
                        if primaryScreenManager.isEditing && primaryScreenManager.selectedTool == .magnifier {
                            if let selection = localSelectedArea, selection.contains(location) {
                                primaryScreenManager.magnifierPreviewPosition = location
                            } else {
                                primaryScreenManager.magnifierPreviewPosition = nil
                            }
                        } else {
                            primaryScreenManager.magnifierPreviewPosition = nil
                        }

                        // 5. 更新光标
                        updateCursor(at: location)

                        // 6. 核心逻辑：动态寻找最顶层窗口并更新全局状态
                        updateHoverState(at: location)

                        // 7. 更新调试层级
                        self.currentLayerName = "Interaction Area (Layer 3)"
                        self.currentLayerLevel = 3

                    case .ended:
                        primaryScreenManager.updateHover(nil, label: nil, on: nil)
                        self.currentLayerLevel = 0
                        NSCursor.arrow.set()
                    }
                }
                // ⚠️ onTapGesture 已移除，点击逻辑统一到 DragGesture.onEnded 中处理
                // 原因：onTapGesture 无法获取准确的点击位置，导致第一次点击无效
        }
        .allowsHitTesting(true)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // ✨ 修复：确保当前屏幕是主屏幕（防止第一次拖拽无效）
                            if !isCurrentlyPrimary {
                                primaryScreenManager.updatePrimaryScreen(screen)
                            }

                            // ✨ 修复：立即更新 mouseLocation，确保 onTapGesture 能获取正确位置
                            self.mouseLocation = value.startLocation

                            // ✨ 修复：主动更新 hover 状态，确保 hoverScreen 正确
                            updateHoverState(at: value.startLocation)

                            // ✨ 关键修复：如果正在编辑文本
                            if primaryScreenManager.editingTextId != nil {
                                // 检查点击位置是否在选区外
                                if let selection = localSelectedArea, !selection.contains(value.startLocation) {
                                    // 点击选区外，完成编辑
                                    primaryScreenManager.finishTextEdit()
                                    // 不 return，继续处理事件
                                } else {
                                    // 点击选区内或没有选区，不处理让 TextField 接收
                                    return
                                }
                            }

                            // ✨ 修复：如果鼠标在 UI 上开始拖拽，不处理 InteractionLayer 的拖拽逻辑
                            if primaryScreenManager.isMouseOverUI && !isDraggingElement && !isMovingSelection && activeHandle == nil {
                                return
                            }

                            if isReleased { return }

                    // 阶段 2: 编辑模式下的交互
                    if primaryScreenManager.isEditing, let selection = localSelectedArea {
                        // 2.1 ✨ 选择工具的移动逻辑
                        if primaryScreenManager.selectedTool == .cursor {
                            if !isDraggingElement {
                                // 检查是否点中了已选中的元素（或点中一个新元素）
                                if let selectedId = primaryScreenManager.selectedElementId,
                                   let element = primaryScreenManager.elements.first(where: { $0.id == selectedId }) {
                                    
                                    if element.tool == .magnifier {
                                        // 1. 优先检查是否点中视觉源点 (小圆圈)
                                        let start = element.points.first!
                                        let dotRect = CGRect(x: start.x - 15, y: start.y - 15, width: 30, height: 30) // 增大热区
                                        if dotRect.contains(value.startLocation) {
                                            isDraggingElement = true
                                            magnifierDragTarget = .sourceDot
                                            initialElementPoints = element.points
                                            addLog("Dragging Magnifier Source Dot")
                                        } else {
                                            // 2. 检查是否点中放大镜圆圈
                                            let circleRect = elementBoundingRect(element).insetBy(dx: -5, dy: -5)
                                            if circleRect.contains(value.startLocation) {
                                                isDraggingElement = true
                                                magnifierDragTarget = .circle
                                                initialMagnifierOffset = element.magnifierOffset
                                                addLog("Dragging Magnifier Circle")
                                            }
                                        }
                                    } else {
                                        let rect = elementBoundingRect(element).insetBy(dx: -10, dy: -10)
                                        if rect.contains(value.startLocation) {
                                            isDraggingElement = true
                                            initialElementPoints = element.points
                                            initialMagnifierOffset = element.magnifierOffset
                                            addLog("Dragging Element: \(element.tool)")
                                        }
                                    }
                                }
                            }
                            
                            if isDraggingElement, let selectedId = primaryScreenManager.selectedElementId {
                                let dx = value.translation.width
                                let dy = value.translation.height
                                
                                if let index = primaryScreenManager.elements.firstIndex(where: { $0.id == selectedId }) {
                                    let element = primaryScreenManager.elements[index]
                                    if element.tool == .magnifier {
                                        if magnifierDragTarget == .circle {
                                            // 放大镜移动显示位置偏移
                                            let rawOffset = CGSize(
                                                width: initialMagnifierOffset.width + dx,
                                                height: initialMagnifierOffset.height + dy
                                            )
                                            
                                            // 限制偏移量，使放大镜保持在选区内
                                            let radius = element.fontSize * 2.5
                                            let padding: CGFloat = 20
                                            let baseX = selection.maxX
                                            let baseY = selection.minY
                                            
                                            let minX = selection.minX + radius
                                            let maxX = selection.maxX - radius
                                            let minY = selection.minY + radius
                                            let maxY = selection.maxY - radius
                                            
                                            let defaultEndX = baseX - radius - padding
                                            let defaultEndY = baseY + radius + padding
                                            
                                            // 目标中心点
                                            let targetX = defaultEndX + rawOffset.width
                                            let targetY = defaultEndY + rawOffset.height
                                            
                                            // 限制后的中心点
                                            let constrainedX = max(minX, min(maxX, targetX))
                                            let constrainedY = max(minY, min(maxY, targetY))
                                            
                                            // 转换回 offset
                                            primaryScreenManager.elements[index].magnifierOffset = CGSize(
                                                width: constrainedX - defaultEndX,
                                                height: constrainedY - defaultEndY
                                            )
                                        } else if magnifierDragTarget == .sourceDot {
                                            // 移动视觉源点，且限制在选区/画布内
                                            let bounds = selection
                                            let newX = max(bounds.minX, min(bounds.maxX, initialElementPoints[0].x + dx))
                                            let newY = max(bounds.minY, min(bounds.maxY, initialElementPoints[0].y + dy))
                                            primaryScreenManager.elements[index].points = [CGPoint(x: newX, y: newY)]
                                        }
                                    } else {
                                        // 其他工具整体移动，保持形状且限制在选区内
                                        let xs = initialElementPoints.map { $0.x }
                                        let ys = initialElementPoints.map { $0.y }
                                        let minX = xs.min() ?? 0
                                        let maxX = xs.max() ?? 0
                                        let minY = ys.min() ?? 0
                                        let maxY = ys.max() ?? 0
                                        
                                        let allowedMinDx = selection.minX - minX
                                        let allowedMaxDx = selection.maxX - maxX
                                        let allowedMinDy = selection.minY - minY
                                        let allowedMaxDy = selection.maxY - maxY
                                        
                                        let constrainedDx = max(allowedMinDx, min(allowedMaxDx, dx))
                                        let constrainedDy = max(allowedMinDy, min(allowedMaxDy, dy))
                                        
                                        primaryScreenManager.elements[index].points = initialElementPoints.map { pt in
                                            CGPoint(x: pt.x + constrainedDx, y: pt.y + constrainedDy)
                                        }
                                    }
                                }
                            }
                            return
                        }

                        // 2.2 ✨ 绘图工具的创建逻辑
                        // ⚠️ .cursor 工具用于选择元素，不应创建新元素
                        guard primaryScreenManager.selectedTool != .cursor else { return }

                        // ✨ 关键修复：只允许在选区内绘制，且排除点击触发型工具（放大镜、文本）
                        if selection.contains(value.location) {
                            if primaryScreenManager.currentElement == nil {
                                // 排除通过点击创建的工具，避免重复创建
                                guard primaryScreenManager.selectedTool != .magnifier && 
                                      primaryScreenManager.selectedTool != .text else { return }
                                
                                primaryScreenManager.currentElement = DrawingElement(
                                    tool: primaryScreenManager.selectedTool,
                                    points: [value.location],
                                    color: primaryScreenManager.selectedColor,
                                    lineWidth: primaryScreenManager.lineWidth,
                                    fontSize: primaryScreenManager.fontSize,
                                    stepNumber: primaryScreenManager.stepCounter
                                )
                            } else {
                                // ✨ 只添加选区内的点
                                if selection.contains(value.location) {
                                    primaryScreenManager.currentElement?.points.append(value.location)
                                }
                            }
                        }
                        return
                    }
                    
                    // 阶段 1: 选区已经存在
                    if let currentSelection = localSelectedArea {
                        // ⚠️ 编辑模式或长图模式下禁止调整选区位置和大小
                        if primaryScreenManager.isEditing || primaryScreenManager.isLongScreenshotMode {
                            return
                        }
                        
                        // 如果还没开始移动/调整，检查起始点
                        if !isMovingSelection && activeHandle == nil {
                            if let handle = getHandle(at: value.startLocation, in: currentSelection) {
                                activeHandle = handle
                                initialSelectionForMove = currentSelection
                                addLog("Resizing Selection Started: \(handle)")
                            } else if currentSelection.contains(value.startLocation) {
                                isMovingSelection = true
                                initialSelectionForMove = currentSelection
                                addLog("Moving Selection Started")
                            } else {
                                // 点击外部，开始新的框选
                                dragStartPoint = value.startLocation
                                primaryScreenManager.updateSelection(nil, on: nil)
                                return
                            }
                        }
                        
                        // 执行调整大小
                        if let handle = activeHandle, let initial = initialSelectionForMove {
                            let deltaX = value.translation.width
                            let deltaY = value.translation.height
                            let newRect = applyResize(to: initial, handle: handle, dx: deltaX, dy: deltaY)
                            primaryScreenManager.updateSelection(newRect, on: screen)
                        } 
                        // 执行移动
                        else if isMovingSelection, let initial = initialSelectionForMove {
                            let deltaX = value.translation.width
                            let deltaY = value.translation.height
                            
                            var newRect = initial
                            newRect.origin.x += deltaX
                            newRect.origin.y += deltaY
                            
                            // 限制在屏幕内
                            newRect.origin.x = max(0, min(newRect.origin.x, screenSize.width - newRect.width))
                            newRect.origin.y = max(0, min(newRect.origin.y, screenSize.height - newRect.height))
                            
                            primaryScreenManager.updateSelection(newRect, on: screen)
                        }
                    } else {
                        // 阶段 0: 还没有选区，执行正常框选
                        if dragStartPoint == nil {
                            dragStartPoint = value.startLocation
                            addLog("Drag Started at: \(Int(value.startLocation.x)),\(Int(value.startLocation.y))")
                        }
                        dragCurrentPoint = value.location
                        
                        // 宽选时隐藏吸附框
                        primaryScreenManager.updateHover(nil, label: nil, on: nil)
                    }
                }
                .onEnded { value in
                    // ✨ 计算移动距离，判断是点击还是拖拽
                    let dragDistance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                    let isClick = dragStartPoint == nil && dragDistance < 5

                    // ✨ 如果是点击，处理点击逻辑
                    if isClick {
                        let clickLocation = value.startLocation

                        // 0. ✨ 选择工具的点选逻辑
                        if primaryScreenManager.isEditing && primaryScreenManager.selectedTool == .cursor {
                            // 寻找点击位置下的最顶层元素
                            if let hitElement = primaryScreenManager.elements.reversed().first(where: { element in
                                let rect = elementBoundingRect(element).insetBy(dx: -10, dy: -10)
                                return rect.contains(clickLocation)
                            }) {
                                if hitElement.tool == .text && primaryScreenManager.selectedElementId == hitElement.id {
                                    primaryScreenManager.editingTextId = hitElement.id
                                    addLog("Text Editing Started")
                                    return
                                }
                                primaryScreenManager.selectedElementId = hitElement.id
                                addLog("Element Selected: \(hitElement.tool)")
                            } else {
                                if primaryScreenManager.editingTextId != nil {
                                    primaryScreenManager.finishTextEdit()
                                }
                                primaryScreenManager.selectedElementId = nil
                            }
                            return
                        }

                        // 1. ✨ 放大镜工具的点击固定逻辑
                        if primaryScreenManager.isEditing && primaryScreenManager.selectedTool == .magnifier {
                            if let selection = localSelectedArea, selection.contains(clickLocation) {
                                let magnifierElement = DrawingElement(
                                    tool: .magnifier,
                                    points: [clickLocation],
                                    color: .white,
                                    lineWidth: primaryScreenManager.lineWidth,
                                    fontSize: primaryScreenManager.fontSize,
                                    magnifierSourcePoint: clickLocation
                                )
                                primaryScreenManager.addElement(magnifierElement)
                                primaryScreenManager.selectedElementId = magnifierElement.id
                                primaryScreenManager.updateTool(.cursor)
                                addLog("Magnifier Placed")
                                return
                            }
                        }

                        // 2. ✨ 文本工具的点击逻辑
                        if primaryScreenManager.isEditing && primaryScreenManager.selectedTool == .text {
                            if let selection = localSelectedArea, selection.contains(clickLocation) {
                                let textElement = DrawingElement(
                                    tool: .text,
                                    points: [clickLocation],
                                    color: primaryScreenManager.selectedColor,
                                    lineWidth: primaryScreenManager.lineWidth,
                                    text: "",
                                    fontSize: primaryScreenManager.fontSize
                                )
                                primaryScreenManager.addElement(textElement)
                                primaryScreenManager.editingTextId = textElement.id
                                addLog("Text Tool Clicked")
                                return
                            }
                        }

                        // 3. ✨ 如果有吸附的窗口，点击即选中
                        if !primaryScreenManager.isEditing,
                           let rect = primaryScreenManager.globalHoveredRect,
                           primaryScreenManager.hoverScreen == screen {
                            primaryScreenManager.updateSelection(rect, on: screen)
                            addLog("Area Selected via Tap")
                            return
                        }

                        // 4. ✨ 如果点击了选区外
                        if let selection = localSelectedArea, !selection.contains(clickLocation) {
                            if !primaryScreenManager.isEditing {
                                primaryScreenManager.updateSelection(nil, on: nil)
                                primaryScreenManager.setEditing(false)
                                addLog("Selection Cleared")
                            }
                            return
                        }

                        // 点击处理完成，直接返回
                        return
                    }

                    // 以下是拖拽逻辑
                    // 阶段 2: 结束绘图或移动
                    if primaryScreenManager.isEditing {
                        if isDraggingElement {
                            isDraggingElement = false
                            initialElementPoints = []
                            initialMagnifierOffset = .zero
                            magnifierDragTarget = nil
                            addLog("Element Dragging Ended")
                            return
                        }

                        if let element = primaryScreenManager.currentElement {
                            primaryScreenManager.addElement(element)
                            primaryScreenManager.currentElement = nil
                        }
                        return
                    }

                    if isMovingSelection || activeHandle != nil {
                        isMovingSelection = false
                        activeHandle = nil
                        initialSelectionForMove = nil
                        addLog("Selection Modification Ended")
                        return
                    }

                    if let start = dragStartPoint {
                        let end = value.location
                        let rect = CGRect(
                            x: min(start.x, end.x),
                            y: min(start.y, end.y),
                            width: abs(end.x - start.x),
                            height: abs(end.y - start.y)
                        )
                        if rect.width > 5 && rect.height > 5 {
                            primaryScreenManager.updateSelection(rect, on: screen)
                            addLog("Area Selected: \(Int(rect.width))x\(Int(rect.height))")
                        }
                    }
                    dragStartPoint = nil
                    dragCurrentPoint = nil

                    // 恢复悬停检测
                    updateHoverState(at: value.location)
                }
        )
    }
    
    // 更新光标状态
    private func updateCursor(at location: CGPoint) {
        if primaryScreenManager.isEditing {
            // 编辑模式下
            if let selection = localSelectedArea, selection.contains(location) {
                if primaryScreenManager.selectedTool == .cursor {
                    // 选择工具使用普通箭头
                    NSCursor.arrow.set()
                } else {
                    // 绘图工具在选区内使用十字准星
                    NSCursor.crosshair.set()
                }
            } else {
                NSCursor.arrow.set()
            }
            return
        }
        
        if let selection = localSelectedArea {
            if let handle = getHandle(at: location, in: selection) {
                switch handle {
                case .topLeft, .bottomRight: 
                    // 尝试使用系统提供的对角线缩放光标
                    NSCursor.crosshair.set() // 暂时用十字，因为没有公开的对角线
                case .topRight, .bottomLeft: 
                    NSCursor.crosshair.set()
                case .top, .bottom: 
                    NSCursor.resizeUpDown.set()
                case .left, .right: 
                    NSCursor.resizeLeftRight.set()
                }
            } else if selection.contains(location) {
                // 四向箭头光标 (使用 openHand 模拟，代表可抓取移动)
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }
        } else {
            NSCursor.crosshair.set()
        }
    }
    
    /// 构建蒙层层：用于实现挖孔效果
    @ViewBuilder
    private func buildMaskOverlay() -> some View {
        if isReleased {
            EmptyView()
        } else {
            // ⚠️ 核心逻辑：动态计算当前需要“变亮”的区域（挖孔）
            let holeRect: CGRect? = {
                // 1. 如果正在拖拽，挖拖拽的孔
                if let start = dragStartPoint, let current = dragCurrentPoint {
                    return CGRect(
                        x: min(start.x, current.x),
                        y: min(start.y, current.y),
                        width: abs(start.x - current.x),
                        height: abs(start.y - current.y)
                    )
                }
                // 2. 如果已经有确定的选区，挖选区的孔
                if let rect = localSelectedArea {
                    return rect
                }
                // 3. 如果有吸附的窗口，挖窗口的孔
                // ⚠️ 统一使用全局悬停状态
                if let rect = primaryScreenManager.globalHoveredRect, 
                   primaryScreenManager.hoverScreen == screen {
                    return rect
                }
                return nil
            }()
            
            ZStack(alignment: .topLeading) {
                // 活动屏幕稍微暗一点 (0.2)，非活动屏幕中等暗 (0.5)
                // 默认初始状态为 0.3，直到鼠标移动确定主屏幕
                let opacity = isCurrentlyPrimary ? 0.2 : (primaryScreenManager.primaryScreen == nil ? 0.3 : 0.5)
                
                Color.black.opacity(opacity)
                    .animation(.easeInOut(duration: 0.2), value: opacity)
                    .compositingGroup()
                    .mask {
                        Rectangle()
                            .overlay(alignment: .topLeading) {
                                // 执行挖孔
                                if let rect = holeRect {
                                    Rectangle()
                                        .frame(width: rect.width, height: rect.height)
                                        .offset(x: rect.minX, y: rect.minY)
                                        .blendMode(.destinationOut)
                                        .animation(.easeOut(duration: 0.15), value: rect) // 挖孔跟随动画
                                }
                            }
                    }
                    .onContinuousHover { phase in
                        if isReleased { return }
                        if case .active(_) = phase {
                            if !hasAnySelection {
                                self.currentLayerName = "Mask Overlay (Layer 2)"
                                self.currentLayerLevel = 2
                            }
                        }
                    }
            }
            .allowsHitTesting(false)
        }
    }
    
    /// 构建标注层：使用完整的标注系统
    @ViewBuilder
    private func buildAnnotationLayer() -> some View {
        if primaryScreenManager.isEditing {
            // 使用新的完整标注系统
            V2AnnotationCanvas(
                stateManager: primaryScreenManager,
                canvasSize: screenSize,
                baseImage: snapshot
            )
            .zIndex(20)

            // ✨ 放大镜预览（标注层的一部分）
            if let previewPos = primaryScreenManager.magnifierPreviewPosition,
               isCurrentlyPrimary,
               let selection = localSelectedArea {  // ✨ 需要选区信息来计算正确位置
                AnnotationMagnifierPreview(
                    snapshot: snapshot,
                    position: previewPos,
                    canvasSize: screenSize,
                    followMouse: primaryScreenManager.magnifierFollowMouse,
                    selectionArea: selection  // ✨ 传递选区信息
                )
                .zIndex(25)
                .allowsHitTesting(false)  // ✨ 关键：不拦截事件，让 Layer 3 能够正常监听
            }

            // ✨ 文本编辑：使用 TextEditor 在 ZStack 中直接渲染
            if let editingId = primaryScreenManager.editingTextId,
               let index = primaryScreenManager.elements.firstIndex(where: { $0.id == editingId }) {
                let element = primaryScreenManager.elements[index]
                let position = element.points.first ?? .zero

                TextEditor(text: Binding(
                    get: { primaryScreenManager.elements[index].text },
                    set: { primaryScreenManager.elements[index].text = $0 }
                ))
                .font(.system(size: element.fontSize, weight: .bold))
                .foregroundColor(element.color)
                .scrollContentBackground(.hidden)
                .background(Color.clear)  // ✨ 透明背景
                .cornerRadius(4)
                .focused($isTextEditingFocused)
                .frame(width: 300, height: 50)  // ✨ 固定尺寸
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            element.color,
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])  // ✨ 虚线边框
                        )
                )
                .position(x: position.x + 150, y: position.y + 25)  // ✨ 中心点定位，补偿尺寸
                .onAppear {
                    print("[V2ScreenshotDebugView] TextEditor appeared, setting focus")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isTextEditingFocused = true
                    }
                }
            }
        }
    }
    
    /// 构建框选层：显示正在拖拽的区域
    @ViewBuilder
    private func buildDragOverlay() -> some View {
        if isReleased {
            EmptyView()
        } else {
            ZStack(alignment: .topLeading) {
                if let start = dragStartPoint, let current = dragCurrentPoint {
                    let rect = CGRect(
                        x: min(start.x, current.x),
                        y: min(start.y, current.y),
                        width: abs(start.x - current.x),
                        height: abs(start.y - current.y)
                    )
                    
                    // ⚠️ 只有当宽度或高度超过 3 像素时才显示框选，过滤点击时的闪烁
                    if rect.width > 3 || rect.height > 3 {
                        YellowWireframe(rect: rect, label: "\(Int(rect.width)) x \(Int(rect.height))", isDashed: true, showBackground: true, isEditing: primaryScreenManager.isEditing, isLongScreenshotMode: primaryScreenManager.isLongScreenshotMode)
                    }
                } else if let rect = localSelectedArea {
                    YellowWireframe(rect: rect, label: "\(Int(rect.width)) x \(Int(rect.height))", isDashed: true, showBackground: false, isEditing: primaryScreenManager.isEditing, isLongScreenshotMode: primaryScreenManager.isLongScreenshotMode, showHandles: true)
                    .onContinuousHover { phase in
                        if case .active(_) = phase {
                            self.currentLayerName = "Selection (Layer 4)"
                            self.currentLayerLevel = 4
                        }
                    }
                } else if let rect = snappedWireframeRect {
                    // ⚠️ 使用全局标签
                    YellowWireframe(rect: rect, label: primaryScreenManager.globalHoveredLabel, isDashed: true, showBackground: true, isEditing: primaryScreenManager.isEditing, isLongScreenshotMode: primaryScreenManager.isLongScreenshotMode, opacity: 0.8)
                        .animation(.easeOut(duration: 0.15), value: rect)
                }
            }
            .allowsHitTesting(false)
        }
    }
}
