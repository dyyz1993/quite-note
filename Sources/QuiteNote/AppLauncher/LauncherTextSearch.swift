import Foundation
import AppKit

/// 启动器可复制的文本条目：收藏片段（置顶剪贴板条目）、备忘（贴纸文本）、闪记收藏（starred 记录）
///
/// 语义（2026-09-11 与用户确认）：↵ = 复制内容到剪贴板（面板收起后 ⌘V 粘贴），
/// 不做"直接粘贴到目标应用"。搜索为简单包含/前缀匹配 + 拼音，字段在构造时预计算。
struct LauncherTextItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case favorite  // 置顶剪贴板条目（文本/链接）
        case memo      // 贴纸首页文本（剥离颜色标记）
        case flash     // 闪记收藏（主面板点星收藏的文本/链接记录）

        var badge: String {
            switch self {
            case .favorite: return "收藏"
            case .memo: return "备忘"
            case .flash: return "闪记"
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
    private static var cachedItems: [LauncherTextItem] = []
    private static var cacheKey = ""

    /// 收集当前可检索的条目（收藏 = 置顶剪贴板条目：文本/链接/图片；备忘 = 贴纸首页文本；
    /// 闪记 = 主面板 starred 的文本/链接记录）
    @MainActor
    static func collect() -> [LauncherTextItem] {
        let clipboardStore = ClipboardHistoryStore.shared
        let stickyStore = StickyNoteManager.shared
        let recordStore = ClipboardFlashNoteService.shared.recordStore
        let searchable = recordStore?.searchableRecords ?? []
        let stickyKey = stickyStore.notes
            .map { "\($0.id.uuidString)-\($0.syncRecordId?.uuidString ?? "nil")-\($0.pages.map(\.content).joined(separator: "\u{1f}").utf8.count)" }
            .joined(separator: "|")
        // 闪记快照来自 DB（点星收藏 + 全部链接，含内存窗口外的老记录）；内容字节数入 key 让正文编辑后缓存失效
        let searchableKey = searchable
            .map { "\($0.id.uuidString)-\($0.content.utf8.count)-\($0.title?.utf8.count ?? 0)" }
            .joined(separator: "|")
        let key = "\(clipboardStore.entriesVersion)-\(stickyKey)-\(searchableKey)"
        if key == cacheKey {
            return cachedItems
        }

        var items: [LauncherTextItem] = []
        for entry in clipboardStore.entries where entry.isPinned {
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
        for note in stickyStore.notes {
            // 取首页全文并剥离贴纸颜色标记 [c:#xxx]
            let content = stripStickyMarkup(note.pages.first?.content ?? "")
            guard !content.isEmpty else { continue }
            items.append(LauncherTextItem(kind: .memo, id: "memo-\(note.id.uuidString)", copyText: content))
        }
        items += Self.flashItems(from: searchable)
        cachedItems = items
        cacheKey = key
        return items
    }

    /// 闪记条目构造（纯函数便于单测）：**链接记录免点星全量收录**（高频取用物、
    /// 数量小）；文本类须点星（防闪记全量淹没搜索结果）；图片/文件类记录的内容
    /// 是路径引用，复制路径无取用价值；便签记录已由备忘覆盖，避免重复。
    static func flashItems(from records: [Record]) -> [LauncherTextItem] {
        records.compactMap { record in
            let isTextual: Bool
            switch record.type {
            case .url:
                isTextual = true
            case .text:
                isTextual = true
                guard record.starred else { return nil }
            case .note:
                return nil
            default:
                isTextual = false
                guard record.starred else { return nil }
            }
            guard !record.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            // 旧记录可能被标成 URL 类型但内容是路径/Markdown 引用；只有真正可
            // 复制的文本/URL 进入启动器取用面。
            guard isTextual else { return nil }
            // 副标题带溯源（类型 · 来源应用 · 相对时间）：长内容只露首行，
            // 但"从哪来的、什么类型、多久之前存的"一眼可见
            let firstLine = record.content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first(where: { !$0.isEmpty }) ?? "(空)"
            var detail = record.type.localizedName
            if let app = record.sourceApp, !app.isEmpty {
                detail += " · 来自 \(app)"
            }
            detail += " · \(ClipboardTimeFormatter.short(record.createdAt))"
            return LauncherTextItem(
                kind: .flash, id: "rec-\(record.id.uuidString)",
                title: firstLine, detail: detail,
                copyText: record.content, imagePath: nil)
        }
    }

    /// 测试辅助：清空收集缓存。
    static func resetCacheForTesting() {
        cachedItems = []
        cacheKey = ""
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
