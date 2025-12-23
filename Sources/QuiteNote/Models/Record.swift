import Foundation

/// 记录模型：标题、内容、创建时间与去重哈希
struct Record: Identifiable {
    let id: UUID
    var title: String? = nil
    let content: String
    var createdAt: Date
    let hash: String
    var aiStatus: String? = nil
    var summary: String? = nil
    var summaryConfidence: Double? = nil
    var starred: Bool = false
    var copiedAt: Date? = nil
    var tags: [String] = []
    var keywords: [String] = []
    var sourceApp: String? = nil
    var sourceUrl: String? = nil
}
