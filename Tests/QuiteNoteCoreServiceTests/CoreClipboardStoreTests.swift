import XCTest
import CoreData
@testable import QuiteNoteCoreService
@testable import QuiteNoteSharedStorage

final class CoreClipboardStoreTests: XCTestCase {
    func testRepositoryWritesCoreConfiguredDatabaseAndPersists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quitenote-core-tests-\(UUID().uuidString)", isDirectory: true)
        let database = root.appendingPathComponent("ClipboardHistory.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try CoreClipboardStore(databaseURL: database)
        let repository = ClipboardHistoryRepository(coreStore: store)
        XCTAssertTrue(try repository.insertText("hello core").inserted)
        XCTAssertFalse(try repository.insertText("hello core").inserted)
        XCTAssertTrue(try repository.insertText("https://example.com").inserted)
        XCTAssertEqual(repository.totalCount(), 2)

        let reopened = ClipboardHistoryRepository(
            persistence: ClipboardHistoryPersistence(databaseURL: database)
        )
        XCTAssertEqual(reopened.totalCount(), 2)
    }

    func testCoreAndAppPersistenceUseSameManagedObjectModel() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quitenote-shared-model-\(UUID().uuidString)", isDirectory: true)
        let database = root.appendingPathComponent("ClipboardHistory.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        let core = try CoreClipboardStore(databaseURL: database)
        XCTAssertTrue(try ClipboardHistoryRepository(coreStore: core).insertText("shared model").inserted)

        let app = ClipboardHistoryPersistence(databaseURL: database)
        let context = app.context
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "CDClipboardEntry")
        request.predicate = NSPredicate(format: "plainText == %@", "shared model")
        request.affectedStores = app.container.persistentStoreCoordinator.persistentStores.filter { $0.url == database }
        var count = 0
        context.performAndWait {
            count = (try? context.count(for: request)) ?? 0
        }

        XCTAssertFalse(request.affectedStores?.isEmpty ?? true, "App/Core 必须打开同一个 SQLite store")
        XCTAssertEqual(count, 1)
    }
}
