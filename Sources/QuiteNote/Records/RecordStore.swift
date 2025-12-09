import Foundation
import Combine
import CoreData

/// 管理记录的增删改查、搜索与轻提示分发
final class RecordStore: ObservableObject {
    @Published private(set) var records: [Record] = []
    @Published var lightHint: String? = nil
    @Published var toast: ToastMessage? = nil
    @Published var aiProvider: AIProvider = .local
    @Published var enableAI: Bool = true
    @Published var searchHistory: [String] = []
    @Published var searchInSummaries: Bool = false
    @Published var searchInTitles: Bool = true
    @Published var searchInContent: Bool = true
    @Published var searchCaseSensitive: Bool = false
    @Published var searchUseRegex: Bool = false
    var ai: AIServiceProtocol? = nil
    
    // 内存管理
    private let memoryManager = MemoryManager.shared
    private var memoryOptimizationCancellable: AnyCancellable?
    
    // 搜索防抖相关
    private var searchWorkItem: DispatchWorkItem?
    private var lastSearchQuery: String = ""
    private var searchResults: [Record] = []
    @Published var titleLimit: Int = 20
    @Published var summaryTrigger: Int = 20
    @Published var summaryLimit: Int = 100
    @Published var dedupEnabled: Bool = true
    @Published var maxRecords: Int = 100
    private let stack = CoreDataStack.shared
    private let prefs = PreferencesManager.shared

    init() {
        loadFromStore()
        loadPreferences()
        loadSearchHistory()
        setupMemoryOptimization()
    }

    

