import Foundation
import os.log

/// 记录搜索器：负责搜索逻辑、正则匹配、大小写敏感等
final class RecordSearcher {
    private static let logger = Logger(subsystem: "com.quitenote.app", category: "RecordSearcher")

    // MARK: - 搜索配置

    var searchInSummaries: Bool = false
    var searchInTitles: Bool = true
    var searchInContent: Bool = true
    var searchCaseSensitive: Bool = false
    var searchUseRegex: Bool = false

    // MARK: - 防抖搜索

    private var searchWorkItem: DispatchWorkItem?
    private var lastSearchQuery: String = ""
    private var cachedResults: [Record] = []

    /// 防抖搜索，减少频繁搜索带来的性能问题
    /// - Parameters:
    ///   - query: 搜索查询
    ///   - records: 要搜索的记录列表
    ///   - delay: 防抖延迟时间，默认0.3秒
    ///   - completion: 搜索完成回调
    func debouncedSearch(
        _ query: String,
        in records: [Record],
        delay: TimeInterval = 0.3,
        completion: @escaping ([Record]) -> Void
    ) {
        // 取消之前的搜索任务
        searchWorkItem?.cancel()

        // 如果查询为空，直接返回所有记录
        if query.isEmpty {
            lastSearchQuery = ""
            cachedResults = records
            completion(records)
            return
        }

        // 如果查询与上次相同，直接返回缓存结果
        if query == lastSearchQuery && !cachedResults.isEmpty {
            completion(cachedResults)
            return
        }

        // 创建新的搜索任务
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // 执行搜索
            let results = self.search(query, in: records)

            // 缓存结果
            self.lastSearchQuery = query
            self.cachedResults = results

            // 返回结果
            DispatchQueue.main.async {
                completion(results)
            }
        }

        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// 搜索记录（支持高级搜索选项）
    func search(_ query: String, in records: [Record]) -> [Record] {
        guard !query.isEmpty else { return records }

        return records.filter { record in
            var matches = false

            // 搜索标题
            if searchInTitles {
                let title = record.title ?? ""
                matches = matches || matchesQuery(text: title, query: query)
            }

            // 搜索内容
            if searchInContent {
                matches = matches || matchesQuery(text: record.content, query: query)
            }

            // 搜索AI总结
            if searchInSummaries {
                let summary = record.summary ?? ""
                matches = matches || matchesQuery(text: summary, query: query)
            }

            // 始终搜索标签和关键词
            let tagsString = record.tags.joined(separator: " ")
            matches = matches || matchesQuery(text: tagsString, query: query)

            let keywordsString = record.keywords.joined(separator: " ")
            matches = matches || matchesQuery(text: keywordsString, query: query)

            return matches
        }
    }

    /// 检查文本是否匹配查询（支持正则表达式和大小写敏感）
    private func matchesQuery(text: String, query: String) -> Bool {
        if searchUseRegex {
            do {
                let options: NSRegularExpression.Options = searchCaseSensitive ? [] : .caseInsensitive
                let regex = try NSRegularExpression(pattern: query, options: options)
                let range = NSRange(location: 0, length: text.utf16.count)
                return regex.firstMatch(in: text, options: [], range: range) != nil
            } catch {
                // 如果正则表达式无效，回退到普通搜索
                Self.logger.warning("正则表达式无效: \(query)，回退到普通搜索")
                return searchCaseSensitive ? text.contains(query) : text.lowercased().contains(query.lowercased())
            }
        } else {
            return searchCaseSensitive ? text.contains(query) : text.lowercased().contains(query.lowercased())
        }
    }

    /// 清除搜索缓存
    func clearCache() {
        lastSearchQuery = ""
        cachedResults = []
        searchWorkItem?.cancel()
        searchWorkItem = nil
    }
}
