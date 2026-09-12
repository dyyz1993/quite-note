import Foundation

/// 剪贴板历史搜索（PRD 9）
///
/// 纯函数实现：搜索范围覆盖文本 / URL / 域名 / 文件名与路径 / OCR 文本 / 来源应用；
/// 排序规则：完整匹配 > 前缀匹配 > 包含匹配，同级按复制时间倒序。
/// 数据量控制在几百到几千条，内存过滤足够；超过约 5000 条再升级 FTS5。
enum ClipboardSearchService {

    /// 单个条目的匹配等级：0 = 不匹配，3 = 完整匹配，2 = 前缀，1 = 包含
    static func matchScore(query: String, entry: ClipboardEntry) -> Int {
        let q = normalize(query)
        guard !q.isEmpty else { return 0 }

        var best = 0
        for field in searchableFields(entry) {
            let f = normalize(field)
            guard !f.isEmpty else { continue }
            if f == q {
                return 3
            } else if f.hasPrefix(q) {
                best = max(best, 2)
            } else if f.contains(q) {
                best = max(best, 1)
            }
        }
        return best
    }

    /// 搜索并排序（无搜索词时：置顶优先，其余按复制时间倒序）
    static func search(_ query: String, in entries: [ClipboardEntry]) -> [ClipboardEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // 空查询免排序：store.entries 已按（置顶优先 + 时间倒序）装载/插入，
            // 旧实现每次按键对全量 O(n log n) 重排是打字卡顿主因之一
            return entries
        }

        return entries
            .compactMap { entry -> (ClipboardEntry, Int)? in
                let score = matchScore(query: trimmed, entry: entry)
                return score > 0 ? (entry, score) : nil
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                if lhs.0.isPinned != rhs.0.isPinned { return lhs.0.isPinned }
                return lhs.0.createdAt > rhs.0.createdAt
            }
            .map(\.0)
    }

    /// 参与搜索的字段列表（PRD 9.1）
    static func searchableFields(_ entry: ClipboardEntry) -> [String] {
        var fields: [String] = []
        if let text = entry.plainText { fields.append(text) }
        if let url = entry.sourceURL { fields.append(url) }
        if let domain = entry.sourceURL.flatMap({ ClipboardTypeDetector.domain(ofURL: $0) }) {
            fields.append(domain)
        }
        // 文件条目的路径和文件名
        if entry.type == .file, let path = entry.plainText {
            fields.append((path as NSString).lastPathComponent)
        }
        if let ocr = entry.ocrText { fields.append(ocr) }
        if let app = entry.sourceApp { fields.append(app) }
        return fields
    }

    /// 大小写 + 音调归一化（中文原样保留，英文不区分大小写）
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
