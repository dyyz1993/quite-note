import Foundation

/// 启动器文件搜索条目（`f ` 前缀模式的结果）
struct LauncherFile: Identifiable, Equatable, Codable {
    let name: String
    let url: URL
    /// 系统 Kind 描述（"PNG 图像"/"PDF 文档"，Spotlight 本地化）
    let kindDescription: String
    var modifiedDate: Date?
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

/// 内置范围命令（用户提议 2026-09-12）：输入范围关键词后**空格或 ↵** 进入对应搜索
/// 模式——比符号前缀好记（' 前缀难输入且无发现性）。关键词用**词**而非字母前缀：
/// 字母在中文输入法下会被当拼音上屏（"f " 实测变「发」），中文词/完整英文词直通。
///
/// - "文件" 单独（后无空格）→ 只显示范围行，↵/点击进入
/// - "文件 报告" 或 "文件 "（后跟空格）→ 直接进入文件模式，查 "报告"
enum LauncherScopeParser {

    struct Match: Equatable {
        let entered: Bool
        let term: String
    }

    /// 范围关键词表（小写）。**只用英文词**——中文词在输入法下打不出来（拼音会被
    /// 当候选上屏），英文词/拼音首字母直通。后续加范围（如网页搜索）在此扩行
    static let fileKeywords = ["file", "files", "fj", "wj"]

    /// 解析输入；nil = 未命中范围词
    static func parse(_ rawText: String) -> Match? {
        let text = rawText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let lowered = text.lowercased()
        for keyword in fileKeywords {
            if lowered == keyword {
                // 尾部空格（原始文本上判断，trim 会吃掉它）= 直接进入空词模式
                if rawText.hasSuffix(" ") { return Match(entered: true, term: "") }
                return Match(entered: false, term: "")   // 只亮范围行，等 ↵/空格
            }
            // 关键词 + 空格 + 词 → 直接进入；关键词本身必须完整词头（避免"文"误触）
            if lowered.hasPrefix(keyword + " ") {
                let term = String(text.dropFirst(keyword.count + 1)).trimmingCharacters(in: .whitespaces)
                return Match(entered: true, term: term)
            }
        }
        return nil
    }
}
