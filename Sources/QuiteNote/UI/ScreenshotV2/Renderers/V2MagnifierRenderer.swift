import SwiftUI
import CoreGraphics

/// 放大镜渲染器
struct MagnifierRenderer: ElementRenderer {
    private let scale: CGFloat = 2.0
    
    // ✨ 新增：用于缓存高分辨率图像片段，避免重复计算
    private static var patchCache: [UUID: NSImage] = [:]

    func render(
        element: DrawingElement,
        in context: inout GraphicsContext,
        config: RendererConfig
    ) {
        guard element.points.count >= 1 else { return }
        let start = element.points.first!  // 视觉源点（圆点位置）
        let contentSource = element.magnifierSourcePoint ?? start // 实际放大内容源点

        // 计算放大镜中心位置（右上角固定 + 用户自定义偏移）
        let radius = element.fontSize * 2.5
        let padding: CGFloat = 20
        let defaultEnd = magnifierCenterPosition(in: config, radius: radius, padding: padding)
        
        // 应用偏移量并进行边界约束
        let rawEnd = CGPoint(
            x: defaultEnd.x + element.magnifierOffset.width,
            y: defaultEnd.y + element.magnifierOffset.height
        )
        let end = constrainedMagnifierPosition(rawEnd, radius: radius, in: config)

        drawMagnifier(
            from: start,
            contentSource: contentSource,
            to: end,
            in: &context,
            size: config.canvasSize,
            baseImage: config.baseImage,
            radius: radius,
            scale: element.magnifierScale, // ✨ 使用元素自带的倍率
            color: element.color,
            isPreview: false
        )
    }

    static func supports(_ tool: AnnotationTool) -> Bool {
        return tool == .magnifier
    }

    /// 限制放大镜位置在选区或画布内
    private func constrainedMagnifierPosition(_ position: CGPoint, radius: CGFloat, in config: RendererConfig) -> CGPoint {
        let bounds: CGRect
        if let selection = config.selectionArea {
            bounds = selection
        } else {
            bounds = CGRect(origin: .zero, size: config.canvasSize)
        }
        
        // 确保放大镜圆圈不超出边界
        let minX = bounds.minX + radius
        let maxX = bounds.maxX - radius
        let minY = bounds.minY + radius
        let maxY = bounds.maxY - radius
        
        return CGPoint(
            x: max(minX, min(maxX, position.x)),
            y: max(minY, min(maxY, position.y))
        )
    }

    /// ✨ 计算放大镜中心位置：优先使用选区右上角，否则使用 canvas 右上角
    private func magnifierCenterPosition(in config: RendererConfig, radius: CGFloat, padding: CGFloat) -> CGPoint {
        // 如果有选区，使用选区右上角
        if let selection = config.selectionArea {
            return CGPoint(
                x: selection.maxX - radius - padding,  // ✨ 选区右边界
                y: selection.minY + radius + padding    // ✨ 选区上边界
            )
        }

        // 否则使用 canvas 右上角（降级处理）
        return CGPoint(
            x: config.canvasSize.width - radius - padding,
            y: radius + padding
        )
    }

    /// 预览模式渲染（不显示源点圆圈）
    func drawMagnifierPreview(
        from start: CGPoint,
        contentSource: CGPoint? = nil,
        to end: CGPoint,
        in context: inout GraphicsContext,
        size: CGSize,
        baseImage: NSImage?,
        radius: CGFloat = 60,
        scale: CGFloat = 2.0, // ✨ 新增倍率参数
        color: Color = .white
    ) {
        drawMagnifier(
            from: start,
            contentSource: contentSource ?? start,
            to: end,
            in: &context,
            size: size,
            baseImage: baseImage,
            radius: radius,
            scale: scale, // ✨ 传递倍率
            color: color,
            isPreview: true
        )
    }

    // MARK: - Private Methods

