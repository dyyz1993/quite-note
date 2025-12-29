import SwiftUI
import AppKit

/// V2 选中预览视图 - 显示选中区域/窗口和工具栏
/// 支持拖拽移动和调整尺寸
struct V2SelectionPreviewView: View {
    let screen: NSScreen
    let snapshot: NSImage
    let selectedRect: CGRect  // 初始选中区域的局部坐标
    let onCancel: () -> Void
    let onSave: (CGRect) -> Void  // ⚠️ 修改：传递最终的选中区域

    /// 工具栏安全边距
    private let toolbarMargin: CGFloat = 16

    /// 工具栏高度估算
    private let toolbarHeight: CGFloat = 50

    /// ⚠️ 可编辑的选中区域
    @State private var editableRect: CGRect

    /// 拖拽状态
    @State private var activeHandle: V2CropHandle?
    @State private var dragStartRect: CGRect = .zero
    @State private var dragStartLocation: CGPoint = .zero

    /// 最小尺寸限制
    private let minSize: CGFloat = 20

    init(
        screen: NSScreen,
        snapshot: NSImage,
        selectedRect: CGRect,
        onCancel: @escaping () -> Void,
        onSave: @escaping (CGRect) -> Void
    ) {
        self.screen = screen
        self.snapshot = snapshot
        self.selectedRect = selectedRect
        self.onCancel = onCancel
        self.onSave = onSave
        self._editableRect = State(initialValue: selectedRect)
    }

    /// ⚠️ 智能计算工具栏位置
    private var toolbarPosition: CGPoint {
        let screenWidth = screen.frame.width
        let screenHeight = screen.frame.height

        let belowY = editableRect.maxY + toolbarMargin + toolbarHeight / 2
        let aboveY = editableRect.minY - toolbarMargin - toolbarHeight / 2
        let insideY = editableRect.maxY - toolbarMargin - toolbarHeight / 2

        if belowY <= screenHeight - toolbarMargin {
            return CGPoint(x: editableRect.midX, y: belowY)
        } else if aboveY >= toolbarMargin {
            return CGPoint(x: editableRect.midX, y: aboveY)
        } else if insideY >= editableRect.minY + toolbarMargin {
            return CGPoint(x: editableRect.midX, y: insideY)
        } else {
            return CGPoint(x: screenWidth / 2, y: screenHeight - toolbarMargin - toolbarHeight / 2)
        }
    }

