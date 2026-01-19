import Foundation

// MARK: - Fuzzy Search Algorithm

/// 模糊搜索算法 - 支持智能排序和匹配
enum FuzzySearch {
    /// ⭐ 仅对触发词进行模糊搜索（不包括 content 和 desc）
    /// 这样记录的 trigger 就是真正参与匹配的那个
    static func matchTrigger(triggers: [String], query: String) -> SearchScore? {
        let q = query.lowercased().filter { !$0.isWhitespace }
        guard !q.isEmpty else { return nil }

        // 移除触发前缀后再搜索触发词
        let prefixes = getConfigTriggerPrefixes()

        var bestScore: SearchScore? = nil

        // 对每个 trigger 分别评分，返回最佳分数
        for trigger in triggers {
            let processedTrigger = trigger.lowercased()
            // 移除配置中的所有前缀
            var processedTriggerNoPrefix = processedTrigger
            for prefix in prefixes {
                if processedTrigger.hasPrefix(prefix) {
                    processedTriggerNoPrefix = String(processedTrigger.dropFirst(prefix.count))
                    break
                }
            }

            // 使用相同的评分逻辑计算分数（priority 固定为 0，确保 trigger 匹配优先）
            if let score = calculateScore(text: processedTriggerNoPrefix, query: q, priority: 0) {
                if bestScore == nil || score < bestScore! {
                    bestScore = score
                }
            }
        }

        return bestScore
    }

    /// ⭐ 通用的符号搜索 - 搜索 content、desc 和 trigger
    /// - Parameters:
    ///   - symbol: 要搜索的符号
    ///   - query: 搜索查询
    /// - Returns: 匹配评分，nil 表示不匹配
    static func match(symbol: SymbolItem, query: String) -> SearchScore? {
        let q = query.lowercased().filter { !$0.isWhitespace }
        guard !q.isEmpty else { return nil }

        // 获取所有配置的触发前缀（从 SymbolConfigManager）
        let prefixes = getConfigTriggerPrefixes()

        // 搜索内容：content + desc + trigger
        let content = symbol.content.lowercased()
        let desc = symbol.desc.lowercased()
        // 移除触发前缀后再搜索触发词
        let triggers = symbol.triggers
            .map { $0.lowercased() }
            .map { trigger in
                // 移除配置中的所有前缀
                for prefix in prefixes {
                    if trigger.hasPrefix(prefix) {
                        return String(trigger.dropFirst(prefix.count))
                    }
                }
                return trigger
            }
            .joined(separator: " ")

        // 在内容、描述、触发词中查找最佳匹配
        var bestScore: SearchScore?

        // 检查 content (priority = 0)
        if let score = calculateScore(text: content, query: q, priority: 0) {
            if let current = bestScore {
                bestScore = min(current, score)
            } else {
                bestScore = score
            }
        }

        // 检查 desc (priority = 1)
        if let score = calculateScore(text: desc, query: q, priority: 1) {
            if let current = bestScore {
                bestScore = min(current, score)
            } else {
                bestScore = score
            }
        }

        // 检查 trigger (priority = 2)
        if let score = calculateScore(text: triggers, query: q, priority: 2) {
            if let current = bestScore {
                bestScore = min(current, score)
            } else {
                bestScore = score
            }
        }

        return bestScore
    }

    /// 从 SymbolConfigManager 获取所有配置的触发前缀
    private static func getConfigTriggerPrefixes() -> [String] {
        return SymbolConfigManager.shared.configs.map { $0.global.triggerPrefix }
    }

    /// 计算单个文本的匹配评分
    private static func calculateScore(text: String, query: String, priority: Int) -> SearchScore? {
        // 首先检查是否包含足够的字符（这是最低门槛）
        guard hasEnoughCharacters(text: text, query: query) else {
            return nil
        }

        // 计算 query 中每个字符在 text 中的匹配数量
        let matchedCharCount = countMatchedCharacters(text: text, query: query)

        // Level 0: 完全匹配
        if text == query {
            return SearchScore(level: 0, matchPosition: 0, textLength: text.count, matchedCharCount: matchedCharCount, priority: priority)
        }

        // Level 1: 前缀匹配
        if text.hasPrefix(query) {
            return SearchScore(level: 1, matchPosition: 0, textLength: text.count, matchedCharCount: matchedCharCount, priority: priority)
        }

        // Level 2: 按顺序匹配（模糊匹配）
        if let matchPos = findSequentialMatch(text: text, query: query) {
            return SearchScore(level: 2, matchPosition: matchPos, textLength: text.count, matchedCharCount: matchedCharCount, priority: priority)
        }

        // Level 3: 包含足够的字符（不要求顺序）
        if let range = text.range(of: query.prefix(1)) {
            let pos = text.distance(from: text.startIndex, to: range.lowerBound)
            let countDiff = characterCountDifference(text: text, query: query)
            return SearchScore(
                level: 3,
                matchPosition: pos,
                textLength: text.count,
                matchedCharCount: matchedCharCount,
                priority: priority + countDiff
            )
        }

        return nil
    }

