import Foundation
import Combine
import CoreData
import os.log

/// 管理记录的增删改查、搜索与轻提示分发
final class RecordStore: ObservableObject {
    private static let logger = Logger(subsystem: "com.quitenote.app", category: "RecordStore")
    @Published private(set) var records: [Record] = []
    @Published var lightHint: String? = nil
    @Published var toast: ToastMessage? = nil
    
    /// 是否有正在处理的 AI 任务
    var isAIProcessing: Bool {
        records.contains { $0.aiStatus == "pending" }
    }
    
    /// 上次 AI 成功的时间，用于 UI 反馈
    @Published var lastAISuccessAt: Date? = nil
    
    /// 上次已处理的 AI 成功时间，用于防止重复显示成功动画
    private var lastProcessedAISuccessAt: Date? = nil
    
    /// 上次粘贴成功的时间，用于 UI 反馈
    @Published var lastPasteSuccessAt: Date? = nil
    
    /// 上次已处理的粘贴成功时间，用于防止重复显示粘贴成功动画
    private var lastProcessedPasteSuccessAt: Date? = nil

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
    @Published var isStarredCollapsed: Bool = false
    private let stack = CoreDataStack.shared
    private let prefs = PreferencesManager.shared

    init() {
        loadFromStore()
        loadPreferences()
        loadSearchHistory()
        setupMemoryOptimization()
    }

    

    /// 获取当前所有记录中已有的唯一标签
    private func getAllUniqueTags() -> [String] {
        let allTags = records.flatMap { $0.tags }
        return Array(Set(allTags)).sorted()
    }

