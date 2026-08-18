import Foundation
import os.log

/// 记录搜索器：负责搜索逻辑、正则匹配、大小写敏感等
///
/// 计算量控制（2026-08-17 第二轮优化）：
/// - **快扫**：每条记录的"可搜索前缀串"（标题 + 内容前 16k 字符 + 总结/标签/关键词）经折叠缓存
///   （大小写折叠 + 字段拼接的结果跨按键复用）后做普通 contains——前缀命中毫秒级交付；
///   常态（内容都不超前缀上限）下快扫即最终结果，单次交付
/// - **深扫**：内容超长（部分折叠）的记录，在停手安静期后只跑一轮全文匹配，
///   打字期间零重复全文扫描；每 32 条检查代际，可被新一轮搜索立即中止
/// - 正则模式不参与折叠（语义基于原文），沿用软时限竞速 + 超时拉黑
///
/// 线程约定：
/// - 配置属性与 `debouncedSearch`/`clearCache` 必须在主线程调用（RecordStore 从 SwiftUI 主线程驱动）
/// - 扫描在后台队列执行，完成回调统一切回主线程；折叠缓存仅后台搜索队列访问（无锁）
final class RecordSearcher {
    private static let logger = Logger(subsystem: "com.quitenote.app", category: "RecordSearcher")

    // MARK: - 搜索配置（主线程读写；后台执行时打快照带走，避免跨线程竞态）

    var searchInSummaries: Bool = false
    var searchInTitles: Bool = true
    var searchInContent: Bool = true
    var searchCaseSensitive: Bool = false
    var searchUseRegex: Bool = false

    /// 配置快照：防抖任务执行期间不受主线程配置变更影响
    private struct OptionsSnapshot {
        let summaries: Bool
        let titles: Bool
        let content: Bool
        let caseSensitive: Bool
        let useRegex: Bool

        init(from searcher: RecordSearcher) {
            self.summaries = searcher.searchInSummaries
            self.titles = searcher.searchInTitles
            self.content = searcher.searchInContent
            self.caseSensitive = searcher.searchCaseSensitive
            self.useRegex = searcher.searchUseRegex
        }
    }

    // MARK: - 常量

    /// 内容折叠前缀上限（字符数）：超长内容只折叠前缀，该记录走深扫补全
    private let foldedPrefixCap = 16_000
    /// 折叠缓存总预算（UTF-8 字节）：超出按 LRU 逐出
    private let foldedCacheBudget = 8 * 1024 * 1024
    /// 深扫默认安静期（秒）：停手多久后才启动全文扫描
    private static let defaultDeepDelay: TimeInterval = 2.0
    /// 批量中止检查粒度：每扫 N 条记录核对一次代际
    private let abortCheckBatch = 32

    // MARK: - 搜索状态（主线程 confined；代际跨线程读写用锁保护）

    private var searchWorkItem: DispatchWorkItem?
    private var lastSearchQuery: String = ""
    private var cachedResults: [Record] = []
    /// 缓存有效性标记：与 cachedResults 分离，零结果的搜索同样可命中缓存
    private var hasCachedResults = false

    private let stateLock = NSLock()
    /// 代际令牌：每轮新搜索 +1；后台任务的启动与交付据此判断是否已被取代
    private var searchGeneration = 0

    /// 超时拉黑的正则 query。ICU 正则无法中断，同款灾难性 query 直接走字面匹配
    private let timedOutRegexLock = NSLock()
    private var timedOutRegexQueries: Set<String> = []
    private let timedOutRegexQueryLimit = 64

    /// 正则单次全量扫描的软时限（秒），超时立即回退字面匹配
    private let regexSearchTimeout: TimeInterval = 1.0

    /// 后台搜索队列：快扫/深扫/正则竞速都在这里执行，绝不占用主线程（串行，折叠缓存免锁）
    private let searchQueue = DispatchQueue(label: "com.quitenote.recordsearch", qos: .userInitiated)

    /// 折叠缓存：仅 searchQueue 上访问
    private let foldedCache = FoldedTextCache(budgetBytes: 8 * 1024 * 1024)

    // MARK: - 防抖搜索

