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

    /// ✨ 新增：长截图实时合成预览（用于预览面板显示拼接后的效果）
    @Published var longScreenshotCompositePreview: NSImage?

    /// ✨ 新增：当前滚动偏移量（用于在预览面板上显示视口指示器）
    @Published var currentScrollOffset: CGFloat = 0

    /// ✨ 新增：选区高度（用于计算视口指示器的高度）
    @Published var longScreenshotSelectionHeight: CGFloat = 0

    /// ✨ 新增：每帧的滚动位置记录（用于精确的滚回引导）
    /// Key: 帧索引, Value: 滚动偏移量（像素）
    @Published var frameScrollPositions: [Int: CGFloat] = [:]

    // ✨ 新增：质量监控相关状态（已移除拼接功能）

    /// 是否显示质量警告面板（已移除）
    @Published var showQualityWarning: Bool = false

    // ✨ 新增：视觉引导相关状态

    /// 是否显示滚回引导
    @Published var isShowingScrollBackGuide: Bool = false

    /// 引导目标帧索引
    @Published var guideTargetFrameIndex: Int = 0

    /// 引导目标滚动偏移
    @Published var guideTargetScrollOffset: CGFloat = 0

    /// 引导滚动方向
    @Published var guideScrollDirection: ScrollDirection = .up

    /// 引导距离目标的像素距离
    @Published var guideDistanceToTarget: CGFloat = 0

    // ✨ 新增：像素检测相关状态

    /// 上一次检测到的变化百分比（用于 UI 显示）
    @Published var lastChangePercentage: CGFloat = 0

    /// 像素检测是否启用
    @Published var pixelDetectionEnabled: Bool = true

    /// 检测到的静止帧数（连续未达到阈值的帧数）
    @Published var staticFrameCount: Int = 0

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
        longScreenshotCompositePreview = nil  // ✅ 新增：清除合成预览
        currentScrollOffset = 0  // ✅ 新增：清除滚动偏移
        longScreenshotSelectionHeight = 0  // ✅ 新增：清除选区高度
        frameScrollPositions = [:]  // ✅ 新增：清除帧滚动位置记录
        lastChangePercentage = 0  // ✅ 新增：清除像素变化百分比
        pixelDetectionEnabled = true  // ✅ 新增：重置像素检测启用状态
        staticFrameCount = 0  // ✅ 新增：清除静止帧计数
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
        selectedElementId = element.id
        
        // 如果是步骤工具，增加计数器
        if element.tool == .steps {
            stepCounter += 1
        }
    }

    /// 更新元素的文本
    func updateElementText(id: UUID, text: String) {
        if let index = elements.firstIndex(where: { $0.id == id }) {
            elements[index].text = text
        }
    }

    /// 清除所有标注元素
    func clearElements() {
        elements = []
        currentElement = nil
        selectedElementId = nil
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
}
