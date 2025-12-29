import SwiftUI

/// 文本渲染器
struct TextRenderer: ElementRenderer {

    func render(
        element: DrawingElement,
        in context: inout GraphicsContext,
        config: RendererConfig
    ) {
        guard !element.text.isEmpty else { return }
        guard let start = element.points.first else { return }

        context.draw(
            Text(element.text)
                .font(.system(size: element.fontSize, weight: .bold))
                .foregroundColor(element.color),
            at: start,
            anchor: .topLeading
        )
    }

    static func supports(_ tool: AnnotationTool) -> Bool {
        return tool == .text
    }
}