    var body: some View {
        ZStack {
            // 静态截图背景
            Image(nsImage: snapshot)
                .resizable()
                .aspectRatio(contentMode: .fit)

            // 半透明黑色遮罩 (非选中区域)
            Color.black.opacity(0.4)
                .allowsHitTesting(false)
                .mask({
                    ZStack {
                        Rectangle().fill(Color.white)
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: editableRect.width, height: editableRect.height)
                            .position(x: editableRect.midX, y: editableRect.midY)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                })

            // ⚠️ 可交互的选中区域
            interactableSelectionRect
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .background(KeyboardShortcutHandlerView(
            onCancel: onCancel,
            onSave: { handleSave() }
        ))
    }

    /// ⚠️ 可交互的选中区域（支持拖拽和调整）
    private var interactableSelectionRect: some View {
        ZStack {
            // 边框（白色单线）
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: editableRect.width, height: editableRect.height)
                .position(x: editableRect.midX, y: editableRect.midY)
                .allowsHitTesting(false)

            // 尺寸标签
            sizeLabel
                .position(x: editableRect.midX, y: editableRect.minY - 20)
                .allowsHitTesting(false)

            // 八个拖拽手柄
            ForEach(V2CropHandle.allCases, id: \.self) { handle in
                if handle != .center {
                    handleView(for: handle)
                }
            }

            // ⚠️ 工具栏（允许点击）
            V2ToolbarView(
                onSave: { handleSave() },
                onCancel: onCancel
            )
            .position(x: toolbarPosition.x, y: toolbarPosition.y)
            .shadow(radius: 5)
        }
        .contentShape(SelectionInteractionShape(rect: editableRect))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    handleDragChanged(value)
                }
                .onEnded { _ in
                    activeHandle = nil
                }
        )
    }

    /// 尺寸标签
    private var sizeLabel: some View {
        Text("\(Int(editableRect.width)) × \(Int(editableRect.height))")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.7))
            .cornerRadius(4)
    }

    /// 拖拽手柄视图
    @ViewBuilder
    private func handleView(for handle: V2CropHandle) -> some View {
        let pos = handlePosition(for: handle)
        let isActive = activeHandle == handle

        ZStack {
            // 触摸热区（不可见但可点击）
            Circle()
                .fill(Color.clear)
                .frame(width: 24, height: 24)

            // 视觉手柄
            if handle == .topLeft || handle == .topRight || handle == .bottomLeft || handle == .bottomRight {
                // 角落：圆形手柄
                Circle()
                    .fill(isActive ? Color.blue : Color.white)
                    .frame(width: isActive ? 12 : 10, height: isActive ? 12 : 10)
                    .shadow(color: .black.opacity(0.3), radius: 2)
            } else {
                // 边缘：方形手柄
                Rectangle()
                    .fill(isActive ? Color.blue : Color.white)
                    .frame(width: isActive ? 10 : 8, height: isActive ? 10 : 8)
                    .shadow(color: .black.opacity(0.3), radius: 2)
            }
        }
        .position(pos)
        .allowsHitTesting(false)
    }

    /// 处理拖拽变化
    private func handleDragChanged(_ value: DragGesture.Value) {
        if activeHandle == nil {
            activeHandle = getHandle(at: value.startLocation)
            if activeHandle != nil {
                dragStartRect = editableRect
                dragStartLocation = value.startLocation
            }
        }

        guard let handle = activeHandle else { return }

        var newRect = dragStartRect
        let translation = value.translation

        switch handle {
        case .topLeft:
            newRect.origin.x += translation.width
            newRect.origin.y += translation.height
            newRect.size.width -= translation.width
            newRect.size.height -= translation.height
        case .topRight:
            newRect.origin.y += translation.height
            newRect.size.width += translation.width
            newRect.size.height -= translation.height
        case .bottomLeft:
            newRect.origin.x += translation.width
            newRect.size.width -= translation.width
            newRect.size.height += translation.height
        case .bottomRight:
            newRect.size.width += translation.width
            newRect.size.height += translation.height
        case .top:
            newRect.origin.y += translation.height
            newRect.size.height -= translation.height
        case .bottom:
            newRect.size.height += translation.height
        case .left:
            newRect.origin.x += translation.width
            newRect.size.width -= translation.width
        case .right:
            newRect.size.width += translation.width
        case .center:
            newRect.origin.x += translation.width
            newRect.origin.y += translation.height
        }

        // 限制最小尺寸
        if newRect.width < minSize {
            if handle == .topLeft || handle == .bottomLeft || handle == .left {
                newRect.origin.x = dragStartRect.maxX - minSize
            }
            newRect.size.width = minSize
        }
        if newRect.height < minSize {
            if handle == .topLeft || handle == .topRight || handle == .top {
                newRect.origin.y = dragStartRect.maxY - minSize
            }
            newRect.size.height = minSize
        }

        // 限制在屏幕范围内
        let screenBounds = screen.frame
        newRect.origin.x = max(0, min(newRect.origin.x, screenBounds.width - newRect.width))
        newRect.origin.y = max(0, min(newRect.origin.y, screenBounds.height - newRect.height))

        editableRect = newRect
    }

    /// 获取手柄位置
    private func handlePosition(for handle: V2CropHandle) -> CGPoint {
        switch handle {
        case .topLeft: return editableRect.origin
        case .topRight: return CGPoint(x: editableRect.maxX, y: editableRect.minY)
        case .bottomLeft: return CGPoint(x: editableRect.minX, y: editableRect.maxY)
        case .bottomRight: return CGPoint(x: editableRect.maxX, y: editableRect.maxY)
        case .top: return CGPoint(x: editableRect.midX, y: editableRect.minY)
        case .bottom: return CGPoint(x: editableRect.midX, y: editableRect.maxY)
        case .left: return CGPoint(x: editableRect.minX, y: editableRect.midY)
        case .right: return CGPoint(x: editableRect.maxX, y: editableRect.midY)
        case .center: return CGPoint(x: editableRect.midX, y: editableRect.midY)
        }
    }

    /// 检测点击位置对应的手柄
    private func getHandle(at point: CGPoint) -> V2CropHandle? {
        let threshold: CGFloat = 20

        // 检查角落和边缘手柄
        for handle in V2CropHandle.allCases {
            if handle == .center { continue }
            let pos = handlePosition(for: handle)
            if hypot(pos.x - point.x, pos.y - point.y) < threshold {
                return handle
            }
        }

        // 检查中心区域
        if editableRect.contains(point) {
            return V2CropHandle.center
        }

        return nil
    }

    /// 处理保存
    private func handleSave() {
        print("[V2SelectionPreviewView] 保存最终区域: \(editableRect)")
        onSave(editableRect)
    }
}

