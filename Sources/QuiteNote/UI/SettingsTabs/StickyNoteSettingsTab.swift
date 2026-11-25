import SwiftUI
import AppKit
import Combine

/// 设置 → 便利贴（快捷键配置 + 冲突提示 + 默认底色 + 使用说明）
///
/// 本 Tab 的偏好全部即时写入（与启动器 Tab 同款），footer 不放保存按钮。
/// 新增 section 的做法：写一个 `private var xxxSection: some View`（照 `section(title:icon:)` 的卡片样式），
/// 再加进 `body` 的列表；文案一律 `L("sticky.settings.*", fallback:)` 并补两份 Localizable.strings。
struct StickyNoteSettingsTab: View {
    @ObservedObject private var prefs = PreferencesManager.shared

    /// 冲突状态轮询（偏好变化 → MainApp 延迟 0.1s refresh 后才更新冲突标志，模式同启动器 Tab）
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    /// 轮询到点的本地重绘触发器。⚠️ 不要用 prefs.objectWillChange.send() 触发重绘——
    /// 那会连带触发 MainApp 的 shortcuts.refresh()（启动器 Tab 实锤过）
    @State private var conflictPollTick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            shortcutSection
            defaultColorSection
            usageSection
        }
        .onReceive(timer) { _ in
            conflictPollTick += 1
        }
    }

    // MARK: - 快捷键

    /// 依赖 conflictPollTick：轮询到点触发 body 重算，读到最新的静态冲突标志
    private var stickyNoteConflict: Bool {
        _ = conflictPollTick
        return KeyboardShortcutManager.stickyNoteShortcutConflict
    }

    private var stickySpacePinConflict: Bool {
        _ = conflictPollTick
        return KeyboardShortcutManager.stickySpacePinShortcutConflict
    }

    private var shortcutSection: some View {
        section(title: L("sticky.settings.shortcut.title", fallback: "快捷键"), icon: .keyboard) {
            VStack(alignment: .leading, spacing: 16) {
                StickyShortcutRow(
                    title: L("sticky.settings.shortcut.newNote", fallback: "新建便利贴"),
                    key: Binding(get: { prefs.stickyNoteShortcut },
                                 set: { prefs.setStickyNoteShortcut($0) }),
                    flags: Binding(get: { prefs.stickyNoteShortcutFlags },
                                   set: { prefs.setStickyNoteShortcutFlags($0) }),
                    defaultKey: PreferencesManager.defaultStickyNoteShortcut,
                    defaultFlags: PreferencesManager.defaultStickyNoteShortcutFlags,
                    conflict: stickyNoteConflict
                )
                StickyShortcutRow(
                    title: L("sticky.settings.shortcut.spacePin", fallback: "固定到所有 Space"),
                    key: Binding(get: { prefs.stickySpacePinShortcut },
                                 set: { prefs.setStickySpacePinShortcut($0) }),
                    flags: Binding(get: { prefs.stickySpacePinShortcutFlags },
                                   set: { prefs.setStickySpacePinShortcutFlags($0) }),
                    defaultKey: PreferencesManager.defaultStickySpacePinShortcut,
                    defaultFlags: PreferencesManager.defaultStickySpacePinShortcutFlags,
                    conflict: stickySpacePinConflict
                )

                Text(L("sticky.settings.shortcut.hint", fallback: "默认：新建便利贴 ⌥⇧⌘N，固定到所有 Space ⌥⌘P。固定只作用于当前正在编辑的那张便利贴；清除快捷键后仍可从状态栏菜单新建便利贴。旧版新建快捷键 ⌘⇧N 会抢走 Finder 的「新建文件夹」，所以换了默认值。"))
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
            }
        }
    }

    /// footer 左侧的状态摘要（SettingsOverlayView 调用）：两个热键当前的展示串，禁用时标「已禁用」
    static func footerStatusLines() -> [String] {
        let prefs = PreferencesManager.shared
        let newNote = KeyboardShortcutManager.hotkeyRegistration(
            key: prefs.stickyNoteShortcut, flags: prefs.stickyNoteShortcutFlags)
        let spacePin = KeyboardShortcutManager.hotkeyRegistration(
            key: prefs.stickySpacePinShortcut, flags: prefs.stickySpacePinShortcutFlags)
        let disabled = L("sticky.settings.shortcut.disabled", fallback: "已禁用")
        let spaceLabel = L("sticky.settings.shortcut.space", fallback: "空格")
        func line(_ title: String, _ registration: HotkeyRegistration) -> String {
            let value = registration.isEnabled ? registration.displayString(spaceLabel: spaceLabel) : disabled
            return "\(title): \(value)"
        }
        return [
            line(L("sticky.settings.shortcut.newNote", fallback: "新建便利贴"), newNote),
            line(L("sticky.settings.shortcut.spacePin", fallback: "固定到所有 Space"), spacePin),
        ]
    }

    // MARK: - 默认颜色

    /// 新建便利贴用的底色。深色系柔和色，明度一致，正文始终是白色（对比度见 StickyNoteColorTests）
    private var defaultColorSection: some View {
        section(title: L("sticky.settings.color.title", fallback: "默认颜色"), icon: .palette) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ForEach(StickyNoteColor.allCases) { color in
                        let selected = color == StickyNoteColor.from(prefs.stickyNoteDefaultColor)
                        Button {
                            prefs.setStickyNoteDefaultColor(color)
                        } label: {
                            VStack(spacing: 4) {
                                // 色环同款色块（外环标识色 + 内芯真实底色）：只画底色的话六个深色圆点
                                // 在深色卡片上分不清。选中标记画在色块外面一圈，不和外环抢位置
                                StickyNoteColorRing(color: color, diameter: 22)
                                    .background(
                                        Circle().stroke(Color.themeBlue400, lineWidth: 2)
                                            .padding(-4)
                                            .opacity(selected ? 1 : 0)
                                    )
                                Text(color.name)
                                    .font(.themeCaptionSmall)
                                    .foregroundColor(selected ? .themeTextPrimary : .themeTextTertiary)
                            }
                            .frame(width: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .help(color.name)
                    }
                }

                Text(L("sticky.settings.color.hint", fallback: "新建便利贴时用的底色。已有便利贴点工具栏里的底色色块单独改；保存到记录后，记录卡片上会有同色标识"))
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
            }
        }
    }

    // MARK: - 使用说明

    private var usageSection: some View {
        section(title: L("sticky.settings.usage.title", fallback: "使用说明"), icon: .scroll) {
            VStack(alignment: .leading, spacing: 10) {
                explanationRow(L("sticky.settings.usage.hover", fallback: "鼠标悬停"),
                               L("sticky.settings.usage.hover.detail", fallback: "鼠标移到便利贴上即可直接输入，无需先点击"))
                explanationRow(L("sticky.settings.usage.toolbar", fallback: "底部工具栏"),
                               L("sticky.settings.usage.toolbar.detail", fallback: "便利贴聚焦时显示：待办、加粗、删除线、符号、颜色，右侧是页码切换"))
                explanationRow(L("sticky.settings.usage.save", fallback: "保存到记录"),
                               L("sticky.settings.usage.save.detail", fallback: "点工具栏的同步图标：首次点击保存为新记录，图标变绿后再点即「更新记录」"))

                markupRow(L("sticky.settings.usage.todo", fallback: "待办"),
                          L("sticky.settings.usage.todo.syntax", fallback: "- [ ] 文本"),
                          L("sticky.settings.usage.todo.note", fallback: "自动显示为方框，点方框勾选"))
                markupRow(L("sticky.settings.usage.bold", fallback: "加粗"),
                          L("sticky.settings.usage.bold.syntax", fallback: "**文本**"), "")
                markupRow(L("sticky.settings.usage.strike", fallback: "删除线"),
                          L("sticky.settings.usage.strike.syntax", fallback: "~~文本~~"), "")
                markupRow(L("sticky.settings.usage.color", fallback: "颜色"),
                          L("sticky.settings.usage.color.syntax", fallback: "[c:FACC15]文本[/c]"),
                          L("sticky.settings.usage.color.note", fallback: "点工具栏的色点会自动插入"))

                explanationRow(L("sticky.settings.usage.noteColor", fallback: "便签底色"),
                               L("sticky.settings.usage.noteColor.detail", fallback: "点工具栏里的底色色块，按住拖到某个颜色上松手即可"))
                explanationRow(L("sticky.settings.usage.list", fallback: "列表"),
                               L("sticky.settings.usage.list.detail", fallback: "「- 项目」或「1. 项目」，回车自动续行"))
            }
        }
    }

    private func explanationRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.themeBody)
                .foregroundColor(.themeTextSecondary)
                .frame(width: 110, alignment: .leading)
            Text(detail)
                .font(.themeCaption)
                .foregroundColor(.themeTextTertiary)
        }
    }

    /// 标记写法行：写法本身用等宽字体，后面跟一句说明（没有说明传空串）
    private func markupRow(_ title: String, _ syntax: String, _ note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.themeBody)
                .foregroundColor(.themeTextSecondary)
                .frame(width: 110, alignment: .leading)
            Text(syntax)
                .font(.themeCaption)
                .monospaced()
                .foregroundColor(.themeTextPrimary)
            if !note.isEmpty {
                Text(note)
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
            }
        }
    }

    // MARK: - 容器（与 LauncherSettingsTab 同款卡片）

    private func section<Content: View>(title: String, icon: IconName, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                LucideView(name: icon, size: 16, color: .themeBlue400)
                Text(title)
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
            }
            content()
        }
        .padding(16)
        .background(Color.themeCard)
        .cornerRadius(12)
    }
}

