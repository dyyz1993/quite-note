import Foundation
import CoreData

/// 剪贴板历史的 Core Data 持久层
///
/// 独立容器、独立库文件（ClipboardHistory.sqlite），与正式记录库（QuiteNote.sqlite）
/// 完全隔离——剪贴板历史的写入/清理/清空不可能影响生产记录数据（数据隔离红线）。
/// 隔离口径与 CoreDataStack 一致：dev 变体用 -Debug 后缀，测试进程经
/// QN_TEST_STORAGE_ROOT 重定向到临时目录。
public final class ClipboardHistoryPersistence {
    public static let shared = ClipboardHistoryPersistence()

    public let container: NSPersistentContainer
    /// 剪贴板库文件位置（占用统计用，含 -wal/-shm）
    public let storeURL: URL
    /// Store load/migration failure description; nil means the SQLite store opened.
    public private(set) var storageLoadErrorDescription: String?

    public init() {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "ClipboardHistory", managedObjectModel: model)
        let databaseURL = Self.defaultDatabaseURL()
        storeURL = databaseURL

        try? FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let desc = NSPersistentStoreDescription(url: databaseURL)
        desc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        desc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        desc.shouldMigrateStoreAutomatically = true
        desc.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [desc]
        loadStores()
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    public init(databaseURL: URL) {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "ClipboardHistory", managedObjectModel: model)
        storeURL = databaseURL

        try? FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let desc = NSPersistentStoreDescription(url: databaseURL)
        desc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        desc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        desc.shouldMigrateStoreAutomatically = true
        desc.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [desc]
        loadStores()
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    private func loadStores() {
        container.loadPersistentStores { [weak self] _, error in
            self?.storageLoadErrorDescription = error.map {
                ($0 as NSError).localizedDescription.isEmpty
                    ? "ClipboardHistory store failed to open"
                    : ($0 as NSError).localizedDescription
            }
        }
    }

    private static func defaultDatabaseURL() -> URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.quitenote.app"
        let executablePath = Bundle.main.executablePath ?? ""
        let isDebug = bundleID.contains("debug") || bundleID.contains("dev") || executablePath.contains(".build")
        let dbName = isDebug ? "ClipboardHistory-Debug.sqlite" : "ClipboardHistory.sqlite"

        let databaseURL: URL
        if let testRoot = ProcessInfo.processInfo.environment["QN_TEST_STORAGE_ROOT"] {
            databaseURL = URL(fileURLWithPath: testRoot, isDirectory: true).appendingPathComponent(dbName)
        } else {
            // 与 CoreDataStack 同目录（QuiteNote / QuiteNote-Debug），便于用户备份与排查
            let directoryName = isDebug ? "QuiteNote-Debug" : "QuiteNote"
            databaseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent(directoryName, isDirectory: true)
                .appendingPathComponent(dbName)
        }
        return databaseURL
    }

    public var context: NSManagedObjectContext { container.viewContext }

    public func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask(block)
    }

    // MARK: - 动态模型

    public static func makeModel() -> NSManagedObjectModel {
        let entity = NSEntityDescription()
        entity.name = "CDClipboardEntry"
        entity.managedObjectClassName = NSStringFromClass(CDClipboardEntry.self)

        func attr(_ name: String, _ type: NSAttributeType, optional: Bool = true, defaultValue: Any? = nil) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = optional
            a.defaultValue = defaultValue
            return a
        }

        let contentHash = attr("contentHash", .stringAttributeType, optional: false)
        entity.properties = [
            attr("id", .UUIDAttributeType, optional: false),
            attr("type", .stringAttributeType, optional: false, defaultValue: "text"),
            attr("createdAt", .dateAttributeType, optional: false),
            attr("lastUsedAt", .dateAttributeType, optional: false),
            attr("plainText", .stringAttributeType),
            attr("sourceURL", .stringAttributeType),
            attr("sourceApp", .stringAttributeType),
            attr("sourceBundleID", .stringAttributeType),
            contentHash,
            attr("assetPath", .stringAttributeType),
            attr("ocrText", .stringAttributeType),
            attr("ocrStatus", .stringAttributeType),
            attr("byteSize", .integer64AttributeType, optional: false, defaultValue: 0),
            attr("pasteCount", .integer32AttributeType, optional: false, defaultValue: 0),
            attr("isPinned", .booleanAttributeType, optional: false, defaultValue: false),
            attr("savedRecordID", .UUIDAttributeType),
        ]
        let contentHashIndexElement = NSFetchIndexElementDescription(
            property: contentHash,
            collationType: .binary
        )
        entity.indexes = [
            NSFetchIndexDescription(
                name: "CDClipboardEntry_contentHash",
                elements: [contentHashIndexElement]
            )
        ]

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }
}

/// 剪贴板条目的 Core Data 托管对象（字段与 ClipboardEntry 一一对应）
public final class CDClipboardEntry: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var type: String
    @NSManaged public var createdAt: Date
    @NSManaged public var lastUsedAt: Date
    @NSManaged public var plainText: String?
    @NSManaged public var sourceURL: String?
    @NSManaged public var sourceApp: String?
    @NSManaged public var sourceBundleID: String?
    @NSManaged public var contentHash: String
    @NSManaged public var assetPath: String?
    @NSManaged public var ocrText: String?
    @NSManaged public var ocrStatus: String?
    @NSManaged public var byteSize: Int64
    @NSManaged public var pasteCount: Int32
    @NSManaged public var isPinned: Bool
    @NSManaged public var savedRecordID: UUID?

    public var asValue: ClipboardEntry {
        ClipboardEntry(
            id: id,
            type: ClipboardEntryType(rawValue: type) ?? .text,
            createdAt: createdAt,
            lastUsedAt: lastUsedAt,
            plainText: plainText,
            sourceURL: sourceURL,
            sourceApp: sourceApp,
            sourceBundleID: sourceBundleID,
            contentHash: contentHash,
            assetPath: assetPath,
            ocrText: ocrText,
            ocrStatus: ocrStatus.flatMap(ClipboardOCRStatus.init(rawValue:)),
            byteSize: byteSize,
            pasteCount: Int(pasteCount),
            isPinned: isPinned,
            savedRecordID: savedRecordID
        )
    }

    public func apply(_ entry: ClipboardEntry) {
        id = entry.id
        type = entry.type.rawValue
        createdAt = entry.createdAt
        lastUsedAt = entry.lastUsedAt
        plainText = entry.plainText
        sourceURL = entry.sourceURL
        sourceApp = entry.sourceApp
        sourceBundleID = entry.sourceBundleID
        contentHash = entry.contentHash
        assetPath = entry.assetPath
        ocrText = entry.ocrText
        ocrStatus = entry.ocrStatus?.rawValue
        byteSize = entry.byteSize
        pasteCount = Int32(entry.pasteCount)
        isPinned = entry.isPinned
        savedRecordID = entry.savedRecordID
    }
}
