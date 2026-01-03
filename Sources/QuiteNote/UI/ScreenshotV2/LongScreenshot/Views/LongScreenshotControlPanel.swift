import SwiftUI
import AppKit

/// 长截图控制面板
/// 显示开始、停止、完成、取消按钮
class LongScreenshotControlPanel: NSPanel {
    private var onStop: (() -> Void)?

    init(selection: CGRect, screen: NSScreen, onStop: @escaping () -> Void) {
        self.onStop = onStop

        // 计算面板尺寸
        let panelWidth: CGFloat = 200
        let panelHeight: CGFloat = 80

        // 计算面板位置（选区下方）
        let panelX = selection.midX - panelWidth / 2
        let panelY = selection.maxY + 20

        // 确保不超出屏幕边界
        var finalY = panelY
        if panelY + panelHeight > screen.frame.height {
            finalY = selection.minY - panelHeight - 20
        }

        let contentRect = CGRect(x: panelX, y: finalY, width: panelWidth, height: panelHeight)

        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // ⚠️ 关键修复：使用 .floating 而非 .screenSaver + 3
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.ignoresMouseEvents = false
        self.isReleasedWhenClosed = false

        // 创建 SwiftUI 内容
        let contentView = LongScreenshotControlContentView(onStop: onStop)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView
    }

    deinit {
        close()
    }
}

/// 控制面板内容视图
struct LongScreenshotControlContentView: View {
    @ObservedObject var stateManager = V2PrimaryScreenStateManager.shared
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 停止按钮
            Button(action: {
                Task {
                    await LongScreenshotFlowController.shared.stopCapture()
                    onStop()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.circle.fill")
                    Text("停止")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.8))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // 完成按钮
            Button(action: {
                Task {
                    await LongScreenshotFlowController.shared.stopCapture()
                    onStop()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("完成")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.green.opacity(0.8))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // 取消按钮
            Button(action: {
                LongScreenshotFlowController.shared.cancelCapture()
                onStop()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                    Text("取消")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.8))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.6))
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(0.5), radius: 15, x: 0, y: 8)
    }
}
