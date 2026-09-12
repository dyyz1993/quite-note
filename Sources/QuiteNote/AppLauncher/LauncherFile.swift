import Foundation

/// 启动器文件搜索条目（`f ` 前缀模式的结果）
struct LauncherFile: Identifiable, Equatable {
    let name: String
    let url: URL
    /// 系统 Kind 描述（"PNG 图像"/"PDF 文档"，Spotlight 本地化）
    let kindDescription: String
    let modifiedDate: Date?
    let isDirectory: Bool

    var id: String { url.path }

    /// 徽标文案：文件夹 > Kind > 兜底「文件」
    var badgeText: String {
        if isDirectory { return "文件夹" }
        return kindDescription.isEmpty ? "文件" : kindDescription
    }
}

/// 文件模式前缀解析（纯函数）
///
/// 前缀必须**不经过输入法候选转换**——中文 IME（搜狗等）会把字母当拼音上屏，
/// `f ` 在中文模式下根本打不出来（实测 "f " 被搜狗转成「发」）。
/// 标点符号直通 IME，所以首选 `'`（Alfred 同款）/ `~`，`f ` 仅作英文模式兜底。
enum FileModeParser {

    /// ASCII ' + 全角左/右单引号（搜狗中文标点会把 ' 转成 ‘ U+2018，两种都要收）+ 波浪号
    static let filePrefixes = ["'", "\u{2018}", "\u{2019}", "~", "\u{FF5E}"]

    /// 命中文件模式时返回前缀长度
    static func filePrefixLength(_ text: String) -> Int? {
        for prefix in filePrefixes where text.hasPrefix(prefix) {
            return prefix.count
        }
        if text.lowercased().hasPrefix("f ") { return 2 }
        return nil
    }

    static func isFileMode(_ text: String) -> Bool {
        filePrefixLength(text) != nil
    }

    /// 去掉前缀后的文件名查询词（去首尾空白）
    static func fileTerm(_ text: String) -> String {
        guard let length = filePrefixLength(text) else { return "" }
        return String(text.dropFirst(length)).trimmingCharacters(in: .whitespaces)
    }
}
