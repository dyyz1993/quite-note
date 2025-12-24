import Foundation
import Combine
import os.log

/// 记录 AI 协调器：负责 AI 服务的协调、批量处理、状态管理
final class RecordAICOORDINATOR {
    private static let logger = Logger(subsystem: "com.quitenote.app", category: "RecordAICOORDINATOR")

    var ai: AIServiceProtocol?
    private var prefs: PreferencesManager
    private weak var recordStore: RecordStore?

    // AI 配置
    var enableAI: Bool = true
    var titleLimit: Int = 20
    var summaryLimit: Int = 100
    var summaryTrigger: Int = 20

    // 状态追踪
    private(set) var isProcessing: Bool = false

    // 防止重复触发的标志
    private var isBulkProcessing = false

    // 缓存的唯一标签，避免频繁计算
    private var cachedUniqueTags: [String] = []
    private var tagsNeedUpdate: Bool = true

    init(prefs: PreferencesManager = .shared) {
        self.prefs = prefs
        loadPreferences()
    }

    /// 设置关联的 RecordStore（用于获取所有标签）
    func attach(recordStore: RecordStore) {
        self.recordStore = recordStore
    }

    /// 连接 AI 服务
    func attachAI(service: AIServiceProtocol) {
        self.ai = service
        if let s = service as? AIService {
            s.openAIBaseURL = prefs.openAIBaseURL
            s.openAIModel = prefs.openAIModel
        }
    }

    // MARK: - 单条记录处理

    /// 处理单条记录的 AI 总结
    func summarize(
        record: Record,
        existingTags: [String],
        completion: @escaping (RecordAIUpdate) -> Void
    ) {
        guard enableAI, let ai else {
            completion(.none)
            return
        }

        guard record.content.count >= self.summaryTrigger else {
            Self.logger.info("内容长度不足 (\(record.content.count) < \(self.summaryTrigger))，跳过 AI 总结")
            completion(.none)
            return
        }

        isProcessing = true

        ai.summarize(
            contextId: record.id.uuidString,
            titleLimit: titleLimit,
            summaryLimit: summaryLimit,
            content: record.content,
            existingTags: existingTags,
            systemPrompt: prefs.aiSystemPrompt,
            userPrompt: prefs.aiUserPrompt
        ) { [weak self] result in
            guard let self = self else {
                completion(.none)
                return
            }

            self.isProcessing = false

            DispatchQueue.main.async {
                switch result {
                case .success(let s):
                    // 处理标签合并：自动识别的标签 + AI 生成的标签
                    var finalTags: [String]? = s.tags
                    if let aiTags = s.tags {
                        let autoTags = record.tags
                        finalTags = Array(Set(autoTags + aiTags)).sorted()
                    }

                    // 处理关键词：确保都有 # 前缀且不超过 10 个
                    var finalKeywords: [String]? = s.keywords
                    if let aiKeywords = s.keywords {
                        let cleaned = aiKeywords.prefix(10).map { k -> String in
                            let trimmed = k.trimmingCharacters(in: .whitespacesAndNewlines)
                            return trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
                        }
                        finalKeywords = Array(cleaned)
                    }

                    completion(.success(
                        title: s.title,
                        summary: s.summary,
                        confidence: s.confidence,
                        tags: finalTags,
                        keywords: finalKeywords
                    ))
                case .failure:
                    completion(.failure)
                }
            }
        }
    }

    // MARK: - 批量处理

    /// 批量对无标题记录触发重新提炼（每次最多处理指定数量）
    func bulkResummarize(
        records: [Record],
        batchSize: Int = 3,
        progressHandler: @escaping (Int, UUID, Record, RecordAIUpdate) -> Void,
        completion: @escaping () -> Void
    ) {
        guard enableAI, let ai, !isBulkProcessing else {
            if isBulkProcessing {
                Self.logger.info("批量处理已在进行中，跳过重复调用")
            }
            completion()
            return
        }

        let targets = records.enumerated().filter { $0.element.title == nil }.prefix(batchSize)
        guard !targets.isEmpty else {
            Self.logger.info("没有需要处理的记录")
            completion()
            return
        }

        isBulkProcessing = true
        let totalCount = targets.count
        Self.logger.info("开始批量处理 \(totalCount) 条记录")

        let existingTags = getAllUniqueTags(from: records)

        for (index, record) in targets {
            // 检查是否已经在处理中
            guard records[index].aiStatus != "pending" else {
                Self.logger.info("跳过已在处理中的记录: \(index)")
                continue
            }

            // 更新状态为 pending
            progressHandler(index, record.id, record, .none)

            ai.summarize(
                contextId: record.id.uuidString,
                titleLimit: titleLimit,
                summaryLimit: summaryLimit,
                content: record.content,
                existingTags: existingTags,
                systemPrompt: prefs.aiSystemPrompt,
                userPrompt: prefs.aiUserPrompt
            ) { [weak self] result in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    switch result {
                    case .success(let s):
                        // 处理标签合并
                        var finalTags: [String]? = s.tags
                        if let aiTags = s.tags {
                            let autoTags = record.tags
                            finalTags = Array(Set(autoTags + aiTags)).sorted()
                        }

                        // 处理关键词
                        var finalKeywords: [String]? = s.keywords
                        if let aiKeywords = s.keywords {
                            let cleaned = aiKeywords.prefix(10).map { k -> String in
                                let trimmed = k.trimmingCharacters(in: .whitespacesAndNewlines)
                                return trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
                            }
                            finalKeywords = Array(cleaned)
                        }

                        progressHandler(index, record.id, record,
                            .success(
                                title: s.title,
                                summary: s.summary,
                                confidence: s.confidence,
                                tags: finalTags,
                                keywords: finalKeywords
                            )
                        )
                        Self.logger.info("批量处理记录 \(index) 成功")
                    case .failure:
                        progressHandler(index, record.id, record, .failure)
                        Self.logger.info("批量处理记录 \(index) 失败")
                    }

                    // 检查是否全部完成
                    if index == totalCount - 1 {
                        self.isBulkProcessing = false
                    }
                }
            }
        }
    }

    /// 检查是否正在批量处理
    var isBulkProcessingActive: Bool {
        isBulkProcessing
    }

    // MARK: - 标签管理

    /// 获取所有唯一标签
    func getAllUniqueTags(from records: [Record]) -> [String] {
        if !tagsNeedUpdate { return cachedUniqueTags }

        let allTags = records.flatMap { $0.tags }
        cachedUniqueTags = Array(Set(allTags)).sorted()
        tagsNeedUpdate = false
        return cachedUniqueTags
    }

    /// 标记标签需要更新
    func markTagsNeedUpdate() {
        tagsNeedUpdate = true
    }

    // MARK: - 偏好设置

    private func loadPreferences() {
        enableAI = prefs.enableAI
        titleLimit = prefs.titleLimit
        summaryTrigger = prefs.summaryTrigger
        summaryLimit = prefs.summaryLimit
    }

    func savePreferences() {
        prefs.setEnableAI(enableAI)
        prefs.setTitleLimit(titleLimit)
        prefs.setSummaryTrigger(summaryTrigger)
        prefs.setSummaryLimit(summaryLimit)
    }
}

// MARK: - AI 更新结果

enum RecordAIUpdate {
    case none
    case failure
    case success(title: String, summary: String, confidence: Double, tags: [String]?, keywords: [String]?)
}
