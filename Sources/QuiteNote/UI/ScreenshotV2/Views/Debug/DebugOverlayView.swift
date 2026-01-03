import SwiftUI
import OSLog

/// 调试信息叠加层 - 显示屏幕信息、日志、窗口列表
struct V2DebugOverlayView: View {
    let screen: NSScreen
    let screenIndex: Int
    let isCurrentlyPrimary: Bool
    let logEntries: [String]
    let windowsOnScreen: [WindowInfo]
    let currentLayerName: String
    let currentLayerLevel: Int
    let onClose: () -> Void
    let onBack: () -> Void
    let onPanelHover: (Bool) -> Void
    let onCloseButtonHover: (Bool) -> Void

    var body: some View {
        // 1. 屏幕中心提示 (放在底层，且禁止交互)
        Text("SCREEN \(screenIndex)")
            .font(.system(size: V2FontConstants.watermarkSize, weight: .bold))
            .foregroundColor(.white.opacity(V2ColorConstants.watermarkOpacity))
            .allowsHitTesting(false)

        // 2. UI 控制面板
        VStack {
            VStack(alignment: .leading, spacing: 8) {
                headerView
                Divider().background(Color.white.opacity(V2ColorConstants.overlayLineOpacity))
                logsView
                Divider().background(Color.white.opacity(V2ColorConstants.overlayLineOpacity))
                windowsView
            }
            .padding()
            .frame(width: V2LayoutConstants.debugPanelWidth)
            .background(Color.black.opacity(V2ColorConstants.debugBackgroundOpacity))
            .cornerRadius(V2FontConstants.cornerRadiusForPanel)
            .overlay(
                RoundedRectangle(cornerRadius: V2FontConstants.cornerRadiusForPanel)
                    .stroke(Color.yellow.opacity(V2ColorConstants.debugBorderOpacity), lineWidth: 1)
            )
            .foregroundColor(.white)
            .onContinuousHover { phase in
                switch phase {
                case .active(_):
                    onPanelHover(true)
                case .ended:
                    onPanelHover(false)
                }
            }

            Spacer()

            Button(action: { isCurrentlyPrimary ? onBack() : onClose() }) {
                Text(isCurrentlyPrimary ? "Back (ESC)" : "Close (ESC)")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(isCurrentlyPrimary ? .orange : .red)
            .keyboardShortcut(.escape, modifiers: [])
            .onContinuousHover { phase in
                switch phase {
                case .active(_):
                    onCloseButtonHover(true)
                case .ended:
                    onCloseButtonHover(false)
                }
            }
        }
    }

    // MARK: - 子视图

    @ViewBuilder
    private var headerView: some View {
        HStack {
            Image(systemName: "display")
            Text("SCREEN \(screenIndex)")
                .font(.system(size: V2FontConstants.screenTitleSize, weight: .black))

            Spacer()

            activityIndicator
        }
        .foregroundColor(.yellow)

        Text("Bounds: \(Int(screen.frame.width))x\(Int(screen.frame.height)) at (\(Int(screen.frame.minX)),\(Int(screen.frame.minY)))")
            .font(.caption)
    }

    private var activityIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isCurrentlyPrimary ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(isCurrentlyPrimary ? "ACTIVE" : "INACTIVE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isCurrentlyPrimary ? .green : .gray)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.black.opacity(V2ColorConstants.activeStatusOpacity))
        .cornerRadius(V2FontConstants.activeStatusCornerRadius)
    }

    @ViewBuilder
    private var logsView: some View {
        Text("Recent Logs:")
            .font(.caption).bold()
        ForEach(logEntries, id: \.self) { log in
            Text(log)
                .font(.system(size: V2FontConstants.logTextSize, design: .monospaced))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var windowsView: some View {
        Text("Selectable Windows (\(windowsOnScreen.count)):")
            .font(.caption).bold()
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(windowsOnScreen.prefix(5), id: \.id) { win in
                    Text("• \(win.ownerName)")
                        .font(.system(size: V2FontConstants.windowNameSize))
                        .foregroundColor(.white.opacity(V2ColorConstants.windowNameOpacity))
                }
            }
        }
        .frame(height: V2LayoutConstants.windowsListHeight)
    }
}
