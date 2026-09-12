import Foundation
import AppKit

/// 启动器可复制的文本条目：收藏片段（置顶剪贴板条目）与备忘（贴纸文本）
///
/// 语义（2026-09-11 与用户确认）：↵ = 复制内容到剪贴板（面板收起后 ⌘V 粘贴），
/// 不做"直接粘贴到目标应用"。搜索为简单包含/前缀匹配 + 拼音，字段在构造时预计算。
struct LauncherTextItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case favorite  // 置顶剪贴板条目（文本/链接）
        case memo      // 贴纸首页文本（剥离颜色标记）

        var badge: String {
            switch self {
            case .favorite: return "收藏"
            case .memo: return "备忘"
            }
        }
    }

    let kind: Kind
    let id: String
    /// 首行作为标题（展示 + 主匹配字段）
    let title: String
    /// 副标题：剩余内容摘要
    let detail: String
    /// ↵ 复制的完整文本
    let copyText: String

    // 预计算匹配字段（构造时算好，搜索热路径零转换）
    let titleNormalized: String
    let contentNormalized: String
    let pinyinCompact: String
    let pinyinInitials: String

    /// 图片条目专用：原图的绝对路径（↵ 复制图片数据用）；文本条目为 nil
    let imagePath: String?

    init(kind: Kind, id: String, copyText: String) {
        let lines = copyText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        self.init(kind: kind, id: id,
                  title: lines.first ?? "(空)",
                  detail: lines.dropFirst().joined(separator: " "),
                  copyText: copyText, imagePath: nil)
    }

    init(kind: Kind, id: String, title: String, detail: String,
         copyText: String, imagePath: String?) {
        self.kind = kind
        self.id = id
        self.copyText = copyText
        self.title = title
        self.detail = detail
        self.imagePath = imagePath

        let pinyin = PinyinTransformer.transliterate(title)
        let fold: (String) -> String = {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }
        self.titleNormalized = fold(title)
        self.contentNormalized = fold(copyText.replacingOccurrences(of: "\n", with: " "))
        self.pinyinCompact = pinyin.full.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
        self.pinyinInitials = pinyin.initials.lowercased()
    }
}

/// 收藏片段与备忘的收集 + 匹配（纯逻辑与数据收集分离，便于单测）
enum LauncherTextSearch {

    /// 收集当前可检索的条目（收藏 = 置顶剪贴板条目：文本/链接/图片；备忘 = 贴纸首页文本）
    @MainActor
    static func collect() -> [LauncherTextItem] {
        var items: [LauncherTextItem] = []
        for entry in ClipboardHistoryStore.shared.entries where entry.isPinned {
            switch entry.type {
            case .text, .link:
                guard let text = entry.plainText, !text.isEmpty else { continue }
                items.append(LauncherTextItem(kind: .favorite, id: "fav-\(entry.id.uuidString)", copyText: text))
            case .image:
                // 图片收藏：标题 = 原文件名，↵ 复制图片数据
                guard let virtualPath = entry.assetPath,
                      let url = FileCoordinator.shared.resolveVirtualPath(virtualPath) else { continue }
                items.append(LauncherTextItem(
                    kind: .favorite, id: "fav-\(entry.id.uuidString)",
                    title: url.lastPathComponent,
                    detail: "收藏图片",
                    copyText: "", imagePath: url.path))
            default:
                continue
            }
        }
        for note in StickyNoteManager.shared.notes {
            // 取首页全文并剥离贴纸颜色标记 [c:#xxx]
            let content = stripStickyMarkup(note.pages.first?.content ?? "")
            guard !content.isEmpty else { continue }
            items.append(LauncherTextItem(kind: .memo, id: "memo-\(note.id.uuidString)", copyText: content))
        }
        return items
    }

    /// 剥离贴纸首行的颜色标记
    static func stripStickyMarkup(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\[c:(#?[0-9a-fA-F]{3,8})\\]") else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    /// 图片条目的复制：读原图文件 → PNG 数据写剪贴板
    @discardableResult
    static func copyImageToPasteboard(imagePath: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: imagePath)) else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.setData(data, forType: .png)
    }

    /// 多 token 匹配（token 须已归一化）：全部命中才保留，单 token 取最高档分
    static func matchingItems(tokens: [String], in items: [LauncherTextItem]) -> [LauncherTextItem] {
        guard !tokens.isEmpty else { return [] }
        return items
            .map { item -> (LauncherTextItem, Int) in
                var total = 0
                for token in tokens {
                    let s = tokenScore(token, item: item)
                    if s == 0 { return (item, 0) }
                    total += s
                }
                return (item, total)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    /// 单 token 打分：标题精确 120 > 标题前缀 100 > 拼音前缀 90 > 标题包含 60 >
    /// 拼音包含 50 > 内容包含 40
    static func tokenScore(_ token: String, item: LauncherTextItem) -> Int {
        if item.titleNormalized == token { return 120 }
        if item.titleNormalized.hasPrefix(token) { return 100 }
        if item.pinyinInitials.hasPrefix(token) { return 92 }
        if item.pinyinCompact.hasPrefix(token) { return 90 }
        if item.titleNormalized.contains(token) { return 60 }
        if item.pinyinCompact.contains(token) { return 50 }
        if item.contentNormalized.contains(token) { return 40 }
        return 0
    }
}
