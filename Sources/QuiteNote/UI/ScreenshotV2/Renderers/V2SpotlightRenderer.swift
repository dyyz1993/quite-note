import SwiftUI

/// 聚光灯渲染器
struct SpotlightRenderer: ElementRenderer {

    func render(
        element: DrawingElement,
        in context: inout GraphicsContext,
        config: RendererConfig
    ) {
        guard element.points.count >= 2 else { return }
        guard let start = element.points.first, let last = element.points.last else { return }

        let rect = CGRect(x: min(start.x, last.x), y: min(start.y, last.y), width: abs(start.x - last.x), height: abs(start.y - last.y))
        context.stroke(Path(ellipseIn: rect), with: .color(element.color.opacity(0.3)), lineWidth: 1)
    }

    static func supports(_ tool: AnnotationTool) -> Bool {
        return tool == .spotlight
    }
}
