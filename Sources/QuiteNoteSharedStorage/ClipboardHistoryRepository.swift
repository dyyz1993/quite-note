import Foundation
import CoreData
#if canImport(Darwin)
import Darwin
#endif

/// 剪贴板内容稳定哈希。
///
/// 这里刻意不用安全哈希：该字段只做内容去重，不承担安全职责。FNV-1a 在
/// App/Core 两个进程中稳定、无依赖，且比旧 App 的“逐字节十六进制拼接”更省内存。
public enum ClipboardContentHasher {
    private static let seed = "quitenote-clipboard-v1"

    public static func hash(_ text: String) -> String {
        let payload = "\(seed)\(text)\(text.utf8.count)"
        var value: UInt64 = 1_469_598_103_934_665_603
        for byte in payload.utf8 {
            value ^= UInt64(byte)
            value = value &* 1_099_511_628_211
        }
        return String(format: "%016x", value)
    }
}

/// App/Core 共用的剪贴板历史仓库。
///
/// UI Store 只保留发布状态与 App 专属副作用（通知、附件清理）；分页、写入、
/// 清理和跨进程变更监听都收敛到这里，保证双进程读写同一 SQLite 契约。
public final class ClipboardHistoryRepository {
    public struct UpsertResult: Equatable {
        public let entry: ClipboardEntry
        public var inserted: Bool
    }

    private let persistence: ClipboardHistoryPersistence
    private var remoteObservers: [UUID: (() -> Void)] = [:]
    private var notificationObservers: [UUID: NSObjectProtocol] = [:]
    private let upsertLock = NSLock()
    private let crossProcessLock: CrossProcessFileLock

    public init(persistence: ClipboardHistoryPersistence) {
        self.persistence = persistence
        self.crossProcessLock = CrossProcessFileLock(
            url: persistence.storeURL.appendingPathExtension("lock")
        )
    }

    /// CoreService 专用：既保留显式校验数据库可用性的入口，又统一走仓库写入。
    public convenience init(coreStore: CoreClipboardStore) {
        self.init(persistence: ClipboardHistoryPersistence(databaseURL: coreStore.storeURL))
    }

    public var storeURL: URL { persistence.storeURL }

    private func makeBackgroundContext() -> NSManagedObjectContext {
        let context = persistence.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    // MARK: - Reads

    public func fetchPage(limit: Int, offset: Int) -> [ClipboardEntry] {
        var entries: [ClipboardEntry] = []
        let context = makeBackgroundContext()
        context.performAndWait {
            let request = NSFetchRequest<CDClipboardEntry>(entityName: "CDClipboardEntry")
            request.sortDescriptors = [
                NSSortDescriptor(key: "isPinned", ascending: false),
                NSSortDescriptor(key: "createdAt", ascending: false),
            ]
            request.fetchLimit = limit
            request.fetchOffset = offset
            entries = ((try? context.fetch(request)) ?? []).map(\.asValue)
        }
        return entries
    }

    public func totalCount() -> Int {
        var count = 0
        let context = makeBackgroundContext()
        context.performAndWait {
            let request = NSFetchRequest<CDClipboardEntry>(entityName: "CDClipboardEntry")
            count = (try? context.count(for: request)) ?? 0
        }
        return count
    }

    public func fetchAllInBackground(completion: @escaping ([ClipboardEntry]) -> Void) {
        let context = makeBackgroundContext()
        context.perform {
            let request = NSFetchRequest<CDClipboardEntry>(entityName: "CDClipboardEntry")
            request.sortDescriptors = [
                NSSortDescriptor(key: "isPinned", ascending: false),
                NSSortDescriptor(key: "createdAt", ascending: false),
            ]
            let entries = ((try? context.fetch(request)) ?? []).map(\.asValue)
            DispatchQueue.main.async {
                completion(entries)
            }
        }
    }

    // MARK: - Writes

    @discardableResult
    public func insertOrUpdate(_ input: ClipboardEntry) throws -> UpsertResult {
        upsertLock.lock()
        defer { upsertLock.unlock() }
        let lockToken = try crossProcessLock.lock()
        defer { lockToken.unlock() }
        var result = UpsertResult(entry: input, inserted: false)
        var writeError: Error?
        let context = makeBackgroundContext()
        context.performAndWait {
            let request = NSFetchRequest<CDClipboardEntry>(entityName: "CDClipboardEntry")
            // A file reference and copied text can contain the same path, but
            // have different paste semantics. Deduplicate only within one type;
            // retain the text fallback for entries written with legacy hashes.
            var contentPredicates = [NSPredicate(format: "contentHash == %@", input.contentHash)]
            if let text = input.plainText {
                contentPredicates.append(NSPredicate(format: "plainText == %@", text))
            }
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "type == %@", input.type.rawValue),
                NSCompoundPredicate(orPredicateWithSubpredicates: contentPredicates),
            ])
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            request.fetchLimit = 1