    /// 查找按顺序匹配的位置
    private static func findSequentialMatch(text: String, query: String) -> Int? {
        var textIndex = text.startIndex
        var queryIndex = query.startIndex
        var firstMatchPos: Int? = nil

        while textIndex < text.endIndex && queryIndex < query.endIndex {
            if text[textIndex] == query[queryIndex] {
                if firstMatchPos == nil {
                    firstMatchPos = text.distance(from: text.startIndex, to: textIndex)
                }
                queryIndex = query.index(after: queryIndex)
            }
            textIndex = text.index(after: textIndex)
        }

        // 只有当所有 query 字符都匹配时才返回成功
        return queryIndex == query.endIndex ? firstMatchPos : nil
    }

    /// 计算 query 中有多少字符在 text 中被匹配（考虑重复字符）
    private static func countMatchedCharacters(text: String, query: String) -> Int {
        var queryCharCount: [Character: Int] = [:]
        for char in query {
            queryCharCount[char, default: 0] += 1
        }

        var textCharCount: [Character: Int] = [:]
        for char in text {
            textCharCount[char, default: 0] += 1
        }

        var matchedCount = 0
        for (char, requiredCount) in queryCharCount {
            let actualCount = textCharCount[char, default: 0]
            matchedCount += min(actualCount, requiredCount)
        }

        return matchedCount
    }

    /// 检查文本是否包含足够的字符（支持重复字符计数）
    private static func hasEnoughCharacters(text: String, query: String) -> Bool {
        var queryCharCount: [Character: Int] = [:]
        for char in query {
            queryCharCount[char, default: 0] += 1
        }

        var textCharCount: [Character: Int] = [:]
        for char in text {
            textCharCount[char, default: 0] += 1
        }

        for (char, requiredCount) in queryCharCount {
            if textCharCount[char, default: 0] < requiredCount {
                return false
            }
        }

        return true
    }

    /// 计算字符计数差异（用于排序）
    private static func characterCountDifference(text: String, query: String) -> Int {
        var queryCharCount: [Character: Int] = [:]
        for char in query {
            queryCharCount[char, default: 0] += 1
        }

        var textCharCount: [Character: Int] = [:]
        for char in text {
            textCharCount[char, default: 0] += 1
        }

        var diff = 0
        for (char, requiredCount) in queryCharCount {
            let actualCount = textCharCount[char, default: 0]
            diff += max(0, actualCount - requiredCount)
        }

        diff += max(0, text.count - query.count)

        return diff
    }
}

/// 搜索评分（越小越好）
struct SearchScore: Comparable {
    // Level: 0=完全匹配, 1=前缀匹配, 2=按顺序匹配, 3=包含所有字符
    let level: Int
    // 匹配位置（越早越好）
    let matchPosition: Int
    // 文本长度（越短越好）
    let textLength: Int
    // 匹配的字符数量（越多越好）
    let matchedCharCount: Int
    // 优先级（0=content, 1=desc, 2=trigger）
    let priority: Int

    static func < (lhs: SearchScore, rhs: SearchScore) -> Bool {
        if lhs.level != rhs.level {
            return lhs.level < rhs.level
        }
        if lhs.matchedCharCount != rhs.matchedCharCount {
            return lhs.matchedCharCount > rhs.matchedCharCount
        }
        if lhs.matchPosition != rhs.matchPosition {
            return lhs.matchPosition < rhs.matchPosition
        }
        if lhs.textLength != rhs.textLength {
            return lhs.textLength < rhs.textLength
        }
        return lhs.priority < rhs.priority
    }

    static func == (lhs: SearchScore, rhs: SearchScore) -> Bool {
        return lhs.level == rhs.level &&
               lhs.matchPosition == rhs.matchPosition &&
               lhs.textLength == rhs.textLength &&
               lhs.matchedCharCount == rhs.matchedCharCount &&
               lhs.priority == rhs.priority
    }
}
