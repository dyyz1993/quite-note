import SwiftUI

/// 标注工具组，用于在工具栏中进行分组显示
enum AnnotationToolGroup: String, CaseIterable {
    case select = "mouse-pointer-2"
    case shape = "square"
    case line = "minus"
    case draw = "pen-tool"
    case effect = "grid-3x3"
}

/// 具体的标注工具
enum AnnotationTool: String, CaseIterable {
    case cursor = "mouse-pointer-2"
    case rectangle = "square"
    case circle = "circle"
    case arrow = "arrow-up-right"
    case line = "minus"
    case pen = "pen-tool"
    case mosaic = "grid-3x3"
    case spotlight = "focus"
    case magnifier = "search"
    case steps = "hash"

    /// 获取所属的工具组
    var group: AnnotationToolGroup {
        switch self {
        case .cursor: return .select
        case .rectangle, .circle: return .shape
        case .arrow, .line: return .line
        case .pen: return .draw
        case .mosaic, .spotlight, .magnifier, .steps: return .effect
        }
    }

    /// 是否支持颜色选择
    var supportsColor: Bool {
        switch self {
        case .cursor, .mosaic, .spotlight, .magnifier:
            return false
        case .rectangle, .circle, .arrow, .line, .pen, .steps:
            return true
        }
    }
}

/// 工具记忆管理
class AnnotationSettings {
    static let shared = AnnotationSettings()

    @AppStorage("lastSelectedTool_select") private var lastSelect = AnnotationTool.cursor.rawValue
    @AppStorage("lastSelectedTool_shape") private var lastShape = AnnotationTool.rectangle.rawValue
    @AppStorage("lastSelectedTool_line") private var lastLine = AnnotationTool.arrow.rawValue
    @AppStorage("lastSelectedTool_draw") private var lastDraw = AnnotationTool.pen.rawValue
    @AppStorage("lastSelectedTool_effect") private var lastEffect = AnnotationTool.mosaic.rawValue

    func setLastTool(_ tool: AnnotationTool) {
        switch tool.group {
        case .select: lastSelect = tool.rawValue
        case .shape: lastShape = tool.rawValue
        case .line: lastLine = tool.rawValue
        case .draw: lastDraw = tool.rawValue
        case .effect: lastEffect = tool.rawValue
        }
    }

    func getLastTool(for group: AnnotationToolGroup) -> AnnotationTool {
        let rawValue: String
        switch group {
        case .select: rawValue = lastSelect
        case .shape: rawValue = lastShape
        case .line: rawValue = lastLine
        case .draw: rawValue = lastDraw
        case .effect: rawValue = lastEffect
        }
        return AnnotationTool(rawValue: rawValue) ?? defaultTool(for: group)
    }

    private func defaultTool(for group: AnnotationToolGroup) -> AnnotationTool {
        switch group {
        case .select: return .cursor
        case .shape: return .rectangle
        case .line: return .arrow
        case .draw: return .pen
        case .effect: return .mosaic
        }
    }
}

/// 绘图元素模型
struct DrawingElement: Identifiable {
    let id = UUID()
    var tool: AnnotationTool
    var points: [CGPoint]
    var color: Color
    var lineWidth: CGFloat
    var text: String = ""
    var fontSize: CGFloat = 20
    var stepNumber: Int = 1
    var magnifierOffset: CGSize = .zero  // 放大镜显示位置的偏移量
    var magnifierSourcePoint: CGPoint? = nil // 放大镜实际放大的源点（内容锁定位置）
}

/// 裁剪框调整手柄
enum CropHandle: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
    case top, bottom, left, right
    case center
}
