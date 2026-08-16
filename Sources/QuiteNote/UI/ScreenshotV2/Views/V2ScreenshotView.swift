import SwiftUI
import AppKit
import os.log

private let v2Logger = Logger(subsystem: "com.quitenote.app", category: "ScreenshotV2")

/// V2 截图视图
/// 支持屏幕选择、窗口高亮、选区调整和标注编辑。
struct V2ScreenshotView: View {
    let screen: NSScreen
    let snapshot: NSImage
    let screenIndex: Int
    let allWindows: [WindowInfo] // 接收真实的窗口列表
    let sessionID: UUID  // ✨ 唯一会话ID，防止旧监听器响应

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

    /// 通知监听器 token（onDisappear 时移除，防止闭包持有整屏截图大图导致内存泄漏）
    @State private var notificationObservers: [NSObjectProtocol] = []

    /// 订阅主屏幕状态变化
    @StateObject private var primaryScreenManager = V2PrimaryScreenStateManager.shared

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
        let isSameScreen = primaryScreenManager.selectionScreen == screen
        let result = isSameScreen ? primaryScreenManager.selectedArea : nil

        // 🔍 调试日志
        if primaryScreenManager.selectedArea != nil {
            print("🔍 [localSelectedArea] screen\(screenIndex)")
            print("   selectionScreen: \(String(describing: primaryScreenManager.selectionScreen?.localizedName))")
            print("   current screen: \(screen.localizedName)")
            print("   isSameScreen: \(isSameScreen)")
            print("   selectedArea: \(String(describing: primaryScreenManager.selectedArea))")
            print("   result: \(String(describing: result))")
        }

        return result
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
        V2ScreenshotView.onLog = { self.addLog($0) }
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
        // ✨ 核心修复：如果已经有选区，不再执行窗口吸附检测
        if hasAnySelection {
            if primaryScreenManager.globalHoveredRect != nil {
                primaryScreenManager.updateHover(nil, label: nil, on: nil)
            }
            return
        }

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

    // 生成最终高清图片（合并底图和标注）
    private func generateFinalImage(rect: CGRect) -> NSImage? {
        guard rect.width > 0 && rect.height > 0 else { return nil }

        // 🔍 调试日志
        print("🔍 [generateFinalImage] screen\(screenIndex)")
        print("   rect (input): \(rect)")
        print("   screen: \(screen.localizedName)")
        print("   screen.frame: \(screen.frame)")
        print("   snapshot.size: \(snapshot.size)")

        // 1. 获取底层的 CGImage 和 真实的缩放倍率
        // ⚠️ 不直接使用 screen.backingScaleFactor，因为系统设置可能导致差异
        guard let fullCGImage = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            addLog("Error: Failed to get CGImage from snapshot")
            return nil
        }
        
        let pixelWidth = CGFloat(fullCGImage.width)
        let pixelHeight = CGFloat(fullCGImage.height)
        let scaleX = pixelWidth / snapshot.size.width
        let scaleY = pixelHeight / snapshot.size.height
        
        addLog("Debug: Snapshot size: \(snapshot.size), Pixel size: \(pixelWidth)x\(pixelHeight), Scale: \(scaleX)x\(scaleY)")
        
        // 2. 计算像素裁剪区域 (CGImage 裁剪坐标系是 Top-Left)
        // ⚠️ 关键：使用整数像素坐标避免偏移，且移除之前的 Y 轴翻转，因为 CGDisplayCreateImage 出来的就是 Top-Left
        let pixelRect = CGRect(
            x: (rect.origin.x * scaleX).rounded(),
            y: (rect.origin.y * scaleY).rounded(),
            width: (rect.width * scaleX).rounded(),
            height: (rect.height * scaleY).rounded()
        )
        
        addLog("Debug: Rect in points: \(rect), Rect in pixels: \(pixelRect)")
        
        guard let croppedCGImage = fullCGImage.cropping(to: pixelRect) else {
            addLog("Error: CGImage cropping failed")
            return nil
        }
        
        // 3. 创建结果 NSImage
        let finalImage = NSImage(cgImage: croppedCGImage, size: rect.size)
        