/// 选中区域交互形状
struct SelectionInteractionShape: Shape {
    let rect: CGRect
    let handleSize: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // 添加八个手柄的热区
        for handle in V2CropHandle.allCases {
            if handle == .center { continue }
            let pos = handlePosition(for: handle)
            path.addEllipse(in: CGRect(
                x: pos.x - handleSize/2,
                y: pos.y - handleSize/2,
                width: handleSize,
                height: handleSize
            ))
        }

        // 添加中心区域的热区
        path.addRect(rect)

        return path
    }

    private func handlePosition(for handle: V2CropHandle) -> CGPoint {
        switch handle {
        case .topLeft: return rect.origin
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .center: return rect.origin
        }
    }
}

// ⚠️ macOS 13 及以下的键盘处理备用方案
struct KeyboardShortcutHandlerView: NSViewRepresentable {
    let onCancel: () -> Void
    let onSave: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyboardHandlerView()
        view.onCancel = onCancel
        view.onSave = onSave
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// 自定义 NSView 用于处理键盘事件
class KeyboardHandlerView: NSView {
    var onCancel: (() -> Void)?
    var onSave: (() -> Void)?
    private var localMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // ESC - 取消
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        // Enter - 保存
        if event.keyCode == 36 {
            onSave?()
            return
        }
        // S - 保存
        if event.charactersIgnoringModifiers == "s" {
            onSave?()
            return
        }
        // V - 粘贴/保存
        if event.charactersIgnoringModifiers == "v" {
            onSave?()
            return
        }
        // 其他按键交给 super 处理
        super.keyDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        // 延迟成为第一响应者（确保窗口已完全加载）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.window?.makeFirstResponder(self)
        }

        // 添加全局键盘监听（作为备用）
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            if event.keyCode == 53 { // ESC
                self.onCancel?()
                return nil
            } else if event.keyCode == 36 { // Enter
                self.onSave?()
                return nil
            } else if event.charactersIgnoringModifiers == "s" {
                self.onSave?()
                return nil
            } else if event.charactersIgnoringModifiers == "v" {
                self.onSave?()
                return nil
            }

            return event
        }
    }

    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

#Preview {
    V2SelectionPreviewView(
        screen: NSScreen.main!,
        snapshot: NSImage(size: NSScreen.main!.frame.size),
        selectedRect: CGRect(x: 100, y: 100, width: 400, height: 300),
        onCancel: { print("取消") },
        onSave: { rect in print("保存: \(rect)") }
    )
}