    /// 防抖搜索，减少频繁搜索带来的性能问题
    /// - Parameters:
    ///   - query: 搜索查询
    ///   - records: 要搜索的记录列表
    ///   - delay: 防抖延迟时间，默认0.3秒
    ///   - deepDelay: 深扫安静期（秒），停手多久后才对超长内容记录跑全文扫描，默认 2 秒
    ///   - completion: 搜索完成回调（主线程；超长内容场景可能先快扫后精化各调一次）
    func debouncedSearch(
        _ query: String,
        in records: [Record],
        delay: TimeInterval = 0.3,
        deepDelay: TimeInterval = RecordSearcher.defaultDeepDelay,
        completion: @escaping ([Record]) -> Void
    ) {
        assert(Thread.isMainThread, "debouncedSearch 必须在主线程调用")

        // 取消之前的搜索任务（未启动的快扫直接跳过；已启动的靠代际检查中止）
        searchWorkItem?.cancel()

        // 如果查询为空，直接返回所有记录
        if query.isEmpty {
            bumpGeneration()
            lastSearchQuery = ""
            cachedResults = records
            hasCachedResults = true
            completion(records)
            return
        }

        // 如果查询与上次相同，直接返回缓存结果
        if query == lastSearchQuery && hasCachedResults {
            completion(cachedResults)
            return
        }

        let generation = bumpGeneration()
        let options = OptionsSnapshot(from: self)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isStale(generation) else { return }
            if options.useRegex {
                // 正则语义基于原文，不参与折叠；软时限竞速单次交付
                let results = self.regexSearchWithWatchdog(query, in: records, options: options)
                self.deliver(generation) { searcher in
                    searcher.settleCache(query: query, results: results)
                    completion(results)
                }
            } else {
                self.runFastAndDeepSearch(query, records: records, options: options,
                                          generation: generation, deepDelay: deepDelay, completion: completion)
            }
        }

        searchWorkItem = workItem
        searchQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// 字面搜索主流程（searchQueue 上执行）：快扫 → 立即交付 → 安静期后深扫精化
    private func runFastAndDeepSearch(
        _ query: String,
        records: [Record],
        options: OptionsSnapshot,
        generation: Int,
        deepDelay: TimeInterval,
        completion: @escaping ([Record]) -> Void
    ) {
        let processedQuery = options.caseSensitive ? query : query.lowercased()

        // 快扫：全部记录走折叠缓存（超长记录只扫折叠前缀）
        var fastResults: [Record] = []
        var partialRecords: [Record] = []
        for (index, record) in records.enumerated() {
            if index % abortCheckBatch == 0, isStale(generation) { return }
            let entry = foldedEntry(for: record, caseSensitive: options.caseSensitive)
            if entry.isPartial {
                partialRecords.append(record)
            }
            if entry.folded.contains(processedQuery) {
                fastResults.append(record)
            }
        }

        deliver(generation) { searcher in
            completion(fastResults)
        }

        if partialRecords.isEmpty {
            // 常态：所有内容都在折叠缓存里，快扫结果即全量正确结果
            deliver(generation) { searcher in
                searcher.settleCache(query: query, results: fastResults)
            }
            return
        }

        // 深扫：安静期后只对超长记录跑全文匹配（打字期间已被代际中止，不会反复启动）
        searchQueue.asyncAfter(deadline: .now() + deepDelay) { [weak self] in
            guard let self, !self.isStale(generation) else { return }
            var refined = fastResults
            for (index, record) in partialRecords.enumerated() {
                if index % self.abortCheckBatch == 0, self.isStale(generation) { return }
                if Self.recordMatches(record, query: query, regex: nil, caseSensitive: options.caseSensitive) {
                    refined.append(record)
                }
            }
            self.deliver(generation) { searcher in
                searcher.settleCache(query: query, results: refined)
                completion(refined)
            }
        }
    }

    /// 折叠前缀条目：命中缓存直接复用，未命中才拼接 + 折叠
    private func foldedEntry(for record: Record, caseSensitive: Bool) -> FoldedTextCache.Entry {
        let key = FoldedTextCache.Key(record: record, caseSensitive: caseSensitive)
        return foldedCache.entry(for: key) {
            // 字段间用记录分隔符拼接：该字符不会出现在正常搜索词里，
            // 保证跨字段的拼接边界不可能产生假阳性（与逐字段独立匹配的语义一致）
            let separator = "\u{1E}"
            let isPartial = record.content.utf8.count > foldedPrefixCap
            var blob = (record.title ?? "") + separator
            blob += isPartial ? String(record.content.prefix(foldedPrefixCap)) : record.content
            blob += separator + (record.summary ?? "")
            blob += separator + record.tags.joined(separator: separator)
            blob += separator + record.keywords.joined(separator: separator)
            let folded = caseSensitive ? blob : blob.lowercased()
            return FoldedTextCache.Entry(folded: folded, isPartial: isPartial)
        }
    }

