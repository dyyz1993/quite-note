import SwiftUI

/// 箭头渲染器
struct ArrowRenderer: ElementRenderer {

    func render(
        element: DrawingElement,
        in context: inout GraphicsContext,
        config: RendererConfig
    ) {
        guard element.points.count >= 2 else { return }
        let start = element.points.first!
        let end = element.points.last!

        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(element.color), lineWidth: element.lineWidth)

        // 绘制箭头头部
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLen: CGFloat = 10 + element.lineWidth * 1.5 // 根据线宽动态调整箭头大小
        let arrowPath = Path { p in
            p.move(to: end)
            p.addLine(to: CGPoint(x: end.x - headLen * cos(angle - .pi/6), y: end.y - headLen * sin(angle - .pi/6)))
            p.move(to: end)
            p.addLine(to: CGPoint(x: end.x - headLen * cos(angle + .pi/6), y: end.y - headLen * sin(angle + .pi/6)))
        }
        context.stroke(arrowPath, with: .color(element.color), lineWidth: element.lineWidth)
    }

    static func supports(_ tool: AnnotationTool) -> Bool {
        return tool == .arrow
    }
}
