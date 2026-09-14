#if !APP_STORE
import AppKit

/// 启动器可执行命令（系统命令等非应用条目）
///
/// 搜索字段与 LauncherApp 同策略：构造时预计算（名称/全拼/首字母/英文别名），
/// 匹配零转换成本。破坏性命令（清废纸篓/重启/关机）由 VM 做"二次回车确认"。
struct LauncherCommand: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let icon: IconName
    /// 破坏性命令第一次回车只亮起确认提示，4 秒内再按一次才执行
    let requiresConfirmation: Bool
    let action: Action

    enum Action: Equatable {
        case lockScreen
        case sleep
        case emptyTrash
        case restart
        case shutdown
        case toggleAppearance
    }

    // MARK: - 预计算搜索字段

    let titleNormalized: String
    let pinyinCompact: String
    let pinyinInitials: String
    /// 英文别名（lock/sleep/trash…，小写）
    let keywords: [String]

    init(id: String, title: String, subtitle: String, icon: IconName,
         requiresConfirmation: Bool, action: Action, keywords: [String]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.requiresConfirmation = requiresConfirmation
        self.action = action
        self.keywords = keywords.map { $0.lowercased() }

        let pinyin = PinyinTransformer.transliterate(title)
        self.titleNormalized = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        self.pinyinCompact = pinyin.full.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
        self.pinyinInitials = pinyin.initials.lowercased()
    }

    // MARK: - 命令清单（静态，拼音在首次访问时算一次）

    static let all: [LauncherCommand] = [
        LauncherCommand(id: "sys.lock", title: "锁屏",
                        subtitle: "立即锁定屏幕", icon: .lock,
                        requiresConfirmation: false, action: .lockScreen,
                        keywords: ["lock", "lockscreen"]),
        LauncherCommand(id: "sys.sleep", title: "睡眠",
                        subtitle: "让 Mac 进入睡眠", icon: .moon,
                        requiresConfirmation: false, action: .sleep,
                        keywords: ["sleep"]),
        LauncherCommand(id: "sys.appearance", title: "切换深浅外观",
                        subtitle: "深色 / 浅色模式互切", icon: .sun,
                        requiresConfirmation: false, action: .toggleAppearance,
                        keywords: ["dark", "light", "theme", "appearance"]),
        LauncherCommand(id: "sys.emptyTrash", title: "清倒废纸篓",
                        subtitle: "永久删除废纸篓中的所有项目", icon: .trash2,
                        requiresConfirmation: true, action: .emptyTrash,
                        keywords: ["trash", "emptytrash"]),
        LauncherCommand(id: "sys.restart", title: "重启电脑",
                        subtitle: "重新启动这台 Mac", icon: .rotateCcw,
                        requiresConfirmation: true, action: .restart,
                        keywords: ["restart", "reboot"]),
        LauncherCommand(id: "sys.shutdown", title: "关机",
                        subtitle: "关闭这台 Mac", icon: .power,
                        requiresConfirmation: true, action: .shutdown,
                        keywords: ["shutdown", "power", "off"]),
    ]
}

/// 命令匹配与执行
enum SystemCommandService {

    /// 单 token 打分（token 已归一化小写）；不命中返回 0
    static func tokenScore(_ token: String, command: LauncherCommand) -> Int {
        if command.titleNormalized == token { return 120 }
        if command.titleNormalized.hasPrefix(token) { return 100 }
        if command.pinyinInitials.hasPrefix(token) { return 90 }
        if command.pinyinCompact.hasPrefix(token) { return 80 }
        if command.titleNormalized.contains(token) { return 60 }
        if command.pinyinCompact.contains(token) { return 50 }
        if command.pinyinInitials.contains(token) { return 45 }
        for keyword in command.keywords {
            if keyword == token { return 70 }
            if keyword.hasPrefix(token) { return 60 }
            if keyword.contains(token) { return 40 }
        }
        return 0
    }

    /// 多 token 全命中才保留（同应用搜索语义）；空查询返回空（命令只在搜索时出现，不进最近使用）
    static func matchingCommands(tokens: [String]) -> [LauncherCommand] {
        guard !tokens.isEmpty else { return [] }
        return LauncherCommand.all
            .map { cmd -> (LauncherCommand, Int) in
                var total = 0
                for token in tokens {
                    let s = tokenScore(token, command: cmd)
                    if s == 0 { return (cmd, 0) }
                    total += s
                }
                return (cmd, total)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    // MARK: - 执行

    @MainActor
    static func execute(_ action: LauncherCommand.Action, title: String) {
        switch action {
        case .lockScreen:
            // CGSession 是菜单栏"快速用户切换"同款机制（无需额外权限）；失败回退熄屏
            if !runProcess("/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
                           arguments: ["-suspend"]) {
                _ = runProcess("/usr/bin/pmset", arguments: ["displaysleepnow"])
            }
        case .sleep:
            _ = runProcess("/usr/bin/pmset", arguments: ["sleepnow"])
        case .emptyTrash:
            runAppleScript("tell application \"Finder\" to empty trash", title: title)
        case .restart:
            runAppleScript("tell application \"System Events\" to restart", title: title)
        case .shutdown:
            runAppleScript("tell application \"System Events\" to shut down", title: title)
        case .toggleAppearance:
            runAppleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode", title: title)
        }
        DiagnosticCenter.info("Launcher", "执行系统命令：\(title)")
    }

    @discardableResult
    private static func runProcess(_ path: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
            return true
        } catch {
            DiagnosticCenter.error("Launcher", "进程启动失败 \(path)：\(error.localizedDescription)")
            return false
        }
    }

    private static func runAppleScript(_ source: String, title: String) {
        // 首次执行 Finder/System Events 控制会触发系统授权弹窗（自动化权限），
        // 拒绝时 error 记日志（功能静默失败，不崩溃）
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            DiagnosticCenter.error("Launcher", "系统命令「\(title)」AppleScript 失败：\(errorInfo)")
        }
    }
}
#endif
