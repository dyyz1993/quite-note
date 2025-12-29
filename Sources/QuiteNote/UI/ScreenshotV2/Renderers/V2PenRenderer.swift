import SwiftUI

/// 画笔渲染器
struct PenRenderer: ElementRenderer {

    func render(
        element: DrawingElement,
        in context: inout GraphicsContext,
        config: RendererConfig
    ) {
        guard element.points.count >= 2 else { return }
        let path = Path { p in p.addLines(element.points) }
        context.stroke(path, with: .color(element.color), lineWidth: element.lineWidth)
    }

    static func supports(_ tool: AnnotationTool) -> Bool {
        return tool == .pen
    }
}
