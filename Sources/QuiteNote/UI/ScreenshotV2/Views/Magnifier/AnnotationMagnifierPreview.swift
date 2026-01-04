import SwiftUI

/// 标注放大镜预览组件（编辑模式下显示）
struct AnnotationMagnifierPreview: View {
    let snapshot: NSImage
    let position: CGPoint  // 源点位置（鼠标位置）
    let canvasSize: CGSize
    let followMouse: Bool  // true=跟随鼠标，false=右上角固定
    let selectionArea: CGRect  // ✨ 选区信息
    let currentFontSize: CGFloat // ✨ 当前设置的字号（用于控制放大镜半径）
    let currentScale: CGFloat // ✨ 新增：当前设置的放大倍率
    let color: Color // ✨ 当前选中的颜色

    private var radius: CGFloat { currentFontSize * 2.5 } // 与渲染器保持一致
    private let padding: CGFloat = 20

    var body: some View {
        if followMouse {
            // 模式2：跟随鼠标 - 放大镜在鼠标位置
            magnifierAtMouse
        } else {
            // 模式1：源点-分离 - 源点在鼠标，放大镜在选区右上角
            magnifierAtCorner
        }
    }

    /// 模式2：放大镜跟随鼠标
    private var magnifierAtMouse: some View {
        Canvas { context, size in
            // ✨ 设置高质量插值，确保预览高清
            context.withCGContext { cgContext in
                cgContext.interpolationQuality = .high
                cgContext.setShouldAntialias(true)
                cgContext.setAllowsAntialiasing(true)
            }

            // 边界约束
            let minX = selectionArea.minX + radius
            let maxX = selectionArea.maxX - radius
            let minY = selectionArea.minY + radius
            let maxY = selectionArea.maxY - radius

            let constrainedX = max(minX, min(maxX, position.x))
            let constrainedY = max(minY, min(maxY, position.y))

            let magnifierRect = CGRect(x: constrainedX - radius, y: constrainedY - radius, width: radius * 2, height: radius * 2)

            // 绘制放大的图像
            context.drawLayer { layer in
                layer.clip(to: Path(ellipseIn: magnifierRect))

                // ✨ 核心改进：直接从原始 CGImage 采样像素
                if let cgImage = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    let pixelWidth = CGFloat(cgImage.width)
                    let pixelHeight = CGFloat(cgImage.height)
                    
                    let sampleRect = CGRect(
                        x: position.x - radius / currentScale,
                        y: position.y - radius / currentScale,
                        width: (radius / currentScale) * 2,
                        height: (radius / currentScale) * 2
                    )
                    
                    let scaleX = pixelWidth / canvasSize.width
                    let scaleY = pixelHeight / canvasSize.height
                    
                    let pixelRect = CGRect(
                        x: sampleRect.origin.x * scaleX,
                        y: sampleRect.origin.y * scaleY,
                        width: sampleRect.width * scaleX,
                        height: sampleRect.height * scaleY
                    )
                    
                    if let cropped = cgImage.cropping(to: pixelRect) {
                        layer.withCGContext { cgContext in
                            cgContext.interpolationQuality = .high
                            cgContext.setShouldAntialias(true)
                            cgContext.setAllowsAntialiasing(true)
                        }
                        layer.draw(Image(decorative: cropped, scale: 1.0, orientation: .up), in: magnifierRect)
                    }
                } else {
                    // 降级方案
                    let dx = constrainedX - position.x * currentScale
                    let dy = constrainedY - position.y * currentScale
                    layer.translateBy(x: dx, y: dy)
                    layer.scaleBy(x: currentScale, y: currentScale)
                    layer.draw(Image(nsImage: snapshot), in: CGRect(origin: .zero, size: canvasSize))
                }
            }

            // 绘制边框
            context.stroke(Path(ellipseIn: magnifierRect), with: .color(color), lineWidth: 3)
            context.stroke(Path(ellipseIn: magnifierRect), with: .color(.gray.opacity(0.3)), lineWidth: 1)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    /// 模式1：源点和放大镜分离
    private var magnifierAtCorner: some View {
        Canvas { context, size in
            // ✨ 设置高质量插值，确保预览高清
            context.withCGContext { cgContext in
                cgContext.interpolationQuality = .high
                cgContext.setShouldAntialias(true)
                cgContext.setAllowsAntialiasing(true)
            }

            let corner = magnifierCenter  // ✨ 使用相对于选区的位置
            let magnifierRect = CGRect(x: corner.x - radius, y: corner.y - radius, width: radius * 2, height: radius * 2)

            // 1. 绘制虚线连接（源点 → 放大镜中心）
            var linePath = Path()
            linePath.move(to: position)
            linePath.addLine(to: corner)
            context.stroke(linePath, with: .color(color.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 2]))

            // 2. 绘制源点小圆圈
            let sourceDotRect = CGRect(x: position.x - 3, y: position.y - 3, width: 6, height: 6)
            context.fill(Path(ellipseIn: sourceDotRect), with: .color(color))

            // 3. 绘制放大的图像
            context.drawLayer { layer in
                layer.clip(to: Path(ellipseIn: magnifierRect))

                // ✨ 核心改进：直接从原始 CGImage 采样像素
                if let cgImage = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    let pixelWidth = CGFloat(cgImage.width)
                    let pixelHeight = CGFloat(cgImage.height)
                    
                    let sampleRect = CGRect(
                        x: position.x - radius / currentScale,
                        y: position.y - radius / currentScale,
                        width: (radius / currentScale) * 2,
                        height: (radius / currentScale) * 2
                    )
                    
                    let scaleX = pixelWidth / canvasSize.width
                    let scaleY = pixelHeight / canvasSize.height
                    
                    let pixelRect = CGRect(
                        x: sampleRect.origin.x * scaleX,
                        y: sampleRect.origin.y * scaleY,
                        width: sampleRect.width * scaleX,
                        height: sampleRect.height * scaleY
                    )
                    
                    if let cropped = cgImage.cropping(to: pixelRect) {
                        layer.withCGContext { cgContext in
                            cgContext.interpolationQuality = .high
                            cgContext.setShouldAntialias(true)
                            cgContext.setAllowsAntialiasing(true)
                        }
                        layer.draw(Image(decorative: cropped, scale: 1.0, orientation: .up), in: magnifierRect)
                    }
                } else {
                    // 降级方案
                    let dx = corner.x - position.x * currentScale
                    let dy = corner.y - position.y * currentScale
                    layer.translateBy(x: dx, y: dy)
                    layer.scaleBy(x: currentScale, y: currentScale)
                    layer.draw(Image(nsImage: snapshot), in: CGRect(origin: .zero, size: canvasSize))
                }
            }

            // 4. 绘制边框
            context.stroke(Path(ellipseIn: magnifierRect), with: .color(color), lineWidth: 3)
            context.stroke(Path(ellipseIn: magnifierRect), with: .color(.gray.opacity(0.3)), lineWidth: 1)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    /// ✨ 计算选区右上角位置（而不是整个 canvas 的右上角）
    private var magnifierCenter: CGPoint {
        return CGPoint(
            x: selectionArea.maxX - radius - padding,  // ✨ 相对于选区右边界
            y: selectionArea.minY + radius + padding    // ✨ 相对于选区上边界
        )
    }
}
