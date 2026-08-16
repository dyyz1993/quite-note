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

        drawMosaic(in: rect, in: &context, size: config.canvasSize, image: image, intensity: element.fontSize)
    }

    static func supports(_ tool: AnnotationTool) -> Bool {
        return tool == .mosaic
    }

    /// 计算马赛克采样区域在 CGImage 像素坐标系中的裁剪矩形
    /// - Parameters:
    ///   - rect: 画布坐标系（SwiftUI，左上角原点）中的马赛克区域
    ///   - canvasSize: 画布逻辑尺寸
    ///   - scaleX/scaleY: 画布逻辑坐标 → 像素坐标的缩放倍率（Retina 为 2）
    /// - Returns: 供 CGImage.cropping(to:) 使用的像素矩形
    ///
    /// ✅ 修复（TDD 验证）：CGImage.cropping 的坐标系原点在左上角（与
    /// generateFinalImage 的裁剪逻辑一致），Y 轴不做翻转；旧实现按
    /// (canvasHeight - maxY) 翻转导致马赛克从垂直镜像位置取色。
    static func pixelCropRect(for rect: CGRect, canvasSize: CGSize, scaleX: CGFloat, scaleY: CGFloat) -> CGRect {
        return CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
    }

    private func drawMosaic(in rect: CGRect, in context: inout GraphicsContext, size: CGSize, image: NSImage, intensity: CGFloat = 20) {
        let gridSize = max(5, intensity) // 确保格子至少有 5px
        
        context.drawLayer { layer in
            layer.clip(to: Path(rect))

            let imageSize = image.size

            if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                // ✅ 修复（端到端像素测试验证）：缩放倍率必须按 cgImage(forProposedRect:)
                // 实际返回的 CGImage 像素尺寸计算。旧实现读 representations.first?.pixelsWide，
                // 但 NSCGImageSnapshotRep 在 Retina 环境下会报告 2 倍尺寸（与实际返回的
                // CGImage 不一致），导致裁剪矩形超出图像边界被 cropping 钳制为整图，
                // 马赛克采样到的是整屏缩略图而非选区内容。
                let scaleX = imageSize.width > 0 ? CGFloat(cgImage.width) / imageSize.width : 1.0
                let scaleY = imageSize.height > 0 ? CGFloat(cgImage.height) / imageSize.height : 1.0

                let pixelRect = Self.pixelCropRect(
                    for: rect,
                    canvasSize: size,
                    scaleX: scaleX,
                    scaleY: scaleY
                )
                
                if let croppedCGImage = cgImage.cropping(to: pixelRect) {
                    // 💡 关键修复：使用 ceil 向上取整，确保低分辨率上下文足够覆盖整个区域
                    // 即使最后一行/一列格子不完整，也会被包含在内
                    let lowResWidth = max(1, Int(ceil(rect.width / gridSize)))
                    let lowResHeight = max(1, Int(ceil(rect.height / gridSize)))
                    
                    // 创建低分辨率上下文进行采样
                    if let colorSpace = cgImage.colorSpace,
                       let smallContext = CGContext(data: nil,
                                                  width: lowResWidth,
                                                  height: lowResHeight,
                                                  bitsPerComponent: 8,
                                                  bytesPerRow: 0,
                                                  space: colorSpace,
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                        
                        smallContext.interpolationQuality = .none
                        // 将裁剪后的图拉伸填充到整个 lowRes 区域进行平均采样
                        smallContext.draw(croppedCGImage, in: CGRect(x: 0, y: 0, width: CGFloat(lowResWidth), height: CGFloat(lowResHeight)))
                        
                        if let lowResCGImage = smallContext.makeImage(),
                           let dataProvider = lowResCGImage.dataProvider,
                           let data = dataProvider.data,
                           let ptr = CFDataGetBytePtr(data) {
                            
                            let bytesPerPixel = 4
                            let bytesPerRow = lowResCGImage.bytesPerRow
                            
                            for row in 0..<lowResHeight {
                                for col in 0..<lowResWidth {
                                    let offset = row * bytesPerRow + col * bytesPerPixel
                                    
                                    let r = CGFloat(ptr[offset]) / 255.0
                                    let g = CGFloat(ptr[offset + 1]) / 255.0
                                    let b = CGFloat(ptr[offset + 2]) / 255.0
                                    let a = CGFloat(ptr[offset + 3]) / 255.0
                                    
                                    // 💡 计算格子矩形：允许最后一个格子超出 rect，但因为有 layer.clip(to: Path(rect))，
                                    // 所以超出的部分会被自动裁剪掉，从而实现“半个格子”的效果
                                    // ✅ 修复：lowResCGImage 的数据 row 0 对应采样区域的顶部（makeImage 后为 top-down 行序），
                                    // 格子应按 row 顺序自上而下排布；旧实现用 (lowResHeight - 1 - row) 反排，
                                    // 与旧裁剪翻转叠加后整幅马赛克呈垂直镜像
                                    let blockRect = CGRect(
                                        x: rect.minX + CGFloat(col) * gridSize,
                                        y: rect.minY + CGFloat(row) * gridSize,
                                        width: gridSize,
                                        height: gridSize
                                    )
                                    
                                    layer.fill(Path(blockRect), with: .color(Color(red: r, green: g, blue: b).opacity(a)))
                                    layer.stroke(Path(blockRect), with: .color(Color.themeShadowLight), lineWidth: 0.3)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // 绘制选区细边框
        context.stroke(Path(rect), with: .color(.white.opacity(0.4)), lineWidth: 1.2)
    }
}
