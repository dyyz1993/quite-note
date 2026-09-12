import Foundation

/// 应用启动器搜索（纯函数，打分只读 LauncherApp 预计算字段——零字符串转换成本）
///
/// 打分阶梯（单 token）：
/// 名称精确 120 > 名称前缀 100 > 首字母前缀 90（wx→微信）> 全拼前缀 80 >
/// 名称包含 60 > 全拼包含 50 > 首字母包含 45 > bundleID 包含 30 >
/// 名称子序列 25（gch→Google Chrome）> 首字母子序列 20；最近使用 +5。
///
/// **多词搜索**：查询按空白拆 token（如 "goo chr"、"wan y"），每个 token 必须独立命中
/// （各取其最高档分数求和），任一 token 无命中则整条排除。
enum AppSearchService {

    /// 搜索入口；空查询返回最近使用（按 MRU 顺序，缺失的 id 静默过滤）
    static func search(_ rawQuery: String, in apps: [LauncherApp], recentIDs: [String]) -> [LauncherApp] {
        let tokens = tokenize(rawQuery)
        guard !tokens.isEmpty else {
            let byID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
            return recentIDs.compactMap { byID[$0] }
        }
        let recentSet = Set(recentIDs)
        var scored: [(LauncherApp, Int)] = []
        scored.reserveCapacity(apps.count)
        for app in apps {
            var total = 0
            var matched = true
            for token in tokens {
                let s = tokenScore(token, app: app)
                if s == 0 { matched = false; break }
                total += s
            }
            guard matched else { continue }
            scored.append((app, recentSet.contains(app.id) ? total + 5 : total))
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.name.localizedStandardCompare(rhs.0.name) == .orderedAscending
            }
            .map { $0.0 }
    }

    /// 单 token 打分（token 须已归一化小写）；不命中返回 0
    static func tokenScore(_ token: String, app: LauncherApp) -> Int {
        if app.nameNormalized == token { return 120 }
        if app.nameNormalized.hasPrefix(token) { return 100 }
        if app.initialsNormalized.hasPrefix(token) { return 90 }
        if app.pinyinCompact.hasPrefix(token) { return 80 }
        if app.nameNormalized.contains(token) { return 60 }
        if app.pinyinCompact.contains(token) { return 50 }
        if app.initialsNormalized.contains(token) { return 45 }
        if !app.bundleIDLower.isEmpty && app.bundleIDLower.contains(token) { return 30 }
        if isSubsequence(token, of: app.nameNormalized) { return 25 }
        if isSubsequence(token, of: app.initialsNormalized) { return 20 }
        return 0
    }

    /// 查询分词：归一化（小写/去变音符/去首尾空白）后按空白拆分
    static func tokenize(_ query: String) -> [String] {
        normalize(query)
            .split(whereSeparator: { $0 == " " })
            .map(String.init)
    }

    /// 归一化：去首尾空白 + 小写 + 去变音符（中文保持原样）
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// 子序列匹配（Alfred 式模糊兜底）：needle 的字符按顺序出现在 haystack 中即可
    /// （"gch" 是 "google chrome" 的子序列：g..c..h）
    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }
        var index = haystack.startIndex
        for char in needle {
            while index < haystack.endIndex, haystack[index] != char {
                index = haystack.index(after: index)
            }
            guard index < haystack.endIndex else { return false }
            index = haystack.index(after: index)
        }
        return true
    }
}
