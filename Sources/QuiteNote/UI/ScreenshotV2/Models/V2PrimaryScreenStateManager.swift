import SwiftUI

/// 主屏幕状态管理器 - 用于动态通知所有视图当前哪个是主屏幕
@MainActor
class V2PrimaryScreenStateManager: ObservableObject {
    static let shared = V2PrimaryScreenStateManager()

    @Published var primaryScreen: NSScreen?

    /// 当前选中的区域（全局共享）
    @Published var selectedArea: CGRect?
    /// 选区所在的屏幕（全局共享）
    @Published var selectionScreen: NSScreen?

    /// 是否处于编辑模式 (由 elements 或 selectedTool 决定)
    var isEditing: Bool {
        !elements.isEmpty || selectedTool != .cursor
    }

    // MARK: - 完整标注系统状态

    /// 标注元素列表
    @Published var elements: [DrawingElement] = []
    /// 当前正在绘制的元素
    @Published var currentElement: DrawingElement?
    /// 当前选中的工具
    @Published var selectedTool: AnnotationTool = .cursor
    /// 当前选中的颜色
    @Published var selectedColor: Color = .red {
        didSet {
            // ✨ 核心需求：如果当前有选中的元素，同步更新其颜色
            if let id = selectedElementId,
               let index = elements.firstIndex(where: { $0.id == id }) {
                elements[index].color = selectedColor
                objectWillChange.send()
            }
        }
    }
    /// 线条宽度
    @Published var lineWidth: CGFloat = 4.0
    /// 字体大小
    @Published var fontSize: CGFloat = 20.0
    /// 放大镜倍率 (1.0 - 5.0)
    @Published var magnifierScale: CGFloat = 2.0 {
        didSet {
            // ✨ 核心需求：如果当前选中了放大镜，同步更新其倍率
            if let id = selectedElementId,
               let index = elements.firstIndex(where: { $0.id == id }),
               elements[index].tool == .magnifier {
                elements[index].magnifierScale = magnifierScale
                objectWillChange.send()
            }
        }
    }
    
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
    
    /// 获取下一个可用的序号（自动补齐空缺）
    func getNextStepNumber() -> Int {
        let existingNumbers = Set(elements.filter { $0.tool == .steps }.map { $0.stepNumber })
        if existingNumbers.isEmpty { return 1 }
        
        // 查找最小的空缺
        var next = 1
        while existingNumbers.contains(next) {
            next += 1
        }
        return next
    }

    /// 选中的元素 ID
    @Published var selectedElementId: UUID? = nil {
        didSet {
            // ✨ 核心需求：选中元素时，同步更新工具栏状态
            if let id = selectedElementId,
               let element = elements.first(where: { $0.id == id }) {
                self.selectedColor = element.color
                self.lineWidth = element.lineWidth
                self.fontSize = element.fontSize
                self.magnifierScale = element.magnifierScale
            }
        }
    }

    /// 放大镜预览状态（鼠标跟随模式）
    @Published var magnifierPreviewPosition: CGPoint? = nil
    /// 放大镜模式：true=跟随鼠标，false=右上角固定
    @Published var magnifierFollowMouse: Bool = true
    
    /// ✨ 新增：鼠标是否悬停在 UI（工具栏等）上
    @Published var isMouseOverUI: Bool = false

    /// ✨ 新增：ESC 键上次按下的时间
    @Published var lastEscKeyPressTime: Date? = nil

    /// ✨ 新增：Toast 消息
    @Published var toastMessage: String? = nil
    @Published var toastType: String = "info"
    
    /// 当前全局悬停的矩形（用于跨屏幕显示唯一黄色线框）
    @Published var globalHoveredRect: CGRect?
    /// 当前全局悬停的窗口标签
    @Published var globalHoveredLabel: String?
    /// 悬停所在的屏幕
    @Published var hoverScreen: NSScreen?

    private init() {}

    /// 发送 Toast 消息
    func postToast(_ message: String, type: String = "info") {
        self.toastMessage = message
        self.toastType = type
        
        // 3秒后自动清除
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.toastMessage == message {
                self.toastMessage = nil
            }
        }
    }

    /// 重置所有状态
    /// ✨ 修复：确保所有状态都被彻底重置，避免残留状态导致bug
    func reset() {
        primaryScreen = nil
        selectedArea = nil
        selectionScreen = nil
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
        magnifierScale = 2.0  // ✅ 新增：重置倍率
        selectedElementId = nil
        lastEscKeyPressTime = nil

        // ✅ 修复（TDD 验证）：Toast 也要重置，否则上一次会话的提示
        // （如"再按一次退出"）会残留到下一次截图界面
        toastMessage = nil
        toastType = "info"
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
        if editing {
            // 如果当前是光标，切换到画笔
            if selectedTool == .cursor {
                updateTool(.pen)
            }
        } else {
            // 退出编辑模式：清空元素并切回光标
            elements = []
            updateTool(.cursor)
        }
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
        guard element.tool != .cursor, !element.points.isEmpty else { return }
        elements.append(element)
        selectedElementId = element.id
    }

    /// 更新元素的粗细/大小 (连续值调节)
    func updateElementSizeContinuous(_ id: UUID, value: CGFloat) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
        let tool = elements[index].tool
        
        if tool == .text || tool == .mosaic || tool == .magnifier {
            elements[index].fontSize = value
        } else {
            elements[index].lineWidth = value
        }
        objectWillChange.send()
    }

    /// 更新元素的粗细/大小 (离散档位调节)
    func updateElementSize(_ id: UUID, level: CGFloat) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
        let tool = elements[index].tool

        // ✅ 修复（TDD 验证）：档位收敛到 1...3，旧实现越界（如 level 0/4）
        // 会直接数组下标越界，导致进程崩溃/挂死
        let clampedLevel = min(3, max(1, Int(level.rounded())))

        if tool == .text || tool == .mosaic || tool == .magnifier {
            let sizes: [CGFloat] = [16, 24, 36]
            elements[index].fontSize = sizes[clampedLevel - 1]
        } else {
            let widths: [CGFloat] = [2, 5, 10]
            elements[index].lineWidth = widths[clampedLevel - 1]
        }
        objectWillChange.send()
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
    }

    /// 撤销最后一个元素
    func undoLastElement() {
        guard !elements.isEmpty else { return }
        let removed = elements.removeLast()
        // ✅ 修复（TDD 验证）：如果被撤销的元素正处于选中态，必须同步清空，
        // 否则 selectedElementId 悬空指向已删除元素，颜色/尺寸同步会静默失效
        if selectedElementId == removed.id {
            selectedElementId = nil
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