    // MARK: - 同步搜索

    /// 搜索记录（支持高级搜索选项）。可在任意线程调用；不经过折叠缓存，语义与深扫一致。
    /// 正则模式下带软时限，灾难性回溯会在时限内回退字面匹配
    func search(_ query: String, in records: [Record]) -> [Record] {
        search(query, in: records, options: OptionsSnapshot(from: self))
    }

    private func search(_ query: String, in records: [Record], options: OptionsSnapshot) -> [Record] {
        guard !query.isEmpty else { return records }

        if options.useRegex {
            return regexSearchWithWatchdog(query, in: records, options: options)
        }

        return records.filter { Self.recordMatches($0, query: query, regex: nil, caseSensitive: options.caseSensitive) }
    }

    /// 正则搜索 + 软时限竞速：超时回退字面匹配并拉黑该 query
    private func regexSearchWithWatchdog(_ query: String, in records: [Record], options: OptionsSnapshot) -> [Record] {
        guard !isRegexTimedOut(query) else {
            return records.filter { Self.recordMatches($0, query: query, regex: nil, caseSensitive: options.caseSensitive) }
        }
        let regexOptions: NSRegularExpression.Options = options.caseSensitive ? [] : .caseInsensitive
        // 正则只编译一次
        guard let regex = try? NSRegularExpression(pattern: query, options: regexOptions) else {
            Self.logger.warning("正则表达式无效: \(query)，回退到普通搜索")
            return records.filter { Self.recordMatches($0, query: query, regex: nil, caseSensitive: options.caseSensitive) }
        }

        let semaphore = DispatchSemaphore(value: 0)
        var regexResults: [Record]?
        DispatchQueue.global(qos: .userInitiated).async {
            regexResults = records.filter { Self.recordMatches($0, query: query, regex: regex, caseSensitive: options.caseSensitive) }
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + regexSearchTimeout) == .success, let results = regexResults {
            return results
        }
        markRegexTimedOut(query)
        Self.logger.warning("正则搜索超过软时限(\(self.regexSearchTimeout)s)，已回退字面匹配并拉黑该 query: \(query)")
        return records.filter { Self.recordMatches($0, query: query, regex: nil, caseSensitive: options.caseSensitive) }
    }

    /// 单条记录全字段匹配：regex 为 nil 时走字面匹配；
    /// 大小写不敏感用 range(of:options:) 原地搜索，避免对整段内容做 lowercased() 拷贝
    private static func recordMatches(
        _ record: Record,
        query: String,
        regex: NSRegularExpression?,
        caseSensitive: Bool
    ) -> Bool {
        var isMatch = false
        if !isMatch, let title = record.title {
            isMatch = textMatches(title, query: query, regex: regex, caseSensitive: caseSensitive)
        }
        if !isMatch {
            isMatch = textMatches(record.content, query: query, regex: regex, caseSensitive: caseSensitive)
        }
        if !isMatch, let summary = record.summary {
            isMatch = textMatches(summary, query: query, regex: regex, caseSensitive: caseSensitive)
        }
        if !isMatch {
            isMatch = textMatches(record.tags.joined(separator: " "), query: query, regex: regex, caseSensitive: caseSensitive)
        }
        if !isMatch {
            isMatch = textMatches(record.keywords.joined(separator: " "), query: query, regex: regex, caseSensitive: caseSensitive)
        }
        return isMatch
    }

    /// 检查文本是否匹配查询（正则需预先编译；字面匹配支持大小写敏感开关）
    private static func textMatches(
        _ text: String,
        query: String,
        regex: NSRegularExpression?,
        caseSensitive: Bool
    ) -> Bool {
        if let regex {
            let range = NSRange(location: 0, length: text.utf16.count)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
        let compareOptions: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        return text.range(of: query, options: compareOptions) != nil
    }

    // MARK: - 交付与缓存（主线程）

    /// 主线程交付：代际不匹配（已被新一轮搜索取代）则丢弃
    private func deliver(_ generation: Int, onMain: @escaping (RecordSearcher) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isStale(generation) else { return }
            onMain(self)
        }
    }

