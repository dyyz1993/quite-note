import SwiftUI

/// 步骤标记渲染器
struct StepsRenderer: ElementRenderer {

    func render(
        element: DrawingElement,
        in context: inout GraphicsContext,
        config: RendererConfig
    ) {
        guard let start = element.points.first else { return }
        drawStep(at: start, number: element.stepNumber, in: &context, color: element.color)
    }

    static func supports(_ tool: AnnotationTool) -> Bool {
        return tool == .steps
    }

    private func drawStep(at point: CGPoint, number: Int, in context: inout GraphicsContext, color: Color) {
        let radius: CGFloat = 12
        context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius*2, height: radius*2)), with: .color(color))
        
        // ✨ 使用 draw(Text, at: anchor:) 并设置锚点为中心，确保完美对齐
         // 💡 针对系统字体视觉中心略微下移的问题，手动向上偏移 0.5pt
         context.draw(
             Text("\(number)")
                 .font(.system(size: 14, weight: .bold))
                 .foregroundColor(.white),
             at: CGPoint(x: point.x, y: point.y - 0.5),
             anchor: .center
         )
    }
}
