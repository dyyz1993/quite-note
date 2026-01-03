import SwiftUI

/// 长截图预览面板视图
/// 显示采集的帧数和实时合成预览
struct LongScreenshotPreviewPanelView: View {
    let selection: CGRect  // ⚠️ 屏幕局部坐标（相对于传入的 screen）
    let screen: NSScreen
    @ObservedObject var stateManager = V2PrimaryScreenStateManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("已采集 \(stateManager.longScreenshotPreviews.count) 帧")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)

            // ✅ 新增：显示当前滚动位置
            if stateManager.longScreenshotPreviews.count > 1 {
                Text("滚动: \(Int(stateManager.currentScrollOffset))px")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }

            // ✅ 优先显示合成预览（宽度增加到 400px，拼接效果更清晰）
            if let compositePreview = stateManager.longScreenshotCompositePreview {
                // 显示合成后的长图预览（可滚动查看）
                GeometryReader { geometry in
                    ZStack {
                        // 原图
                        Image(nsImage: compositePreview)
                            .resizable()
                            .scaledToFit()

                        // ✅ 新增：视口指示器（显示当前可见区域）
                        if stateManager.longScreenshotPreviews.count > 0,
                           let preview = stateManager.longScreenshotPreviews.first {
                            let indicatorHeight = calculateViewportIndicatorHeight(
                                selectionHeight: preview.size.height,
                                compositeHeight: compositePreview.size.height,
                                scrollOffset: stateManager.currentScrollOffset,
                                previewDisplayHeight: 200  // geometry.size.height
                            )

                            let indicatorY = calculateViewportIndicatorY(
                                scrollOffset: stateManager.currentScrollOffset,
                                compositeHeight: compositePreview.size.height,
                                previewDisplayHeight: 200  // geometry.size.height
                            )

                            // 视口指示器框（蓝色半透明）
                            Rectangle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: 376, height: indicatorHeight)
                                .overlay(
                                    Rectangle()
                                        .stroke(Color.blue, lineWidth: 2)
                                )
                                .offset(y: indicatorY - 100)  // 居中校正
                        }
                    }
                    .frame(width: 376, height: 200)  // ✅ 增加尺寸：400-24=376，高度也相应增加
                }
                .cornerRadius(4)
            } else if !stateManager.longScreenshotPreviews.isEmpty {
                // 降级：显示最新帧
                if let latestFrame = stateManager.longScreenshotPreviews.last {
                    Text("合成中...")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Image(nsImage: latestFrame)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 60)
                        .cornerRadius(4)
                }
            } else {
                // 等待状态
                Text("等待采集...")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .frame(width: 400, height: 260)  // ✅ 增加面板尺寸以容纳更大的预览图
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(radius: 10)
    }

    // MARK: - 视口指示器计算辅助方法

    /// 计算视口指示器的高度
    /// - Parameters:
    ///   - selectionHeight: 选区的实际高度（像素）
    ///   - compositeHeight: 合成后图片的总高度
    ///   - scrollOffset: 当前滚动偏移量
    ///   - previewDisplayHeight: 预览面板显示高度
    /// - Returns: 指示器在预览面板中的高度
    private func calculateViewportIndicatorHeight(
        selectionHeight: CGFloat,
        compositeHeight: CGFloat,
        scrollOffset: CGFloat,
        previewDisplayHeight: CGFloat
    ) -> CGFloat {
        // 计算缩放比例（合成图缩放到预览显示尺寸）
        let scale = previewDisplayHeight / compositeHeight

        // 视口指示器高度 = 选区高度 × 缩放比例
        return selectionHeight * scale
    }

    /// 计算视口指示器的 Y 位置
    /// - Parameters:
    ///   - scrollOffset: 当前滚动偏移量
    ///   - compositeHeight: 合成后图片的总高度
    ///   - previewDisplayHeight: 预览面板显示高度
    /// - Returns: 指示器在预览面板中的 Y 位置（相对于中心）
    private func calculateViewportIndicatorY(
        scrollOffset: CGFloat,
        compositeHeight: CGFloat,
        previewDisplayHeight: CGFloat
    ) -> CGFloat {
        // 计算缩放比例
        let scale = previewDisplayHeight / compositeHeight

        // 指示器 Y 位置（从顶部开始）= 滚动偏移 × 缩放比例
        let indicatorYFromTop = scrollOffset * scale

        // 转换为相对于中心的坐标（SwiftUI 坐标系原点在中心）
        return indicatorYFromTop - previewDisplayHeight / 2
    }
}
