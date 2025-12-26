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

        let tagsAttr = NSAttributeDescription()
        tagsAttr.name = "tagsRaw"
        tagsAttr.attributeType = .stringAttributeType
        tagsAttr.isOptional = true

        let keywordsAttr = NSAttributeDescription()
        keywordsAttr.name = "keywordsRaw"
        keywordsAttr.attributeType = .stringAttributeType
        keywordsAttr.isOptional = true

        let sourceAppAttr = NSAttributeDescription()
        sourceAppAttr.name = "sourceApp"
        sourceAppAttr.attributeType = .stringAttributeType
        sourceAppAttr.isOptional = true

        let sourceUrlAttr = NSAttributeDescription()
        sourceUrlAttr.name = "sourceUrl"
        sourceUrlAttr.attributeType = .stringAttributeType
        sourceUrlAttr.isOptional = true

        let typeAttr = NSAttributeDescription()
        typeAttr.name = "type"
        typeAttr.attributeType = .stringAttributeType
        typeAttr.isOptional = false
        typeAttr.defaultValue = "text"

        let skipAIAttr = NSAttributeDescription()
        skipAIAttr.name = "skipAI"
        skipAIAttr.attributeType = .booleanAttributeType
        skipAIAttr.isOptional = false
        skipAIAttr.defaultValue = false

        entity.properties = [idAttr, titleAttr, contentAttr, createdAtAttr, digestAttr, aiStatusAttr, summaryAttr, summaryConfAttr, starredAttr, copiedAtAttr, tagsAttr, keywordsAttr, sourceAppAttr, sourceUrlAttr, typeAttr, skipAIAttr]
        model.entities = [entity]

        container = NSPersistentContainer(name: "QuiteNote", managedObjectModel: model)

        // 使用 Bundle Identifier 和可执行文件路径分离开发和生产环境的数据
        let bundleID = Bundle.main.bundleIdentifier ?? "com.quitenote.app"
        let executablePath = Bundle.main.executablePath ?? ""

        // 检测是否为开发环境：
        // 1. Bundle ID 包含 "debug" 或 "dev"
        // 2. 可执行文件路径包含 .build (swift build/run 产生的)
        let isDebug = bundleID.contains("debug") || bundleID.contains("dev") || executablePath.contains(".build")

        let dbName = isDebug ? "QuiteNote-Debug.sqlite" : "QuiteNote.sqlite"
        let directoryName = isDebug ? "QuiteNote-Debug" : "QuiteNote"

        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(directoryName).appendingPathComponent(dbName)

        #if DEBUG
        print("[CoreDataStack] 使用数据库路径: \(url.path)")
        print("[CoreDataStack] Bundle ID: \(bundleID), isDebug: \(isDebug)")
        print("[CoreDataStack] 可执行文件路径: \(executablePath)")
        #endif

        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let desc = NSPersistentStoreDescription(url: url)
        container.persistentStoreDescriptions = [desc]
        container.loadPersistentStores { _, _ in }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    var context: NSManagedObjectContext { container.viewContext }

    /// 在后台执行数据库操作
    /// - Parameter block: 要在后台执行的操作
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask(block)
    }

    func fetchRecords() throws -> [CDRecord] {
        let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
        let sortStarred = NSSortDescriptor(key: "starred", ascending: false)
        let sortDate = NSSortDescriptor(key: "createdAt", ascending: false)
        req.sortDescriptors = [sortStarred, sortDate]
        return try context.fetch(req)
    }
    
    /// 分页查询记录，提高性能和内存效率
    /// - Parameters:
    ///   - limit: 每页记录数，默认50条
    ///   - offset: 偏移量，默认0
    /// - Returns: 指定范围内的记录数组
    func fetchRecords(limit: Int = 50, offset: Int = 0) throws -> [CDRecord] {
        let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
        let sortStarred = NSSortDescriptor(key: "starred", ascending: false)
        let sortDate = NSSortDescriptor(key: "createdAt", ascending: false)
        req.sortDescriptors = [sortStarred, sortDate]
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
        let sortStarred = NSSortDescriptor(key: "starred", ascending: false)
        let sortDate = NSSortDescriptor(key: "createdAt", ascending: false)
        req.sortDescriptors = [sortStarred, sortDate]
        req.predicate = NSPredicate(format: "createdAt >= %@ AND createdAt <= %@", startDate as CVarArg, endDate as CVarArg)
        req.fetchLimit = limit
        req.fetchOffset = offset
        return try context.fetch(req)
    }

    /// 根据日期范围查询所有记录（不分页，用于热力图等统计功能）
    /// - Parameters:
    ///   - startDate: 开始日期
    ///   - endDate: 结束日期
    /// - Returns: 指定日期范围内的所有记录数组
    func fetchAllRecords(from startDate: Date, to endDate: Date) throws -> [CDRecord] {
        let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
        req.predicate = NSPredicate(format: "createdAt >= %@ AND createdAt <= %@", startDate as CVarArg, endDate as CVarArg)
        // 不设置 fetchLimit，获取所有记录
        return try context.fetch(req)
    }

    func newRecord() -> CDRecord {
        CDRecord(context: context)
    }

    func save() { if context.hasChanges { try? context.save() } }
}
