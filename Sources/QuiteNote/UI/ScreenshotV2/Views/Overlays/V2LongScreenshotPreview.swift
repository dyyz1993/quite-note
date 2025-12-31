import SwiftUI

/// 长图滚动预览内容组件
struct V2LongScreenshotPreviewContent: View {
    @ObservedObject var stateManager = V2PrimaryScreenStateManager.shared
    var width: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("长图预览")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 4)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 2) {
                    if stateManager.longScreenshotPreviews.isEmpty {
                        // 空状态
                        VStack(spacing: 8) {
                            Image(systemName: "scroll.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.2))
                            Text("等待滚动...")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .frame(height: 120)
                    } else {
                        // 渲染实时采集的图片块
                        ForEach(0..<stateManager.longScreenshotPreviews.count, id: \.self) { index in
                            Image(nsImage: stateManager.longScreenshotPreviews[index])
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(2)
                        }
                    }
                }
                .padding(4)
            }
            .background(Color.black.opacity(0.2))
            .cornerRadius(6)
            .frame(height: 200) // 限制预览高度
        }
        .frame(width: width)
    }
}

/// 长图滚动预览组件 (旧版，保留定位逻辑用于主视图显示)
struct V2LongScreenshotPreview: View {
    let selection: CGRect
    let screen: NSScreen
    @ObservedObject var stateManager = V2PrimaryScreenStateManager.shared

    var body: some View {
        V2LongScreenshotPreviewContent()
            .padding(12)
            .background(
                ZStack {
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                }
            )
            .shadow(color: .black.opacity(0.5), radius: 10)
            .position(calculatePosition())
            .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func calculatePosition() -> CGPoint {
        // 放在选区右侧，如果空间不够则放在左侧
        let spacing: CGFloat = 20
        let previewWidth: CGFloat = 160

        var x = selection.maxX + previewWidth/2 + spacing
        if x > screen.frame.width - 20 {
            x = selection.minX - previewWidth/2 - spacing
        }

        return CGPoint(x: x, y: selection.midY)
    }
}
