import Foundation
import CoreData

@objc(CDRecord)
final class CDRecord: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var title: String?
    @NSManaged var content: String
    @NSManaged var createdAt: Date
    @NSManaged var digest: String
    @NSManaged var aiStatus: String?
    @NSManaged var summary: String?
    @NSManaged var summaryConfidence: Double
    @NSManaged var starred: Bool
    @NSManaged var copiedAt: Date?
    @NSManaged var tagsRaw: String?
    @NSManaged var keywordsRaw: String?
    @NSManaged var sourceApp: String?
    @NSManaged var sourceUrl: String?
    @NSManaged var type: String?
    @NSManaged var skipAI: Bool
    @NSManaged var size: Int64
    @NSManaged var noteFrameData: Data?  // 便签窗口位置（编码后的 NSRect）
}
