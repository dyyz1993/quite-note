import Foundation

/// AI 总结结果结构：标题、总结、置信度、标签与关键词
struct SummaryResult: Codable {
    let title: String
    let summary: String
    let confidence: Double
    let tags: [String]?
    let keywords: [String]?
}

/// AI 请求配置
struct AIRequestConfig {
    let contextId: String?
    let titleLimit: Int
    let summaryLimit: Int
    let content: String
    let existingTags: [String]
    let systemPrompt: String?
    let userPrompt: String?
    let timestamp: Date

    init(contextId: String? = nil,
         titleLimit: Int = 30,
         summaryLimit: Int = 100,
         content: String,
         existingTags: [String] = [],
         systemPrompt: String? = nil,
         userPrompt: String? = nil) {
        self.contextId = contextId
        self.titleLimit = titleLimit
        self.summaryLimit = summaryLimit
        self.content = content
        self.existingTags = existingTags
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.timestamp = Date()
    }
}

/// AI 队列中的请求项
struct AIRequestItem {
    let id = UUID()
    let config: AIRequestConfig
    let completion: (Result<SummaryResult, Error>) -> Void
}

/// AI 服务常量
enum AIConstants {
    static let defaultTitleLimit = 30
    static let defaultSummaryLimit = 100
    static let defaultMaxTokens = 5000
    static let defaultTemperature = 0.3
    static let defaultTimeout: TimeInterval = 60
    static let maxConcurrentRequests = 3
    static let fallbackTitleLength = 15
}
