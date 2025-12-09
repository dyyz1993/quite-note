import Foundation
import CoreData

final class CoreDataStack {
    static let shared = CoreDataStack()

    let container: NSPersistentContainer

    init() {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "CDRecord"
        entity.managedObjectClassName = NSStringFromClass(CDRecord.self)

        let idAttr = NSAttributeDescription()
        idAttr.name = "id"
        idAttr.attributeType = .UUIDAttributeType
        idAttr.isOptional = false

        let titleAttr = NSAttributeDescription()
        titleAttr.name = "title"
        titleAttr.attributeType = .stringAttributeType
        titleAttr.isOptional = true

        let contentAttr = NSAttributeDescription()
        contentAttr.name = "content"
        contentAttr.attributeType = .stringAttributeType
        contentAttr.isOptional = false

        let createdAtAttr = NSAttributeDescription()
        createdAtAttr.name = "createdAt"
        createdAtAttr.attributeType = .dateAttributeType
        createdAtAttr.isOptional = false

        let digestAttr = NSAttributeDescription()
        digestAttr.name = "digest"
        digestAttr.attributeType = .stringAttributeType
        digestAttr.isOptional = false

        let aiStatusAttr = NSAttributeDescription()
        aiStatusAttr.name = "aiStatus"
        aiStatusAttr.attributeType = .stringAttributeType
        aiStatusAttr.isOptional = true

        let summaryAttr = NSAttributeDescription()
        summaryAttr.name = "summary"
        summaryAttr.attributeType = .stringAttributeType
        summaryAttr.isOptional = true

        let summaryConfAttr = NSAttributeDescription()
        summaryConfAttr.name = "summaryConfidence"
        summaryConfAttr.attributeType = .doubleAttributeType
        summaryConfAttr.isOptional = true

        let starredAttr = NSAttributeDescription()
        starredAttr.name = "starred"
        starredAttr.attributeType = .booleanAttributeType
        starredAttr.isOptional = false
        starredAttr.defaultValue = false

        let copiedAtAttr = NSAttributeDescription()
        copiedAtAttr.name = "copiedAt"
        copiedAtAttr.attributeType = .dateAttributeType
        copiedAtAttr.isOptional = true

        entity.properties = [idAttr, titleAttr, contentAttr, createdAtAttr, digestAttr, aiStatusAttr, summaryAttr, summaryConfAttr, starredAttr, copiedAtAttr]
        model.entities = [entity]

        container = NSPersistentContainer(name: "QuiteNote", managedObjectModel: model)

        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("QuiteNote").appendingPathComponent("QuiteNote.sqlite")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let desc = NSPersistentStoreDescription(url: url)
        container.persistentStoreDescriptions = [desc]
        container.loadPersistentStores { _, _ in }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    var context: NSManagedObjectContext { container.viewContext }

    func fetchRecords() throws -> [CDRecord] {
        let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
        let sort = NSSortDescriptor(key: "createdAt", ascending: false)
        req.sortDescriptors = [sort]
        return try context.fetch(req)
    }
    
    /// 分页查询记录，提高性能和内存效率
    /// - Parameters:
    ///   - limit: 每页记录数，默认50条
    ///   - offset: 偏移量，默认0
    /// - Returns: 指定范围内的记录数组
    func fetchRecords(limit: Int = 50, offset: Int = 0) throws -> [CDRecord] {
        let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
        let sort = NSSortDescriptor(key: "createdAt", ascending: false)
        req.sortDescriptors = [sort]
        req.fetchLimit = limit
        req.fetchOffset = offset
        return try context.fetch(req)
    }
    
    /// 获取记录总数
    /// - Returns: 记录总数
    func getRecordsCount() throws -> Int {
        let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
        return try context.count(for: req)
    }
    
    /// 根据日期范围查询记录
    /// - Parameters:
    ///   - startDate: 开始日期
    ///   - endDate: 结束日期
    ///   - limit: 每页记录数，默认50条
    ///   - offset: 偏移量，默认0
    /// - Returns: 指定日期范围内的记录数组
    func fetchRecords(from startDate: Date, to endDate: Date, limit: Int = 50, offset: Int = 0) throws -> [CDRecord] {
        let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
        let sort = NSSortDescriptor(key: "createdAt", ascending: false)
        req.sortDescriptors = [sort]
        req.predicate = NSPredicate(format: "createdAt >= %@ AND createdAt <= %@", startDate as CVarArg, endDate as CVarArg)
        req.fetchLimit = limit
        req.fetchOffset = offset
        return try context.fetch(req)
    }

    func newRecord() -> CDRecord {
        CDRecord(context: context)
    }

    func save() { if context.hasChanges { try? context.save() } }
}
