import SwiftUI

struct V2CaptureStopToolbarView: View {
    let onFinish: () -> Void
    @ObservedObject var stateManager = V2PrimaryScreenStateManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 顶部：状态指示
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(stateManager.isCapturing ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.8).repeatForever(), value: stateManager.isCapturing)

                Text("长图预览")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.bottom, 4)

            // 中间：滚动预览区域 (高度自适应)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 2) {
                    if stateManager.longScreenshotPreviews.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "scroll.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white.opacity(0.15))
                            Text("向下滚动网页\n实时拼接图片")
                                .font(.system(size: 11))
                                .multilineTextAlignment(.center)
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .frame(height: 300)
                    } else {
                        ForEach(0..<stateManager.longScreenshotPreviews.count, id: \.self) { index in
                            Image(nsImage: stateManager.longScreenshotPreviews[index])
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(6)
            }
            .background(Color.black.opacity(0.2))
            .cornerRadius(8)
            .frame(maxHeight: .infinity)

            Divider()
                .background(Color.white.opacity(0.1))

            // 底部：操作按钮
            Button(action: onFinish) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("完成并保存")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.green)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
    }
}
