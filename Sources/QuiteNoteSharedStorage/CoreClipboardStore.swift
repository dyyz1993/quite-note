import Foundation


public enum SharedStorageError: Error, Equatable {
    case databaseUnavailable(String)
    case lockUnavailable(String)
}

/// 常驻核心专用存储层。
///
/// CoreService 只用它显式打开/校验同一 SQLite 契约；实际读写统一走
/// ClipboardHistoryRepository，避免保留第二套写入口。
public final class CoreClipboardStore {
    public let storeURL: URL
    private let persistence: ClipboardHistoryPersistence

    public init(databaseURL: URL) throws {
        storeURL = databaseURL
        persistence = ClipboardHistoryPersistence(databaseURL: databaseURL)

        // The persistence initializer currently keeps store-load errors to itself.
        // Validate the SQLite URL by opening the actual coordinator before accepting it.
        let coordinator = persistence.container.persistentStoreCoordinator
        if coordinator.persistentStores.isEmpty {
            throw SharedStorageError.databaseUnavailable("ClipboardHistory store failed to open")
        }
    }

    public func makeRepository() -> ClipboardHistoryRepository {
        ClipboardHistoryRepository(persistence: persistence)
    }
}


