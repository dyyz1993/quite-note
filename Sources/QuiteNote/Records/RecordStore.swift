import Foundation
import Combine
import CoreData
import os.log

/// 管理记录的增删改查、搜索与轻提示分发
/// 重构后：核心状态管理，委托具体操作给专门的处理类
final class RecordStore: ObservableObject {
    private static let logger = Logger(subsystem: "com.quitenote.app", category: "RecordStore")

    // MARK: - Published Properties

    /// 核心数据：记录列表
    @Published private(set) var records: [Record] = []

    /// 搜索配置（直接存储，同步到 searcher）
    @Published var searchInSummaries: Bool = false
    @Published var searchInTitles: Bool = true
    @Published var searchInContent: Bool = true
    @Published var searchCaseSensitive: Bool = false
    @Published var searchUseRegex: Bool = false

    /// 通知（直接存储，同步到 notifier）
    @Published var lightHint: String? = nil
    @Published var toast: ToastMessage? = nil

    /// AI 配置（直接存储，同步到 aiCoordinator）
    @Published var enableAI: Bool = true
    @Published var titleLimit: Int = 20
    @Published var summaryTrigger: Int = 20
    @Published var summaryLimit: Int = 100

    /// 搜索历史（直接存储，同步到 searchHistoryManager）
    @Published var searchHistory: [String] = []

    /// 是否有正在处理的 AI 任务
    var isAIProcessing: Bool {
        records.contains { $0.aiStatus == "pending" }
    }

    /// 上次 AI 成功的时间，用于 UI 反馈
    @Published var lastAISuccessAt: Date? = nil

    /// 上次粘贴成功的时间，用于 UI 反馈
    @Published var lastPasteSuccessAt: Date? = nil

    // MARK: - 子组件

    /// 搜索器
    private let searcher: RecordSearcher

    /// 数据访问层
    private let repository: RecordRepository

    /// AI 协调器
    private let aiCoordinator: RecordAICOORDINATOR

    /// 通知器
    private let notifier: RecordNotifier

    /// 搜索历史管理器
    private let searchHistoryManager: SearchHistory
    private var searchHistoryCancellable: AnyCancellable?
    private var toastCancellable: AnyCancellable?
    private var lightHintCancellable: AnyCancellable?

    /// 暴露 AI 服务（用于 UI 访问）
    var ai: AIServiceProtocol? {
        aiCoordinator.ai
    }

    // MARK: - 配置

    private let prefs = PreferencesManager.shared
    @Published var dedupEnabled: Bool = true
    @Published var maxRecords: Int = 100
    @Published var isStarredCollapsed: Bool = false

    // MARK: - 内存管理

    private let memoryManager = MemoryManager.shared
    private var memoryOptimizationCancellable: AnyCancellable?

    // MARK: - Initialization

    init() {
        // 初始化子组件
        self.searcher = RecordSearcher()
        self.repository = RecordRepository()
        self.aiCoordinator = RecordAICOORDINATOR()
        self.notifier = RecordNotifier()
        self.searchHistoryManager = SearchHistory()

        // 设置关联
        aiCoordinator.attach(recordStore: self)

        // 同步初始值
        syncToSearcher()
        syncToAICoordinator()
        syncFromSearchHistoryManager()

        // 加载数据和偏好
        loadFromStore()
        loadPreferences()

        // 设置内存优化
        setupMemoryOptimization()
    }

    // MARK: - 属性同步

    private func syncToSearcher() {
        searcher.searchInSummaries = searchInSummaries
        searcher.searchInTitles = searchInTitles
        searcher.searchInContent = searchInContent
        searcher.searchCaseSensitive = searchCaseSensitive
        searcher.searchUseRegex = searchUseRegex
    }

    private func syncToAICoordinator() {
        aiCoordinator.enableAI = enableAI
        aiCoordinator.titleLimit = titleLimit
        aiCoordinator.summaryTrigger = summaryTrigger
        aiCoordinator.summaryLimit = summaryLimit
    }

    private func syncFromSearchHistoryManager() {
        searchHistory = searchHistoryManager.history

        // 订阅搜索历史更新
        searchHistoryCancellable = searchHistoryManager.didUpdate
            .sink { [weak self] in
                self?.searchHistory = self?.searchHistoryManager.history ?? []
            }

        // 订阅 toast 更新
        toastCancellable = notifier.$toast
            .sink { [weak self] newValue in
                self?.toast = newValue
            }

        // 订阅 lightHint 更新
        lightHintCancellable = notifier.$lightHint
            .sink { [weak self] newValue in
                self?.lightHint = newValue
            }
    }

