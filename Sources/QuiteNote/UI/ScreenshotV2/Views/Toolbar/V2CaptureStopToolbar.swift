import SwiftUI

/// 长图采集过程中的停止按钮（位于屏幕顶部，尽量少占空间）
struct V2CaptureStopToolbar: View {
    @ObservedObject var stateManager = V2PrimaryScreenStateManager.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "record.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 14))

            Text("正在采集长图...")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)

            Divider()
                .frame(width: 1, height: 16)
                .background(Color.white.opacity(0.2))

            Button(action: {
                stateManager.setCapturing(false)
                // 不直接退出长图模式，让用户看到预览和主工具栏，可以继续操作或保存
            }) {
                Text("完成采集")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(Capsule())
                Capsule()
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            }
        )
        .shadow(radius: 10)
        .padding(.top, 40) // 避开菜单栏
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
