import SwiftUI
import AppKit

/// 截图预览视图 - 终极重构版 (模块化、子菜单、全功能实现)
struct ScreenshotPreviewView: View {
    let image: NSImage
    let initialCropRect: CGRect?
    let sourceRect: CGRect // 来源区域（用于动画）
    let transitionFrom: TransitionSource // 过渡来源
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var elements: [DrawingElement] = []
    @State private var currentElement: DrawingElement?
    @State private var selectedTool: AnnotationTool = AnnotationSettings.shared.getLastTool(for: .draw)
    @State private var selectedColor: Color = .red
    @State private var lineWidth: CGFloat = 4.0
    @State private var fontSize: CGFloat = 20.0
    @State private var stepCounter = 1
    
    // UI 交互状态
    @State private var isHoveringToolbar = false
    @State private var editingTextId: UUID? = nil
    @State private var selectedElementId: UUID? = nil
    @State private var lastDragLocation: CGPoint? = nil
    @State private var textInput: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var magnifierDragMode: MagnifierDragMode? = nil  // 记录放大镜的拖动模式

    // 双击检测
    @State private var lastClickTime: Date? = nil
    @State private var lastClickElementId: UUID? = nil

    // 放大镜拖动模式
    enum MagnifierDragMode {
        case displayCircle  // 只能拖动显示圆圈
    }

    // 四阶段枚举
    enum ScreenshotPhase {
        case windowDetection  // 阶段0：窗口识别（全屏透明，瞄准镜光标）
        case initialCrop      // 阶段1：初始裁剪（全屏虚线框，截图光标，无工具栏）
        case confirmCrop      // 阶段2：调整确认（有工具栏，不可调整）
        case editing          // 阶段3：编辑标注（虚线框固定，可标注）
    }

    // 模式状态：cropping (调整区域) vs editing (标注)
    @State private var screenshotPhase: ScreenshotPhase = .initialCrop

    // 向后兼容的计算属性
    private var isCropping: Bool {
        screenshotPhase == .initialCrop || screenshotPhase == .confirmCrop
    }
    @State private var cropRect: CGRect = .zero
    @State private var activeHandle: CropHandle? = nil
    @State private var lastDragDelta: CGSize = .zero
    @State private var currentCursor: NSCursor = .arrow
    @State private var mouseLocation: CGPoint = .zero // 实时记录鼠标位置
    @State private var magnifierCursor: NSCursor? = nil // 缓存放大镜光标
    @State private var screenshotCursor: NSCursor? = nil // 缓存截图光标（阶段1使用）

    // 【修复】动态坐标偏移量 - 用于准确转换鼠标坐标到 Canvas 内部坐标
    @State private var canvasFrameInZStack: CGRect = .zero
    @State private var actualCanvasSize: CGSize = .zero  // 缓存 Canvas 的实际渲染尺寸

    // ESC 退出逻辑
    @State private var showExitConfirm = false
    @State private var exitConfirmTimer: Timer? = nil

    var body: some View {
        ZStack {
            // 1. 背景点击处理（只在非裁剪模式下响应）
            if !isCropping {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingTextId = nil
                        selectedElementId = nil
                    }
            }
            
            VStack(spacing: 0) {
                // 2. 统一悬浮工具栏 (阶段2和3显示，阶段1隐藏)
                if screenshotPhase != .initialCrop {
                    ScreenshotToolbar(
                        selectedTool: $selectedTool,
                        selectedColor: $selectedColor,
                        fontSize: $fontSize,
                        isCropping: screenshotPhase == .confirmCrop, // 阶段2时禁用工具
                        onToolSelect: {
                            // 点击工具时进入编辑模式
                            if screenshotPhase == .confirmCrop {
                                screenshotPhase = .editing
                            }
                        },
                    onUndo: undo,
                    onCancel: onCancel,
                    onCopy: copyToClipboard,
                    onSave: onSave
                )
                .padding(.top, 8)  // 减少顶部间距，让工具栏紧贴
                .zIndex(100)
                .onChange(of: fontSize) { newValue in
                    // 当工具栏修改字号时，如果当前有选中元素，则实时同步更新
                    if let selectedId = selectedElementId,
                       let index = elements.firstIndex(where: { $0.id == selectedId }) {
                        elements[index].fontSize = newValue
                    }
                }
                .onChange(of: selectedColor) { newValue in
                    // 同理，当工具栏修改颜色时，实时更新选中元素的颜色
                    if let selectedId = selectedElementId,
                       let index = elements.firstIndex(where: { $0.id == selectedId }) {
                        elements[index].color = newValue
                    }
                }
                }

                // 3. 图片与交互画布
                ZStack {
                    if isCropping {
                        // 裁剪模式下显示原始图片层
                        GeometryReader { geo in
                            ZStack(alignment: .topLeading) {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .cornerRadius(8)
                                    .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                                // 裁剪覆盖层
                                cropOverlayLayer(for: geo.size)
                            }
                            .onAppear {
                                // 阶段1初始化：使用 initialCropRect 或默认全屏
                                if screenshotPhase == .initialCrop {
                                    if let initialRect = initialCropRect {
                                        // 使用从阶段0传递过来的裁剪区域
                                        cropRect = initialRect
                                    } else {
                                        // 默认全屏
                                        cropRect = CGRect(origin: .zero, size: geo.size)
                                    }
                                } else {
                                    setupInitialCrop(geo.size)
                                }
                            }
                        }
                    } else {
                        // 编辑模式下使用 Canvas 统一渲染所有内容（包括图片）
                        canvasView
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                        
                        // 文本编辑层
                        textEditLayer
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 16)  // 减少垂直间距，从 40 改为 16
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    Group {
                        if showExitConfirm {
                            Text("再按一次 ESC 退出截图")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.black.opacity(0.7)))
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .padding(.bottom, 20)
                        }
                    },
                    alignment: .bottom
                )
                
