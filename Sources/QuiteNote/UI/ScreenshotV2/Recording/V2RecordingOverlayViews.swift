import SwiftUI

/// 录制中选区红框：2pt 描边 + REC 呼吸角标；暂停时变黄色虚线 + 「已暂停」角标
/// 面板已被控制器摆在选区外侧 2pt，且内容过滤排除本应用窗口——不会入画
struct V2RecordingBorderView: View {
    /// 观察 controller 以响应暂停态切换
    @ObservedObject var controller: V2RecordingController
    @State private var pulsing = false

    private var paused: Bool { controller.isPaused }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: ThemeRadius.sm.rawValue)
                .stroke(paused ? Color.themeYellow500 : Color.themeRed500,
                        style: StrokeStyle(lineWidth: 2, dash: paused ? [6, 4] : []))

            HStack(spacing: ThemeSpacing.px2.rawValue) {
                if paused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                    Text("已暂停")
                        .font(.themeCaption)
                        .foregroundColor(.white)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                        .opacity(pulsing ? 0.25 : 1.0)
                    Text("REC")
                        .font(.themeCaption)
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, ThemeSpacing.px3.rawValue)
            .padding(.vertical, ThemeSpacing.px1.rawValue + 2)
            .background(
                Capsule().fill((paused ? Color.themeYellow500 : Color.themeRed500).opacity(0.92))
            )
            .offset(y: -26)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: ThemeDuration._500.rawValue).repeatForever()) {
                pulsing = true
            }
        }
    }
}

/// 录制控制条：音频状态 + 计时 + 暂停/停止/取消；收尾时整条切换为「正在保存…」
struct V2RecordingControlBarView: View {
    @ObservedObject var controller: V2RecordingController
    /// 本次会话实际生效的音频配置（启动时快照，录制中不随设置变化）
    let systemAudio: Bool
    let microphone: Bool

    var body: some View {
        HStack(spacing: ThemeSpacing.px3.rawValue) {
            if controller.isFinalizing {
                ProgressView()
                    .controlSize(.small)
                Text("正在保存…")
                    .font(.themeBody)
                    .foregroundColor(.themeTextSecondary)
            } else {
                HStack(spacing: ThemeSpacing.px2.rawValue) {
                    Circle()
                        .fill(controller.isPaused ? Color.themeYellow500 : Color.themeRed500)
                        .frame(width: 8, height: 8)
                        .opacity(controller.isPaused ? 1.0 :
                                    (controller.elapsed.truncatingRemainder(dividingBy: 1.0) < 0.6 ? 1.0 : 0.3))
                    Text(Self.timeString(controller.elapsed))
                        .font(.themeBody.weight(.semibold))
                        .monospacedDigit()
                        .fixedSize()
                        .lineLimit(1)
                        .foregroundColor(controller.isPaused ? .themeYellow500 : .themeTextPrimary)
                }

                // 本次录制的音频源（只读展示，避免录到一半改变行为导致音轨不一致）
                HStack(spacing: ThemeSpacing.px1.rawValue + 2) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundColor(systemAudio ? .themeStatusSuccess : .themeTextTertiary)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11))
                        .foregroundColor(microphone ? .themeStatusSuccess : .themeTextTertiary)
                }
                .help(systemAudio || microphone
                      ? "正在录制：\(systemAudio ? "系统声音" : "")\(systemAudio && microphone ? " + " : "")\(microphone ? "麦克风" : "")"
                      : "无声录制（可在截图工具栏 ⏺ 旁的 ▾ 开启音频）")

                Divider()
                    .frame(height: 18)

                controlButton(label: controller.isPaused ? "继续" : "暂停",
                              icon: controller.isPaused ? "play.fill" : "pause.fill",
                              isPrimary: false,
                              help: controller.isPaused ? "继续录制" : "暂停（成片无暂停痕迹）") {
                    controller.togglePause()
                }
                controlButton(label: "停止",
                              icon: "stop.fill",
                              isPrimary: true,
                              help: "停止并保存") {
                    controller.stop()
                }
                controlButton(label: "取消",
                              icon: "xmark",
                              isPrimary: false,
                              help: "取消（丢弃本次录制）") {
                    controller.cancel()
                }
            }
        }
        .padding(.horizontal, ThemeSpacing.px4.rawValue)
        .padding(.vertical, ThemeSpacing.px2.rawValue + 2)
        .background(
            RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                .fill(Color.themeGray900.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                        .stroke(Color.themeBorderSubtle, lineWidth: 1)
                )
        )
    }

    private func controlButton(label: String, icon: String, isPrimary: Bool,
                               help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: ThemeSpacing.px1.rawValue + 2) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.themeCaption)
                    .fixedSize()
                    .lineLimit(1)
            }
            .foregroundColor(isPrimary ? .white : .themeTextSecondary)
            .padding(.horizontal, ThemeSpacing.px2.rawValue + 2)
            .padding(.vertical, ThemeSpacing.px1.rawValue + 2)
            .background(
                RoundedRectangle(cornerRadius: ThemeRadius.md.rawValue)
                    .fill(isPrimary ? Color.themeRed500 : Color.themeGray700)
            )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private static func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