    // MARK: - 核心操作：添加记录

    /// 添加一条记录并触发 UI 刷新
    func addRecord(content: String, hash: String, sourceApp: String? = nil, sourceUrl: String? = nil) {
        // 校验相同内容是否已存在
        if records.contains(where: { $0.hash == hash }) {
            Self.logger.info("发现重复记录，仅更新时间: \(hash)")
            updateTimestampForHash(hash)
            notifier.postToast("记录已去重，更新了时间戳", type: "info")
            return
        }

        let now = Date()
        let id = UUID()
        let autoTags = ContentClassifier.classify(content)

        // 1. 创建记录对象
        let record = Record(
            id: id,
            title: nil,
            content: content,
            createdAt: now,
            hash: hash,
            aiStatus: nil,
            summary: nil,
            summaryConfidence: nil,
            starred: false,
            copiedAt: nil,
            tags: autoTags,
            keywords: [],
            sourceApp: sourceApp,
            sourceUrl: sourceUrl
        )

        // 2. 异步保存到 CoreData
        do { try repository.save(record) }
        catch {
            Self.logger.error("保存记录失败: \(error.localizedDescription)")
        }

        // 3. 立即更新内存 UI (在主线程)
        records.insert(record, at: 0)
        aiCoordinator.markTagsNeedUpdate()
        sortRecordsInPlace()

        // 设置粘贴成功时间用于 UI 反馈
        notifier.markPasteSuccess()
        lastPasteSuccessAt = Date()
        notifier.postToast("已自动创建新记录", type: "success")

        // 限制最大记录数
        if records.count > maxRecords { records = Array(records.prefix(maxRecords)) }

        // 4. 触发 AI 总结 (如果启用)
        syncToAICoordinator()
        Self.logger.info("AI调用条件检查: enableAI=\(self.aiCoordinator.enableAI), content.count=\(content.count), summaryTrigger=\(self.aiCoordinator.summaryTrigger)")
        guard self.aiCoordinator.enableAI, content.count >= self.aiCoordinator.summaryTrigger else {
            Self.logger.info("AI功能未启用或内容长度不足，跳过AI总结")
            return
        }

        Self.logger.info("开始调用AI总结，内容长度: \(content.count)")
        if let idx = records.firstIndex(where: { $0.id == id }) {
            records[idx].aiStatus = "pending"
        }

        let existingTags = self.aiCoordinator.getAllUniqueTags(from: records)

        self.aiCoordinator.summarize(record: record, existingTags: existingTags) { [weak self] update in
            guard let self = self else { return }

            switch update {
            case .none:
                break
            case .failure:
                self.updateRecordAI(id: id, title: nil, summary: nil, confidence: nil, aiStatus: "fail")
            case .success(let title, let summary, let confidence, let tags, let keywords):
                self.updateRecordAI(
                    id: id,
                    title: title,
                    summary: summary,
                    confidence: confidence,
                    aiStatus: "success",
                    tags: tags,
                    keywords: keywords
                )
                self.notifier.markAISuccess()
                self.lastAISuccessAt = Date()
            }
        }
    }

    /// 更新指定哈希的记录时间戳
    private func updateTimestampForHash(_ hash: String) {
        let now = Date()
        if let idx = records.firstIndex(where: { $0.hash == hash }) {
            let id = records[idx].id
            records[idx].createdAt = now

            // 异步更新数据库
            do { try repository.updateTimestamp(id: id, to: now) }
            catch {
                Self.logger.error("更新时间戳失败: \(error.localizedDescription)")
            }

            sortRecordsInPlace()
        }
    }

    // MARK: - 核心操作：删除记录

    /// 删除指定记录
    func delete(_ record: Record) {
        records.removeAll { $0.id == record.id }
        aiCoordinator.markTagsNeedUpdate()
        repository.delete(id: record.id)
    }

    /// 清空所有记录
    func clearAll() {
        records.removeAll()
        aiCoordinator.markTagsNeedUpdate()
        repository.deleteAll()
    }

    // MARK: - 通知方法（委托给 notifier）

    /// 发送轻量提示（悬浮窗右下角气泡）
    func postLightHint(_ text: String) {
        notifier.postLightHint(text)
    }

    /// 顶部右侧 Toast 提示
    func postToast(_ text: String, type: String = "info") {
        notifier.postToast(text, type: type)
    }

