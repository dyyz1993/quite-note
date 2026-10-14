import Foundation

/// 统一搜索索引文档。
///
/// `payload` 保留调用方原值，`metadata` 提供轻量筛选与 UI 展示字段；索引层只负责
/// 建档、打分、排序、分页和取消，不感知具体业务界面。
struct SearchIndexDocument<Payload: Equatable> {
    enum Source: String, Equatable {
        case clipboard
        case flash
        case launcherApp
        case launcherText
        case launcherFile
    }

    let id: String
    let source: Source
    let payload: Payload
    let title: String
    let body: String
    let keywords: [String]
    let pinyin: String
    let pinyinInitials: String
    let titleNormalized: String
    let bodyNormalized: String
    let keywordsNormalized: [String]
    let pinyinNormalized: String
    let pinyinInitialsNormalized: String
    let createdAt: Date
    let isPinned: Bool
    let scoreBonus: Int

    init(
        id: String,
        source: Source,
        payload: Payload,
        title: String = "",
        body: String = "",
        keywords: [String] = [],
        pinyin: String = "",
        pinyinInitials: String = "",
        createdAt: Date = .distantPast,
        isPinned: Bool = false,
        scoreBonus: Int = 0
    ) {
        self.id = id
        self.source = source
        self.payload = payload
        self.title = title
        self.body = body
        self.keywords = keywords
        self.pinyin = pinyin
        self.pinyinInitials = pinyinInitials
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.scoreBonus = scoreBonus
        self.titleNormalized = SearchIndexText.normalize(title)
        self.bodyNormalized = SearchIndexText.normalize(body)
        self.keywordsNormalized = keywords.map(SearchIndexText.normalize)
        self.pinyinNormalized = SearchIndexText.normalize(pinyin)
        self.pinyinInitialsNormalized = SearchIndexText.normalize(pinyinInitials)
    }

    /// Adapter 专用：字段已由调用方缓存/预计算时跳过建档归一化成本。
    init(
        id: String,
        source: Source,
        payload: Payload,
        normalizedTitle: String,
        normalizedBody: String,
        normalizedKeywords: [String] = [],
        normalizedPinyin: String = "",
        normalizedPinyinInitials: String = "",
        createdAt: Date = .distantPast,
        isPinned: Bool = false,
        scoreBonus: Int = 0
    ) {
        self.id = id
        self.source = source
        self.payload = payload
        self.title = normalizedTitle
        self.body = normalizedBody
        self.keywords = normalizedKeywords
        self.pinyin = normalizedPinyin
        self.pinyinInitials = normalizedPinyinInitials
        self.titleNormalized = normalizedTitle
        self.bodyNormalized = normalizedBody
        self.keywordsNormalized = normalizedKeywords
        self.pinyinNormalized = normalizedPinyin
        self.pinyinInitialsNormalized = normalizedPinyinInitials
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.scoreBonus = scoreBonus
    }

}

enum SearchIndexText {
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}

/// 统一搜索结果页。
struct SearchIndexPage<Document: SearchIndexDocumentProtocol> {
    let query: String
    let offset: Int
    let documents: [Document]
    let totalCount: Int
    let isComplete: Bool

    var nextOffset: Int { offset + documents.count }
}

protocol SearchIndexDocumentProtocol {
    associatedtype Payload: Equatable
    var id: String { get }
    var source: SearchIndexDocument<Payload>.Source { get }
    var title: String { get }
    var body: String { get }
    var keywords: [String] { get }
    var pinyin: String { get }
    var pinyinInitials: String { get }
    var titleNormalized: String { get }
    var bodyNormalized: String { get }
    var keywordsNormalized: [String] { get }
    var pinyinNormalized: String { get }
    var pinyinInitialsNormalized: String { get }
    var createdAt: Date { get }
    var isPinned: Bool { get }
    var scoreBonus: Int { get }
}

extension SearchIndexDocument: SearchIndexDocumentProtocol {}

enum SearchIndexDefaults {
    static let pageSize = 100
}

/// 可取消、可分页、可重建的统一索引服务。
///
/// 当前版本先收敛内存索引和匹配语义，作为三条搜索链路的共同底座：
/// - 建档成本由调用方控制（业务已有预计算/缓存继续复用）；
/// - 查询在串行后台队列执行，代际令牌保证旧结果不会覆盖新输入；
/// - `search` 返回匹配结果 + 总数，调用方可按 offset/limit 分页取用；
/// - `rebuild` 在后台整体替换快照，读取端永远拿到完整一致数组。
final class SearchIndexService<Document: SearchIndexDocumentProtocol> {
    private let queue = DispatchQueue(label: "com.quitenote.search-index", qos: .userInitiated)
    private let stateLock = NSLock()
    private var generation = 0
    private var documents: [Document] = []
    private(set) var version = 0
    private var rebuildWork: DispatchWorkItem?

    init(documents: [Document] = []) {
        self.documents = documents
    }

