import Foundation
import CoreData
import os

final class CoreDataStack {
    static let shared = CoreDataStack()
    private static let logger = Logger(subsystem: "com.quitenote.app", category: "CoreDataStack")

    let container: NSPersistentContainer
    /// 持久化存储加载失败（文件损坏、目录不可写、旧库迁移不了）时非 nil。
    /// 上层据此区分"查不到记录"和"数据库根本没打开"——后者绝不能当成记录已被删除
    private(set) var loadError: Error?

    /// 迁移失败的原因
    enum StoreError: Error {
        /// 库是某个不认识的历史模型建的
        case unrecognizedStoreModel
    }

    /// 历史模型，旧 → 新。数据模型是代码手写的（没有 .xcdatamodeld 的版本文件），
    /// Core Data 自己找不到旧模型，轻量迁移时要在这里把旧版本原样提供出来。
    /// 加字段时：把"加之前"的模型追加到这个列表的末尾，再改 makeModel。
    /// 用闭包是为了让旧模型只在真的需要迁移时才被实例化
    private static let legacyModelBuilders: [() -> NSManagedObjectModel] = [
        { makeModel(includesNoteColor: false, includesFileCount: false) },   // 加 noteColor 字段之前（v1.6.0 及更早）
        { makeModel(includesNoteColor: true, includesFileCount: false) },    // 加 fileCount 字段之前
    ]

    convenience init() {
        self.init(databaseURL: Self.defaultDatabaseURL())
    }

    /// 测试与迁移验证用：显式指定数据库文件
    init(databaseURL url: URL) {
        let opened = Self.open(model: Self.makeModel(includesNoteColor: true, includesFileCount: true), at: url)
        container = opened.container
        loadError = opened.error
    }

    // MARK: - 打开与迁移

    private static func open(model: NSManagedObjectModel, at url: URL) -> (container: NSPersistentContainer, error: Error?) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // 下面 addStore 遇到旧模型的库会自动做轻量迁移——原地改库。动手之前先留一份原库
        backupStoreIfNeeded(at: url, to: model)
        let container = NSPersistentContainer(name: "QuiteNote", managedObjectModel: model)
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        let description = NSPersistentStoreDescription(url: url)
        container.persistentStoreDescriptions = [description]