    // MARK: - 搜索

    /// 搜索记录
    func search(_ query: String) -> [Record] {
        guard !query.isEmpty else { return records }

        // 同步搜索配置
        syncToSearcher()

        // 添加到搜索历史
        searchHistoryManager.add(query)

        return searcher.search(query, in: records)
    }

    /// 防抖搜索
    func debouncedSearch(_ query: String, delay: TimeInterval = 0.3, completion: @escaping ([Record]) -> Void) {
        guard !query.isEmpty else {
            completion(records)
            return
        }

        // 同步搜索配置
        syncToSearcher()

        // 添加到搜索历史
        searchHistoryManager.add(query)

        searcher.debouncedSearch(query, in: records, delay: delay, completion: completion)
    }

    /// 清空搜索历史
    func clearSearchHistory() {
        searchHistoryManager.clear()
    }

    /// 生成搜索结果总结
    func generateSearchSummary(for query: String, completion: @escaping (String?) -> Void) {
        guard aiCoordinator.enableAI, let ai = aiCoordinator.ai else {
            completion(nil)
            return
        }

        let results = search(query)
        guard !results.isEmpty else {
            completion("没有找到匹配的记录")
            return
        }

        // 准备用于总结的内容
        let content = results.prefix(10).map { record in
            let title = record.title ?? "无标题"
            let summary = record.summary ?? ""
            return "标题: \(title)\n总结: \(summary)"
        }.joined(separator: "\n\n")

        let prompt = "请为以下搜索结果生成一个简短的总结，不超过100字。搜索关键词: \(query)\n\n搜索结果:\n\(content)"

        let existingTags = aiCoordinator.getAllUniqueTags(from: records)
        ai.summarize(contextId: "search-\(query)", titleLimit: 50, summaryLimit: 100, content: prompt, existingTags: existingTags) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let summaryResult):
                    completion(summaryResult.summary)
                case .failure:
                    completion("生成搜索总结失败")
                }
            }
        }
    }

    // MARK: - AI 操作

    /// 连接 AI 提炼服务
    func attachAI(service: AIServiceProtocol) {
        aiCoordinator.attachAI(service: service)
    }

    /// 配置 OpenAI 连接参数并写入 Keychain（仅密钥）
    func configureOpenAI(apiKey: String, baseURL: String, model: String) {
        KeychainHelper.shared.write(service: "QuiteNote", account: "openai_api_key", value: apiKey)
        prefs.setOpenAIBaseURL(baseURL)
        prefs.setOpenAIModel(model)
        if let s = aiCoordinator.ai as? AIService {
            s.openAIBaseURL = baseURL
            s.openAIModel = model
        }
    }

    /// 批量对无标题记录触发重新提炼（每次最多处理 3 条）
    func bulkResummarize(batchSize: Int = 3) {
        aiCoordinator.bulkResummarize(
            records: records,
            batchSize: batchSize
        ) { [weak self] index, id, record, update in
            guard let self = self else { return }

            // 更新 pending 状态
            if case .none = update {
                if let idx = self.records.firstIndex(where: { $0.id == id }) {
                    self.records[idx].aiStatus = "pending"
                }
            } else {
                // 处理结果
                switch update {
                case .none:
                    break
                case .failure:
                    self.updateRecordAI(id: id, title: nil, summary: nil, confidence: nil, aiStatus: "fail")
                case .success(let title, let summary, let confidence, let tags, let keywords):
                    self.updateRecordAI(
                        id: id,
                        title: title,
                        summary: summary,
                        confidence: confidence,
                        aiStatus: "success",
                        tags: tags,
                        keywords: keywords
                    )
                    self.notifier.markAISuccess()
                    self.lastAISuccessAt = Date()
                }
            }
        } completion: {
            Self.logger.info("批量处理完成")
        }
    }

    /// 重新提炼指定记录
    func resummarize(record: Record) {
        guard let idx = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[idx].aiStatus = "pending"

        let existingTags = self.aiCoordinator.getAllUniqueTags(from: records)

        self.aiCoordinator.summarize(record: record, existingTags: existingTags) { [weak self] update in
            guard let self = self else { return }

            switch update {
            case .none:
                break
            case .failure:
                self.updateRecordAI(id: record.id, title: nil, summary: nil, confidence: nil, aiStatus: "fail")
            case .success(let title, let summary, let confidence, let tags, let keywords):
                self.updateRecordAI(
                    id: record.id,
                    title: title,
                    summary: summary,
                    confidence: confidence,
                    aiStatus: "success",
                    tags: tags,
                    keywords: keywords
                )
                self.notifier.markAISuccess()
                self.lastAISuccessAt = Date()
            }
        }
    }

    /// 检查是否应该显示 AI 成功动画
    func shouldShowAISuccessAnimation() -> Bool {
        // 同步时间戳后再检查
        if let notifierTime = notifier.lastAISuccessAt, lastAISuccessAt != notifierTime {
            lastAISuccessAt = notifierTime
        }
        return notifier.shouldShowAISuccessAnimation()
    }

    /// 检查是否应该显示粘贴成功动画
    func shouldShowPasteSuccessAnimation() -> Bool {
        // 同步时间戳后再检查
        if let notifierTime = notifier.lastPasteSuccessAt, lastPasteSuccessAt != notifierTime {
            lastPasteSuccessAt = notifierTime
        }
        return notifier.shouldShowPasteSuccessAnimation()
    }

    // MARK: - 其他操作

    /// 切换收藏状态
    func toggleStar(_ record: Record) {
        if let idx = records.firstIndex(where: { $0.id == record.id }) {
            records[idx].starred.toggle()

            // 异步更新数据库
            do { try repository.toggleStar(id: record.id) }
            catch {
                Self.logger.error("切换收藏状态失败: \(error.localizedDescription)")
            }

            sortRecordsInPlace()
        }
    }

    /// 导出全部记录为 Markdown
    func exportMarkdown() -> String {
        let dateFormatter = ISO8601DateFormatter()
        var md = "# QuiteNote 导出\n\n"
        for r in records.reversed() {
            // 标题
            if let t = r.title {
                md += "## \(t)\n\n"
            } else {
                md += "## 无标题\n\n"
            }

            // 元数据
            md += "**创建时间**：\(dateFormatter.string(from: r.createdAt))\n\n"

            // 标签
            if !r.tags.isEmpty {
                md += "**标签**：\(r.tags.joined(separator: "、"))\n\n"
            }

            // 关键词
            if !r.keywords.isEmpty {
                md += "**关键词**：\(r.keywords.joined(separator: "、"))\n\n"
            }

            // 来源信息
            if let source = r.sourceApp {
                md += "**来源**：\(source)"
                if let url = r.sourceUrl {
                    md += " ([\(url)](\(url)))"
                }
                md += "\n\n"
            }

            // 内容
            md += "\(r.content)\n\n"

            // 总结
            if let s = r.summary {
                md += "> **总结**：\(s)\n\n"
            }

            md += "---\n\n"
        }
        return md
    }

    /// 从 Markdown 内容导入记录
    func importFromMarkdown(_ markdown: String) -> Int {
        var importedCount = 0
        var skippedCount = 0
        let sections = markdown.components(separatedBy: "\n## ")

        // 先获取所有已存在的哈希值用于去重
        let existingHashes = Set(records.map { $0.hash })

        for section in sections {
            let trimmed = section.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            // 解析各个部分
            var title: String?
            var createdAt: Date?
            var tags: [String] = []
            var keywords: [String] = []
            var content: String = ""
            var summary: String?

            let lines = trimmed.components(separatedBy: "\n")
            var i = 0

            // 第一行是标题
            if i < lines.count {
                let firstLine = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if !firstLine.isEmpty && !firstLine.hasPrefix("---") {
                    title = firstLine == "无标题" ? nil : firstLine
                }
                i += 1
            }

            // 解析元数据
            while i < lines.count {
                let line = lines[i].trimmingCharacters(in: .whitespaces)

                // 空行跳过
                if line.isEmpty {
                    i += 1
                    continue
                }

                // 创建时间
                if line.hasPrefix("**创建时间**") || line.hasPrefix("创建时间：") {
                    let dateStr = line.replacingOccurrences(of: "**创建时间**：", with: "")
                                   .replacingOccurrences(of: "创建时间：", with: "")
                    // 尝试多种日期格式
                    let dateFormatter1 = ISO8601DateFormatter()
                    var date = dateFormatter1.date(from: dateStr)

                    if date == nil {
                        // 尝试其他格式
                        let dateFormatter2 = DateFormatter()
                        dateFormatter2.dateFormat = "yyyy-MM-dd HH:mm:ss"
                        date = dateFormatter2.date(from: dateStr)
                    }

                    if date == nil {
                        let dateFormatter3 = DateFormatter()
                        dateFormatter3.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                        date = dateFormatter3.date(from: dateStr)
                    }

                    createdAt = date ?? Date()
                    Self.logger.info("导入记录日期解析: '\(dateStr)' -> \(createdAt ?? Date())")
                    i += 1
                    continue
                }

                // 标签
                if line.hasPrefix("**标签**") || line.hasPrefix("标签") {
                    let tagsStr = line.replacingOccurrences(of: "**标签**：", with: "")
                                  .replacingOccurrences(of: "标签：", with: "")
                    tags = tagsStr.components(separatedBy: "、").map { $0.trimmingCharacters(in: .whitespaces) }
                    i += 1
                    continue
                }

                // 关键词
                if line.hasPrefix("**关键词**") || line.hasPrefix("关键词") {
                    let keywordsStr = line.replacingOccurrences(of: "**关键词**：", with: "")
                                     .replacingOccurrences(of: "关键词：", with: "")
                    keywords = keywordsStr.components(separatedBy: "、").map { $0.trimmingCharacters(in: .whitespaces) }
                    i += 1
                    continue
                }

                // 来源
                if line.hasPrefix("**来源**") {
                    i += 1
                    continue
                }

                // 分隔符或内容开始
                if line == "---" {
                    i += 1
                    continue
                }

                // 总结
                if line.hasPrefix(">") {
                    summary = line.replacingOccurrences(of: "> ", with: "")
                               .replacingOccurrences(of: ">**总结**：", with: "")
                               .replacingOccurrences(of: "> 总结：", with: "")
                    i += 1
                    continue
                }

                // 内容开始
                break
            }

            // 收集剩余内容
            while i < lines.count {
                let line = lines[i]
                if line != "---" {
                    content += line + "\n"
                }
                i += 1
            }

            // 保存记录
            let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedContent.isEmpty {
                // 计算哈希用于去重
                let data = Data(trimmedContent.utf8)
                let hash = data.reduce(into: "") { $0 += String(format: "%02x", $1) }

                // 检查是否已存在
                if existingHashes.contains(hash) {
                    skippedCount += 1
                } else {
                    addImportedRecord(
                        title: title,
                        content: trimmedContent,
                        summary: summary,
                        tags: tags,
                        keywords: keywords,
                        createdAt: createdAt
                    )
                    importedCount += 1
                }
            }
        }

        // 立即重新加载内存数据（CoreData 保存已在 addImportedRecord 中同步完成）
        if importedCount > 0 {
            loadFromStore()
        }

        return importedCount
    }

    /// 添加单条导入的记录（同步保存）
    private func addImportedRecord(title: String?, content: String, summary: String?, tags: [String], keywords: [String], createdAt: Date?) {
        // 使用简单哈希算法（与 ClipboardService 保持一致）
        let data = Data(content.utf8)
        let hash = data.reduce(into: "") { $0 += String(format: "%02x", $1) }

        let record = Record(
            id: UUID(),
            title: title?.isEmpty == false ? title : nil,
            content: content,
            createdAt: createdAt ?? Date(),
            hash: hash,
            aiStatus: "completed",
            summary: summary?.isEmpty == false ? summary : nil,
            tags: tags,
            keywords: keywords
        )

        // 使用同步保存，确保数据立即写入 CoreData
        do {
            try repository.saveSync(record)
        } catch {
            Self.logger.error("导入记录保存失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 数据加载

    private func loadFromStore() {
        loadFromStore(pageSize: 50, offset: 0)
    }

    /// 分页加载记录，提高性能
    func loadFromStore(pageSize: Int = 50, offset: Int = 0) {
        // 异步加载数据，避免阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let newRecords = try self.repository.fetchRecords(limit: pageSize, offset: offset)

                // 如果有 pending 状态的记录，需要在后台更新数据库
                let pendingIds = newRecords.filter { $0.aiStatus == "pending" }.map { $0.id }
                if !pendingIds.isEmpty {
                    self.repository.clearPendingStatus(for: pendingIds)
                }

                DispatchQueue.main.async {
                    if offset == 0 {
                        self.records = newRecords
                    } else {
                        let existingIds = Set(self.records.map { $0.id })
                        let uniqueNewRecords = newRecords.filter { !existingIds.contains($0.id) }
                        self.records.append(contentsOf: uniqueNewRecords)
                    }
                    self.sortRecordsInPlace()
                }
            } catch {
                Self.logger.error("加载记录失败: \(error.localizedDescription)")
            }
        }
    }

    /// 加载更多记录
    func loadMoreRecords() {
        let currentCount = records.count
        loadFromStore(pageSize: 50, offset: currentCount)

        // 限制内存中的记录数量，保留最新的 200 条记录
        if records.count > 200 {
            records = Array(records.prefix(200))
        }
    }

    // MARK: - 排序

    /// 对内存中的记录进行排序：收藏优先，时间倒序
    private func sortRecordsInPlace() {
        // 如果记录较多，考虑在后台排序后更新
        if records.count > 100 {
            let currentRecords = records
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var sorted = currentRecords
                sorted.sort { (r1, r2) -> Bool in
                    if r1.starred != r2.starred {
                        return r1.starred && !r2.starred
                    }
                    return r1.createdAt > r2.createdAt
                }
                DispatchQueue.main.async {
                    self?.records = sorted
                }
            }
        } else {
            records.sort { (r1, r2) -> Bool in
                if r1.starred != r2.starred {
                    return r1.starred && !r2.starred
                }
                return r1.createdAt > r2.createdAt
            }
        }
    }

    // MARK: - AI 更新

    func updateRecordAI(
        id: UUID,
        title: String? = nil,
        summary: String? = nil,
        confidence: Double? = nil,
        aiStatus: String? = nil,
        tags: [String]? = nil,
        keywords: [String]? = nil
    ) {
        // 异步更新数据库
        repository.updateAI(
            id: id,
            title: title,
            summary: summary,
            confidence: confidence,
            aiStatus: aiStatus,
            tags: tags,
            keywords: keywords
        )

        // 返回主线程更新内存 UI
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let index = self.records.firstIndex(where: { $0.id == id }) {
                if let title = title {
                    self.records[index].title = title
                }
                if let summary = summary {
                    self.records[index].summary = summary
                }
                if let confidence = confidence {
                    self.records[index].summaryConfidence = confidence
                }
                if let aiStatus = aiStatus {
                    self.records[index].aiStatus = aiStatus
                }
                if let tags = tags {
                    self.records[index].tags = tags
                }
                if let keywords = keywords {
                    self.records[index].keywords = keywords
                }
            }

            self.aiCoordinator.markTagsNeedUpdate()
        }
    }

    // MARK: - 偏好设置

    private func loadPreferences() {
        enableAI = prefs.enableAI
        titleLimit = prefs.titleLimit
        summaryTrigger = prefs.summaryTrigger
        summaryLimit = prefs.summaryLimit
        dedupEnabled = prefs.dedupEnabled
        maxRecords = prefs.maxRecords

        // 同步到 AI 协调器
        syncToAICoordinator()

        // 延迟初始化AI服务
        if enableAI {
            Self.logger.info("正在初始化AI服务 (延迟加载Key)...")
            let aiService = AIService()
            aiService.openAIBaseURL = prefs.openAIBaseURL
            aiService.openAIModel = prefs.openAIModel
            attachAI(service: aiService)
            Self.logger.info("AI服务对象已创建，模型: \(aiService.openAIModel)")
        } else {
            Self.logger.info("AI功能已禁用")
        }
    }

    func savePreferences() {
        prefs.setEnableAI(enableAI)
        prefs.setTitleLimit(titleLimit)
        prefs.setSummaryTrigger(summaryTrigger)
        prefs.setSummaryLimit(summaryLimit)
        prefs.setDedupEnabled(dedupEnabled)
        prefs.setMaxRecords(maxRecords)

        aiCoordinator.savePreferences()
    }

    // MARK: - 内存优化

    /// 设置内存优化
    private func setupMemoryOptimization() {
        // 监听内存优化通知
        memoryOptimizationCancellable = NotificationCenter.default.publisher(for: .memoryOptimizationNeeded)
            .sink { [weak self] _ in
                self?.performMemoryOptimization()
            }
    }

    /// 执行内存优化
    private func performMemoryOptimization() {
        // 清理搜索缓存
        searcher.clearCache()

        // 如果记录数量过多，只保留最近的记录
        if records.count > 500 {
            records = Array(records.prefix(200))
        }

        // 清理搜索历史
        if searchHistory.count > 50 {
            let trimmed = Array(searchHistory.prefix(20))
            // 通过 searchHistoryManager 更新
            searchHistoryManager.clear()
            for item in trimmed {
                searchHistoryManager.add(item)
            }
            searchHistory = trimmed
        }
    }
}