    /// 写入同查询快捷缓存（仅对最终结果调用；快扫的中间结果不写）
    private func settleCache(query: String, results: [Record]) {
        assert(Thread.isMainThread)
        lastSearchQuery = query
        cachedResults = results
        hasCachedResults = true
    }

    // MARK: - 代际（跨线程读写，锁保护）

    private func currentGeneration() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return searchGeneration
    }

    @discardableResult
    private func bumpGeneration() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        searchGeneration += 1
        return searchGeneration
    }

    private func isStale(_ generation: Int) -> Bool {
        currentGeneration() != generation
    }

    // MARK: - 超时正则拉黑

    private func isRegexTimedOut(_ query: String) -> Bool {
        timedOutRegexLock.lock()
        defer { timedOutRegexLock.unlock() }
        return timedOutRegexQueries.contains(query)
    }

    private func markRegexTimedOut(_ query: String) {
        timedOutRegexLock.lock()
        defer { timedOutRegexLock.unlock() }
        guard timedOutRegexQueries.count < timedOutRegexQueryLimit else { return }
        timedOutRegexQueries.insert(query)
    }

    // MARK: - 缓存管理

    /// 清除搜索缓存
    func clearCache() {
        assert(Thread.isMainThread, "clearCache 必须在主线程调用")
        lastSearchQuery = ""
        cachedResults = []
        hasCachedResults = false
        bumpGeneration()
        searchWorkItem?.cancel()
        searchWorkItem = nil
        searchQueue.async { [weak self] in
            self?.foldedCache.removeAll()
        }
    }
}

/// 折叠缓存：缓存每条记录"可搜索前缀串"的处理结果（字段拼接 + 大小写折叠），
/// 让连续按键复用同一份折叠产物，避免每次搜索重新整段处理。
///
/// 仅在 RecordSearcher.searchQueue（串行）上访问，无需加锁；
/// 超出字节预算按 LRU 逐出。
final class FoldedTextCache {
    /// 缓存键：记录身份 + 内容指纹（去重哈希 + 各字段字节数）。
    /// 内容/AI 提炼结果变化 → 字节数或哈希变化 → 键失效重折叠
    struct Key: Hashable {
        let id: UUID
        let contentHash: String
        let contentBytes: Int
        let titleBytes: Int?
        let summaryBytes: Int?
        let tagsBytes: Int
        let keywordsBytes: Int
        let caseSensitive: Bool

        init(record: Record, caseSensitive: Bool) {
            self.id = record.id
            self.contentHash = record.hash
            self.contentBytes = record.content.utf8.count
            self.titleBytes = record.title?.utf8.count
            self.summaryBytes = record.summary?.utf8.count
            self.tagsBytes = record.tags.joined().utf8.count
            self.keywordsBytes = record.keywords.joined().utf8.count
            self.caseSensitive = caseSensitive
        }
    }

    struct Entry {
        /// 处理后的可搜索串（大小写不敏感模式为小写折叠版；大小写敏感模式为原文）
        let folded: String
        /// 内容超过前缀上限、只折叠了前缀（该记录需要深扫补全）
        let isPartial: Bool
    }

    private struct Slot {
        let entry: Entry
        let bytes: Int
    }

    private var slots: [Key: Slot] = [:]
    /// LRU 顺序，尾部为最近使用
    private var lru: [Key] = []
    private(set) var hitCount = 0
    let budgetBytes: Int

    init(budgetBytes: Int) {
        self.budgetBytes = budgetBytes
    }

    func entry(for key: Key, make: () -> Entry) -> Entry {
        if let slot = slots[key] {
            hitCount += 1
            touch(key)
            return slot.entry
        }
        let made = make()
        slots[key] = Slot(entry: made, bytes: made.folded.utf8.count)
        lru.append(key)
        evictIfNeeded()
        return made
    }

    func removeAll() {
        slots.removeAll()
        lru.removeAll()
    }

    private func touch(_ key: Key) {
        if let index = lru.firstIndex(of: key) {
            lru.remove(at: index)
            lru.append(key)
        }
    }

    private func evictIfNeeded() {
        var used = slots.values.reduce(0) { $0 + $1.bytes }
        while used > budgetBytes, let oldest = lru.first {
            used -= slots[oldest]?.bytes ?? 0
            slots[oldest] = nil
            lru.removeFirst()
        }
    }
}