/// 一行可配置的便利贴热键：标题 + 录制器 + 清除按钮 + 冲突提示 + 「恢复默认」
private struct StickyShortcutRow: View {
    let title: String
    @Binding var key: String
    @Binding var flags: Int
    /// 默认值：「恢复默认」写回它；当前值与它不同才显示该按钮
    let defaultKey: String
    let defaultFlags: Int
    let conflict: Bool

    /// 能注册成功、但会抢走别的 App 自身快捷键的组合——选了就给黄色提醒。
    /// Finder 把带 N 的三种两键组合全占了，所以默认值用的是三修饰键的 ⌥⇧⌘N
    private static let knownConflicts: [(registration: HotkeyRegistration, messageKey: String, fallback: String)] = [
        (HotkeyRegistration(key: "n", modifiers: [.command, .shift]),
         "sticky.settings.shortcut.finderWarning",
         "与 Finder「新建文件夹」相同，Finder 里该快捷键会被 Quite Note 接管"),
        (HotkeyRegistration(key: "n", modifiers: [.control, .command]),
         "sticky.settings.shortcut.finderSelectionWarning",
         "与 Finder「用所选项目新建文件夹」相同，Finder 里该快捷键会被 Quite Note 接管"),
        (HotkeyRegistration(key: "n", modifiers: [.option, .command]),
         "sticky.settings.shortcut.smartFolderWarning",
         "与 Finder「新建智能文件夹」和 Xcode「New Group」相同，那里该快捷键会被 Quite Note 接管"),
    ]

