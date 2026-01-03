import SwiftUI

/// 文本渲染器 - 将文本元素渲染到 Canvas
struct V2TextRenderer: ElementRenderer {

    func render(
        element: DrawingElement,
        in context: inout GraphicsContext,
        config: RendererConfig
    ) {
        guard !element.text.isEmpty else { return }
        guard let startPoint = element.points.first else { return }

        // 分割多行文本
        let lines = element.text.components(separatedBy: .newlines)
        let lineHeight = element.fontSize * 1.3

        for (index, line) in lines.enumerated() {
            let y = startPoint.y + CGFloat(index) * lineHeight
            
            let text = Text(line)
                .font(.system(size: element.fontSize, weight: .medium))
                .foregroundColor(element.color)

            // ✨ 修复对齐：x + 8 (padding.horizontal), y + 6 (padding.vertical)
            // 确保 Canvas 渲染位置与 AnnotationTextEditorView 的 Text 层完全重合
            context.draw(text, at: CGPoint(x: startPoint.x + 8, y: y + 6), anchor: .topLeading)
        }
    }

    static func supports(_ tool: AnnotationTool) -> Bool {
        return tool == .text
    }
}