    /// 添加一条记录并触发 UI 刷新
    func addRecord(content: String, hash: String, sourceApp: String? = nil, sourceUrl: String? = nil) {
        // 校验相同内容是否已存在
        if records.contains(where: { $0.hash == hash }) {
            Self.logger.info("发现重复记录，仅更新时间: \(hash)")
            updateTimestampForHash(hash)
            postToast("记录已去重，更新了时间戳", type: "info")
            return
        }

        let now = Date()
        let cd = stack.newRecord()
        cd.id = UUID()
        cd.content = content
        cd.createdAt = now
        cd.digest = hash
        cd.starred = false
        cd.sourceApp = sourceApp
        cd.sourceUrl = sourceUrl
        
        // 自动识别内容类型并添加标签
        let autoTags = ContentClassifier.classify(content)
        cd.tagsRaw = toJSONString(autoTags)
        
        stack.save()
        let record = Record(
            id: cd.id, 
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
        records.insert(record, at: 0)
        sortRecordsInPlace()
        
        // 设置粘贴成功时间用于 UI 反馈
        lastPasteSuccessAt = Date()
        
        postToast("已自动创建新记录", type: "success")
        
        if records.count > maxRecords { records = Array(records.prefix(maxRecords)) }
        Self.logger.info("AI调用条件检查: enableAI=\(self.enableAI), content.count=\(content.count), summaryTrigger=\(self.summaryTrigger), ai=\(self.ai != nil)")
        guard enableAI, content.count >= summaryTrigger, let ai else { 
            Self.logger.info("AI功能未启用或内容长度不足，跳过AI总结")
            return 
        }
        Self.logger.info("开始调用AI总结，内容长度: \(content.count)")
        let index = 0
        records[index].aiStatus = "pending"
        
        let existingTags = getAllUniqueTags()
        
        ai.summarize(
            titleLimit: titleLimit, 
            summaryLimit: summaryLimit, 
            content: content,
            existingTags: existingTags,
            systemPrompt: prefs.aiSystemPrompt,
            userPrompt: prefs.aiUserPrompt
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let s):
                    self.updateRecordAI(
                        id: cd.id, 
                        title: s.title, 
                        summary: s.summary, 
                        confidence: s.confidence, 
                        aiStatus: "success",
                        tags: s.tags,
                        keywords: s.keywords
                    )
                    self.lastAISuccessAt = Date()
                case .failure:
                    self.updateRecordAI(id: cd.id, title: nil, summary: nil, confidence: nil, aiStatus: "fail")
                }
            }
        }
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
            sortRecordsInPlace()
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
            
            // 始终搜索标签和关键词
            let tagsString = record.tags.joined(separator: " ")
            matches = matches || matchesQuery(text: tagsString, query: query)
            
            let keywordsString = record.keywords.joined(separator: " ")
            matches = matches || matchesQuery(text: keywordsString, query: query)
            
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
        // 避免频繁更新，如果查询已在历史记录顶部，则不更新
        if let first = searchHistory.first, first == query {
            return
        }
        
        // 移除重复项
        searchHistory.removeAll { $0 == query }
        // 添加到开头
        searchHistory.insert(query, at: 0)
        // 限制历史记录数量
        if searchHistory.count > 20 {
            searchHistory = Array(searchHistory.prefix(20))
        }
        
        // 异步保存到偏好设置，避免阻塞UI
        DispatchQueue.global(qos: .utility).async {
            self.saveSearchHistory()
        }
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
        
        let existingTags = getAllUniqueTags()
        ai.summarize(titleLimit: 50, summaryLimit: 100, content: prompt, existingTags: existingTags) { result in
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
            s.openAIBaseURL = prefs.openAIBaseURL
            s.openAIModel = prefs.openAIModel
        }
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
        
        // 延迟初始化AI服务：不再启动时立即从 Keychain 读取 API Key
        // 只有当真正需要调用 summarize 时，AIService 内部才会去读取 Key
        if enableAI {
            Self.logger.info("正在初始化AI服务 (延迟加载Key)...")
            let aiService = AIService()
            aiService.openAIBaseURL = prefs.openAIBaseURL
            aiService.openAIModel = prefs.openAIModel
            self.ai = aiService
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

    // 防止重复触发的标志
    private var isBulkProcessing = false
    
    /// 批量对无标题记录触发重新提炼（每次最多处理 3 条）
    func bulkResummarize(batchSize: Int = 3) {
        guard enableAI, let ai, !isBulkProcessing else { 
            if isBulkProcessing {
                print("[BULK] 批量处理已在进行中，跳过重复调用")
            }
            return 
        }
        
        isBulkProcessing = true
        defer { isBulkProcessing = false }
        
        let targets = records.enumerated().filter { $0.element.title == nil }.prefix(batchSize)
        guard !targets.isEmpty else {
            print("[BULK] 没有需要处理的记录")
            return
        }
        
        print("[BULK] 开始批量处理 \(targets.count) 条记录")
        
        for (index, r) in targets {
            // 检查是否已经在处理中
            guard records[index].aiStatus != "pending" else {
                print("[BULK] 跳过已在处理中的记录: \(index)")
                continue
            }
            
            records[index].aiStatus = "pending"
            let existingTags = getAllUniqueTags()
            ai.summarize(
                titleLimit: titleLimit, 
                summaryLimit: summaryLimit, 
                content: r.content,
                existingTags: existingTags,
                systemPrompt: prefs.aiSystemPrompt,
                userPrompt: prefs.aiUserPrompt
            ) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success(let s):
                        self.updateRecordAI(
                            id: r.id, 
                            title: s.title, 
                            summary: s.summary, 
                            confidence: s.confidence, 
                            aiStatus: "success",
                            tags: s.tags,
                            keywords: s.keywords
                        )
                        self.lastAISuccessAt = Date()
                        print("[BULK] 记录 \(index) 处理成功")
                    case .failure(let error):
                        self.updateRecordAI(id: r.id, title: nil, summary: nil, confidence: nil, aiStatus: "fail")
                        print("[BULK] 记录 \(index) 处理失败: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func loadFromStore() {
        loadFromStore(pageSize: 50, offset: 0)
    }
    
    /// 将 JSON 字符串解析为数组
    private func parseJSONArray(_ json: String?) -> [String] {
        guard let json = json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
    
    /// 将数组转换为 JSON 字符串
    private func toJSONString(_ array: [String]) -> String? {
        guard let data = try? JSONEncoder().encode(array) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 分页加载记录，提高性能
    func loadFromStore(pageSize: Int = 50, offset: Int = 0) {
        let cds = (try? stack.fetchRecords(limit: pageSize, offset: offset)) ?? []
        let newRecords = cds.map { r -> Record in
            // 检查并重置pending状态的记录
            let aiStatus = r.aiStatus == "pending" ? nil : r.aiStatus
            if r.aiStatus == "pending" {
                // 更新数据库中的状态
                r.aiStatus = nil
            }
            return Record(
                id: r.id, 
                title: r.title, 
                content: r.content, 
                createdAt: r.createdAt, 
                hash: r.digest, 
                aiStatus: aiStatus, 
                summary: r.summary, 
                summaryConfidence: r.summaryConfidence, 
                starred: r.starred, 
                copiedAt: r.copiedAt,
                tags: parseJSONArray(r.tagsRaw),
                keywords: parseJSONArray(r.keywordsRaw),
                sourceApp: r.sourceApp,
                sourceUrl: r.sourceUrl
            )
        }
        
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
        
        sortRecordsInPlace()
    }
    
    /// 对内存中的记录进行排序：收藏优先，时间倒序
    private func sortRecordsInPlace() {
        records.sort { (r1, r2) -> Bool in
            if r1.starred != r2.starred {
                return r1.starred && !r2.starred
            }
            return r1.createdAt > r2.createdAt
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
    func updateRecordAI(id: UUID, title: String?, summary: String?, confidence: Double?, aiStatus: String?, tags: [String]? = nil, keywords: [String]? = nil) {
        // 1. 处理标签合并：自动识别的标签 + AI 生成的标签
        var finalTags: [String]? = tags
        if let aiTags = tags, let index = records.firstIndex(where: { $0.id == id }) {
            let autoTags = records[index].tags
            finalTags = Array(Set(autoTags + aiTags)).sorted()
        }

        // 2. 处理关键词：确保都有 # 前缀且不超过 10 个
        var finalKeywords: [String]? = keywords
        if let aiKeywords = keywords {
            let cleaned = aiKeywords.prefix(10).map { k -> String in
                let trimmed = k.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
            }
            finalKeywords = Array(cleaned)
        }

        updateCDRecord(id: id, title: title, summary: summary, confidence: confidence, aiStatus: aiStatus, tags: finalTags, keywords: finalKeywords)
        
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
            if let ft = finalTags {
                records[index].tags = ft
            }
            if let fk = finalKeywords {
                records[index].keywords = fk
            }
        }
    }

    private func updateCDRecord(id: UUID, title: String?, summary: String?, confidence: Double?, aiStatus: String?, tags: [String]? = nil, keywords: [String]? = nil) {
        let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let obj = try? stack.context.fetch(req).first {
            if let title = title { obj.title = title }
            if let summary = summary { obj.summary = summary }
            if let confidence = confidence { obj.summaryConfidence = confidence }
            if let aiStatus = aiStatus { obj.aiStatus = aiStatus }
            if let tags = tags { obj.tagsRaw = toJSONString(tags) }
            if let keywords = keywords { obj.keywordsRaw = toJSONString(keywords) }
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
            sortRecordsInPlace()
        }
    }

    func resummarize(record: Record) {
        guard let ai, enableAI else { return }
        guard let idx = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[idx].aiStatus = "pending"
        
        let existingTags = getAllUniqueTags()
        
        ai.summarize(
            titleLimit: titleLimit, 
            summaryLimit: summaryLimit, 
            content: record.content,
            existingTags: existingTags
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let s):
                    self.updateRecordAI(
                        id: record.id, 
                        title: s.title, 
                        summary: s.summary, 
                        confidence: s.confidence, 
                        aiStatus: "success",
                        tags: s.tags,
                        keywords: s.keywords
                    )
                    self.lastAISuccessAt = Date()
                case .failure:
                    self.updateRecordAI(id: record.id, title: nil, summary: nil, confidence: nil, aiStatus: "fail")
                }
            }
        }
    }
    
    /// 检查是否应该显示 AI 成功动画
    /// 只有当成功时间真正更新且与上次处理的时间不同时才返回 true
    func shouldShowAISuccessAnimation() -> Bool {
        guard let newSuccessTime = lastAISuccessAt else { return false }
        
        // 如果没有处理过的时间，或者时间不同，则应该显示动画
        if lastProcessedAISuccessAt == nil || lastProcessedAISuccessAt! != newSuccessTime {
            lastProcessedAISuccessAt = newSuccessTime
            return true
        }
        
        return false
    }
    
    /// 检查是否应该显示粘贴成功动画
    /// 只有当粘贴成功时间真正更新且与上次处理的时间不同时才返回 true
    func shouldShowPasteSuccessAnimation() -> Bool {
        guard let newSuccessTime = lastPasteSuccessAt else { return false }
        
        // 如果没有处理过的时间，或者时间不同，则应该显示动画
        if lastProcessedPasteSuccessAt == nil || lastProcessedPasteSuccessAt! != newSuccessTime {
            lastProcessedPasteSuccessAt = newSuccessTime
            return true
        }
        
        return false
    }
}
