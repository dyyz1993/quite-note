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
}