            let object = (try? context.fetch(request))?.first ?? CDClipboardEntry(context: context)
            result.inserted = object.isInserted
            if result.inserted {
                object.apply(input)
            } else {
                var touched = object.asValue
                touched.type = input.type
                touched.plainText = input.plainText
                touched.sourceURL = input.sourceURL ?? touched.sourceURL
                touched.sourceApp = input.sourceApp ?? touched.sourceApp
                touched.sourceBundleID = input.sourceBundleID ?? touched.sourceBundleID
                touched.assetPath = input.assetPath ?? touched.assetPath
                touched.ocrStatus = input.ocrStatus ?? touched.ocrStatus
                touched.ocrText = input.ocrText ?? touched.ocrText
                touched.byteSize = input.byteSize
                touched.createdAt = input.createdAt
                touched.lastUsedAt = input.lastUsedAt
                object.apply(touched)
            }
            object.lastUsedAt = Date()
            do {
                try context.save()
            } catch {
                context.rollback()
                writeError = error
                return
            }
            result = UpsertResult(entry: object.asValue, inserted: result.inserted)
        }
        if let writeError { throw writeError }
        return result
    }

    @discardableResult
    public func insertText(
        _ text: String,
        sourceApp: String? = nil,
        sourceBundleID: String? = nil,
        createdAt: Date = Date()
    ) throws -> UpsertResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return UpsertResult(entry: .init(type: .text, contentHash: ""), inserted: false) }
        let type: ClipboardEntryType = ClipboardTypeDetector.isPureURL(trimmed) ? .link : .text
        let entry = ClipboardEntry(
            type: type,
            createdAt: createdAt,
            plainText: trimmed,
            sourceApp: sourceApp,
            sourceBundleID: sourceBundleID,
            contentHash: ClipboardContentHasher.hash(trimmed),
            byteSize: Int64(trimmed.utf8.count)
        )
        return try insertOrUpdate(entry)
    }

    @discardableResult
    public func update(id: UUID, transform: (inout ClipboardEntry) -> Void) -> ClipboardEntry? {
        var updated: ClipboardEntry?
        let context = makeBackgroundContext()
        context.performAndWait {
            let request = NSFetchRequest<CDClipboardEntry>(entityName: "CDClipboardEntry")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            guard let object = (try? context.fetch(request))?.first else { return }
            var value = object.asValue
            transform(&value)
            object.apply(value)
            try? context.save()
            updated = object.asValue
        }
        return updated
    }

    @discardableResult
    public func delete(id: UUID) -> ClipboardEntry? {
        var removed: ClipboardEntry?
        let context = makeBackgroundContext()
        context.performAndWait {
            let request = NSFetchRequest<CDClipboardEntry>(entityName: "CDClipboardEntry")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            guard let object = (try? context.fetch(request))?.first else { return }
            removed = object.asValue
            context.delete(object)
            try? context.save()
        }
        return removed
    }

    public func deleteIDs(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let context = makeBackgroundContext()
        context.performAndWait {
            let request = NSFetchRequest<CDClipboardEntry>(entityName: "CDClipboardEntry")
            request.predicate = NSPredicate(format: "id IN %@", Array(ids))
            ((try? context.fetch(request)) ?? []).forEach(context.delete)
            try? context.save()
        }
    }

    public func clearAll() {
        let context = makeBackgroundContext()
        context.performAndWait {
            let request = NSFetchRequest<CDClipboardEntry>(entityName: "CDClipboardEntry")
            ((try? context.fetch(request)) ?? []).forEach(context.delete)
            try? context.save()
        }
    }

    // MARK: - Retention

    @discardableResult
    public func applyRetention(
        now: Date = Date(),
        retentionDays: Int,
        maxEntries: Int
    ) -> [ClipboardEntry] {
        let all = fetchPage(limit: .max, offset: 0)
        let ids = Self.retentionVictims(
            all,
            now: now,
            retentionDays: retentionDays,
            maxEntries: maxEntries
        )
        guard !ids.isEmpty else { return [] }
        let victims = all.filter { ids.contains($0.id) }
        deleteIDs(ids)
        return victims
    }

    public static func retentionVictims(
        _ entries: [ClipboardEntry],
        now: Date,
        retentionDays: Int,
        maxEntries: Int
    ) -> Set<UUID> {
        var victims = Set<UUID>()

        if retentionDays > 0 {
            let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
            for entry in entries where !entry.isPinned && entry.savedRecordID == nil && entry.createdAt < cutoff {
                victims.insert(entry.id)
            }
        }

        let evictable = entries
            .filter { !$0.isPinned && $0.savedRecordID == nil && !victims.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
        // Expired entries were already excluded above. Subtracting victims
        // again would leave the remaining ordinary history over its limit.
        if evictable.count > maxEntries {
            let overflow = evictable.count - maxEntries
            for entry in evictable.prefix(overflow) {
                victims.insert(entry.id)
            }
        }

        return victims
    }

    // MARK: - Cross-process changes

    @discardableResult
    public func addRemoteChangeObserver(_ handler: @escaping () -> Void) -> UUID {
        let id = UUID()
        remoteObservers[id] = handler
        let observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.persistence.context.perform {
                self.persistence.context.reset()
            }
            for handler in self.remoteObservers.values {
                handler()
            }
        }
        notificationObservers[id] = observer
        return id
    }

    public func removeRemoteChangeObserver(_ id: UUID) {
        remoteObservers[id] = nil
        if let observer = notificationObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    deinit {
        for observer in notificationObservers.values {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

/// `flock` wraps an app/Core-wide critical section around the read-then-save upsert.
private final class CrossProcessFileLock {
    private let fileDescriptor: CInt

    init(url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        fileDescriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
    }

    deinit {
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }

    func lock() throws -> Token {
        guard fileDescriptor >= 0 else {
            throw SharedStorageError.lockUnavailable("cannot open lock file")
        }
        let result = flock(fileDescriptor, LOCK_EX)
        guard result == 0 else {
            throw SharedStorageError.lockUnavailable("flock failed")
        }
        return Token(fileDescriptor: fileDescriptor)
    }

    struct Token {
        private let fileDescriptor: CInt

        init(fileDescriptor: CInt) {
            self.fileDescriptor = fileDescriptor
        }

        func unlock() {
            _ = flock(fileDescriptor, LOCK_UN)
        }
    }
}
