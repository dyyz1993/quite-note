import SwiftUI

/// 形状渲染器 - 处理矩形、圆形、直线
struct ShapeRenderer: ElementRenderer {

    func render(
        element: DrawingElement,
        in context: inout GraphicsContext,
        config: RendererConfig
    ) {
        guard element.points.count >= 2 else { return }

        let start = element.points.first!
        let end = element.points.last!

        switch element.tool {
        case .rectangle:
            renderRectangle(from: start, to: end, element: element, in: &context)
        case .circle:
            renderCircle(from: start, to: end, element: element, in: &context)
        case .line:
            renderLine(from: start, to: end, element: element, in: &context)
        default:
            break
        }
    }

    static func supports(_ tool: AnnotationTool) -> Bool {
        return tool == .rectangle || tool == .circle || tool == .line
    }

    // MARK: - Private Rendering Methods

    private func renderRectangle(
        from start: CGPoint,
        to end: CGPoint,
        element: DrawingElement,
        in context: inout GraphicsContext
    ) {
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
        context.stroke(Path(rect), with: .color(element.color), lineWidth: element.lineWidth)
    }

    private func renderCircle(
        from start: CGPoint,
        to end: CGPoint,
        element: DrawingElement,
        in context: inout GraphicsContext
    ) {
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
        context.stroke(Path(ellipseIn: rect), with: .color(element.color), lineWidth: element.lineWidth)
    }

    private func renderLine(
        from start: CGPoint,
        to end: CGPoint,
        element: DrawingElement,
        in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(element.color), lineWidth: element.lineWidth)
    }
}
