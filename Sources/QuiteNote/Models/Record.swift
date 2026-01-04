import Foundation

/// 记录类型
enum RecordType: String, Codable, CaseIterable {
    case text = "text"
    case file = "file"
    case folder = "folder"
    case image = "image"
    case video = "video"
    case screenshot = "screenshot"
}

/// 记录模型：标题、内容、创建时间与去重哈希
struct Record: Identifiable, Equatable {
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
    var type: RecordType = .text
    var skipAI: Bool = false
    var fileCount: Int? = nil  // 文件夹包含的文件数量

    static func == (lhs: Record, rhs: Record) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.content == rhs.content &&
        lhs.createdAt == rhs.createdAt &&
        lhs.hash == rhs.hash &&
        lhs.aiStatus == rhs.aiStatus &&
        lhs.summary == rhs.summary &&
        lhs.summaryConfidence == rhs.summaryConfidence &&
        lhs.starred == rhs.starred &&
        lhs.copiedAt == rhs.copiedAt &&
        lhs.tags == rhs.tags &&
        lhs.keywords == rhs.keywords &&
        lhs.sourceApp == rhs.sourceApp &&
        lhs.sourceUrl == rhs.sourceUrl &&
        lhs.type == rhs.type &&
        lhs.skipAI == rhs.skipAI &&
        lhs.fileCount == rhs.fileCount
    }
}
