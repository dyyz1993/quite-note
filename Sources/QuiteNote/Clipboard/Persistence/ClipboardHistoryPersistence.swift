import Foundation
import CoreData

/// 剪贴板历史的 Core Data 持久层
///
/// 独立容器、独立库文件（ClipboardHistory.sqlite），与正式记录库（QuiteNote.sqlite）
/// 完全隔离——剪贴板历史的写入/清理/清空不可能影响生产记录数据（数据隔离红线）。
/// 隔离口径与 CoreDataStack 一致：dev 变体用 -Debug 后缀，测试进程经
/// QN_TEST_STORAGE_ROOT 重定向到临时目录。
final class ClipboardHistoryPersistence {
    static let shared = ClipboardHistoryPersistence()

    let container: NSPersistentContainer
    /// 剪贴板库文件位置（占用统计用，含 -wal/-shm）
    let storeURL: URL

    init() {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "ClipboardHistory", managedObjectModel: model)

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
        storeURL = databaseURL

        try? FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let desc = NSPersistentStoreDescription(url: databaseURL)
        desc.shouldMigrateStoreAutomatically = true
        desc.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [desc]
        container.loadPersistentStores { _, error in
            if let error {
                DiagnosticCenter.error("Clipboard", "剪贴板历史库加载失败: \(error.localizedDescription)")
            }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    var context: NSManagedObjectContext { container.viewContext }

    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask(block)
    }

    // MARK: - 动态模型

    private static func makeModel() -> NSManagedObjectModel {
        let entity = NSEntityDescription()
        entity.name = "CDClipboardEntry"
        entity.managedObjectClassName = NSStringFromClass(CDClipboardEntry.self)

        func attr(_ name: String, _ type: NSAttributeType, optional: Bool = true, defaultValue: Any? = nil, indexed: Bool = false) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = optional
            a.defaultValue = defaultValue
            a.isIndexed = indexed
            return a
        }

        entity.properties = [
            attr("id", .UUIDAttributeType, optional: false),
            attr("type", .stringAttributeType, optional: false, defaultValue: "text"),
            attr("createdAt", .dateAttributeType, optional: false),
            attr("lastUsedAt", .dateAttributeType, optional: false),
            attr("plainText", .stringAttributeType),
            attr("sourceURL", .stringAttributeType),
            attr("sourceApp", .stringAttributeType),
            attr("sourceBundleID", .stringAttributeType),
            attr("contentHash", .stringAttributeType, optional: false, indexed: true),
            attr("assetPath", .stringAttributeType),
            attr("ocrText", .stringAttributeType),
            attr("ocrStatus", .stringAttributeType),
            attr("byteSize", .integer64AttributeType, optional: false, defaultValue: 0),
            attr("pasteCount", .integer32AttributeType, optional: false, defaultValue: 0),
            attr("isPinned", .booleanAttributeType, optional: false, defaultValue: false),
            attr("savedRecordID", .UUIDAttributeType),
        ]

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }
}

/// 剪贴板条目的 Core Data 托管对象（字段与 ClipboardEntry 一一对应）
final class CDClipboardEntry: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var type: String
    @NSManaged var createdAt: Date
    @NSManaged var lastUsedAt: Date
    @NSManaged var plainText: String?
    @NSManaged var sourceURL: String?
    @NSManaged var sourceApp: String?
    @NSManaged var sourceBundleID: String?
    @NSManaged var contentHash: String
    @NSManaged var assetPath: String?
    @NSManaged var ocrText: String?
    @NSManaged var ocrStatus: String?
    @NSManaged var byteSize: Int64
    @NSManaged var pasteCount: Int32
    @NSManaged var isPinned: Bool
    @NSManaged var savedRecordID: UUID?

    var asValue: ClipboardEntry {
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

    func apply(_ entry: ClipboardEntry) {
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