        // 4. ✨ 叠加标注系统
        if !primaryScreenManager.elements.isEmpty {
            // 获取全屏标注图层
            let exportCanvas = V2AnnotationCanvas(
                stateManager: primaryScreenManager,
                canvasSize: screenSize,
                baseImage: snapshot,
                isExporting: true
            )
            .frame(width: screenSize.width, height: screenSize.height)

            let renderer = ImageRenderer(content: exportCanvas)
            // 标注图层的渲染必须匹配屏幕缩放
            renderer.scale = screen.backingScaleFactor
            
            if let annotationImage = renderer.nsImage {
                // ✨ 核心修复：创建一个具有正确比例的图片，并确保绘制时坐标系正确
                let resultWithAnnotations = NSImage(size: rect.size)
                
                // 确保结果图片也有正确的 representations，以便在 Retina 屏幕上清晰
                let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: Int(pixelRect.width),
                    pixelsHigh: Int(pixelRect.height),
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0
                )
                if let rep = rep {
                    resultWithAnnotations.addRepresentation(rep)
                }
                
                resultWithAnnotations.lockFocus()
                
                // 1. 先画底图
                finalImage.draw(in: CGRect(origin: .zero, size: rect.size))
                
                // 2. 再画标注
                // 💡 关键：NSImage.draw(in:from:...) 的 fromRect 是相对于图片自身的坐标系（AppKit 默认左下角）
                // 而 ImageRenderer 生成的 NSImage 是 Top-Down 的。
                // 我们需要将 Top-Left 的 rect 转换为 Bottom-Left 的 sourceRect
                let annSourceRect = CGRect(
                    x: rect.origin.x,
                    y: annotationImage.size.height - rect.origin.y - rect.height,
                    width: rect.width,
                    height: rect.height
                )
                
                annotationImage.draw(in: CGRect(origin: .zero, size: rect.size),
                                   from: annSourceRect,
                                   operation: .sourceOver,
                                   fraction: 1.0)
                
                resultWithAnnotations.unlockFocus()
                return resultWithAnnotations
            }
        }
        
        return finalImage
    }

    // 保存到剪贴板
    private func saveToClipboard(rect: CGRect) {
        addLog("Saving selection to clipboard...")
        
        guard let finalImage = generateFinalImage(rect: rect) else { return }

        // 写入剪贴板
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([finalImage])
        
        addLog("Saved to clipboard! Closing...")
        
        // 关闭所有调试窗口
        V2ScreenshotController.close()
    }

    // OCR 文字识别（不关闭截图会话，识别完可继续标注）
    private func runOCR(rect: CGRect) {
        guard let finalImage = generateFinalImage(rect: rect) else { return }

        primaryScreenManager.postToast("文字识别中…", type: "info")
        DiagnosticCenter.info("OCR", "开始识别，选区 \(Int(rect.width))x\(Int(rect.height))")

        V2OCRService.shared.recognizeText(in: finalImage) { text in
            guard let text, !text.isEmpty else {
                V2PrimaryScreenStateManager.shared.postToast("未识别到文字", type: "error")
                DiagnosticCenter.warning("OCR", "未识别到文字")
                return
            }
            DiagnosticCenter.info("OCR", "识别完成，\(text.count) 字符")
            V2OCRResultPanelController.shared.show(text: text)
        }
    }

    // 保存到闪记（同时导出文件到默认目录并复制路径）
    private func saveToFlashNotes(rect: CGRect) {
        addLog("Saving selection to flash notes...")

        guard let finalImage = generateFinalImage(rect: rect) else { return }

        // 保存链路：导出 PNG 到默认目录 → 复制绝对路径到剪贴板 → 存入闪记
        ScreenshotService.shared.saveScreenshotWithFile(image: finalImage)

        addLog("Saved! Closing...")

        // 关闭所有调试窗口
        V2ScreenshotController.close()
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
                    V2MaskOverlayView(
                        isReleased: isReleased,
                        screenSize: screenSize,
                        dragStartPoint: dragStartPoint,
                        dragCurrentPoint: dragCurrentPoint,
                        localSelectedArea: localSelectedArea,
                        snappedRect: snappedWireframeRect,
                        isCurrentlyPrimary: isCurrentlyPrimary,
                        hasPrimaryScreen: primaryScreenManager.primaryScreen != nil
                    )
                }
                
                // 3. 交互层：处理悬停和点击
                buildInteractionLayer()
                    .allowsHitTesting(true) // ✨ 修复：始终允许点击，通过 contentShape 的 hole 穿透
                    .onChange(of: primaryScreenManager.isLongScreenshotMode) { isLongMode in
                        // 长图模式下，如果是当前屏幕有选区，则需要根据选区动态设置是否忽略鼠标事件
                        if let panel = V2ScreenshotController.screenPanelMap[screen] {
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
                    .zIndex(50)  // ⚠️ 关键修复：提升层级确保线框始终可见（在标注层之上）
                
                // 4.5. 标注层：显示绘图内容 (长图模式下隐藏标注)
                if !primaryScreenManager.isLongScreenshotMode {
                    buildAnnotationLayer()
                        .zIndex(60) // ⚠️ 确保在交互层之上，但低于工具栏
                }

                // 新增：截图工具栏 (仅在有选区时显示)
                if let selection = localSelectedArea, !primaryScreenManager.isLongScreenshotMode {
                    if !primaryScreenManager.isCapturing {
                        // 普通截图模式：显示标注工具栏
                        V2FloatingToolbar(selection: selection, screen: screen)
                            .zIndex(1000) // ⚠️ 最顶层：工具栏始终可点击
                            .allowsHitTesting(true) // ⚠️ 关键：显式启用工具栏事件接收
                    }
                }
                
                // ✨ 新增：Toast 提示层
                if let message = primaryScreenManager.toastMessage {
                    Text(message)
                        .font(.themeCaption)
                        .foregroundColor(.themeTextPrimary)
                        .padding(.horizontal, ThemeSpacing.px4.rawValue)
                        .padding(.vertical, ThemeSpacing.px2.rawValue)
                        .background(
                            RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                                .fill(primaryScreenManager.toastType == "error" ? Color.themeStatusError : Color.themePanel)
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .position(x: screenSize.width / 2, y: 100)
                        .zIndex(2000)
                        .animation(.easeOut(duration: ThemeDuration._300.rawValue), value: message)
                }

                // 新增：长图采集过程中的悬浮停止按钮
                // 此时按钮已经在独立的 V2LongScreenshotControlPanel 中显示
                // 这里只需保留空逻辑或移除旧的内置 Toolbar
                if primaryScreenManager.isCapturing {
                    // 空实现，UI 已经由独立窗口承载
                }

                // ⚠️ 放大镜预览 (隶属于 Layer 5)
                // 约束规则：
                // 1. 仅在鼠标当前所在的屏幕显示 (isCurrentlyPrimary)
                // 2. 仅在尚未完成选区 (Phase 0) 且 未开始拖拽 时显示
                // 3. 必须监测到鼠标移动过 (hasMouseMoved)
                if isCurrentlyPrimary && !hasAnySelection && dragStartPoint == nil && hasMouseMoved && !primaryScreenManager.isCapturing {
                    MagnifierView(
                        snapshot: snapshot,
                        location: mouseLocation,
                        screen: screen,
                        color: primaryScreenManager.selectedColor // 传递当前标注系统的颜色
                    )
                    .position(
                        x: mouseLocation.x + (mouseLocation.x > screen.frame.width - 150 ? -100 : 100),
                        y: mouseLocation.y + (mouseLocation.y > screen.frame.height - 150 ? -100 : 100)
                    )
                }
            }
        }
        .frame(width: screen.frame.width, height: screen.frame.height)
        .background(isReleased ? Color.clear : Color.black)  // 释放时透明，否则黑色
        // ✨ 新增：处理滚轮事件，用于调节放大倍率
        .onScrollWheel { event in
            guard primaryScreenManager.isEditing else { return }
            
            // 1. 如果选中了放大镜工具（正在预览）
            if primaryScreenManager.selectedTool == .magnifier {
                let delta = -event.scrollingDeltaY * 0.05
                let newScale = max(1.0, min(5.0, primaryScreenManager.magnifierScale + delta))
                primaryScreenManager.magnifierScale = newScale
                return
            }
            
            // 2. 如果当前选中了一个已有的放大镜元素
            if let id = primaryScreenManager.selectedElementId,
               let index = primaryScreenManager.elements.firstIndex(where: { $0.id == id }),
               primaryScreenManager.elements[index].tool == .magnifier {
                let delta = -event.scrollingDeltaY * 0.05
                let newScale = max(1.0, min(5.0, primaryScreenManager.elements[index].magnifierScale + delta))
                primaryScreenManager.elements[index].magnifierScale = newScale
                primaryScreenManager.objectWillChange.send()
            }
        }
        .onAppear {
            addLog("Debug window appeared on Screen \(screenIndex)")

            // ✨ 修复：延迟激活 Panel，确保成为 key window
            // 解决"第一次点击无效"的问题（NSPanel 激活是异步的）
            DispatchQueue.main.async {
                if let panel = V2ScreenshotController.debugPanels.first(where: { $0.frame == screen.frame }) {
                    panel.becomeKey()
                    addLog("Panel became key on Screen \(screenIndex)")
                }
            }

            // ✨ 关键修复：使用 sessionID 防止旧监听器响应
            // 捕获当前的 sessionID，闭包会使用这个值
            let currentSessionID = sessionID
            let controllerSessionID = V2ScreenshotController.currentSessionID

            // 监听保存通知 (Command+S)
            let saveToken = NotificationCenter.default.addObserver(forName: NSNotification.Name("SaveScreenshot"), object: nil, queue: .main) { [self] _ in
                // ✅ 检查 sessionID 是否匹配，防止旧空间的监听器响应
                guard controllerSessionID == currentSessionID else {
                    print("⚠️ [SaveScreenshot] Ignored - session mismatch (expected: \(currentSessionID))")
                    return
                }
                if let selection = localSelectedArea {
                    saveToFlashNotes(rect: selection)
                }
            }

            // 监听复制通知 (Command+C)
            let copyToken = NotificationCenter.default.addObserver(forName: NSNotification.Name("CopyScreenshot"), object: nil, queue: .main) { [self] _ in
                // ✅ 检查 sessionID 是否匹配，防止旧空间的监听器响应
                guard controllerSessionID == currentSessionID else {
                    print("⚠️ [CopyScreenshot] Ignored - session mismatch (expected: \(currentSessionID))")
                    return
                }
                if let selection = localSelectedArea {
                    saveToClipboard(rect: selection)
                }
            }

            // 监听 OCR 通知 (Command+O)：识别后不关闭截图会话，可继续标注
            let ocrToken = NotificationCenter.default.addObserver(forName: NSNotification.Name("OCRScreenshot"), object: nil, queue: .main) { [self] _ in
                guard controllerSessionID == currentSessionID else {
                    print("⚠️ [OCRScreenshot] Ignored - session mismatch")
                    return
                }
                if let selection = localSelectedArea {
                    runOCR(rect: selection)
                }
            }

            notificationObservers = [saveToken, copyToken, ocrToken]
        }
        .onDisappear {
            // 移除通知监听器：不移除的话闭包会一直持有视图（含整屏截图 NSImage），每次截图都泄漏一份
            for token in notificationObservers {
                NotificationCenter.default.removeObserver(token)
            }
            notificationObservers = []
        }
        .onChange(of: isReleased) { released in
            // 当屏幕被释放时，允许鼠标穿透，这样用户就能感觉到"释放"了
            // 直接从控制器中寻找对应的面板
            if let panel = V2ScreenshotController.debugPanels.first(where: { $0.frame == screen.frame }) {
                panel.ignoresMouseEvents = released
                if released {
                    addLog("Screen \(screenIndex) released - Mouse events ignored")
                } else {
                    panel.ignoresMouseEvents = false
                    addLog("Screen \(screenIndex) reclaimed - Mouse events captured")
                }
            }
        }
    }

    /// 构建交互层：处理鼠标悬停、点击、拖拽等
    // 计算当前应该显示的唯一吸附线框
    private var snappedWireframeRect: CGRect? {
        // ⚠️ 统一使用全局悬停矩形
        if let rect = primaryScreenManager.globalHoveredRect, primaryScreenManager.hoverScreen == screen {
            // ✅ 修复：全屏窗口不内缩，保持与选区线框一致
            // 原因：stroke 边框会被裁剪，且内缩后与选区线框不一致
            return rect
        }
        return nil
    }

    // MARK: - 交互层构建

    /// 构建交互层：处理鼠标悬停、点击、拖拽等
    @ViewBuilder
    private func buildInteractionLayer() -> some View {
        ZStack {
            // MARK: 悬停监听层
            // ⚠️ 统一监听层：整个屏幕都是热区
            Color.white.opacity(0.0001)
                .contentShape(InvertedRectangle(hole: primaryScreenManager.isLongScreenshotMode ? localSelectedArea : nil), eoFill: true)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        // ✨ 关键修复：鼠标在 InteractionLayer 上移动时，强制重置 isMouseOverUI
                        // 因为鼠标在 InteractionLayer 上，肯定不在 UI 上
                        // 这修复了 isMouseOverUI 状态残留导致悬停逻辑被阻断的问题
                        if primaryScreenManager.isMouseOverUI {
                            primaryScreenManager.isMouseOverUI = false
                        }

                        if isReleased { return }

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
                        // ✨ 修复：不在 hover .ended 中清除 globalHoveredRect
                        // 原因：DragGesture.onEnded 需要读取 globalHoveredRect 来执行点击选择
                        // 如果在这里清除，会导致点击选择逻辑失败
                        // globalHoveredRect 会在鼠标移动时通过 updateHoverState 自动更新
                        // primaryScreenManager.updateHover(nil, label: nil, on: nil)
                        self.currentLayerLevel = 0
                        NSCursor.arrow.set()
                    }
                }
                // ⚠️ onTapGesture 已移除，点击逻辑统一到 DragGesture.onEnded 中处理
                // 原因：onTapGesture 无法获取准确的点击位置，导致第一次点击无效
        }
        .allowsHitTesting(true)

        // MARK: 拖拽手势处理
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // MARK: - onChanged: 初始化检查

                            // ✨ 修复：确保当前屏幕是主屏幕（防止第一次拖拽无效）
                            if !isCurrentlyPrimary {
                                primaryScreenManager.updatePrimaryScreen(screen)
                            }

                            // ✨ 修复：立即更新 mouseLocation，确保 onTapGesture 能获取正确位置
                            self.mouseLocation = value.startLocation

                            // ✨ 修复：主动更新 hover 状态，确保 hoverScreen 正确
                            updateHoverState(at: value.startLocation)

                            // ✨ Bug修复：主动重置可能阻断拖拽的残留状态
                            // 修复多屏环境下首次点击无法框选的问题
                            if primaryScreenManager.isMouseOverUI {
                                primaryScreenManager.isMouseOverUI = false
                                addLog("🐛 Reset isMouseOverUI flag")
                            }

                            // ✨ 修复：如果鼠标在 UI 上开始拖拽，不处理 InteractionLayer 的拖拽逻辑
                            if primaryScreenManager.isMouseOverUI && !isDraggingElement && !isMovingSelection && activeHandle == nil {
                                return
                            }

                            if isReleased { return }

                            // MARK: - onChanged: Phase 2 编辑模式交互

                    // 阶段 2: 编辑模式下的交互
                    if primaryScreenManager.isEditing {
                        // ✨ 核心修复：锁定编辑模式下的全域交互
                        // 1. 获取当前屏幕选区，如果当前屏幕没有选区但全域有选区，说明点击了错误的屏幕
                        guard let selection = localSelectedArea else {
                            if hasAnySelection { return }
                            return // 兜底
                        }
                        
                        // 2. 必须点击在选区内部才能开始交互
                        if !selection.contains(value.startLocation) {
                            return
                        }

                        // 2.1 ✨ 选择工具的移动逻辑
                        if primaryScreenManager.selectedTool == .cursor {
                            if !isDraggingElement {
                                // 1. 优先检查当前已选中的元素
                                var targetElement: DrawingElement? = nil
                                if let selectedId = primaryScreenManager.selectedElementId,
                                   let element = primaryScreenManager.elements.first(where: { $0.id == selectedId }) {
                                    let rect = elementBoundingRect(element, selection: localSelectedArea, screenSize: screenSize).insetBy(dx: -10, dy: -10)
                                    
                                    // 序号工具圆形判定
                                    var hit = false
                                    if element.tool == .steps {
                                        if let center = element.points.first {
                                            let dist = sqrt(pow(value.startLocation.x - center.x, 2) + pow(value.startLocation.y - center.y, 2))
                                            hit = dist <= rect.width / 2
                                        }
                                    } else {
                                        hit = rect.contains(value.startLocation)
                                    }
                                    
                                    if hit {
                                        targetElement = element
                                    }
                                }
                                
                                // 2. 如果没点中已选中的，检查是否点中了其他任何元素（实现一键选中并拖拽）
                                if targetElement == nil {
                                    if let hit = primaryScreenManager.elements.reversed().first(where: { element in
                                        let rect = elementBoundingRect(element, selection: localSelectedArea, screenSize: screenSize).insetBy(dx: -10, dy: -10)
                                        if element.tool == .steps {
                                            if let center = element.points.first {
                                                let dist = sqrt(pow(value.startLocation.x - center.x, 2) + pow(value.startLocation.y - center.y, 2))
                                                return dist <= rect.width / 2
                                            }
                                        }
                                        return rect.contains(value.startLocation)
                                    }) {
                                        targetElement = hit
                                        primaryScreenManager.selectedElementId = hit.id // 立即选中
                                        addLog("Element Selected via Drag: \(hit.tool)")
                                    }
                                }
                                
                                // 3. 如果确认了拖拽目标，初始化状态
                                if let element = targetElement {
                                    if element.tool == .magnifier {
                                        // 放大镜特殊逻辑
                                        let start = element.points.first!
                                        let dotRect = CGRect(x: start.x - 15, y: start.y - 15, width: 30, height: 30)
                                        if dotRect.contains(value.startLocation) {
                                            isDraggingElement = true
                                            magnifierDragTarget = .sourceDot
                                            initialElementPoints = element.points
                                            addLog("Dragging Magnifier Source Dot")
                                        } else {
                                            let circleRect = elementBoundingRect(element, selection: localSelectedArea, screenSize: screenSize).insetBy(dx: -5, dy: -5)
                                            if circleRect.contains(value.startLocation) {
                                                isDraggingElement = true
                                                magnifierDragTarget = .circle
                                                initialMagnifierOffset = element.magnifierOffset
                                                addLog("Dragging Magnifier Circle")
                                            }
                                        }
                                    } else {
                                        isDraggingElement = true
                                        initialElementPoints = element.points
                                        initialMagnifierOffset = element.magnifierOffset
                                        addLog("Dragging Element: \(element.tool)")
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
                                return
                            }
                        }

                        // 2.2 ✨ 绘图工具的创建逻辑
                        // ⚠️ .cursor 工具用于选择元素，不应创建新元素
                        guard primaryScreenManager.selectedTool != .cursor else { return }

                        // ✨ 关键修复：只允许在选区内绘制，且排除点击触发型工具（放大镜）
                        if selection.contains(value.location) {
                            if primaryScreenManager.currentElement == nil {
                                // 排除通过点击创建的工具，避免重复创建和逻辑冲突
                                // .steps, .text, .magnifier 均在 onEnded 中通过 Tap 逻辑处理
                                guard primaryScreenManager.selectedTool != .magnifier &&
                                      primaryScreenManager.selectedTool != .steps &&
                                      primaryScreenManager.selectedTool != .text else { return }

                                primaryScreenManager.currentElement = DrawingElement(
                                    tool: primaryScreenManager.selectedTool,
                                    points: [value.location],
                                    color: primaryScreenManager.selectedColor,
                                    lineWidth: primaryScreenManager.lineWidth,
                                    fontSize: primaryScreenManager.fontSize
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

                    // MARK: - onChanged: Phase 1 选区调整

                    // 阶段 1: 选区已经存在
                    if let currentSelection = localSelectedArea {
                        // 如果还没开始移动/调整，检查起始点
                        if !isMovingSelection && activeHandle == nil {
                            if let handle = getHandle(at: value.startLocation, in: currentSelection) {
                                // ⚠️ 编辑模式或长图模式下禁止调整选区
                                if primaryScreenManager.isEditing || primaryScreenManager.isLongScreenshotMode {
                                    return
                                }
                                activeHandle = handle
                                initialSelectionForMove = currentSelection
                                addLog("Resizing Selection Started: \(handle)")
                            } else if currentSelection.contains(value.startLocation) {
                                // ⚠️ 编辑模式或长图模式下禁止移动选区
                                if primaryScreenManager.isEditing || primaryScreenManager.isLongScreenshotMode {
                                    return
                                }
                                isMovingSelection = true
                                initialSelectionForMove = currentSelection
                                addLog("Moving Selection Started")
                            } else {
                                // ✨ 核心修复：点击选区外部直接忽略（不重画、不消失）
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

                        // MARK: - onChanged: Phase 0 新选区创建

                        // 阶段 0: 还没有选区，执行正常框选
                        // ✨ 核心修复：如果任意屏幕已经有选区了，禁止在当前屏幕开启新选区
                        if hasAnySelection { return }

                        if dragStartPoint == nil {
                            dragStartPoint = value.startLocation
                            addLog("🐛 [Phase 0] Drag Started at: \(Int(value.startLocation.x)),\(Int(value.startLocation.y))")
                            print("🐛 [Phase 0] Set dragStartPoint to \(value.startLocation)")
                        }
                        dragCurrentPoint = value.location
                    }
                }
                .onEnded { value in
                    // MARK: - onEnded: 点击检测与处理

                    // ✨ 计算移动距离，判断是点击还是拖拽
                    let dragDistance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                    let isClick = dragDistance < 5

                    // ✨ 如果是点击，处理点击逻辑
                    if isClick {
                        // ⚠️ 核心修复：点击也属于手势结束，必须重置所有拖拽/移动状态
                        // 否则会导致状态残留，下次拖拽时旧元素会“飞走”
                        defer {
                            isDraggingElement = false
                            isMovingSelection = false
                            activeHandle = nil
                            dragStartPoint = nil
                            dragCurrentPoint = nil
                            initialElementPoints = []
                            initialSelectionForMove = nil
                            initialMagnifierOffset = .zero
                            magnifierDragTarget = nil
                        }

                        let clickLocation = value.startLocation

                        // ✨ 核心修复：锁定点击交互
                        // 1. 如果全局已有选区
                        if hasAnySelection {
                            // 检查是否点击在当前屏幕的选区内
                            let inLocalSelection = localSelectedArea?.contains(clickLocation) ?? false
                            
                            // 检查是否正在编辑文本（如果是，需要允许点击外部以完成编辑）
                            let isEditingText = primaryScreenManager.selectedElementId != nil && 
                                               primaryScreenManager.elements.first(where: { $0.id == primaryScreenManager.selectedElementId })?.tool == .text
                            
                            // 如果点击在选区外，且不是为了完成文本编辑，则直接忽略
                            if !inLocalSelection && !isEditingText {
                                addLog("Click outside selection ignored")
                                return
                            }
                        }

                        // 1. ✨ 处理正在进行的文本编辑 (点击外部完成编辑)
                        if let selectedId = primaryScreenManager.selectedElementId,
                           let element = primaryScreenManager.elements.first(where: { $0.id == selectedId }),
                           element.tool == .text {
                            
                            // 检查是否点击在当前文本编辑框附近（增加容错）
                            let rect = elementBoundingRect(element, selection: localSelectedArea, screenSize: screenSize).insetBy(dx: -15, dy: -15)
                            if !rect.contains(clickLocation) {
                                // 点击了外部，完成并结束编辑
                                if element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    primaryScreenManager.elements.removeAll { $0.id == selectedId }
                                }
                                primaryScreenManager.selectedElementId = nil
                                addLog("Text Edit: Finished by clicking away")
                                
                                // ✨ 关键修复：点击空白处失焦后，不要在同一次点击中创建新文本
                                return
                            } else {
                                // 点击在框内，不重复执行逻辑，让 TextField 保持焦点
                                return
                            }
                        }

                        // 1. ✨ 阶段 0：窗口吸附选择（优先级最高）
                        if !primaryScreenManager.isEditing && !hasAnySelection,
                           let rect = primaryScreenManager.globalHoveredRect,
                           primaryScreenManager.hoverScreen == screen {
                            // ✨ 同时更新选区和主屏幕，确保 isCurrentlyPrimary = true
                            primaryScreenManager.updatePrimaryScreen(screen)
                            primaryScreenManager.updateSelection(rect, on: screen)
                            // ✅ 关键修复：清空拖拽状态，否则 buildDragOverlay 条件不满足
                            dragStartPoint = nil
                            dragCurrentPoint = nil
                            addLog("Area Selected via Tap")
                            return
                        }

                        // 2. ✨ 阶段 1：编辑模式下的工具选择
                        if primaryScreenManager.isEditing && primaryScreenManager.selectedTool == .cursor {
                            if let hitElement = primaryScreenManager.elements.reversed().first(where: { element in
                                let rect = elementBoundingRect(element, selection: localSelectedArea, screenSize: screenSize).insetBy(dx: -10, dy: -10)
                                
                                // ✨ 序号工具使用圆形热区判断
                                if element.tool == .steps {
                                    guard let center = element.points.first else { return false }
                                    let radius = rect.width / 2
                                    let distance = sqrt(pow(clickLocation.x - center.x, 2) + pow(clickLocation.y - center.y, 2))
                                    return distance <= radius
                                }
                                
                                return rect.contains(clickLocation)
                            }) {
                                primaryScreenManager.selectedElementId = hitElement.id
                                addLog("Element Selected: \(hitElement.tool)")
                            } else {
                                primaryScreenManager.selectedElementId = nil
                            }
                            return
                        }

                        // 3. ✨ 放大镜工具的点击
                        if primaryScreenManager.isEditing && primaryScreenManager.selectedTool == .magnifier {
                            if let selection = localSelectedArea, selection.contains(clickLocation) {
                                let magnifierElement = DrawingElement(
                                    tool: .magnifier,
                                    points: [clickLocation],
                                    color: primaryScreenManager.selectedColor,
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

                        // 3.5 ✨ 序号（步骤）工具的点击
                        if primaryScreenManager.isEditing && primaryScreenManager.selectedTool == .steps {
                            if let selection = localSelectedArea, selection.contains(clickLocation) {
                                // ⚠️ 核心修复：如果点击的是现有的序号，则选中它，而不是创建新的
                                // 这能防止用户在想选择序号时意外创建出重叠的新序号
                                if let hitElement = primaryScreenManager.elements.reversed().first(where: { element in
                                    guard element.tool == .steps else { return false }
                                    let rect = elementBoundingRect(element, selection: localSelectedArea, screenSize: screenSize).insetBy(dx: -5, dy: -5)
                                    guard let center = element.points.first else { return false }
                                    let radius = rect.width / 2
                                    let distance = sqrt(pow(clickLocation.x - center.x, 2) + pow(clickLocation.y - center.y, 2))
                                    return distance <= radius
                                }) {
                                    primaryScreenManager.selectedElementId = hitElement.id
                                    addLog("Steps Tool: Selected existing sequence number")
                                    return
                                }

                                let stepNumber = primaryScreenManager.getNextStepNumber()
                                let stepElement = DrawingElement(
                                    tool: .steps,
                                    points: [clickLocation],
                                    color: primaryScreenManager.selectedColor,
                                    lineWidth: primaryScreenManager.lineWidth,
                                    fontSize: primaryScreenManager.fontSize,
                                    stepNumber: stepNumber
                                )
                                primaryScreenManager.addElement(stepElement)
                                addLog("Step Placed: \(stepNumber)")
                                return
                            }
                        }

                        // 4. ✨ 文本工具的点击
                        if primaryScreenManager.isEditing && primaryScreenManager.selectedTool == .text {
                            if let selection = localSelectedArea, selection.contains(clickLocation) {
                                // 如果当前已经选中了一个元素，点击空白处时先取消选中，而不立即创建
                                if primaryScreenManager.selectedElementId != nil {
                                    primaryScreenManager.selectedElementId = nil
                                    addLog("Text Tool: Deselected current element")
                                    return
                                }

                                // 否则正常执行点击选中或创建逻辑
                                if let hitElement = primaryScreenManager.elements.reversed().first(where: { element in
                                    let rect = elementBoundingRect(element, selection: localSelectedArea, screenSize: screenSize).insetBy(dx: -5, dy: -5)
                                    return element.tool == .text && rect.contains(clickLocation)
                                }) {
                                    primaryScreenManager.selectedElementId = hitElement.id
                                    addLog("Text Tool: Selected existing element")
                                } else {
                                    // 否则创建新元素
                                    let textElement = DrawingElement(
                                        tool: .text,
                                        points: [clickLocation],
                                        color: primaryScreenManager.selectedColor,
                                        lineWidth: primaryScreenManager.lineWidth,
                                        text: "",
                                        fontSize: primaryScreenManager.fontSize
                                    )
                                    primaryScreenManager.addElement(textElement)
                                    primaryScreenManager.selectedElementId = textElement.id
                                    
                                    // ✨ 确保当前窗口成为 Key Window 以接收键盘输入
                                    if let panel = V2ScreenshotController.screenPanelMap[screen] {
                                        panel.makeKey()
                                        NSApp.activate(ignoringOtherApps: true)
                                        addLog("Text Tool: Panel made Key Window")
                                    }
                                    
                                    addLog("Text Tool: New element created")
                                }
                                return
                            }
                        }

                        // 5. ✨ 点击已有文本元素进行再次编辑
                        if primaryScreenManager.isEditing && primaryScreenManager.selectedTool == .cursor {
                            if let hitElement = primaryScreenManager.elements.reversed().first(where: { element in
                                let rect = elementBoundingRect(element, selection: localSelectedArea, screenSize: screenSize).insetBy(dx: -5, dy: -5)
                                return element.tool == .text && rect.contains(clickLocation)
                            }) {
                                primaryScreenManager.selectedElementId = hitElement.id
                                if let panel = V2ScreenshotController.screenPanelMap[screen] {
                                    panel.makeKey()
                                    NSApp.activate(ignoringOtherApps: true)
                                }
                                addLog("Text Tool: Selected existing element for editing")
                                return
                            }
                        }

                        // 点击处理完成
                        return
                    }

                    // MARK: - onEnded: 拖拽结束处理

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

    /// 构建标注层：使用完整的标注系统
    @ViewBuilder
    private func buildAnnotationLayer() -> some View {
        if primaryScreenManager.isEditing {
            ZStack {
                // 1. Canvas 渲染已有的非文本元素（或所有元素）
                V2AnnotationCanvas(
                    stateManager: primaryScreenManager,
                    canvasSize: screenSize,
                    baseImage: snapshot
                )
                .zIndex(20)

                // 2. ✨ 文本编辑器 (仅在选中了文本工具时显示)
                if let selectedId = primaryScreenManager.selectedElementId,
                   let element = primaryScreenManager.elements.first(where: { $0.id == selectedId }),
                   element.tool == .text,
                   primaryScreenManager.selectedTool == .text {
                    
                    let pos = element.points.first ?? .zero
                    
                    // ✨ 修复：改用 ZStack + offset 定位，避免 .position() 导致的布局压缩
                    ZStack(alignment: .topLeading) {
                        AnnotationTextEditorView(
                            text: Binding(
                                get: { element.text },
                                set: { primaryScreenManager.updateElementText(id: selectedId, text: $0) }
                            ),
                            color: element.color,
                            fontSize: element.fontSize,
                            onCommit: {
                                primaryScreenManager.selectedElementId = nil
                            }
                        )
                    }
                    .offset(x: pos.x, y: pos.y) // ✨ 关键修复：移除 +8 偏移，让编辑器内边距(8px)正好对齐渲染起点
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .zIndex(30)
                }

                // 3. ✨ 放大镜预览
                if let previewPos = primaryScreenManager.magnifierPreviewPosition,
                   isCurrentlyPrimary,
                   let selection = localSelectedArea {
                    AnnotationMagnifierPreview(
                        snapshot: snapshot,
                        position: previewPos,
                        canvasSize: screenSize,
                        followMouse: primaryScreenManager.magnifierFollowMouse,
                        selectionArea: selection,
                        currentFontSize: primaryScreenManager.fontSize, // ✨ 传入实时字号
                        currentScale: primaryScreenManager.magnifierScale, // ✨ 传入实时倍率
                        color: primaryScreenManager.selectedColor // ✨ 传入实时颜色
                    )
                    .zIndex(25)
                    .allowsHitTesting(false)
                }
            }
            // ✨ 核心需求：文本不能在线框外编辑，超出的部分被遮住
            .clipShape(Rectangle().path(in: localSelectedArea ?? CGRect(origin: .zero, size: screenSize)))
        }
    }
    
    /// 构建框选层：显示正在拖拽的区域
    @ViewBuilder
    private func buildDragOverlay() -> some View {
        // ✅ 修复：改用独立判断而非 else if 链，避免分支遗漏
        ZStack(alignment: .topLeading) {
            // ✅ 优先级1: 拖拽中的临时选区
            if let start = dragStartPoint, let current = dragCurrentPoint {
                let rect = CGRect(
                    x: min(start.x, current.x),
                    y: min(start.y, current.y),
                    width: abs(start.x - current.x),
                    height: abs(start.y - current.y)
                )

                // 🔴 调试：打印拖拽坐标
                let _ = print("🐛 [Drag Overlay] screen\(screenIndex)")
                let _ = print("   dragStartPoint: \(dragStartPoint!)")
                let _ = print("   dragCurrentPoint: \(dragCurrentPoint!)")
                let _ = print("   calculated rect: \(rect)")
                let _ = print("   screen.frame: \(screen.frame)")

                if rect.width > 3 || rect.height > 3 {
                    YellowWireframe(rect: rect, label: "\(Int(rect.width)) x \(Int(rect.height))", isDashed: true, showBackground: false, isEditing: primaryScreenManager.isEditing, isLongScreenshotMode: primaryScreenManager.isLongScreenshotMode)
                }
            }

            // ✅ 优先级2: 已确认选区（独立判断，不使用 else if）
            if let rect = localSelectedArea, dragStartPoint == nil {
                let _ = print("🐛 [buildDragOverlay] Creating YellowWireframe for selected area: \(rect)")
                let _ = print("   screen\(screenIndex), localSelectedArea: \(rect)")
                YellowWireframe(rect: rect, label: "\(Int(rect.width)) x \(Int(rect.height))", isDashed: false, showBackground: false, isEditing: primaryScreenManager.isEditing, isLongScreenshotMode: primaryScreenManager.isLongScreenshotMode, showHandles: true)
                .onContinuousHover { phase in
                    if case .active(_) = phase {
                        self.currentLayerName = "Selection (Layer 4)"
                        self.currentLayerLevel = 4
                    }
                }
            }

            // ✅ 优先级3: 悬停预览（添加额外条件避免冲突）
            if let rect = snappedWireframeRect,
               dragStartPoint == nil,
               localSelectedArea == nil,
               !isReleased {
                YellowWireframe(rect: rect, label: primaryScreenManager.globalHoveredLabel, isDashed: false, showBackground: false, isEditing: primaryScreenManager.isEditing, isLongScreenshotMode: primaryScreenManager.isLongScreenshotMode, opacity: 1.0)
                    .animation(.easeOut(duration: 0.15), value: rect)
            }
        }
        .allowsHitTesting(false) // ⚠️ 关键：线框层不拦截事件，所有交互由 Layer 3 的 DragGesture 处理
    }
}