    /// 后台重建索引。完成回调主线程交付；重建期间旧快照继续可查。
    ///
    /// 写入在 work item 内直接执行（item 已在串行队列上跑）：若再包一层
    /// queue.async，紧随其后的 `search` 会先于写入执行、读到旧快照。
    func rebuild(documents newDocuments: [Document]) {
        let requestGeneration = nextGeneration()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isCurrent(requestGeneration) else { return }
            self.documents = newDocuments
            self.version += 1
        }
        rebuildWork = workItem
        queue.async(execute: workItem)
    }

    func rebuild(
        using makeDocuments: @escaping () -> [Document],
        completion: ((Int) -> Void)? = nil
    ) {
        let requestGeneration = nextGeneration()
        let workItem = DispatchWorkItem { [weak self] in
            let rebuilt = makeDocuments()
            guard let self else { return }
            self.queue.async {
                guard self.isCurrent(requestGeneration) else { return }
                self.documents = rebuilt
                self.version += 1
                DispatchQueue.main.async {
                    completion?(self.version)
                }
            }
        }
        rebuildWork = workItem
        queue.async(execute: workItem)
    }

    /// 后台搜索。空查询按 pinned/时间排序；非空查询按完整/前缀/包含 + 拼音阶梯排序。
    ///
    /// 搜索是读操作：只读当前代际、不递增——递增会把先于它入队的 `rebuild`
    /// 写入判为过期丢弃，索引将永远停留在空快照（rebuild+search 背靠背调用的坑）。
    func search(
        _ query: String,
        offset: Int = 0,
        limit: Int = SearchIndexDefaults.pageSize,
        completion: @escaping (SearchIndexPage<Document>) -> Void
    ) {
        let requestGeneration = currentGeneration()
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let offset = max(0, offset)
        let limit = max(1, limit)
        queue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.documents
            let scored = Self.score(query: trimmedQuery, documents: snapshot)
            let end = min(scored.count, offset + limit)
            let pageDocuments = offset < end ? Array(scored[offset..<end]) : []
            self.deliverIfCurrent(requestGeneration) {
                completion(SearchIndexPage(
                    query: trimmedQuery,
                    offset: offset,
                    documents: pageDocuments,
                    totalCount: scored.count,
                    isComplete: end >= scored.count
                ))
            }
        }
    }

    /// 同步搜索仅供单元测试和后台调用方使用；UI 热路径必须走异步 `search`。
    func searchSync(_ query: String, offset: Int = 0, limit: Int = SearchIndexDefaults.pageSize) -> SearchIndexPage<Document> {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let scored = Self.score(query: trimmedQuery, documents: documents)
        let safeOffset = max(0, offset)
        let safeLimit = max(1, limit)
        let end = min(scored.count, safeOffset + safeLimit)
        let pageDocuments = safeOffset < end ? Array(scored[safeOffset..<end]) : []
        return SearchIndexPage(
            query: trimmedQuery,
            offset: safeOffset,
            documents: pageDocuments,
            totalCount: scored.count,
            isComplete: end >= scored.count
        )
    }

    /// 取消挂起请求并让后台快照重建失效。
    func cancel() {
        _ = nextGeneration()
        rebuildWork?.cancel()
        rebuildWork = nil
    }

    private func nextGeneration() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        generation += 1
        return generation
    }

    /// 只读当前代际（读操作用，不使排在前面的写入失效）
    private func currentGeneration() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return generation
    }

    private func isCurrent(_ requestGeneration: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return generation == requestGeneration
    }

    private func deliverIfCurrent(_ requestGeneration: Int, deliver: @escaping () -> Void) {
        guard isCurrent(requestGeneration) else { return }
        DispatchQueue.main.async {
            deliver()
        }
    }

    private static func score(query: String, documents: [Document]) -> [Document] {
        guard !query.isEmpty else {
            return documents.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.createdAt > $1.createdAt
            }
        }

        let tokens = tokenize(query)
        var scored: [(document: Document, score: Int)] = []
        scored.reserveCapacity(documents.count)
        for document in documents {
            var total = 0
            var matched = true
            for token in tokens {
                let score = tokenScore(token, document: document)
                if score == 0 {
                    matched = false
                    break
                }
                total += score
            }
            if matched {
                scored.append((document, total + document.scoreBonus))
            }
        }
        return scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.document.isPinned != rhs.document.isPinned { return lhs.document.isPinned }
            return lhs.document.createdAt > rhs.document.createdAt
        }.map(\.document)
    }

    private static func tokenScore(_ token: String, document: Document) -> Int {
        let title = document.titleNormalized
        if title == token { return 120 }
        if title.hasPrefix(token) { return 100 }
        if document.pinyinInitialsNormalized.hasPrefix(token) { return 90 }
        if document.pinyinNormalized.hasPrefix(token) { return 85 }
        if title.contains(token) { return 70 }
        if document.pinyinNormalized.contains(token) { return 60 }
        if document.keywordsNormalized.contains(where: { $0.contains(token) }) { return 50 }
        if document.bodyNormalized.contains(token) { return 40 }
        if !title.isEmpty && Self.isSubsequence(token, of: title) { return 25 }
        if !document.pinyinInitialsNormalized.isEmpty &&
            Self.isSubsequence(token, of: document.pinyinInitialsNormalized) { return 20 }
        return 0
    }

    private static func tokenize(_ query: String) -> [String] {
        SearchIndexText.normalize(query)
            .split(whereSeparator: { $0 == " " })
            .map(String.init)
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }
        var index = haystack.startIndex
        for character in needle {
            while index < haystack.endIndex, haystack[index] != character {
                index = haystack.index(after: index)
            }
            guard index < haystack.endIndex else { return false }
            index = haystack.index(after: index)
        }
        return true
    }
}
