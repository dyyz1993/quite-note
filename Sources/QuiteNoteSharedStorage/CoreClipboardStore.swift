import Foundation
import CoreData

public enum SharedStorageError: Error, Equatable {
    case databaseUnavailable(String)
}

/// 常驻核心专用存储层。
///
/// 之所以不直接复用 App target 的 ClipboardHistoryStore：那个类型同时承担 UI 发布、
/// 保留策略定时器、附件删除和面板分页状态，不适合作为 headless 进程的第一块拆分。
/// 这里先锁住同一个 CoreData 模型与库文件契约，后续 UI/App 再迁到共享库 target。
public final class CoreClipboardStore {
    private let container: NSPersistentContainer
    public let storeURL: URL
    public private(set) var insertedCount = 0

    public init(databaseURL: URL) throws {
        storeURL = databaseURL
        let model = ClipboardHistoryPersistence.makeModel()
        container = NSPersistentContainer(name: "QuiteNoteCoreClipboard", managedObjectModel: model)

        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let description = NSPersistentStoreDescription(url: databaseURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            throw SharedStorageError.databaseUnavailable(loadError.localizedDescription)
        }
    }

    /// 插入或按内容哈希更新。返回 false 表示该内容已存在。
    @discardableResult
    public func insert(text: String, sourceApp: String? = nil, sourceBundleID: String? = nil) throws -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let hash = Self.stableHash(trimmed)
        let context = container.viewContext
        var inserted = false
        context.performAndWait {
            let request = NSFetchRequest<CDClipboardEntry>(entityName: "CDClipboardEntry")
            request.predicate = NSPredicate(format: "contentHash == %@", hash)
            request.fetchLimit = 1
            let object = try? context.fetch(request).first ?? {
                let made = CDClipboardEntry(context: context)
                made.id = UUID()
                made.createdAt = Date()
                inserted = true
                return made
            }()
            guard let object else { return }
            object.type = ClipboardTypeDetector.isPureURL(trimmed) ? "link" : "text"
            object.lastUsedAt = Date()
            object.plainText = trimmed
            object.sourceApp = sourceApp
            object.sourceBundleID = sourceBundleID
            object.contentHash = hash
            object.byteSize = Int64(trimmed.utf8.count)
            try? context.save()
        }
        if inserted { insertedCount += 1 }
        return inserted
    }

    public func count() throws -> Int {
        let request = NSFetchRequest<CDClipboardEntry>(entityName: "CDClipboardEntry")
        return try container.viewContext.count(for: request)
    }

    private static func stableHash(_ text: String) -> String {
        // Stable process-independent FNV-1a. The App's schema stores this as a string,
        // so a deterministic hash is sufficient for core-side deduplication.
        let base = "\(Self.trimmedHashSeed)\(text)\(text.utf8.count)"
        var result: UInt64 = 1469598103934665603
        for byte in base.utf8 {
            result ^= UInt64(byte)
            result = result &* 1099511628211
        }
        return String(format: "%016x", result)
    }

    private static let trimmedHashSeed = "quitenote-core-v1"
}


