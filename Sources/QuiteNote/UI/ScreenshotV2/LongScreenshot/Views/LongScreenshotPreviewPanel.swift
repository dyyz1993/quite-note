import SwiftUI
import AppKit

/// 长截图预览面板
/// 显示已采集的帧数和预览
class LongScreenshotPreviewPanel: NSPanel {
    init(selection: CGRect, screen: NSScreen) {
        // 计算面板尺寸
        let panelWidth: CGFloat = 180
        let panelHeight: CGFloat = 300
        let spacing: CGFloat = 20

        // ✨ 智能位置计算：优先右侧，其次左侧，最后内部
        var panelX: CGFloat = selection.maxX + spacing
        var panelY: CGFloat = selection.minY

        // 1. 尝试放在选区右侧
        if panelX + panelWidth > screen.frame.width {
            // 2. 右侧空间不足，尝试左侧
            panelX = selection.minX - panelWidth - spacing
            if panelX < 0 {
                // 3. 左侧也不足，放在选区内部右侧
                panelX = selection.maxX - panelWidth - 10
                if panelX < selection.minX {
                    // 4. 选区太窄，放在选区内部左侧
                    panelX = selection.minX + 10
                }
            }
        }

        // 确保不超出水平边界
        if panelX < 0 { panelX = 10 }
        if panelX + panelWidth > screen.frame.width {
            panelX = screen.frame.width - panelWidth - 10
        }

        // 垂直位置：与选区顶部对齐，如果超出底部则向上调整
        if panelY + panelHeight > screen.frame.height {
            panelY = screen.frame.height - panelHeight - 10
        }
        if panelY < 10 {
            panelY = 10
        }

        let contentRect = CGRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)

        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // ⚠️ 关键修复：使用 .floating 而非 .screenSaver + 2
        // .floating 在长截图模式下不会阻挡滚动事件穿透到底层应用
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.ignoresMouseEvents = false  // 面板本身可交互（如关闭按钮）
        self.isReleasedWhenClosed = false

        // 创建 SwiftUI 内容
        let contentView = LongScreenshotPreviewContentView()
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView
    }

    deinit {
        close()
    }
}

/// 预览面板内容视图
struct LongScreenshotPreviewContentView: View {
    @ObservedObject var stateManager = V2PrimaryScreenStateManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundColor(.green)
                Text("长图预览")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }

            Divider()
                .background(Color.white.opacity(0.2))

            // 帧数统计
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("已采集帧数:")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text("\(stateManager.longScreenshotPreviews.count)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.green)
                }

                if stateManager.isCapturing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("采集中...")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.2))

            // 预览缩略图（只显示最新的几帧）
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(stateManager.longScreenshotPreviews.enumerated().reversed()), id: \.offset) { index, image in
                        HStack {
                            Text("#\(stateManager.longScreenshotPreviews.count - index)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: 30)

                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 60)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(4)
                        }
                    }
                }
            }

            // 提示信息
            if stateManager.longScreenshotPreviews.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.4))
                    Text("在选区内滚动")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                    Text("自动捕获")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .padding(16)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.5))
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
        .frame(width: 180, height: 300)
    }
}
