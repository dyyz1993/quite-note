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

        // 配置字体
        let font = NSFont.systemFont(ofSize: element.fontSize)
        let lineHeight = element.fontSize * 1.3

        // 分割多行文本
        let lines = element.text.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            let y = startPoint.y + CGFloat(index) * lineHeight

            // 创建文本属性
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(element.color)
            ]

            // 计算文本尺寸
            let textSize = (line as NSString).size(withAttributes: attributes)

            // 可选：添加半透明背景提高可读性
            if element.color != .white && element.color != .yellow {
                let bgRect = CGRect(
                    x: startPoint.x - 2,
                    y: y - 2,
                    width: textSize.width + 4,
                    height: textSize.height + 4
                )
                context.fill(Path(roundedRect: bgRect, cornerRadius: 4),
                           with: .color(.black.opacity(0.3)))
            }

            // 绘制文本
            let attributedString = NSAttributedString(string: line, attributes: attributes)
            context.draw(attributedString, at: CGPoint(x: startPoint.x, y: y))
        }
    }

    static func supports(_ tool: AnnotationTool) -> Bool {
        return tool == .text
    }
}