        if let error = addStore(to: container) {
            // 文件损坏、目录不可写、不是旧模型建的情况，迁移也无能为力
            guard FileManager.default.fileExists(atPath: url.path) else {
                logger.error("记录数据库加载失败: \(error.localizedDescription, privacy: .public)")
                return (container, error)
            }
            do {
                guard try migrateStoreIfNeeded(at: url, to: model) else {
                    logger.error("记录数据库加载失败: \(error.localizedDescription, privacy: .public)")
                    return (container, error)
                }
            } catch {
                logger.error("记录数据库迁移失败: \(error.localizedDescription, privacy: .public)")
                return (container, error)
            }
            // 迁移后换一个干净的容器重开
            let migrated = NSPersistentContainer(name: "QuiteNote", managedObjectModel: model)
            migrated.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            migrated.viewContext.automaticallyMergesChangesFromParent = true
            migrated.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
            if let retryError = addStore(to: migrated) {
                logger.error("记录数据库迁移后仍打不开: \(retryError.localizedDescription, privacy: .public)")
                return (migrated, retryError)
            }
            logger.notice("记录数据库已迁移到当前模型")
            return (migrated, nil)
        }
        return (container, nil)
    }

    private static func addStore(to container: NSPersistentContainer) -> Error? {
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        return loadError
    }

    /// 库是旧模型建的（接下来 Core Data 会自动迁移它）：先把原库拷成 .pre-migration 备份。
    /// 库不存在、或已经是当前模型时什么都不做（每次启动都拷一份就成了垃圾）。
    /// 拷失败不挡迁移，只记日志
    static func backupStoreIfNeeded(at url: URL, to model: NSManagedObjectModel) {
        guard FileManager.default.fileExists(atPath: url.path),
              let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType, at: url, options: nil
              ),
              !model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) else { return }
        do {
            try backupStore(at: url)
            logger.notice("记录数据库是旧模型，迁移前已留原库备份")
        } catch {
            logger.warning("记录数据库迁移前的备份没留成: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 把库拷成 .pre-migration 备份：主文件连同 WAL / SHM 一起拷（Core Data 的 WAL 是持久化的，
    /// 只拷主文件会缺最后几笔写入）。已有备份先删掉——一次迁移只留最近一份
    private static func backupStore(at url: URL) throws {
        let backupURL = url.appendingPathExtension("pre-migration")
        removeSQLiteStore(at: backupURL)
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try FileManager.default.copyItem(at: source, to: URL(fileURLWithPath: backupURL.path + suffix))
        }
    }

    /// 数据库是旧模型建的就做一次轻量迁移到当前模型；已经兼容时返回 false
    static func migrateStoreIfNeeded(at url: URL, to destinationModel: NSManagedObjectModel) throws -> Bool {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: url, options: nil
        )
        if destinationModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) {
            return false
        }

        var sourceModel: NSManagedObjectModel?
        for build in legacyModelBuilders {
            let candidate = build()
            if candidate.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) {
                sourceModel = candidate
                break
            }
        }
        guard let sourceModel else {
            throw StoreError.unrecognizedStoreModel
        }

        let mapping = try NSMappingModel.inferredMappingModel(forSourceModel: sourceModel, destinationModel: destinationModel)
        let temporaryURL = url.deletingLastPathComponent().appendingPathComponent("migration-\(UUID().uuidString).sqlite")
        defer { removeSQLiteStore(at: temporaryURL) }
        try NSMigrationManager(sourceModel: sourceModel, destinationModel: destinationModel).migrateStore(
            from: url, sourceType: NSSQLiteStoreType, options: nil, with: mapping,
            toDestinationURL: temporaryURL, destinationType: NSSQLiteStoreType, destinationOptions: nil
        )

        // 替换前留一份原库：迁移后的数据要是有闪失，还能从这里找回
        try backupStore(at: url)
        // 旧库的 WAL/SHM 残留会盖掉迁移后的内容
        removeSQLiteStore(at: url)
        try NSPersistentStoreCoordinator(managedObjectModel: destinationModel).replacePersistentStore(
            at: url, destinationOptions: nil, withPersistentStoreFrom: temporaryURL, sourceOptions: nil, ofType: NSSQLiteStoreType
        )
        return true
    }

    /// 删掉一个 SQLite 库文件连同它的边车文件（-wal / -shm / -journal）
    private static func removeSQLiteStore(at url: URL) {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    // MARK: - 数据模型

    /// 代码手写的数据模型。两个开关分别表示"加便签底色字段之前"、"加文件数字段之前"的
    /// 历史模型；历史形态的属性名、类型、可选性、默认值一个都不能动——版本哈希靠它们对上老库
    static func makeModel(includesNoteColor: Bool, includesFileCount: Bool) -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "CDRecord"
        entity.managedObjectClassName = NSStringFromClass(CDRecord.self)

        var properties: [NSAttributeDescription] = []

        func attribute(_ name: String, _ type: NSAttributeType, optional: Bool, defaultValue: Any? = nil) {
            let attr = NSAttributeDescription()
            attr.name = name
            attr.attributeType = type
            attr.isOptional = optional
            if let defaultValue { attr.defaultValue = defaultValue }
            properties.append(attr)
        }

        attribute("id", .UUIDAttributeType, optional: false)
        attribute("title", .stringAttributeType, optional: true)
        attribute("content", .stringAttributeType, optional: false)
        attribute("createdAt", .dateAttributeType, optional: false)
        attribute("digest", .stringAttributeType, optional: false)
        attribute("aiStatus", .stringAttributeType, optional: true)
        attribute("summary", .stringAttributeType, optional: true)
        attribute("summaryConfidence", .doubleAttributeType, optional: true)
        attribute("starred", .booleanAttributeType, optional: false, defaultValue: false)
        attribute("copiedAt", .dateAttributeType, optional: true)
        attribute("tagsRaw", .stringAttributeType, optional: true)
        attribute("keywordsRaw", .stringAttributeType, optional: true)
        attribute("sourceApp", .stringAttributeType, optional: true)
        attribute("sourceUrl", .stringAttributeType, optional: true)
        attribute("type", .stringAttributeType, optional: false, defaultValue: "text")
        attribute("skipAI", .booleanAttributeType, optional: false, defaultValue: false)
        attribute("size", .integer64AttributeType, optional: false, defaultValue: 0)
        if includesFileCount {
            attribute("fileCount", .integer64AttributeType, optional: true)
        }
        attribute("noteFrameData", .binaryDataAttributeType, optional: true)
        if includesNoteColor {
            attribute("noteColor", .stringAttributeType, optional: true)
        }

        entity.properties = properties
        model.entities = [entity]
        return model
    }

    /// 按 Bundle ID / 构建路径分库，测试进程经 QN_TEST_STORAGE_ROOT 整体重定向
    static func defaultDatabaseURL() -> URL {
        // 使用 Bundle Identifier 和可执行文件路径分离开发和生产环境的数据
        let bundleID = Bundle.main.bundleIdentifier ?? "com.quitenote.app"
        let executablePath = Bundle.main.executablePath ?? ""

        // 检测是否为开发环境：
        // 1. Bundle ID 包含 "debug" 或 "dev"
        // 2. 可执行文件路径包含 .build (swift build/run 产生的)
        let isDebug = bundleID.contains("debug") || bundleID.contains("dev") || executablePath.contains(".build")

        let dbName = isDebug ? "QuiteNote-Debug.sqlite" : "QuiteNote.sqlite"
        let directoryName = isDebug ? "QuiteNote-Debug" : "QuiteNote"

        // 数据隔离红线：测试进程通过 QN_TEST_STORAGE_ROOT 把数据库重定向到临时目录，
        // 绝不读写真实数据库（生产库 QuiteNote.sqlite / 开发库 QuiteNote-Debug.sqlite 都不碰）
        if let testRoot = ProcessInfo.processInfo.environment["QN_TEST_STORAGE_ROOT"] {
            return URL(fileURLWithPath: testRoot, isDirectory: true).appendingPathComponent(dbName)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(directoryName).appendingPathComponent(dbName)
    }

    /// 记录库是否可用。加载失败时所有查询都会报错或返回空，上层不得据此做删除类决策
    var isStoreUnavailable: Bool { loadError != nil }

    var context: NSManagedObjectContext { container.viewContext }

    /// 在后台执行数据库操作
    /// - Parameter block: 要在后台执行的操作
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask(block)
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
}