    private var registration: HotkeyRegistration {
        KeyboardShortcutManager.hotkeyRegistration(key: key, flags: flags)
    }

    private var isDefault: Bool {
        registration == KeyboardShortcutManager.hotkeyRegistration(key: defaultKey, flags: defaultFlags)
    }

    private var knownConflictWarning: String? {
        guard let known = Self.knownConflicts.first(where: { $0.registration == registration }) else { return nil }
        return L(known.messageKey, fallback: known.fallback)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.themeBody)
                    .foregroundColor(.themeTextSecondary)
                Spacer()
                ShortcutRecorderView(shortcut: $key, modifiers: $flags)
                if !key.isEmpty {
                    Button(action: {
                        key = ""
                        flags = 0
                    }) {
                        // 图标只有 14pt，垫一圈 padding 把点击区域放大到约 22pt
                        LucideView(name: .circleX, size: 14, color: .themeTextTertiary)
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .help(L("sticky.settings.shortcut.clear", fallback: "清除快捷键（禁用此全局热键）"))
                }
            }

            if conflict {
                warningRow(L("sticky.settings.shortcut.conflict", fallback: "快捷键被系统或其他应用占用，未能注册，请换一组"),
                           color: .themeStatusError)
            }
            if let knownConflictWarning {
                warningRow(knownConflictWarning, color: .themeStatusWarning)
            }
            if !isDefault {
                // 「恢复默认 ⌥⇧⌘N」：展示串由默认值现算，默认值改了文案不会走样
                Button {
                    key = defaultKey
                    flags = defaultFlags
                } label: {
                    HStack(spacing: 4) {
                        LucideView(name: .rotateCcw, size: 11, color: .themeBlue400)
                        Text(L("sticky.settings.shortcut.restoreDefault", fallback: "恢复默认"))
                        Text(KeyboardShortcutManager.hotkeyRegistration(key: defaultKey, flags: defaultFlags)
                            .displayString(spaceLabel: L("sticky.settings.shortcut.space", fallback: "空格")))
                    }
                    .font(.themeCaption)
                    .foregroundColor(.themeBlue400)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
    }

    private func warningRow(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            LucideView(name: .alertTriangle, size: 12, color: color)
            Text(text)
                .font(.themeCaption)
                .foregroundColor(color)
        }
    }
}
