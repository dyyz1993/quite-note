import SwiftUI
import AppKit

/// 设置 → 启动器（快捷键配置 + 冲突提示 + 使用说明）
struct LauncherSettingsTab: View {
    @ObservedObject private var prefs = PreferencesManager.shared

    /// 冲突状态轮询（偏好变化 → MainApp 延迟 0.1s refresh 后更新，模式同剪贴板 Tab）
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    /// 轮询到点的本地重绘触发器。⚠️ 不能用 prefs.objectWillChange.send() 触发重绘——
    /// 那会让 MainApp 的 sink 执行 shortcuts.refresh()，把录制期间挂起的全局热键
    /// 重新注册回去，录制器又会收不到按键（实锤过）
    @State private var conflictPollTick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            shortcutSection
            usageSection
        }
        .onReceive(timer) { _ in
            conflictPollTick += 1
        }
    }

    // MARK: - 快捷键

    /// 依赖 conflictPollTick：轮询到点触发 body 重算，读到最新的静态冲突标志
    private var launcherConflict: Bool {
        _ = conflictPollTick
        return KeyboardShortcutManager.launcherShortcutConflict
    }

    /// 当前是否为默认 ⌥空格（不是则显示"恢复默认"按钮——清除后 ⌥空格 被输入法
    /// 拦截无法直接录制，见 AGENTS.md 应用启动器章节）
    private var isDefaultShortcut: Bool {
        _ = conflictPollTick
        return prefs.launcherOpenShortcut == " "
            && prefs.launcherOpenShortcutFlags == Int(NSEvent.ModifierFlags([.option]).rawValue)
    }

    private var shortcutSection: some View {
        section(title: "快捷键", icon: .keyboard) {
            VStack(spacing: 12) {
                HStack {
                    Text("唤起应用启动器")
                        .font(.themeBody)
                        .foregroundColor(.themeTextSecondary)
                    Spacer()
                    ShortcutRecorderView(
                        shortcut: Binding(
                            get: { prefs.launcherOpenShortcut },
                            set: { prefs.setLauncherOpenShortcut($0) }
                        ),
                        modifiers: Binding(
                            get: { prefs.launcherOpenShortcutFlags },
                            set: { prefs.setLauncherOpenShortcutFlags($0) }
                        )
                    )
                    if !prefs.launcherOpenShortcut.isEmpty {
                        Button(action: {
                            prefs.setLauncherOpenShortcut("")
                            prefs.setLauncherOpenShortcutFlags(0)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.themeTextTertiary)
                        }
                        .buttonStyle(.plain)
                        .help("清除快捷键（禁用全局唤起）")
                    }
                }

                if launcherConflict {
                    HStack(spacing: 6) {
                        LucideView(name: .alertTriangle, size: 12, color: .themeStatusError)
                        Text("快捷键与系统或其他应用冲突（⌥空格常与 Alfred/Raycast 相同），未能注册，请换一组")
                            .font(.themeCaption)
                            .foregroundColor(.themeStatusError)
                    }
                }

                if !isDefaultShortcut {
                    HStack(spacing: 10) {
                        Button {
                            prefs.setLauncherOpenShortcut(" ")
                            prefs.setLauncherOpenShortcutFlags(Int(NSEvent.ModifierFlags([.option]).rawValue))
                        } label: {
                            HStack(spacing: 4) {
                                LucideView(name: .rotateCcw, size: 11, color: .themeBlue400)
                                Text("恢复默认 ⌥空格")
                            }
                            .font(.themeCaption)
                            .foregroundColor(.themeBlue400)
                        }
                        .buttonStyle(.plain)
                        Text("清除后 ⌥空格 会被输入法拦截、无法直接录制，用此按钮一键恢复")
                            .font(.themeCaption)
                            .foregroundColor(.themeTextTertiary)
                    }
                }

                Text("默认 ⌥空格；窗口内：↑↓ 选择 · ↵ 打开 · ⌘1–9 直接打开 · esc / ⌘W 关闭。搜狗等中文输入法可能吞掉第一个 esc（关它自己的候选窗），再按一次或用 ⌘W 即可退出。清除快捷键后仍可从状态栏菜单打开。")
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
            }
        }
    }

    // MARK: - 使用说明

    private var usageSection: some View {
        section(title: "搜索说明", icon: .search) {
            VStack(alignment: .leading, spacing: 10) {
                explanationRow("输入应用名称", "如 Safari、微信")
                explanationRow("输入全拼", "如 weixin → 微信")
                explanationRow("输入拼音首字母", "如 wx → 微信、gc → Google Chrome")
                explanationRow("空搜索", "显示最近使用的应用（经启动器启动过的最近 10 个）")
                explanationRow("快速计算", "12+34、(50-8)×2、2^10 幂、√144、5² 上标、π/e 常量，回车复制结果")
                explanationRow("系统命令", "锁屏 / 睡眠 / 切换深浅外观 / 清倒废纸篓 / 重启 / 关机（后三项需再按一次 ↵ 确认）")
                explanationRow("搜文件", "输「文件」后空格或 ↵ 进入（也可 ' 或 ~ 前缀直通），回车用默认应用打开")
                explanationRow("搜收藏/备忘", "置顶的剪贴板文本与贴纸会出现在结果里（绿「收藏」/黄「备忘」），↵ 复制到剪贴板")
                explanationRow("网页搜索", "搜索 词 / 百度 词 / gh 词 / so 词 / npm 词 / 知乎 词 → 回车用浏览器搜索")
                explanationRow("退出应用", "退出 应用名（如 退出 微信）→ 回车退出该运行中应用")
                explanationRow("搜符号", "符号库（emoji 等）按触发词混在结果里（黄「符号」徽标），↵ 复制")
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

    // MARK: - 容器（与 ClipboardSettingsTab 同款卡片）

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
