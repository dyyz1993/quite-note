import XCTest
import CoreData
@testable import QuiteNoteCoreService
@testable import QuiteNoteSharedStorage

final class CoreClipboardStoreTests: XCTestCase {
    func testInsertDeduplicatesAndPersists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quitenote-core-tests-\(UUID().uuidString)", isDirectory: true)
        let database = root.appendingPathComponent("ClipboardHistory.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try CoreClipboardStore(databaseURL: database)
        XCTAssertTrue(try store.insert(text: "hello core"))
        XCTAssertFalse(try store.insert(text: "hello core"))
        XCTAssertTrue(try store.insert(text: "https://example.com"))
        XCTAssertEqual(try store.count(), 2)

        let reopened = try CoreClipboardStore(databaseURL: database)
        XCTAssertEqual(try reopened.count(), 2)
    }

    func testCoreAndAppPersistenceUseSameManagedObjectModel() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quitenote-shared-model-\(UUID().uuidString)", isDirectory: true)
        let database = root.appendingPathComponent("ClipboardHistory.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        let core = try CoreClipboardStore(databaseURL: database)
        XCTAssertTrue(try core.insert(text: "shared model"))

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
