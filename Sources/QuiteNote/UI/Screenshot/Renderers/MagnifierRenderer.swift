import SwiftUI

/// 放大镜渲染器
struct MagnifierRenderer: ElementRenderer {
    private let scale: CGFloat = 2.0

    func render(
        element: DrawingElement,
        in context: inout GraphicsContext,
        config: RendererConfig
    ) {
        guard element.points.count >= 1 else { return }
        let start = element.points.first!  // 源点（鼠标位置）

        // 计算放大镜中心位置（右上角固定 + 用户自定义偏移）
        let radius = element.fontSize * 2.5
        let padding: CGFloat = 20
        let defaultEnd = magnifierCenterPosition(in: config.canvasSize, radius: radius, padding: padding)
        let end = CGPoint(
            x: defaultEnd.x + element.magnifierOffset.width,
            y: defaultEnd.y + element.magnifierOffset.height
        )

        print("[DEBUG RENDER] start: \(start), dynamic end: \(end), offset: \(element.magnifierOffset)")

        drawMagnifier(
            from: start,
            to: end,
            in: &context,
            size: config.canvasSize,
            baseImage: config.baseImage,
            radius: radius,
            isPreview: false
        )
    }

    static func supports(_ tool: AnnotationTool) -> Bool {
        return tool == .magnifier
    }

    /// 计算放大镜在 Canvas 右上角的固定位置
    private func magnifierCenterPosition(in canvasSize: CGSize, radius: CGFloat, padding: CGFloat) -> CGPoint {
        return CGPoint(
            x: canvasSize.width - radius - padding,
            y: radius + padding
        )
    }

    /// 预览模式渲染（不显示源点圆圈）
    func drawMagnifierPreview(
        from start: CGPoint,
        to end: CGPoint,
        in context: inout GraphicsContext,
        size: CGSize,
        baseImage: NSImage?,
        radius: CGFloat = 60
    ) {
        drawMagnifier(
            from: start,
            to: end,
            in: &context,
            size: size,
            baseImage: baseImage,
            radius: radius,
            isPreview: true
        )
    }

    // MARK: - Private Methods

    private func drawMagnifier(
        from start: CGPoint,
        to end: CGPoint,
        in context: inout GraphicsContext,
        size: CGSize,
        baseImage: NSImage?,
        radius: CGFloat = 60,
        isPreview: Bool = false
    ) {
        guard let image = baseImage else { return }

        // 放大镜显示的圆圈
        let magnifierRect = CGRect(x: end.x - radius, y: end.y - radius, width: radius * 2, height: radius * 2)

        // 计算源点到放大镜中心的距离
        let distance = hypot(end.x - start.x, end.y - start.y)

        // 如果源点在放大镜圆圈内，则隐藏连线和源点小圆
        let shouldHideSource = distance < radius * 0.8

        // 1. 绘制虚线连接（如果源点不在圆圈内）
        if !shouldHideSource {
            var linePath = Path()
            linePath.move(to: start)
            linePath.addLine(to: end)
            let lineOpacity = isPreview ? 0.3 : 0.5
            context.stroke(linePath, with: .color(.white.opacity(lineOpacity)), style: StrokeStyle(lineWidth: 1, dash: [4, 2]))
        }

        // 2. 绘制放大镜内容（在源点之前绘制，避免遮挡源点）
        context.drawLayer { layer in
            // 裁剪为圆形
            layer.clip(to: Path(ellipseIn: magnifierRect))

            // 绘制放大的图片部分
            let dx = end.x - start.x * scale
            let dy = end.y - start.y * scale

            layer.translateBy(x: dx, y: dy)
            layer.scaleBy(x: scale, y: scale)
            layer.draw(Image(nsImage: image), in: CGRect(origin: .zero, size: size))
        }

        // 3. 绘制装饰边框
        context.stroke(Path(ellipseIn: magnifierRect), with: .color(.white), lineWidth: 3)
        context.stroke(Path(ellipseIn: magnifierRect), with: .color(.gray.opacity(0.3)), lineWidth: 1)

        // 4. 在起始位置画一个小圆点，表示来源（仅固化态显示且源点不在圆圈内）
        if !isPreview && !shouldHideSource {
            context.fill(Path(ellipseIn: CGRect(x: start.x-3, y: start.y-3, width: 6, height: 6)), with: .color(.white))
            context.stroke(Path(ellipseIn: CGRect(x: start.x-3, y: start.y-3, width: 6, height: 6)), with: .color(.black.opacity(0.3)), lineWidth: 0.5)
        }
    }
}
