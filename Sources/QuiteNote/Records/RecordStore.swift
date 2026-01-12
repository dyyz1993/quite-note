import Foundation
import Combine
import CoreData
import os.log
import SwiftUI

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
    @Published var confirmConfig: ConfirmConfig? = nil

    /// AI 配置（直接存储，同步到 aiCoordinator）
    @Published var enableAI: Bool = true
    @Published var titleLimit: Int = 20
    @Published var summaryTrigger: Int = 20
    @Published var summaryLimit: Int = 100

    /// 是否启用自动去重
    @Published var dedupEnabled: Bool = true

    /// 最大截图保留数
    @Published var maxScreenshots: Int = 200

    /// 附件存储路径
    @Published var attachmentsPath: String = ""

    /// 搜索历史（直接存储，同步到 searchHistoryManager）
    @Published var searchHistory: [String] = []

    /// 筛选类型（nil 表示全部）
    @Published var filterType: RecordType? = nil

    /// 是否有正在处理的 AI 任务
    var isAIProcessing: Bool {
        records.contains { $0.aiStatus == "pending" }
    }

    /// 上次 AI 成功的时间，用于 UI 反馈
    @Published var lastAISuccessAt: Date? = nil

    /// 上次粘贴成功的时间，用于 UI 反馈
    @Published var lastPasteSuccessAt: Date? = nil

    /// 是否折叠收藏夹
    @Published var isStarredCollapsed: Bool = false

    /// 标记是否正在内部拖拽（用于屏蔽应用自身的导入蒙层）
    @Published var isInternalDragging: Bool = false

    /// 全局预览记录
    @Published var previewRecord: Record? = nil
    /// 全局预览位置
    @Published var previewLocation: CGPoint = .zero
    /// 全局预览偏移量（相对于触发点）
    @Published var previewOffset: CGSize = .zero

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
    private var confirmCancellable: AnyCancellable?

    /// 暴露 AI 服务（用于 UI 访问）
    var ai: AIServiceProtocol? {
        aiCoordinator.ai
    }

    /// 隐藏确认对话框
    func dismissConfirm() {
        notifier.dismissConfirm()
    }

    /// 显示统一确认对话框
    func confirm(
        title: String,
        message: String,
        confirmTitle: String = "确定",
        cancelTitle: String? = "取消",
        isDestructive: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        notifier.confirm(
            title: title,
            message: message,
            confirmTitle: confirmTitle,
            cancelTitle: cancelTitle,
            isDestructive: isDestructive,
            action: action
        )
    }

    // MARK: - 附件处理逻辑

    /// 附件存储目录
    public var currentAttachmentsDirectory: URL {
        if !attachmentsPath.isEmpty {
            let customURL = URL(fileURLWithPath: attachmentsPath)
            // 确保目录存在
            try? FileManager.default.createDirectory(at: customURL, withIntermediateDirectories: true)
            return customURL
        }
        
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("QuiteNote", isDirectory: true)
        let attachments = appSupport.appendingPathComponent("Attachments", isDirectory: true)
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        return attachments
    }

    /// 附件存储目录（内部使用）
    private var attachmentsDirectory: URL {
        return currentAttachmentsDirectory
    }

    /// 处理拖拽的文件 URL 列表和直接传入的图片对象
    /// - Parameters:
    ///   - urls: 文件 URL 数组
    ///   - images: 直接传入的 NSImage 数组（常用于网页拖拽）
    func handleDroppedContent(urls: [URL], images: [NSImage]) {
        print("[DEBUG] RecordStore handleDroppedContent 开始处理, URL数量: \(urls.count), 图片数量: \(images.count)")
        
        // 1. 处理 URL
        if !urls.isEmpty {
            handleDroppedUrls(urls)
        }
        
        // 2. 处理直接传入的图片对象
        for image in images {
            do {
                // 网页拖拽的图片通常没有文件名，生成一个
                let fileName = "web_drag_image.png"
                let storedURL = try FileCoordinator.shared.storeImage(image, type: .image, originalName: fileName)
                
                if let virtualPath = FileCoordinator.shared.convertToVirtualPath(from: storedURL) {
                    let content = "网页拖拽图片: \(fileName)"
                    let hash = ClipboardService.sha1(content + UUID().uuidString) // 避免相同内容的图片 hash 重复
                    
                    addRecord(
                        content: content,
                        hash: hash,
                        sourceApp: "Web Drag",
                        sourceUrl: virtualPath,
                        type: .image,
                        skipAI: true,
                        fileName: fileName
                    )
                    
                    // 生成缩略图
                    ThumbnailGenerator.shared.getThumbnailURLAsync(for: storedURL) { _ in }
                    print("[DEBUG] 网页拖拽图片已持久化: \(virtualPath)")
                }
            } catch {
                print("[DEBUG] 网页拖拽图片持久化失败: \(error.localizedDescription)")
            }
        }
        
        if !images.isEmpty {
            // 发送触觉反馈
            HapticFeedbackManager.shared.success()
            // 触发 UI 成功动画
            DispatchQueue.main.async {
                self.lastPasteSuccessAt = Date()
            }
        }
    }

    /// 处理拖拽的文件 URL 列表
    /// - Parameter urls: 文件 URL 数组
    func handleDroppedUrls(_ urls: [URL]) {
        print("[DEBUG] RecordStore handleDroppedUrls 开始处理, 数量: \(urls.count)")
        for url in urls {
            // 获取文件路径
            var finalUrl = url
            let fileName = url.lastPathComponent
            
            // 检查是否是文件夹
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            let isFolder = exists && isDirectory.boolValue
            
            // 确定记录类型
            var recordType: RecordType = isFolder ? .folder : .file
            let imageExtensions = ["png", "jpg", "jpeg", "gif", "tiff", "bmp", "webp", "heic"]
            if !isFolder && imageExtensions.contains(url.pathExtension.lowercased()) {
                recordType = .image
            }
            
            // 使用 FileCoordinator 持久化非文件夹资源
            var sourceUrlStr: String = url.path
            if !isFolder {
                do {
                    let type: ResourceType = (recordType == .image) ? .image : .file
                    let storedURL = try FileCoordinator.shared.storeFile(at: url, type: type)
                    finalUrl = storedURL
                    if let virtualPath = FileCoordinator.shared.convertToVirtualPath(from: storedURL) {
                        sourceUrlStr = virtualPath
                    }
                    
                    // 如果是图片，生成缩略图
                    if recordType == .image {
                        ThumbnailGenerator.shared.getThumbnailURLAsync(for: storedURL) { _ in }
                    }
                    print("[DEBUG] 文件已持久化: \(sourceUrlStr)")
                } catch {
                    print("[DEBUG] 文件持久化失败: \(error.localizedDescription)")
                }
            }
            
            let skipAI = isFolder || recordType == .image
            
            // 处理内容显示
            var content = ""
            if isFolder {
                let treeResult = generateTreeStructure(for: finalUrl)
                content = treeResult.content
                let fileCount = treeResult.fileCount
                let hash = ClipboardService.sha1(content)

                addRecord(
                    content: content,
                    hash: hash,
                    sourceApp: "Folder Drag",
                    sourceUrl: sourceUrlStr,
                    type: .folder,
                    skipAI: skipAI,
                    fileName: fileName,
                    fileCount: fileCount
                )
                continue
            } else {
                // 文本文件读取逻辑
                let textExtensions = ["txt", "md", "js", "ts", "swift", "py", "html", "css", "json", "yml", "yaml", "xml", "c", "cpp", "h"]
                if textExtensions.contains(finalUrl.pathExtension.lowercased()) {
                    do {
                        content = try String(contentsOf: finalUrl, encoding: .utf8)
                    } catch {
                        content = "文件路径: \(finalUrl.path)\n(内容读取失败)"
                    }
                } else {
                    content = "文件路径: \(finalUrl.path)\n文件名: \(fileName)"
                }
            }
            
            let hash = ClipboardService.sha1(content)
            addRecord(
                content: content,
                hash: hash,
                sourceApp: "File Drag",
                sourceUrl: sourceUrlStr,
                type: recordType,
                skipAI: skipAI,
                fileName: fileName
            )
        }
        
        // 发送触觉反馈
        HapticFeedbackManager.shared.success()
        // 触发 UI 成功动画
        DispatchQueue.main.async {
            self.lastPasteSuccessAt = Date()
        }
    }

    // MARK: - 内存管理

    private let prefs = PreferencesManager.shared
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

        // 订阅 confirmConfig 更新
        confirmCancellable = notifier.$confirmConfig
            .sink { [weak self] newValue in
                self?.confirmConfig = newValue
            }
    }

    // MARK: - 核心操作：添加记录

    /// 添加新记录到 Store 和数据库
    func addRecord(
        content: String,
        hash: String,
        sourceApp: String? = nil,
        sourceUrl: String? = nil,
        type: RecordType = .text,
        skipAI: Bool = false,
        fileName: String? = nil,
        fileCount: Int? = nil,
        noteFrame: NSRect? = nil
    ) {
        print("[DEBUG] RecordStore.addRecord 被调用，内容长度: \(content.count), hash: \(hash), type: \(type)")
        // 1. 检查是否已存在相同哈希的记录
        if records.contains(where: { $0.hash == hash }) {
            print("[DEBUG] 记录已存在，仅更新时间戳")
            updateTimestampForHash(hash)
            notifier.postToast("记录已去重，更新了时间戳", type: "info")
            return
        }

        // 2. 创建并保存到数据库
        let now = Date()
        let id = UUID()
        var autoTags = ContentClassifier.classify(content)
        var keywords: [String] = []

        // 文件夹特殊处理：打上 folder 标签，加入关键词
        if type == .folder {
            if !autoTags.contains("folder") {
                autoTags.append("folder")
            }
            if let name = fileName {
                keywords.append(name)
            }
        }

        // 计算文件大小
        var calculatedSize: Int64 = 0
        if type != .text {
            if let path = sourceUrl {
                let fileURL: URL?
                if path.starts(with: "/") {
                    fileURL = URL(fileURLWithPath: path)
                } else {
                    fileURL = FileCoordinator.shared.resolveVirtualPath(path)
                }

                if let url = fileURL {
                    do {
                        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                        calculatedSize = attrs[.size] as? Int64 ?? 0
                    } catch {
                        print("[DEBUG] 获取文件大小失败: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            // 文本记录的大小即为其字符串长度（估算）
            calculatedSize = Int64(content.utf8.count)
        }

        let record = Record(
            id: id,
            title: fileName,
            content: content,
            createdAt: now,
            hash: hash,
            aiStatus: nil,
            summary: nil,
            summaryConfidence: nil,
            starred: false,
            copiedAt: nil,
            tags: autoTags,
            keywords: keywords,
            sourceApp: sourceApp,
            sourceUrl: sourceUrl,
            type: type,
            skipAI: skipAI,
            fileCount: fileCount,
            size: calculatedSize,
            noteFrame: noteFrame
        )

        do { try repository.save(record) }
        catch {
            Self.logger.error("保存记录失败: \(error.localizedDescription)")
        }
        print("[DEBUG] 记录已插入数据库，ID: \(id)")

        // 3. 更新内存列表并排序
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            var recordWithStatus = record
            
            // 4. 触发 AI 总结 (如果启用)
            self.syncToAICoordinator()
            let shouldAI = self.aiCoordinator.enableAI && !skipAI && content.count >= self.aiCoordinator.summaryTrigger
            
            if shouldAI {
                recordWithStatus.aiStatus = "pending"
                Self.logger.info("开始调用AI总结，内容长度: \(content.count)")
            } else {
                Self.logger.info("AI功能未启用、显式跳过或内容长度不足，跳过AI总结")
            }
            
            self.records.insert(recordWithStatus, at: 0)
            print("[DEBUG] 记录已插入内存数组，当前 records.count: \(self.records.count)")
            self.aiCoordinator.markTagsNeedUpdate()
            self.sortRecordsInPlace()

            // 设置粘贴成功时间用于 UI 反馈
            self.notifier.markPasteSuccess()
            self.lastPasteSuccessAt = Date()
            self.notifier.postToast("已自动创建新记录", type: "success")

            // 限制截图最大保留数 (仅针对截图类型)
            if type == .screenshot {
                let screenshots = self.records.filter { $0.type == .screenshot }
                if screenshots.count > self.maxScreenshots {
                    // 找出最旧的非收藏截图进行清理
                    let oldScreenshots = screenshots
                        .filter { !$0.starred } // 不清理收藏的
                        .sorted { $0.createdAt < $1.createdAt }
                    
                    if let toDelete = oldScreenshots.first {
                        self.delete(toDelete)
                        print("[DEBUG] 已自动清理超过上限的旧截图: \(toDelete.id)")
                    }
                }
            }
            
            // 如果需要 AI，则在主线程获取标签后触发
            if shouldAI {
                let existingTags = self.aiCoordinator.getAllUniqueTags(from: self.records)
                self.aiCoordinator.summarize(record: recordWithStatus, existingTags: existingTags) { [weak self] update in
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
        }
    }

    /// 添加现有记录（用于便签保存等场景）
    func addExistingRecord(_ record: Record) {
        // 检查是否已存在相同哈希的记录
        if records.contains(where: { $0.hash == record.hash }) {
            updateTimestampForHash(record.hash)
            notifier.postToast("记录已存在", type: "info")
            return
        }

        // 保存到数据库
        do { try repository.save(record) }
        catch {
            Self.logger.error("保存记录失败: \(error.localizedDescription)")
            notifier.postToast("保存失败", type: "error")
            return
        }

        // 更新 UI
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.records.insert(record, at: 0)
            self.sortRecordsInPlace()
            self.notifier.postToast("已添加记录", type: "success")

            // 触发 AI 总结（如果需要）
            if self.aiCoordinator.enableAI && !record.skipAI && record.content.count >= self.aiCoordinator.summaryTrigger {
                let existingTags = self.aiCoordinator.getAllUniqueTags(from: self.records)
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
                    }
                }
            }
        }
    }

    /// 切换类型筛选
    func toggleFilterType(_ type: RecordType) {
        if filterType == type {
            filterType = nil
        } else {
            filterType = type
        }
    }

    /// 获取筛选后的记录列表
    func filteredRecords() -> [Record] {
        var result = records
        
        // 类型筛选
        if let type = filterType {
            result = result.filter { $0.type == type }
        }
        
        return result
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

    /// 按类型删除记录
    func deleteRecords(ofType type: RecordType) {
        let toDelete = records.filter { $0.type == type }
        for record in toDelete {
            delete(record)
        }
    }

    /// 删除指定记录
    func delete(_ record: Record) {
        print("[DEBUG RecordStore.delete()] 开始删除记录, ID: \(record.id), Type: \(record.type)")
        Self.logger.info("开始删除记录, ID: \(record.id), Type: \(record.type.rawValue)")

        // 1. 如果是文件/图片/截图，尝试将关联的物理文件移动到废纸篓
        if record.type != .text {
            // 优先从 sourceUrl 获取物理路径
            var fileURL: URL? = nil
            if let path = record.sourceUrl {
                if path.starts(with: "/") {
                    fileURL = URL(fileURLWithPath: path)
                } else {
                    // 解析虚拟路径 (如: attachment://...)
                    fileURL = FileCoordinator.shared.resolveVirtualPath(path)
                }
            }

            if let url = fileURL {
                // 安全检查：只有在附件目录下的文件才真正处理
                let attachmentsPath = currentAttachmentsDirectory.path
                if url.path.contains(attachmentsPath) {
                    // 使用 trashItem 代替 removeItem，更安全
                    do {
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                        print("[DEBUG] 已将物理文件移至废纸篓: \(url.path)")
                    } catch {
                        print("[DEBUG] 移至废纸篓失败: \(error.localizedDescription)")
                    }
                    // 缩略图可以直接删除，因为它是可以重新生成的缓存
                    ThumbnailGenerator.shared.removeThumbnail(for: url)
                }
            }
        }

        // 2. 从内存和数据库删除
        records.removeAll { $0.id == record.id }
        aiCoordinator.markTagsNeedUpdate()
        print("[DEBUG RecordStore.delete()] 调用 repository.delete()")
        repository.delete(id: record.id)
        print("[DEBUG RecordStore.delete()] repository.delete() 返回")

        // 3. 通知 StickyNoteManager 清理关联的便签
        if record.type == .note {
            print("[DEBUG RecordStore.delete()] 发送 RecordDeleted 通知, ID: \(record.id)")
            NotificationCenter.default.post(
                name: NSNotification.Name("RecordDeleted"),
                object: record.id
            )
            Self.logger.info("已发送记录删除通知，记录ID: \(record.id)")
        }
        print("[DEBUG RecordStore.delete()] 删除流程完成")
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
            DispatchQueue.main.async {
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

    /// 同步文件夹到本地
    func syncFolder(_ record: Record) {
        guard record.type == .folder, let sourceUrl = record.sourceUrl else { return }
        
        // 如果已经是同步过的虚拟路径，则不再重复同步
        if sourceUrl.hasPrefix("app://attachments/SyncedFolders") {
            Self.logger.info("文件夹已同步: \(sourceUrl)")
            return
        }
        
        let sourceURL = URL(fileURLWithPath: sourceUrl)
        
        // 后台执行同步
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let storedURL = try FileCoordinator.shared.storeFile(at: sourceURL, type: .syncedFolder)
                if let virtualPath = FileCoordinator.shared.convertToVirtualPath(from: storedURL) {
                    DispatchQueue.main.async {
                        self.updateRecordSourceUrl(id: record.id, newUrl: virtualPath)
                        self.notifier.postLightHint("文件夹同步成功")
                    }
                }
            } catch {
                Self.logger.error("文件夹同步失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.notifier.postLightHint("同步失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func updateRecordSourceUrl(id: UUID, newUrl: String) {
        if let idx = records.firstIndex(where: { $0.id == id }) {
            records[idx].sourceUrl = newUrl
            
            // 更新数据库
            do {
                try repository.updateSourceUrl(id: id, sourceUrl: newUrl)
            } catch {
                Self.logger.error("更新数据库 sourceUrl 失败: \(error.localizedDescription)")
            }
        }
    }

    /// 切换收藏状态
    func toggleStar(_ record: Record) {
        if let idx = records.firstIndex(where: { $0.id == record.id }) {
            // 先在主线程更新 UI 状态，确保即时响应
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                records[idx].starred.toggle()
                sortRecordsInPlace()
            }

            // 异步更新数据库
            do {
                try repository.toggleStar(id: record.id)
            } catch {
                Self.logger.error("切换收藏状态失败: \(error.localizedDescription)")
            }
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

    /// 从数据库加载所有记录
    private func loadFromStore() {
        do {
            records = try repository.fetchRecords(limit: 1000, offset: 0)
            print("[DEBUG] RecordStore 从数据库加载了 \(records.count) 条记录")
            
            // 异步补全缺失的 size 信息（针对旧数据）
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.backfillMissingSizes()
            }
        } catch {
            Self.logger.error("从数据库加载记录失败: \(error.localizedDescription)")
        }
    }

    /// 为旧记录补全缺失的 size 信息
    private func backfillMissingSizes() {
        let recordsToUpdate = records.filter { $0.type != .text && $0.size == 0 }
        guard !recordsToUpdate.isEmpty else { return }
        
        print("[DEBUG] 开始补全 \(recordsToUpdate.count) 条旧记录的 size 信息")
        
        for record in recordsToUpdate {
            var size: Int64 = 0
            
            // 尝试获取物理路径
            var fileURL: URL? = nil
            if let path = record.sourceUrl {
                if path.starts(with: "/") {
                    fileURL = URL(fileURLWithPath: path)
                } else {
                    fileURL = FileCoordinator.shared.resolveVirtualPath(path)
                }
            }
            
            if let url = fileURL {
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                    size = attrs[.size] as? Int64 ?? 0
                } catch {}
            }
            
            if size > 0 {
                // 更新内存和数据库
                DispatchQueue.main.async { [weak self] in
                    if let idx = self?.records.firstIndex(where: { $0.id == record.id }) {
                        self?.records[idx].size = size
                        // 这里可以考虑批量保存，或者直接单条保存
                        try? self?.repository.updateSize(id: record.id, size: size)
                    }
                }
            }
        }
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

    // MARK: - 便签内容更新

    /// 更新便签记录的内容、标题和位置（同步执行，确保更新完成）
    /// - Returns: 是否成功更新（false 表示记录不存在）
    @discardableResult
    func updateContent(
        id: UUID,
        content: String,
        title: String?,
        noteFrame: NSRect?
    ) -> Bool {
        var success = false
        var recordExists = false

        // 先检查记录是否存在
        if let index = records.firstIndex(where: { $0.id == id }) {
            recordExists = true
            let oldRecord = records[index]

            // 创建新的 Record 对象
            let updatedRecord = Record(
                id: oldRecord.id,
                title: title,
                content: content,
                createdAt: oldRecord.createdAt,
                hash: oldRecord.hash,
                aiStatus: oldRecord.aiStatus,
                summary: oldRecord.summary,
                summaryConfidence: oldRecord.summaryConfidence,
                starred: oldRecord.starred,
                copiedAt: oldRecord.copiedAt,
                tags: oldRecord.tags,
                keywords: oldRecord.keywords,
                sourceApp: oldRecord.sourceApp,
                sourceUrl: oldRecord.sourceUrl,
                type: oldRecord.type,
                skipAI: oldRecord.skipAI,
                fileCount: oldRecord.fileCount,
                size: oldRecord.size,
                noteFrame: noteFrame ?? oldRecord.noteFrame
            )

            // 更新内存
            records[index] = updatedRecord

            // 同步保存到数据库（使用 updateSync 更新现有记录）
            do {
                try repository.updateSync(updatedRecord)
                Self.logger.info("便签记录已更新: \(id)")

                // 在主线程发送通知和提示
                DispatchQueue.main.async {
                    self.notifier.postToast("记录已更新", type: "success")
                    // 发送记录更新通知，让UI刷新
                    self.objectWillChange.send()
                }
                success = true
            } catch {
                Self.logger.error("更新便签记录失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.notifier.postToast("更新失败: \(error.localizedDescription)", type: "error")
                }
            }
        }

        if !recordExists {
            // 记录不存在，发送通知告知便签清除 syncRecordId
            Self.logger.warning("尝试更新不存在的记录: \(id)")
            NotificationCenter.default.post(
                name: NSNotification.Name("StickyNoteUpdateFailed"),
                object: id
            )
        }

        return success
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

    /// 从 UserDefaults 加载偏好设置
    func loadPreferences() {
        enableAI = prefs.enableAI
        titleLimit = prefs.titleLimit
        summaryTrigger = prefs.summaryTrigger
        summaryLimit = prefs.summaryLimit
        dedupEnabled = prefs.dedupEnabled
        maxScreenshots = prefs.maxScreenshots
        attachmentsPath = prefs.attachmentsPath ?? ""

        // 同步到 AI 协调器
        syncToAICoordinator()
        syncToSearcher()

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
        prefs.setMaxScreenshots(maxScreenshots)
        prefs.setAttachmentsPath(attachmentsPath.isEmpty ? nil : attachmentsPath)

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

// MARK: - 文件夹 Tree 结构生成

extension RecordStore {
    /// Tree 结构生成结果
    private struct TreeResult {
        let content: String
        let fileCount: Int
    }

    /// 为文件夹生成 tree 结构的内容
    private func generateTreeStructure(for folderURL: URL) -> TreeResult {
        let folderName = folderURL.lastPathComponent
        let folderPath = folderURL.path

        // 递归遍历文件夹，生成 tree 结构
        func traverseDirectory(_ url: URL, level: Int = 0) -> (lines: [String], fileCount: Int) {
            var lines: [String] = []
            var fileCount = 0
            let indent = String(repeating: "│  ", count: level)
            _ = String(repeating: "└── ", count: 1)

            do {
                let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.nameKey, .isDirectoryKey], options: [.skipsHiddenFiles])

                // 排序：文件夹在前，文件在后
                let sorted = contents.sorted { a, b in
                    let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if aIsDir != bIsDir {
                        return aIsDir && !bIsDir  // 文件夹排在前面
                    }
                    return a.lastPathComponent < b.lastPathComponent
                }

                for (index, item) in sorted.enumerated() {
                    let name = item.lastPathComponent
                    let isDirectory = (try? item.resourceValues(forKeys: [URLResourceKey.isDirectoryKey]))?.isDirectory ?? false

                    let isLast = index == sorted.count - 1
                    let prefix = isLast ? "└── " : "├── "
                    let connector = isLast ? "    " : "│   "

                    if isDirectory {
                        lines.append("\(indent)\(prefix)\(name)/")
                        let subResult = traverseDirectory(item, level: level + 1)
                        fileCount += subResult.fileCount

                        // 添加子项内容
                        for subLine in subResult.lines {
                            lines.append("\(indent)\(connector)\(subLine)")
                        }
                    } else {
                        lines.append("\(indent)\(prefix)\(name)")
                        fileCount += 1
                    }
                }
            } catch {
                lines.append("\(indent)└── (无法读取内容)")
            }

            return (lines, fileCount)
        }

        var resultLines: [String] = []
        resultLines.append("文件夹路径: \(folderPath)")
        resultLines.append("文件夹名: \(folderName)")
        resultLines.append("文件结构:")
        resultLines.append(".")

        let (treeLines, totalFiles) = traverseDirectory(folderURL)
        resultLines.append(contentsOf: treeLines)

        let content = resultLines.joined(separator: "\n")
        return TreeResult(content: content, fileCount: totalFiles)
    }
}
