import SwiftUI

/// 绘图路径（保留用于简单画线）
struct DrawingPath: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var color: Color = .red
    var lineWidth: CGFloat = 4.0
}

/// 主屏幕状态管理器 - 用于动态通知所有视图当前哪个是主屏幕
@MainActor
class V2PrimaryScreenStateManager: ObservableObject {
    static let shared = V2PrimaryScreenStateManager()

    @Published var primaryScreen: NSScreen?

    /// 当前选中的区域（全局共享）
    @Published var selectedArea: CGRect?
    /// 选区所在的屏幕（全局共享）
    @Published var selectionScreen: NSScreen?

    /// 是否处于编辑模式
    @Published var isEditing: Bool = false
    /// 是否处于长图截取模式
    @Published var isLongScreenshotMode: Bool = false
    /// 是否正在执行长图采集 (用于隐藏 UI)
    @Published var isCapturing: Bool = false
    /// 长图截取的实时预览图列表 (这里暂时存图片，实际开发可能存路径或纹理)
    @Published var longScreenshotPreviews: [NSImage] = []

    // MARK: - 完整标注系统状态

    /// 标注元素列表
    @Published var elements: [DrawingElement] = []
    /// 当前正在绘制的元素
    @Published var currentElement: DrawingElement?
    /// 当前选中的工具
    @Published var selectedTool: AnnotationTool = .cursor
    /// 当前选中的颜色
    @Published var selectedColor: Color = .red
    /// 线条宽度
    @Published var lineWidth: CGFloat = 4.0
    /// 字体大小
    @Published var fontSize: CGFloat = 20.0
    
    /// 更新当前工具
    func updateTool(_ tool: AnnotationTool) {
        selectedTool = tool

        // ✨ 切换工具时，如果正在编辑文本，需要先完成编辑
        finishTextEdit()

        // 如果切换到选择工具，默认选中最后一个元素
        if tool == .cursor {
            selectedElementId = elements.last?.id
        } else {
            // 切换到其他工具时，清除选中状态
            selectedElementId = nil
        }
    }
    
    /// 步骤计数器
    @Published var stepCounter: Int = 1
    /// 选中的元素 ID
    @Published var selectedElementId: UUID? = nil
    /// 正在编辑的文本 ID
    @Published var editingTextId: UUID? = nil

    /// 放大镜预览状态（鼠标跟随模式）
    @Published var magnifierPreviewPosition: CGPoint? = nil
    /// 放大镜模式：true=跟随鼠标，false=右上角固定
    @Published var magnifierFollowMouse: Bool = true
    
    /// ✨ 新增：鼠标是否悬停在 UI（工具栏等）上
    @Published var isMouseOverUI: Bool = false

    /// 绘图路径列表（保留兼容，但推荐使用 elements）
    @Published var drawingPaths: [DrawingPath] = []
    
    /// 当前全局悬停的矩形（用于跨屏幕显示唯一黄色线框）
    @Published var globalHoveredRect: CGRect?
    /// 当前全局悬停的窗口标签
    @Published var globalHoveredLabel: String?
    /// 悬停所在的屏幕
    @Published var hoverScreen: NSScreen?

    private init() {}

    /// 重置所有状态
    /// ✨ 修复：确保所有状态都被彻底重置，避免残留状态导致bug
    func reset() {
        primaryScreen = nil
        selectedArea = nil
        selectionScreen = nil
        isEditing = false
        isLongScreenshotMode = false
        isCapturing = false
        longScreenshotPreviews = []
        drawingPaths = []
        globalHoveredRect = nil
        globalHoveredLabel = nil
        hoverScreen = nil

        // ✨ 新增：重置这些状态，避免残留
        magnifierPreviewPosition = nil
        magnifierFollowMouse = true
        isMouseOverUI = false

        // 重置标注系统状态
        elements = []
        currentElement = nil
        selectedTool = .cursor
        selectedColor = .red
        lineWidth = 4.0
        fontSize = 20.0
        stepCounter = 1
        selectedElementId = nil
        editingTextId = nil

        // 关闭文本编辑面板
        closeTextEditPanel()
    }

    /// 更新主屏幕
    func updatePrimaryScreen(_ screen: NSScreen) {
        primaryScreen = screen
    }
    
    /// 更新全局选区
    func updateSelection(_ rect: CGRect?, on screen: NSScreen?) {
        selectedArea = rect
        selectionScreen = screen
    }
    
    /// 切换编辑模式
    func setEditing(_ editing: Bool) {
        isEditing = editing
        if editing {
            isLongScreenshotMode = false
        }
    }
    
    /// 切换长图模式
    func setLongScreenshotMode(_ active: Bool) {
        isLongScreenshotMode = active
        if active {
            isEditing = false
        } else {
            isCapturing = false
        }
    }
    
    /// 切换采集状态
    func setCapturing(_ capturing: Bool) {
        isCapturing = capturing
    }
    
    /// 添加路径
    func addPath(_ path: DrawingPath) {
        drawingPaths.append(path)
    }
    
    /// 清除路径
    func clearPaths() {
        drawingPaths = []
    }
    
    /// 更新全局悬停状态
    func updateHover(_ rect: CGRect?, label: String?, on screen: NSScreen?) {
        globalHoveredRect = rect
        globalHoveredLabel = label
        hoverScreen = screen
    }

    /// 检查指定屏幕是否是主屏幕
    func isPrimary(_ screen: NSScreen) -> Bool {
        return screen == primaryScreen
    }

    // MARK: - 标注系统辅助方法

    /// 添加标注元素
    func addElement(_ element: DrawingElement) {
        elements.append(element)
        if element.tool == .steps {
            stepCounter += 1
        }
    }

    /// 清除所有标注元素
    func clearElements() {
        elements = []
        currentElement = nil
        selectedElementId = nil
        editingTextId = nil
        stepCounter = 1
    }

    /// 撤销最后一个元素
    func undoLastElement() {
        if !elements.isEmpty {
            elements.removeLast()
        }
    }

    /// 删除选中的元素
    func deleteSelectedElement() {
        if let id = selectedElementId {
            elements.removeAll { $0.id == id }
            selectedElementId = nil
        }
    }

    // MARK: - 文本编辑面板管理

    /// 关闭文本编辑面板（面板由 TextEditPanelRepresentable 管理）
    func closeTextEditPanel() {
        editingTextId = nil
    }

    /// ✨ 完成文本编辑：检查空文本并清理
    /// 当用户退出文本编辑时调用，如果文本为空则删除该元素
    func finishTextEdit() {
        guard let editingId = editingTextId else { return }

        // 检查当前编辑的文本是否为空
        if let index = elements.firstIndex(where: { $0.id == editingId }) {
            let element = elements[index]
            if element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // 如果文本为空，移除该元素
                elements.remove(at: index)
            }
        }

        // 清除编辑状态
        editingTextId = nil
    }
}