    private func drawMagnifier(
        from start: CGPoint,
        contentSource: CGPoint,
        to end: CGPoint,
        in context: inout GraphicsContext,
        size: CGSize,
        baseImage: NSImage?,
        radius: CGFloat = 60,
        scale: CGFloat = 2.0, // ✨ 允许自定义倍率
        color: Color = .white,
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
            // ✨ 计算连线到圆外径的交点
            let dx = end.x - start.x
            let dy = end.y - start.y
            let dist = hypot(dx, dy)
            
            // 交点 = 中心点 - 单位向量 * 半径
            let edgePoint = CGPoint(
                x: end.x - (dx / dist) * radius,
                y: end.y - (dy / dist) * radius
            )
            
            var linePath = Path()
            linePath.move(to: start)
            linePath.addLine(to: edgePoint)
            let lineOpacity = isPreview ? 0.3 : 0.5
            context.stroke(linePath, with: .color(color.opacity(lineOpacity)), style: StrokeStyle(lineWidth: 1, dash: [4, 2]))
        }

        // 2. 绘制放大镜内容（在源点之前绘制，避免遮挡源点）
        context.drawLayer { layer in
            // 裁剪为圆形
            layer.clip(to: Path(ellipseIn: magnifierRect))

            // ✨ 核心改进：不再缩放整个图层，而是计算源图像的像素区域并直接绘制
            // 这样可以确保我们直接利用 NSImage 内部 CGImage 的原始像素
            if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                // 计算像素级别的坐标
                // ✨ 核心改进：直接使用 cgImage 的真实宽高，不依赖 image.size
                let pixelWidth = CGFloat(cgImage.width)
                let pixelHeight = CGFloat(cgImage.height)
                
                // 采样区域相对于画布尺寸的比例
                let sampleRect = CGRect(
                    x: contentSource.x - radius / scale,
                    y: contentSource.y - radius / scale,
                    width: (radius / scale) * 2,
                    height: (radius / scale) * 2
                )
                
                let scaleX = pixelWidth / size.width
                let scaleY = pixelHeight / size.height
                
                let pixelRect = CGRect(
                    x: sampleRect.origin.x * scaleX,
                    y: sampleRect.origin.y * scaleY,
                    width: sampleRect.width * scaleX,
                    height: sampleRect.height * scaleY
                )
                
                if let cropped = cgImage.cropping(to: pixelRect) {
                    layer.withCGContext { cgContext in
                        // ✨ 使用最高级别的插值
                        cgContext.interpolationQuality = .high
                        cgContext.setShouldAntialias(true)
                        cgContext.setAllowsAntialiasing(true)
                    }
                    // 指定 scale 为 1.0，让系统明白 cropped 就是原始像素
                    layer.draw(Image(decorative: cropped, scale: 1.0, orientation: .up), in: magnifierRect)
                }
            } else {
                // 降级方案：原有的缩放逻辑
                let dx = end.x - contentSource.x * scale
                let dy = end.y - contentSource.y * scale
                layer.translateBy(x: dx, y: dy)
                layer.scaleBy(x: scale, y: scale)
                layer.draw(Image(nsImage: image), in: CGRect(origin: .zero, size: size))
            }
        }

        // 3. 绘制装饰边框
        context.stroke(Path(ellipseIn: magnifierRect), with: .color(color), lineWidth: 3)
        context.stroke(Path(ellipseIn: magnifierRect), with: .color(.gray.opacity(0.3)), lineWidth: 1)

        // 4. 在起始位置画一个小圆点，表示来源（仅固化态显示且源点不在圆圈内）
        if !isPreview && !shouldHideSource {
            context.fill(Path(ellipseIn: CGRect(x: start.x-3, y: start.y-3, width: 6, height: 6)), with: .color(color))
            context.stroke(Path(ellipseIn: CGRect(x: start.x-3, y: start.y-3, width: 6, height: 6)), with: .color(.black.opacity(0.3)), lineWidth: 0.5)
        }
    }
}
