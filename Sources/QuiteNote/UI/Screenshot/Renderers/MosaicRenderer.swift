import SwiftUI

/// 马赛克渲染器
struct MosaicRenderer: ElementRenderer {

    func render(
        element: DrawingElement,
        in context: inout GraphicsContext,
        config: RendererConfig
    ) {
        guard element.points.count >= 2 else { return }
        guard let image = config.baseImage else { return }

        let start = element.points.first!
        let end = element.points.last!
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x - end.x), height: abs(start.y - end.y))

        drawMosaic(in: rect, in: &context, size: config.canvasSize, image: image, granularity: element.fontSize)
    }

    static func supports(_ tool: AnnotationTool) -> Bool {
        return tool == .mosaic
    }

    private func drawMosaic(in rect: CGRect, in context: inout GraphicsContext, size: CGSize, image: NSImage, granularity: CGFloat = 10) {
        // 真正的马赛克：通过模糊底层图片并叠加像素网格实现
        context.drawLayer { layer in
            layer.clip(to: Path(rect))
            // 1. 绘制模糊后的底层图
            layer.addFilter(.blur(radius: granularity))
            layer.draw(Image(nsImage: image), in: CGRect(origin: .zero, size: size))

            // 2. 叠加像素格感
            let gridSize: CGFloat = granularity
            for x in stride(from: rect.minX, to: rect.maxX, by: gridSize) {
                for y in stride(from: rect.minY, to: rect.maxY, by: gridSize) {
                    let block = CGRect(x: x, y: y, width: gridSize, height: gridSize)
                    layer.stroke(Path(block), with: .color(.black.opacity(0.05)), lineWidth: 0.5)
                }
            }
        }
        context.stroke(Path(rect), with: .color(.white.opacity(0.3)), lineWidth: 1)
    }
}