    /// 添加一条记录并触发 UI 刷新
    func addRecord(content: String, hash: String) {
        let now = Date()
        let cd = stack.newRecord()
        cd.id = UUID()
        cd.content = content
        cd.createdAt = now
        cd.digest = hash
        cd.starred = false
        stack.save()
        let record = Record(id: cd.id, title: nil, content: content, createdAt: now, hash: hash, aiStatus: nil, summary: nil, summaryConfidence: nil, starred: false, copiedAt: nil)
        records.insert(record, at: 0)
        if records.count > maxRecords { records = Array(records.prefix(maxRecords)) }
        guard enableAI, content.count >= summaryTrigger, let ai else { return }
        let index = 0
        records[index].aiStatus = "pending"
        ai.summarize(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let s):
                    self.records[index].title = s.title
                    self.records[index].summary = s.summary
                    self.records[index].summaryConfidence = s.confidence
                    self.records[index].aiStatus = "success"
                    self.updateCDRecord(id: cd.id, title: s.title, summary: s.summary, confidence: s.confidence, aiStatus: "success")
                case .failure:
                    self.records[index].aiStatus = "fail"
                    self.updateCDRecord(id: cd.id, title: nil, summary: nil, confidence: nil, aiStatus: "fail")
                }
            }
        }
    }

    /// 判断是否为近期重复记录
    func isRecentDuplicate(hash: String, withinMinutes: Int) -> Bool {
        let threshold = Date().addingTimeInterval(Double(-withinMinutes) * 60)
        return records.first(where: { $0.hash == hash && $0.createdAt >= threshold }) != nil
    }

    func updateTimestampForHash(_ hash: String) {
        let now = Date()
        if let idx = records.firstIndex(where: { $0.hash == hash }) {
            let id = records[idx].id
            records[idx].createdAt = now
            let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let obj = try? stack.context.fetch(req).first {
                obj.createdAt = now
                stack.save()
            }
        }
    }

    /// 删除指定记录
    func delete(_ record: Record) {
        records.removeAll { $0.id == record.id }
        deleteCDRecord(id: record.id)
    }
    
    /// 清空所有记录
    func clearAll() {
        records.removeAll()
        let req = NSFetchRequest<NSFetchRequestResult>(entityName: "CDRecord")
        let deleteReq = NSBatchDeleteRequest(fetchRequest: req)
        _ = try? stack.context.execute(deleteReq)
        stack.save()
    }

    /// 搜索记录（支持高级搜索选项）
    func search(_ query: String) -> [Record] {
        guard !query.isEmpty else { return records }
        
        // 添加到搜索历史
        addToSearchHistory(query)
        
        // 根据搜索选项进行过滤
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
            
            return matches
        }
    }
    
    /// 防抖搜索，减少频繁搜索带来的性能问题
    /// - Parameters:
    ///   - query: 搜索查询
    ///   - delay: 防抖延迟时间，默认0.3秒
    ///   - completion: 搜索完成回调
    func debouncedSearch(_ query: String, delay: TimeInterval = 0.3, completion: @escaping ([Record]) -> Void) {
        // 取消之前的搜索任务
        searchWorkItem?.cancel()
        
        // 如果查询为空，直接返回所有记录
        if query.isEmpty {
            lastSearchQuery = ""
            searchResults = records
            completion(records)
            return
        }
        
        // 如果查询与上次相同，直接返回缓存结果
        if query == lastSearchQuery && !searchResults.isEmpty {
            completion(searchResults)
            return
        }
        
        // 创建新的搜索任务
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // 执行搜索
            let results = self.search(query)
            
            // 缓存结果
            self.lastSearchQuery = query
            self.searchResults = results
            
            // 返回结果
            DispatchQueue.main.async {
                completion(results)
            }
        }
        
        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
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
                return searchCaseSensitive ? text.contains(query) : text.lowercased().contains(query.lowercased())
            }
        } else {
            return searchCaseSensitive ? text.contains(query) : text.lowercased().contains(query.lowercased())
        }
    }
    
    /// 添加搜索词到历史记录
    private func addToSearchHistory(_ query: String) {
        // 移除重复项
        searchHistory.removeAll { $0 == query }
        // 添加到开头
        searchHistory.insert(query, at: 0)
        // 限制历史记录数量
        if searchHistory.count > 20 {
            searchHistory = Array(searchHistory.prefix(20))
        }
        // 保存到偏好设置
        saveSearchHistory()
    }
    
    /// 清空搜索历史
    func clearSearchHistory() {
        searchHistory.removeAll()
        saveSearchHistory()
    }
    
    /// 从偏好设置加载搜索历史
    private func loadSearchHistory() {
        searchHistory = prefs.stringArray(forKey: "searchHistory") ?? []
    }
    
    /// 保存搜索历史到偏好设置
    private func saveSearchHistory() {
        prefs.set(searchHistory, forKey: "searchHistory")
    }
    
    /// 生成搜索结果总结
    func generateSearchSummary(for query: String, completion: @escaping (String?) -> Void) {
        guard enableAI, let ai = ai else {
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
        
        ai.summarize(titleLimit: 50, summaryLimit: 100, content: prompt) { result in
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

    /// 发送轻量提示（悬浮窗右下角气泡）
    func postLightHint(_ text: String) {
        lightHint = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.lightHint = nil }
    }

    /// 顶部右侧 Toast 提示
    func postToast(_ text: String, type: String = "info") {
        toast = ToastMessage(text: text, type: type)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.toast = nil }
    }

    /// 连接 AI 提炼服务
    func attachAI(service: AIServiceProtocol) {
        self.ai = service
        if let s = ai as? AIService {
            s.provider = aiProvider
            s.openAIBaseURL = prefs.openAIBaseURL
            s.openAIModel = prefs.openAIModel
        }
    }

    /// 设置 AI 提供商（本地/OpenAI）
    func setAIProvider(_ provider: AIProvider) {
        self.aiProvider = provider
        if let s = ai as? AIService { s.provider = provider }
        prefs.setAIProvider(provider == .openai ? "openai" : "local")
    }

    /// 配置 OpenAI 连接参数并写入 Keychain（仅密钥）
    func configureOpenAI(apiKey: String, baseURL: String, model: String) {
        KeychainHelper.shared.write(service: "QuiteNote", account: "openai_api_key", value: apiKey)
        prefs.setOpenAIBaseURL(baseURL)
        prefs.setOpenAIModel(model)
        if let s = ai as? AIService {
            s.openAIBaseURL = baseURL
            s.openAIModel = model
        }
    }

    func loadPreferences() {
        enableAI = prefs.enableAI
        titleLimit = prefs.titleLimit
        summaryTrigger = prefs.summaryTrigger
        summaryLimit = prefs.summaryLimit
        dedupEnabled = prefs.dedupEnabled
        maxRecords = prefs.maxRecords
        aiProvider = prefs.aiProvider == "openai" ? .openai : .local
    }

    func savePreferences() {
        prefs.setEnableAI(enableAI)
        prefs.setTitleLimit(titleLimit)
        prefs.setSummaryTrigger(summaryTrigger)
        prefs.setSummaryLimit(summaryLimit)
        prefs.setDedupEnabled(dedupEnabled)
        prefs.setMaxRecords(maxRecords)
    }

    /// 导出全部记录为 Markdown（占位：返回生成的文本）
    func exportMarkdown() -> String {
        var md = "# QuiteNote 导出\n\n"
        for r in records.reversed() {
            if let t = r.title {
                md += "## \(t)\n\n"
            } else {
                md += "## 无标题\n\n"
            }
            md += "创建时间：\(r.createdAt)\n\n"
            md += "\(r.content)\n\n"
            if let s = r.summary { md += "> 总结：\(s)\n\n" }
        }
        return md
    }

    /// 批量对无标题记录触发重新提炼（每次最多处理 3 条）
    func bulkResummarize(batchSize: Int = 3) {
        guard enableAI, let ai else { return }
        let targets = records.enumerated().filter { $0.element.title == nil }.prefix(batchSize)
        for (index, r) in targets {
            records[index].aiStatus = "pending"
            ai.summarize(titleLimit: titleLimit, summaryLimit: summaryLimit, content: r.content) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success(let s):
                        self.records[index].title = s.title
                        self.records[index].summary = s.summary
                        self.records[index].summaryConfidence = s.confidence
                        self.records[index].aiStatus = "success"
                        self.updateCDRecord(id: self.records[index].id, title: s.title, summary: s.summary, confidence: s.confidence, aiStatus: "success")
                    case .failure:
                        self.records[index].aiStatus = "fail"
                        self.updateCDRecord(id: self.records[index].id, title: nil, summary: nil, confidence: nil, aiStatus: "fail")
                    }
                }
            }
        }
    }

    private func loadFromStore() {
        loadFromStore(pageSize: 50, offset: 0)
    }
    
    /// 分页加载记录，提高性能
    /// - Parameters:
    ///   - pageSize: 每页记录数
    ///   - offset: 偏移量
    func loadFromStore(pageSize: Int = 50, offset: Int = 0) {
        let cds = (try? stack.fetchRecords(limit: pageSize, offset: offset)) ?? []
        let newRecords = cds.map { r in
            // 检查并重置pending状态的记录
            let aiStatus = r.aiStatus == "pending" ? nil : r.aiStatus
            if r.aiStatus == "pending" {
                // 更新数据库中的状态
                r.aiStatus = nil
            }
            return Record(id: r.id, title: r.title, content: r.content, createdAt: r.createdAt, hash: r.digest, aiStatus: aiStatus, summary: r.summary, summaryConfidence: r.summaryConfidence, starred: r.starred, copiedAt: r.copiedAt)
        }.sorted { $0.createdAt > $1.createdAt }
        
        // 如果有pending状态的记录被重置，保存更改
        if cds.contains(where: { $0.aiStatus == "pending" }) {
            stack.save()
        }
        
        // 如果是第一页，直接替换；否则追加
        if offset == 0 {
            records = newRecords
        } else {
            // 检查是否已经加载了这些记录，避免重复
            let existingIds = Set(records.map { $0.id })
            let uniqueNewRecords = newRecords.filter { !existingIds.contains($0.id) }
            records.append(contentsOf: uniqueNewRecords)
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
        searchResults.removeAll()
        lastSearchQuery = ""
        
        // 如果记录数量过多，只保留最近的记录
        if records.count > 500 {
            records = Array(records.prefix(200))
        }
        
        // 取消所有待处理的搜索任务
        searchWorkItem?.cancel()
        searchWorkItem = nil
        
        // 清理搜索历史
        if searchHistory.count > 50 {
            searchHistory = Array(searchHistory.prefix(20))
        }
    }
    
    /// 更新记录的AI状态和内容
    func updateRecordAI(id: UUID, title: String?, summary: String?, confidence: Double?, aiStatus: String?) {
        updateCDRecord(id: id, title: title, summary: summary, confidence: confidence, aiStatus: aiStatus)
        
        // 更新内存中的记录
        if let index = records.firstIndex(where: { $0.id == id }) {
            if let title = title {
                records[index].title = title
            }
            if let summary = summary {
                records[index].summary = summary
            }
            if let confidence = confidence {
                records[index].summaryConfidence = confidence
            }
            if let aiStatus = aiStatus {
                records[index].aiStatus = aiStatus
            }
        }
    }

    private func updateCDRecord(id: UUID, title: String?, summary: String?, confidence: Double?, aiStatus: String?) {
        let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let obj = try? stack.context.fetch(req).first {
            obj.title = title
            obj.summary = summary
            obj.summaryConfidence = confidence ?? obj.summaryConfidence
            obj.aiStatus = aiStatus
            stack.save()
        }
    }

    private func deleteCDRecord(id: UUID) {
        let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let obj = try? stack.context.fetch(req).first {
            stack.context.delete(obj)
            stack.save()
        }
    }

    func toggleStar(_ record: Record) {
        if let idx = records.firstIndex(where: { $0.id == record.id }) {
            records[idx].starred.toggle()
            let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
            req.predicate = NSPredicate(format: "id == %@", record.id as CVarArg)
            if let obj = try? stack.context.fetch(req).first {
                obj.starred = records[idx].starred
                stack.save()
            }
        }
    }

    func resummarize(record: Record) {
        guard let ai, enableAI else { return }
        guard let idx = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[idx].aiStatus = "pending"
        ai.summarize(titleLimit: titleLimit, summaryLimit: summaryLimit, content: record.content) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let s):
                    self.records[idx].title = s.title
                    self.records[idx].summary = s.summary
                    self.records[idx].summaryConfidence = s.confidence
                    self.records[idx].aiStatus = "success"
                    self.updateCDRecord(id: record.id, title: s.title, summary: s.summary, confidence: s.confidence, aiStatus: "success")
                case .failure:
                    self.records[idx].aiStatus = "fail"
                    self.updateCDRecord(id: record.id, title: nil, summary: nil, confidence: nil, aiStatus: "fail")
                }
            }
        }
    }
}
