import SwiftUI

/// 录制前准备提示：只显示在选区中心，不会进入实际录制内容
struct V2RecordingCountdownView: View {
    @ObservedObject var controller: V2RecordingController

    var body: some View {
        VStack(spacing: 4) {
            Text("准备录制")
                .font(.themeCaption)
                .foregroundColor(.themeTextSecondary)
            Text("\(controller.countdownRemaining ?? 0)")
                .font(.themeH1.monospacedDigit())
                .foregroundColor(.themeTextPrimary)
            Text("切换到需要演示的画面")
                .font(.themeCaptionSmall)
                .foregroundColor(.themeTextTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                .fill(Color.themeGray900.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                        .stroke(Color.themeBlue500.opacity(0.7), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 18)
    }
}

/// 录制中选区红框：红色虚线 + REC 呼吸角标；暂停时变黄色虚线 + 「已暂停」角标
/// 面板已被控制器摆在选区外侧 2pt，且内容过滤排除本应用窗口——不会入画
struct V2RecordingBorderView: View {
    /// 观察 controller 以响应暂停态切换
    @ObservedObject var controller: V2RecordingController
    @State private var pulsing = false

    private var paused: Bool { controller.isPaused }

    var body: some View {
        ZStack(alignment: .topLeading) {
            let dash: [CGFloat] = paused ? [6, 4] : [8, 5]
            RoundedRectangle(cornerRadius: ThemeRadius.sm.rawValue)
                .stroke(paused ? Color.themeYellow500 : Color.themeRed500,
                        style: StrokeStyle(lineWidth: 2, dash: dash, dashPhase: pulsing ? 0 : 3))

            HStack(spacing: ThemeSpacing.px2.rawValue) {
                if paused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                    Text("已暂停")
                        .font(.themeCaption)
                        .foregroundColor(.white)
                } else if controller.isStarting {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                    Text("准备中")
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

/// 录制控制条：音频来源 + 电平 + 计时 + 暂停/停止/取消；收尾时整条切换为「正在保存…」
struct V2RecordingControlBarView: View {
    @ObservedObject var controller: V2RecordingController

    var body: some View {
        HStack(spacing: ThemeSpacing.px3.rawValue) {
            if controller.isFinalizing {
                ProgressView()
                    .controlSize(.small)
                Text("正在保存…")
                    .font(.themeBody)
                    .foregroundColor(.themeTextSecondary)
            } else {
                statusView

                // 本次录制的音频源 + 实时电平（说话/放音乐时柱子随音量起伏）
                HStack(spacing: ThemeSpacing.px2.rawValue) {
                    AudioLevelMeter(systemImage: "speaker.wave.2.fill",
                                    level: controller.systemAudioLevel,
                                    active: controller.pendingSystemAudio,
                                    color: .themeBlue400)
                    AudioLevelMeter(systemImage: "mic.fill",
                                    level: controller.micLevel,
                                    active: controller.pendingMicrophone,
                                    color: .themePurple400)
                }

                audioToggleButton(icon: "speaker.wave.2.fill", title: "电脑声",
                                  isOn: controller.pendingSystemAudio,
                                  action: { controller.setPendingSystemAudio(!controller.pendingSystemAudio) })
                audioToggleButton(icon: "mic.fill", title: "麦克风",
                                  isOn: controller.pendingMicrophone,
                                  action: { controller.setPendingMicrophone(!controller.pendingMicrophone) })

                Divider()
                    .frame(height: 18)

                if controller.isStarting {
                    Text("起流前可切换")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                        .fixedSize()
                } else {
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

    private var statusView: some View {
        HStack(spacing: ThemeSpacing.px2.rawValue) {
            Circle()
                .fill(controller.isStarting ? Color.themeRed500 :
                        (controller.isPaused ? Color.themeYellow500 : Color.themeRed500))
                .frame(width: 8, height: 8)
                .opacity(controller.isStarting || controller.isPaused ? 1.0 :
                            (controller.elapsed.truncatingRemainder(dividingBy: 1.0) < 0.6 ? 1.0 : 0.3))
            Text(controller.isStarting ? "准备录制…" : Self.timeString(controller.elapsed))
                .font(.themeBody.weight(.semibold))
                .monospacedDigit()
                .fixedSize()
                .lineLimit(1)
                .foregroundColor(controller.isPaused ? .themeYellow500 : .themeTextPrimary)
        }
    }

    private func audioToggleButton(icon: String, title: String, isOn: Bool,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.themeCaptionSmall)
                    .fixedSize()
            }
            .foregroundColor(isOn ? .white : .themeTextTertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: ThemeRadius.sm.rawValue)
                    .fill(isOn ? Color.themeBlue600.opacity(0.9) : Color.themeGray700)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ThemeRadius.sm.rawValue)
                    .stroke(isOn ? Color.themeBlue400 : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!controller.isStarting)
        .opacity(controller.isStarting ? 1 : 0.72)
        .help(controller.isStarting ? "切换\(title)录制" : "本次录制音源已锁定")
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

/// 音频电平表：图标 + 三根灵敏度递增的电平柱（说话/放音乐时实时起伏）
struct AudioLevelMeter: View {
    let systemImage: String
    let level: Float
    let active: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundColor(active ? color : .themeTextTertiary)

            if active {
                HStack(spacing: 1.5) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(color)
                            .frame(width: 2.5, height: barHeight(i))
                    }
                }
                .frame(height: 16, alignment: .bottom)
                .animation(.linear(duration: 0.08), value: level)
            }
        }
        .help(active ? "实时电平（录制中）" : "未开启此音源")
    }

    /// 三根柱子不同阈值/跨度：第一根很轻就动，第三根要很响才满
    private func barHeight(_ index: Int) -> CGFloat {
        let thresholds: [Float] = [0.04, 0.22, 0.5]
        let spans: [Float] = [0.28, 0.4, 0.5]
        let value = max(0, min(1, (level - thresholds[index]) / spans[index]))
        return 3 + CGFloat(value) * 13
    }
}
