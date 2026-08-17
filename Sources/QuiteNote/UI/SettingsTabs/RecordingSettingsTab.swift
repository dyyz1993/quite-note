import SwiftUI

/// 录屏设置标签页：两路音频独立开关（与截图工具栏 ⏺ 旁的 ▾ 快选共用同一存储）
struct RecordingSettingsTab: View {
    @ObservedObject private var prefs = PreferencesManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            audioSection
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("音频", icon: .video)

            settingRow(
                title: "录制系统声音",
                subtitle: "电脑播放的声音（音乐、会议对方声音），免驱动内录，推荐开启",
                isOn: Binding(
                    get: { prefs.recordingSystemAudio },
                    set: { prefs.setRecordingSystemAudio($0) }))

            settingRow(
                title: "录制麦克风",
                subtitle: "录自己的解说（口播）。首次开启需要麦克风权限；会拾到扬声器声音，口播建议只开这一路",
                isOn: Binding(
                    get: { prefs.recordingMicrophone },
                    set: { prefs.setRecordingMicrophone($0) }))

            hintCard("两个开关独立组合：口播=只开麦克风 · 会议解说=都开 · 操作演示=只开系统声 · 都关=无声录制。截图工具栏 ⏺ 旁的 ▾ 可在每次录制前临时切换（会被记住）。")
        }
        .padding(ThemeSpacing.px4.rawValue)
        .background(Color.themeCard)
        .cornerRadius(ThemeRadius.lg.rawValue)
    }

    private func sectionHeader(_ title: String, icon: IconName) -> some View {
        HStack(spacing: ThemeSpacing.px2.rawValue) {
            LucideView(name: icon, size: 16, color: .themeBlue500)
            Text(title)
                .font(.themeH2)
                .foregroundColor(.themeTextPrimary)
        }
    }

    private func settingRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: ThemeSpacing.px3.rawValue) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.themeBody)
                    .foregroundColor(.themeTextPrimary)
                Text(subtitle)
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.vertical, ThemeSpacing.px1.rawValue + 2)
    }

    private func hintCard(_ text: String) -> some View {
        Text(text)
            .font(.themeCaption)
            .foregroundColor(.themeTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(ThemeSpacing.px3.rawValue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ThemeRadius.md.rawValue)
                    .fill(Color.themeBlue500.opacity(0.08))
            )
    }
}
