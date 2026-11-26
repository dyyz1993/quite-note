import SwiftUI

/// 设置页分区卡片（ClipboardSettingsTab / LauncherSettingsTab / StickyNoteSettingsTab /
/// FeedbackSettingsTab 四处逐字重复的 `section(title:icon:)` 合并而来，视觉不变）：
/// Lucide 图标 + 标题 + 内容，themeCard 底、16pt 内边距、12pt 圆角。
struct SettingsSectionCard<Content: View>: View {
    private let title: String
    private let icon: IconName
    private let content: Content

    init(title: String, icon: IconName, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                LucideView(name: icon, size: 16, color: .themeBlue400)
                Text(title)
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
            }
            content
        }
        .padding(16)
        .background(Color.themeCard)
        .cornerRadius(12)
    }
}