                if isCropping {
                    // 裁剪模式底部操作栏（移除提示文字）
                    HStack(spacing: 16) {
                        Button("全屏") {
                            // 全屏模式：使用整个图片
                            cropRect = CGRect(origin: .zero, size: image.size)
                            screenshotPhase = .editing
                        }
                        .controlSize(.small)

                        Button("确定") {
                            screenshotPhase = .editing
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("取消") {
                            onCancel()
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.6))
                            .shadow(color: .black.opacity(0.3), radius: 10)
                    )
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        // 【修复】定义命名坐标空间，用于动态计算 Canvas 相对于 ZStack 的偏移
        .coordinateSpace(name: "zstackSpace")
        // 【修复】接收 Canvas 位置更新
        .onPreferenceChange(CanvasFramePreferenceKey.self) { frame in
            if let frame = frame {
                canvasFrameInZStack = frame
            }
        }
        .onContinuousHover { phase in
            if case .active(let location) = phase {
                mouseLocation = location // 更新鼠标位置
                updateCursor(at: location)
            }
        }
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // ESC
                    handleEscape()
                    return nil
                }
                if event.keyCode == 36 { // Enter
                    // 三阶段状态转换逻辑
                    if screenshotPhase == .initialCrop {
                        // 阶段1 → 阶段2：显示工具栏
                        screenshotPhase = .confirmCrop
                    } else if screenshotPhase == .confirmCrop {
                        // 阶段2 → 阶段3：进入编辑模式
                        screenshotPhase = .editing
                    } else {
                        // 阶段3：编辑模式
                        if editingTextId != nil {
                            // 正在编辑文本 → 完成编辑，进入选中状态
                            finishEditingAndSelect()
                        } else {
                            // 没有在编辑 → 切换到选择工具
                            selectedTool = .cursor
                        }
                    }
                    return nil
                }
                // Command+C - 复制到剪贴板
                if event.keyCode == 8 && event.modifierFlags.contains(.command) {
                    copyToClipboard()
                    return nil
                }
                // Command+S - 保存并退出
                if event.keyCode == 1 && event.modifierFlags.contains(.command) {
                    onSave()
                    return nil
                }
                // Delete 或 Backspace - 删除选中元素
                if (event.keyCode == 51 || event.keyCode == 117) && selectedElementId != nil {
                    deleteSelectedElement()
                    return nil
                }
                return event
            }
        }
    }

    private func handleEscape() {
        // 四阶段 ESC 分层处理逻辑
        // 1. 优先：文本编辑状态
        if editingTextId != nil {
            editingTextId = nil
            isTextFieldFocused = false
            if let lastId = editingTextId {
                selectedElementId = lastId
            }
            return
        }

        // 2. 其次：选中元素状态
        if selectedElementId != nil {
            selectedElementId = nil
            return
        }

        // 3. 根据当前阶段处理状态转换
        switch screenshotPhase {
        case .editing:
            // 阶段3：双击退出逻辑
            if showExitConfirm {
                // 第2次 ESC: 直接退出
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

        case .confirmCrop:
            // 阶段2：1次 ESC → 返回阶段1
            screenshotPhase = .initialCrop

        case .initialCrop:
            // 阶段1：暂时直接退出（等阶段0实现后可以返回）
            onCancel()

        case .windowDetection:
            // 阶段0：1次 ESC → 退出
            onCancel()
        }
    }

    /// 完成文本编辑并进入选中状态
    private func finishEditingAndSelect() {
        if let editingId = editingTextId {
            // 从编辑状态转换到选中状态
            selectedElementId = editingId
            editingTextId = nil
            isTextFieldFocused = false
            selectedTool = .cursor

            // 同步工具栏状态
            if let element = elements.first(where: { $0.id == editingId }) {
                fontSize = element.fontSize
                selectedColor = element.color
            }
        }
    }

    private func setupInitialCrop(_ size: CGSize) {
        print("[DEBUG PHASE1] setupInitialCrop called, cropRect: \(cropRect), size: \(size), screenshotPhase: \(screenshotPhase)")
        if cropRect == .zero {
            // 默认全屏模式
            cropRect = CGRect(origin: .zero, size: size)
            print("[DEBUG PHASE1] Set cropRect to fullscreen: \(cropRect)")
        }
    }

    /// 创建放大镜工具的光标（纯十字准星，无中心点）
    private func createMagnifierCursor() -> NSCursor {
        let cursorSize = NSSize(width: 24, height: 24)

        let image = NSImage(size: cursorSize)
        image.lockFocus()

        let centerX = cursorSize.width / 2
        let centerY = cursorSize.height / 2

        // 绘制十字准星线（无中心点）
        let crossSize: CGFloat = 10
        let lineWidth: CGFloat = 1.5

        // 横线
        let horizontalPath = NSBezierPath()
        horizontalPath.move(to: NSPoint(x: centerX - crossSize, y: centerY))
        horizontalPath.line(to: NSPoint(x: centerX + crossSize, y: centerY))
        NSColor.white.setStroke()
        horizontalPath.lineWidth = lineWidth
        horizontalPath.stroke()

        // 竖线
        let verticalPath = NSBezierPath()
        verticalPath.move(to: NSPoint(x: centerX, y: centerY - crossSize))
        verticalPath.line(to: NSPoint(x: centerX, y: centerY + crossSize))
        verticalPath.stroke()

        image.unlockFocus()

        return NSCursor(image: image, hotSpot: NSPoint(x: centerX, y: centerY))
    }

    /// 创建截图光标（阶段1使用，带相机emoji的十字准星）
    private func createScreenshotCursor() -> NSCursor {
        let cursorSize = NSSize(width: 32, height: 32)

        let image = NSImage(size: cursorSize)
        image.lockFocus()

        let centerX = cursorSize.width / 2
        let centerY = cursorSize.height / 2

        // 绘制相机emoji作为截图光标中心
        let cameraString: NSString = "📷"
        let cameraAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16)
        ]
        let cameraSize = cameraString.size(withAttributes: cameraAttrs)
        let cameraOrigin = NSPoint(
            x: centerX - cameraSize.width / 2,
            y: centerY - cameraSize.height / 2
        )
        cameraString.draw(at: cameraOrigin, withAttributes: cameraAttrs)

        image.unlockFocus()

        return NSCursor(image: image, hotSpot: NSPoint(x: centerX, y: centerY))
    }

    private func updateCursor(at location: CGPoint) {
        // 阶段1：显示截图光标
        if screenshotPhase == .initialCrop {
            if screenshotCursor == nil {
                screenshotCursor = createScreenshotCursor()
            }
            screenshotCursor?.set()
            return
        }

        // 阶段2：禁用调整光标，只显示箭头
        if screenshotPhase == .confirmCrop {
            NSCursor.arrow.set()
            return
        }

        if !isCropping {
            if selectedTool == .magnifier {
                // 使用自定义放大镜光标
                if magnifierCursor == nil {
                    magnifierCursor = createMagnifierCursor()
                }
                magnifierCursor?.set()
                return
            }

            // 【修复】使用动态计算的坐标转换
            let canvasLocation = convertToCanvasCoordinates(location)

            // 如果鼠标悬浮在某个可选中的元素上
            if hitTest(canvasLocation) != nil {
                NSCursor.pointingHand.set()
                return
            }
        }

        guard isCropping else {
            NSCursor.arrow.set()
            return
        }

        let handle = getHandle(at: location)
        switch handle {
        case .topLeft:
            _createDiagonalCursorNWSE()?.set() ?? NSCursor.arrow.set()
        case .bottomRight:
            _createDiagonalCursorNWSE()?.set() ?? NSCursor.arrow.set()
        case .topRight:
            _createDiagonalCursorNESW()?.set() ?? NSCursor.arrow.set()
        case .bottomLeft:
            _createDiagonalCursorNESW()?.set() ?? NSCursor.arrow.set()
        case .top:
            NSCursor.resizeUpDown.set()
        case .bottom:
            NSCursor.resizeUpDown.set()
        case .left:
            NSCursor.resizeLeftRight.set()
        case .right:
            NSCursor.resizeLeftRight.set()
        case .center:
            // 使用移动光标（四个箭头）
            _createMoveCursor()?.set() ?? NSCursor.arrow.set()
        case .none:
            NSCursor.arrow.set()
        }
    }

    // 创建移动光标（四个箭头）
    private func _createMoveCursor() -> NSCursor? {
        let cursorSize = NSSize(width: 16, height: 16)
        let image = NSImage(size: cursorSize)
        image.lockFocus()

        let centerX = cursorSize.width / 2
        let centerY = cursorSize.height / 2
        let arrowLength: CGFloat = 5
        let lineWidth: CGFloat = 1.5

        NSColor.white.setStroke()
        // 黑色描边让白色更清晰
        NSColor.black.setStroke()

        // 上箭头
        let upPath = NSBezierPath()
        upPath.move(to: NSPoint(x: centerX, y: centerY - arrowLength))
        upPath.line(to: NSPoint(x: centerX, y: centerY - 2))
        upPath.lineWidth = lineWidth + 1
        NSColor.black.setStroke()
        upPath.stroke()
        NSColor.white.setStroke()
        upPath.lineWidth = lineWidth
        upPath.stroke()

        // 下箭头
        let downPath = NSBezierPath()
        downPath.move(to: NSPoint(x: centerX, y: centerY + arrowLength))
        downPath.line(to: NSPoint(x: centerX, y: centerY + 2))
        NSColor.black.setStroke()
        downPath.lineWidth = lineWidth + 1
        downPath.stroke()
        NSColor.white.setStroke()
        downPath.lineWidth = lineWidth
        downPath.stroke()

        // 左箭头
        let leftPath = NSBezierPath()
        leftPath.move(to: NSPoint(x: centerX - arrowLength, y: centerY))
        leftPath.line(to: NSPoint(x: centerX - 2, y: centerY))
        NSColor.black.setStroke()
        leftPath.lineWidth = lineWidth + 1
        leftPath.stroke()
        NSColor.white.setStroke()
        leftPath.lineWidth = lineWidth
        leftPath.stroke()

        // 右箭头
        let rightPath = NSBezierPath()
        rightPath.move(to: NSPoint(x: centerX + arrowLength, y: centerY))
        rightPath.line(to: NSPoint(x: centerX + 2, y: centerY))
        NSColor.black.setStroke()
        rightPath.lineWidth = lineWidth + 1
        rightPath.stroke()
        NSColor.white.setStroke()
        rightPath.lineWidth = lineWidth
        rightPath.stroke()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: centerX, y: centerY))
    }

    // 创建西北-东南对角线调整大小光标
    private func _createDiagonalCursorNWSE() -> NSCursor? {
        let cursorSize = NSSize(width: 16, height: 16)
        let image = NSImage(size: cursorSize)
        image.lockFocus()

        let centerX = cursorSize.width / 2
        let centerY = cursorSize.height / 2
        let offset: CGFloat = 4
        let lineWidth: CGFloat = 1.5

        // 绘制双箭头（左上到右下）
        let path = NSBezierPath()
        // 左上箭头
        path.move(to: NSPoint(x: centerX - offset, y: centerY - offset))
        path.line(to: NSPoint(x: centerX - 1, y: centerY - 1))
        // 右下箭头
        path.move(to: NSPoint(x: centerX + offset, y: centerY + offset))
        path.line(to: NSPoint(x: centerX + 1, y: centerY + 1))
        path.lineWidth = lineWidth
        NSColor.black.setStroke()
        path.stroke()
        NSColor.white.setStroke()
        path.lineWidth = lineWidth - 0.5
        path.stroke()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: centerX, y: centerY))
    }

    // 创建东北-西南对角线调整大小光标
    private func _createDiagonalCursorNESW() -> NSCursor? {
        let cursorSize = NSSize(width: 16, height: 16)
        let image = NSImage(size: cursorSize)
        image.lockFocus()

        let centerX = cursorSize.width / 2
        let centerY = cursorSize.height / 2
        let offset: CGFloat = 4
        let lineWidth: CGFloat = 1.5

        // 绘制双箭头（右上到左下）
        let path = NSBezierPath()
        // 右上箭头
        path.move(to: NSPoint(x: centerX + offset, y: centerY - offset))
        path.line(to: NSPoint(x: centerX + 1, y: centerY - 1))
        // 左下箭头
        path.move(to: NSPoint(x: centerX - offset, y: centerY + offset))
        path.line(to: NSPoint(x: centerX - 1, y: centerY + 1))
        path.lineWidth = lineWidth
        NSColor.black.setStroke()
        path.stroke()
        NSColor.white.setStroke()
        path.lineWidth = lineWidth - 0.5
        path.stroke()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: centerX, y: centerY))
    }

    /// 从全局坐标（ZStack）获取手柄 - 用于光标更新
    private func getHandle(at point: CGPoint) -> CropHandle? {
        // 将外层 ZStack 坐标转换为相对于图片的坐标（考虑 padding）
        let adjustedPoint = CGPoint(
            x: point.x - 80,  // 水平 padding
            y: point.y - 40   // 垂直 padding（不包括工具栏）
        )

        // 使用缓存的 canvas 尺寸
        return getHandleInLocalCoordinates(at: adjustedPoint, containerSize: actualCanvasSize)
    }

    /// 从局部坐标（图片容器）获取手柄 - 用于拖拽处理
    private func getHandleInLocalCoordinates(at point: CGPoint, containerSize: CGSize) -> CropHandle? {
        // 如果 cropRect 是 zero，假设是全屏
        let rect = cropRect == .zero ? CGRect(origin: .zero, size: containerSize) : cropRect

        // 角手柄检测区域较大
        let cornerMargin: CGFloat = 15
        if abs(point.x - rect.minX) < cornerMargin && abs(point.y - rect.minY) < cornerMargin { return .topLeft }
        if abs(point.x - rect.maxX) < cornerMargin && abs(point.y - rect.minY) < cornerMargin { return .topRight }
        if abs(point.x - rect.minX) < cornerMargin && abs(point.y - rect.maxY) < cornerMargin { return .bottomLeft }
        if abs(point.x - rect.maxX) < cornerMargin && abs(point.y - rect.maxY) < cornerMargin { return .bottomRight }

        // 边手柄检测区域较小，避免误触
        let edgeMargin: CGFloat = 10
        if abs(point.y - rect.minY) < edgeMargin && point.x > rect.minX && point.x < rect.maxX { return .top }
        if abs(point.y - rect.maxY) < edgeMargin && point.x > rect.minX && point.x < rect.maxX { return .bottom }
        if abs(point.x - rect.minX) < edgeMargin && point.y > rect.minY && point.y < rect.maxY { return .left }
        if abs(point.x - rect.maxX) < edgeMargin && point.y > rect.minY && point.y < rect.maxY { return .right }

        if rect.contains(point) { return .center }
        return nil
    }

    // MARK: - Crop Layer

    private func cropOverlayLayer(for containerSize: CGSize) -> some View {
        // 如果 cropRect 是 zero，使用全屏尺寸（阶段1初始状态）
        let displayCropRect = cropRect == .zero ? CGRect(origin: .zero, size: containerSize) : cropRect

        return ZStack(alignment: .topLeading) {
            // 半透明背景（非选中区域）- 设置透明度为0，移除蒙尘效果
            Path { path in
                path.addRect(CGRect(origin: .zero, size: containerSize))
                path.addRect(displayCropRect)
            }
            .fill(Color.black.opacity(0), style: FillStyle(eoFill: true))

            // 选中区域边框 - 虚线
            Rectangle()
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .frame(width: displayCropRect.width, height: displayCropRect.height)
                .position(x: displayCropRect.midX, y: displayCropRect.midY)

            // 8 个调整手柄
            Group {
                // 四角
                handleView(.topLeft, x: displayCropRect.minX, y: displayCropRect.minY)
                handleView(.topRight, x: displayCropRect.maxX, y: displayCropRect.minY)
                handleView(.bottomLeft, x: displayCropRect.minX, y: displayCropRect.maxY)
                handleView(.bottomRight, x: displayCropRect.maxX, y: displayCropRect.maxY)

                // 四边
                handleView(.top, x: displayCropRect.midX, y: displayCropRect.minY)
                handleView(.bottom, x: displayCropRect.midX, y: displayCropRect.maxY)
                handleView(.left, x: displayCropRect.minX, y: displayCropRect.midY)
                handleView(.right, x: displayCropRect.maxX, y: displayCropRect.midY)
            }

            // 尺寸提示
            Text("\(Int(displayCropRect.width)) x \(Int(displayCropRect.height))")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue)
                .cornerRadius(4)
                .position(x: displayCropRect.minX + 35, y: displayCropRect.minY - 15)
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .contentShape(Rectangle()) // 确保整个区域都能接收点击
        .gesture(
            screenshotPhase == .initialCrop ?
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    handleCropDrag(value, containerSize: containerSize)
                }
                .onEnded { _ in
                    activeHandle = nil
                    lastDragDelta = .zero
                } :
            DragGesture()
                .onChanged { _ in }
                .onEnded { _ in }
        )
    }

    @ViewBuilder
    private func handleView(_ handle: CropHandle, x: CGFloat, y: CGFloat) -> some View {
        // 阶段1显示手柄，阶段2隐藏
        if screenshotPhase == .initialCrop {
            let handleView: some View = {
                switch handle {
                case .top, .bottom:
                    // 上下边手柄：横向长条
                    return Rectangle()
                        .fill(Color.white)
                        .frame(width: 30, height: 8)
                        .overlay(Rectangle().stroke(Color.blue, lineWidth: 1))
                case .left, .right:
                    // 左右边手柄：纵向长条
                    return Rectangle()
                        .fill(Color.white)
                        .frame(width: 8, height: 30)
                        .overlay(Rectangle().stroke(Color.blue, lineWidth: 1))
                default:
                    // 四角手柄：方形
                    return Rectangle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .overlay(Rectangle().stroke(Color.blue, lineWidth: 1))
                }
            }()
            handleView.position(x: x, y: y)
        }
    }

    // MARK: - 坐标转换系统（统一使用 Canvas 相对坐标）

    /// 将全局坐标（ZStack）转换为 Canvas 内部坐标
    /// - Parameter point: 相对于 ZStack 的坐标
    /// - Returns: 相对于 Canvas 内部的坐标
    private func convertToCanvasCoordinates(_ point: CGPoint) -> CGPoint {
        // 视图结构：
        // ZStack (coordinateSpace: "zstackSpace")
        //   └── VStack
        //         ├── ScreenshotToolbar (.padding(.top, 8))
        //         └── ZStack (Canvas区域)
        //               .padding(.horizontal, 80)
        //               .padding(.vertical, 16)
        //
        // 需要减去的偏移量：
        // - 水平：80 (Canvas 容器的水平 padding)
        // - 垂直：8 (工具栏顶部 padding) + 工具栏高度(~60) + 16 (Canvas 容器的垂直 padding)

        let offsetX: CGFloat = 80
        let offsetY: CGFloat = 84  // 8 + 60 + 16 = 84

        let result = CGPoint(
            x: point.x - offsetX,
            y: point.y - offsetY
        )

        print("[DEBUG COORD] ZStack(\(point.x), \(point.y)) -> Canvas(\(result.x), \(result.y))")
        return result
    }

    /// 将 Canvas 内部坐标转换为全局坐标（ZStack）
    /// - Parameter point: 相对于 Canvas 内部的坐标
    /// - Returns: 相对于 ZStack 的坐标
    private func convertFromCanvasCoordinates(_ point: CGPoint) -> CGPoint {
        let offsetX: CGFloat = 80
        let offsetY: CGFloat = 84  // 8 + 60 + 16 = 84

        return CGPoint(
            x: point.x + offsetX,
            y: point.y + offsetY
        )
    }

    /// 计算放大镜在 Canvas 右上角的固定位置
    /// - Parameter canvasSize: Canvas 的尺寸
    /// - Returns: 放大镜中心点在 Canvas 内部的坐标
    private func magnifierCenterPosition(in canvasSize: CGSize, radius: CGFloat, padding: CGFloat = 20) -> CGPoint {
        let center = CGPoint(
            x: canvasSize.width - radius - padding,
            y: radius + padding
        )
        print("[DEBUG MAGNIFIER] canvasSize: \(canvasSize), magnifierCenter: \(center)")
        return center
    }

    private func handleCropDrag(_ value: DragGesture.Value, containerSize: CGSize) {
        // 阶段2禁用拖动
        guard screenshotPhase == .initialCrop else { return }

        if activeHandle == nil {
            // 使用局部坐标版本，因为 startLocation 是相对于 cropOverlayLayer 的
            activeHandle = getHandleInLocalCoordinates(at: value.startLocation, containerSize: containerSize)
        }

        guard let handle = activeHandle else { return }

        // 如果 cropRect 是 zero，先初始化为全屏
        if cropRect == .zero {
            cropRect = CGRect(origin: .zero, size: containerSize)
        }

        var newRect = cropRect
        let deltaX = value.translation.width - lastDragDelta.width
        let deltaY = value.translation.height - lastDragDelta.height

        switch handle {
        case .topLeft:
            newRect.origin.x += deltaX; newRect.origin.y += deltaY
            newRect.size.width -= deltaX; newRect.size.height -= deltaY
        case .topRight:
            newRect.origin.y += deltaY
            newRect.size.width += deltaX; newRect.size.height -= deltaY
        case .bottomLeft:
            newRect.origin.x += deltaX
            newRect.size.width -= deltaX; newRect.size.height += deltaY
        case .bottomRight:
            newRect.size.width += deltaX; newRect.size.height += deltaY
        case .top:
            newRect.origin.y += deltaY; newRect.size.height -= deltaY
        case .bottom:
            newRect.size.height += deltaY
        case .left:
            newRect.origin.x += deltaX; newRect.size.width -= deltaX
        case .right:
            newRect.size.width += deltaX
        case .center:
            newRect.origin.x += deltaX; newRect.origin.y += deltaY
        }

        // 限制在容器范围内
        newRect.origin.x = max(0, min(newRect.origin.x, containerSize.width - newRect.width))
        newRect.origin.y = max(0, min(newRect.origin.y, containerSize.height - newRect.height))
        // 限制尺寸不超过容器
        newRect.size.width = min(newRect.size.width, containerSize.width - newRect.origin.x)
        newRect.size.height = min(newRect.size.height, containerSize.height - newRect.origin.y)

        // 限制最小尺寸
        if newRect.size.width > 20 && newRect.size.height > 20 {
            cropRect = newRect
        }
        lastDragDelta = value.translation

        // 设置拖动时的光标
        switch handle {
        case .center: NSCursor.closedHand.set()
        case .topLeft, .bottomRight: _createDiagonalCursorNWSE()?.set()
        case .topRight, .bottomLeft: _createDiagonalCursorNESW()?.set()
        case .top, .bottom: NSCursor.resizeUpDown.set()
        case .left, .right: NSCursor.resizeLeftRight.set()
        }
    }

    private func undo() {
        if !elements.isEmpty {
            elements.removeLast()
        }
    }

    private func deleteSelectedElement() {
        if let selectedId = selectedElementId {
            elements.removeAll { $0.id == selectedId }
            selectedElementId = nil
        }
    }


    
    // MARK: - Canvas View
    
    private var canvasView: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                // 【修复】缓存 Canvas 的实际渲染尺寸，确保点击创建时使用正确的尺寸
                if actualCanvasSize != size {
                    actualCanvasSize = size
                    print("[DEBUG CANVAS] size updated to: \(size)")
                }

                // 1. 绘制底层图片
                context.draw(Image(nsImage: image), in: CGRect(origin: .zero, size: size))
                
                // 2. 绘制聚光灯背景 (如果有聚光灯)
                if elements.contains(where: { $0.tool == .spotlight }) || currentElement?.tool == .spotlight {
                    var spotlightContext = context
                    spotlightContext.addFilter(.colorMultiply(.black.opacity(0.6)))
                    spotlightContext.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.6)))
                    
                    // 挖出聚光灯区域
                    for element in (elements + [currentElement].compactMap { $0 }).filter({ $0.tool == .spotlight }) {
                        if let start = element.points.first, let last = element.points.last {
                            let rect = CGRect(x: min(start.x, last.x), y: min(start.y, last.y), width: abs(start.x - last.x), height: abs(start.y - last.y))
                            context.blendMode = .destinationOut
                            context.fill(Path(ellipseIn: rect), with: .color(.black))
                            context.blendMode = .normal
                            // 绘制边缘线
                            context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.5)), lineWidth: 2)
                        }
                    }
                }
                
                // 3. 绘制普通标注元素
                for element in elements {
                    if element.tool == .spotlight { continue } // 聚光灯已处理
                    drawElement(element, in: &context, size: size)
                    
                    if element.id == selectedElementId {
                        drawSelectionIndicator(element, in: &context)
                    }
                }

                // 4. 绘制当前正在拖动的元素
                if let current = currentElement, current.tool != .spotlight {
                    drawElement(current, in: &context, size: size)
                }

                // 5. 绘制放大镜预览 (右上角固定显示模式)
                if selectedTool == .magnifier && currentElement == nil && !isCropping {
                    let radius = fontSize * 2.5
                    let padding: CGFloat = 20

                    // 使用统一的坐标转换方法
                    let canvasMouseLocation = convertToCanvasCoordinates(mouseLocation)
                    let magnifierCenter = magnifierCenterPosition(in: size, radius: radius, padding: padding)

                    // 【调试】绘制绿色小点显示转换后的鼠标位置
                    context.fill(Path(ellipseIn: CGRect(x: canvasMouseLocation.x - 3, y: canvasMouseLocation.y - 3, width: 6, height: 6)), with: .color(.green))
                    context.stroke(Path(ellipseIn: CGRect(x: canvasMouseLocation.x - 3, y: canvasMouseLocation.y - 3, width: 6, height: 6)), with: .color(.black), lineWidth: 1)

                    // 【调试】绘制红色小点显示放大镜中心位置
                    context.fill(Path(ellipseIn: CGRect(x: magnifierCenter.x - 2, y: magnifierCenter.y - 2, width: 4, height: 4)), with: .color(.red))

                    print("[DEBUG PREVIEW] mouse: \(mouseLocation) -> canvasMouse: \(canvasMouseLocation)")
                    print("[DEBUG PREVIEW] magnifierCenter: \(magnifierCenter)")

                    // 直接调用底层绘制方法，传递 isPreview: true
                    let renderer = MagnifierRenderer()
                    renderer.drawMagnifierPreview(
                        from: canvasMouseLocation,
                        to: magnifierCenter,
                        in: &context,
                        size: size,
                        baseImage: image,
                        radius: radius
                    )
                }
            }
            // 【修复】传递 Canvas 位置到父视图
            .preference(key: CanvasFramePreferenceKey.self, value: geometry.frame(in: .named("zstackSpace")))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDragChanged(value, in: geometry.size)
                    }
                    .onEnded { _ in
                        handleDragEnded()
                    }
            )
        }
    }
    
    private func handleDragChanged(_ value: DragGesture.Value, in size: CGSize) {
        if selectedTool == .cursor {
            // 【关键修复】DragGesture 的坐标已经是 Canvas 本地坐标，不需要转换
            let canvasStartLocation = value.startLocation
            let canvasCurrentLocation = value.location

            if lastDragLocation == nil {
                // 第一次点击，检测点击位置并记录拖动模式
                if let hit = elements.last(where: { hitTest($0, at: canvasStartLocation) }) {
                    // 检测双击
                    let now = Date()
                    if let lastTime = lastClickTime,
                       let lastId = lastClickElementId,
                       lastId == hit.id,
                       now.timeIntervalSince(lastTime) < 0.5 {
                        // 双击 → 进入编辑模式（仅文本元素）
                        if hit.tool == .text {
                            selectedElementId = hit.id
                            editingTextId = hit.id
                            isTextFieldFocused = true
                            lastClickTime = nil
                            lastDragLocation = canvasStartLocation
                            // 同步工具栏状态
                            fontSize = hit.fontSize
                            selectedColor = hit.color
                            return
                        }
                    }
                    lastClickTime = now
                    lastClickElementId = hit.id

                    selectedElementId = hit.id
                    lastDragLocation = canvasStartLocation
                    // 同步工具栏的 fontSize 和 color 到选中元素的值
                    fontSize = hit.fontSize
                    selectedColor = hit.color

                    // 如果是放大镜，记录拖动模式
                    if hit.tool == .magnifier {
                        magnifierDragMode = getMagnifierDragMode(hit, at: canvasStartLocation)
                        print("[DEBUG MAGNIFIER] Drag mode: \(String(describing: magnifierDragMode))")
                    } else {
                        magnifierDragMode = nil
                    }
                } else {
                    selectedElementId = nil
                    editingTextId = nil // 点击空白处退出编辑
                    magnifierDragMode = nil
                }
            } else if let selectedId = selectedElementId, let lastLoc = lastDragLocation {
                let deltaX = canvasCurrentLocation.x - lastLoc.x
                let deltaY = canvasCurrentLocation.y - lastLoc.y
                if let index = elements.firstIndex(where: { $0.id == selectedId }) {
                    if elements[index].tool == .magnifier && magnifierDragMode != nil {
                        // 放大镜：只移动显示圆圈
                        elements[index].magnifierOffset.width += deltaX
                        elements[index].magnifierOffset.height += deltaY
                    } else {
                        // 通用移动逻辑
                        for i in 0..<elements[index].points.count {
                            elements[index].points[i].x += deltaX
                            elements[index].points[i].y += deltaY
                        }
                    }
                }
                lastDragLocation = canvasCurrentLocation
            }
            return
        }

        if currentElement == nil {
            // 【关键修复】DragGesture 的坐标已经是 Canvas 本地坐标，不需要转换
            var newElement = DrawingElement(
                tool: selectedTool,
                points: [value.startLocation],
                color: selectedColor,
                lineWidth: lineWidth,
                fontSize: fontSize
            )

            if selectedTool == .steps {
                newElement.stepNumber = stepCounter
            }

            if selectedTool == .text {
                // 点击即创建文本
                let id = newElement.id
                elements.append(newElement)
                editingTextId = id
                textInput = ""
                // 延迟聚焦，确保视图已渲染
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isTextFieldFocused = true
                }
            } else if selectedTool == .magnifier {
                // 放大镜逻辑：点击即固化
                // 【关键修复】DragGesture 坐标已经是 Canvas 本地坐标，直接使用
                let canvasClickLocation = value.startLocation

                print("[DEBUG CLICK] canvasClickLocation: \(canvasClickLocation)")

                let newElement = DrawingElement(
                    tool: .magnifier,
                    points: [canvasClickLocation],  // 只存储源点，不存储 magnifierCenter
                    color: selectedColor,
                    lineWidth: 2,
                    fontSize: fontSize
                )
                elements.append(newElement)
                // 自动选择刚刚创建的放大镜
                selectedElementId = newElement.id
                lastDragLocation = canvasClickLocation  // 记录源点位置以支持立即移动
                selectedTool = .cursor // 点击后切回选中模式
            } else {
                currentElement = newElement
            }
        } else {
            // 【关键修复】DragGesture 的坐标已经是 Canvas 本地坐标，直接使用
            currentElement?.points.append(value.location)
        }
    }
    
    private func handleDragEnded() {
        if selectedTool == .cursor {
            lastDragLocation = nil
            magnifierDragMode = nil  // 清除拖动模式
            return
        }

        if let current = currentElement {
            if selectedTool == .steps {
                stepCounter += 1
            }
            elements.append(current)
        }
        currentElement = nil
    }

    // MARK: - Hit Testing
    
    private func hitTest(_ point: CGPoint) -> DrawingElement? {
        elements.reversed().first { hitTest($0, at: point) }
    }
    
    private func hitTest(_ element: DrawingElement, at point: CGPoint) -> Bool {
        guard let start = element.points.first else { return false }

        switch element.tool {
        case .pen:
            // 简单的点距离测试
            return element.points.contains { hypot($0.x - point.x, $0.y - point.y) < 10 }
        case .rectangle, .mosaic, .spotlight:
            guard let last = element.points.last else { return false }
            let rect = CGRect(x: min(start.x, last.x), y: min(start.y, last.y), width: abs(start.x - last.x), height: abs(start.y - last.y)).insetBy(dx: -5, dy: -5)
            return rect.contains(point) || hypot(last.x - point.x, last.y - point.y) < 20
        case .magnifier:
            // 放大镜：可以点击源点、显示圆圈区域或连线
            return getMagnifierDragMode(element, at: point) != nil
        case .circle:
            guard let last = element.points.last else { return false }
            let rect = CGRect(x: min(start.x, last.x), y: min(start.y, last.y), width: abs(start.x - last.x), height: abs(start.y - last.y)).insetBy(dx: -5, dy: -5)
            return rect.contains(point)
        case .line, .arrow:
            guard let last = element.points.last else { return false }
            // 简单的线段距离测试 (简化版)
            return rectForPoints([start, last]).insetBy(dx: -10, dy: -10).contains(point)
        case .text:
            // 文本：根据文本内容估算点击区域
            // 估算文本尺寸（每个字符约 12x18 像素，根据字号调整）
            let charWidth = element.fontSize * 0.6
            let charHeight = element.fontSize * 1.2
            let textWidth = max(charWidth * CGFloat(element.text.count), charWidth * 3)  // 最小宽度 3 个字符
            let textHeight = charHeight

            let textRect = CGRect(
                x: start.x - 10,
                y: start.y - 10,
                width: textWidth + 20,
                height: textHeight + 20
            )
            return textRect.contains(point)

        case .steps:
            // 步骤：更大的点击区域
            let stepRadius: CGFloat = 30
            let stepRect = CGRect(
                x: start.x - stepRadius,
                y: start.y - stepRadius,
                width: stepRadius * 2,
                height: stepRadius * 2
            )
            return stepRect.contains(point)

        default:
            return false
        }
    }

    /// 获取放大镜的拖动模式（点击的是哪个部分）
    private func getMagnifierDragMode(_ element: DrawingElement, at point: CGPoint) -> MagnifierDragMode? {
        let radius = element.fontSize * 2.5
        let padding: CGFloat = 20

        // 计算显示圆圈位置
        guard actualCanvasSize != .zero else { return nil }
        let defaultEnd = CGPoint(
            x: actualCanvasSize.width - radius - padding,
            y: radius + padding
        )
        let end = CGPoint(
            x: defaultEnd.x + element.magnifierOffset.width,
            y: defaultEnd.y + element.magnifierOffset.height
        )

        // 只检查是否点击了显示圆圈
        if hypot(end.x - point.x, end.y - point.y) < radius {
            return .displayCircle
        }

        // 源点和连线不可选中，返回 nil
        return nil
    }

    /// 计算点到线段的距离
    private func pointToLineDistance(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let A = point.x - lineStart.x
        let B = point.y - lineStart.y
        let C = lineEnd.x - lineStart.x
        let D = lineEnd.y - lineStart.y

        let dot = A * C + B * D
        let lenSq = C * C + D * D

        let param = lenSq != 0 ? dot / lenSq : -1

        var closestX: CGFloat
        var closestY: CGFloat

        if param < 0 {
            closestX = lineStart.x
            closestY = lineStart.y
        } else if param > 1 {
            closestX = lineEnd.x
            closestY = lineEnd.y
        } else {
            closestX = lineStart.x + param * C
            closestY = lineStart.y + param * D
        }

        return hypot(point.x - closestX, point.y - closestY)
    }
    
    private func rectForPoints(_ points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .zero }
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    private func drawSelectionIndicator(_ element: DrawingElement, in context: inout GraphicsContext) {
        switch element.tool {
        case .magnifier:
            // 放大镜：在显示圆圈周围画一个明显的选中框
            let radius = element.fontSize * 2.5
            let padding: CGFloat = 20
            let defaultEnd = CGPoint(
                x: actualCanvasSize.width - radius - padding,
                y: radius + padding
            )
            let end = CGPoint(
                x: defaultEnd.x + element.magnifierOffset.width,
                y: defaultEnd.y + element.magnifierOffset.height
            )
            let indicatorRect = CGRect(
                x: end.x - radius - 8,
                y: end.y - radius - 8,
                width: radius * 2 + 16,
                height: radius * 2 + 16
            )
            context.stroke(Path(ellipseIn: indicatorRect), with: .color(.blue), style: StrokeStyle(lineWidth: 3, dash: [6, 4]))

        case .text:
            // 文本：根据文本内容绘制选中框
            guard let start = element.points.first else { return }
            let charWidth = element.fontSize * 0.6
            let charHeight = element.fontSize * 1.2
            let textWidth = max(charWidth * CGFloat(element.text.count), charWidth * 3)
            let textHeight = charHeight

            let textRect = CGRect(
                x: start.x - 10,
                y: start.y - 10,
                width: textWidth + 20,
                height: textHeight + 20
            )
            context.stroke(Path(roundedRect: textRect, cornerSize: CGSize(width: 8, height: 8)),
                          with: .color(.blue),
                          style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

        case .steps:
            // 步骤：圆角框
            guard let start = element.points.first else { return }
            let stepRadius: CGFloat = 30
            let stepRect = CGRect(
                x: start.x - stepRadius,
                y: start.y - stepRadius,
                width: stepRadius * 2,
                height: stepRadius * 2
            )
            context.stroke(Path(roundedRect: stepRect, cornerSize: CGSize(width: 8, height: 8)),
                          with: .color(.blue),
                          style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

        case .pen:
            // 画笔：框住所有点
            let rect = rectForPoints(element.points).insetBy(dx: -8, dy: -8)
            context.stroke(Path(roundedRect: rect, cornerSize: CGSize(width: 4, height: 4)),
                          with: .color(.blue),
                          style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

        default:
            // 其他元素：矩形框
            let rect = rectForPoints(element.points).insetBy(dx: -6, dy: -6)
            context.stroke(Path(roundedRect: rect, cornerSize: CGSize(width: 4, height: 4)),
                          with: .color(.blue),
                          style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
    }
    
    private func drawElement(_ element: DrawingElement, in context: inout GraphicsContext, size: CGSize) {
        // 使用新的渲染器系统
        let config = RendererConfig(
            imageSize: image.size,
            canvasSize: size,
            baseImage: image
        )

        // 跳过正在编辑的文本（由 textEditLayer 处理）
        if element.tool == .text && editingTextId == element.id {
            return
        }

        let renderer = ElementRendererFactory.renderer(for: element.tool)
        renderer.render(element: element, in: &context, config: config)
    }
    
    // MARK: - Text Edit Layer

    private var textEditLayer: some View {
        ZStack {
            ForEach($elements) { $element in
                if element.id == editingTextId {
                    TextEditor(text: $element.text)
                        .font(.system(size: element.fontSize, weight: .bold))
                        .foregroundColor(element.color)
                        .scrollContentBackground(.hidden)
                        .background(Color.black.opacity(0.05)) // 稍微有一点背景色提示输入区域
                        .cornerRadius(4)
                        .focused($isTextFieldFocused)
                        .frame(minWidth: 100, maxWidth: 400, minHeight: 40)
                        .fixedSize(horizontal: false, vertical: true)
                        .position(
                            x: (element.points.first?.x ?? 0) + 200, 
                            y: (element.points.first?.y ?? 0) + 20
                        )
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}

// MARK: - Preference Keys

/// 【新增】Canvas Frame PreferenceKey - 用于传递 Canvas 在 ZStack 中的位置
struct CanvasFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue()
    }
}
