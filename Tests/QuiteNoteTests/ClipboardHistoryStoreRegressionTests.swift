import CoreData
import QuiteNoteSharedStorage
import XCTest
@testable import QuiteNote

final class ClipboardHistoryStoreRegressionTests: XCTestCase {
    private func makePersistence() -> ClipboardHistoryPersistence {
        TestStorageIsolation.activate
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quitenote-history-store-regression-\(UUID().uuidString)", isDirectory: true)
        let persistence = ClipboardHistoryPersistence(
            databaseURL: root.appendingPathComponent("ClipboardHistory.sqlite")
        )
        addTeardownBlock {
            // Finish queued context work, close SQLite through Core Data, then
            // remove the files. Unlinking an open WAL store causes later I/O errors.
            let context = persistence.context
            await context.perform(schedule: .enqueued) { context.reset() }
            let coordinator = persistence.container.persistentStoreCoordinator
            try coordinator.performAndWait {
                for store in coordinator.persistentStores {
                    try coordinator.remove(store)
                }
            }
            try FileManager.default.removeItem(at: root)
        }
        return persistence
    }

    @MainActor
    func testSameHashAcrossTypesDoesNotOverwriteLoadedEntry() {
        TestStorageIsolation.activate
        let prefs = PreferencesManager.shared
        let savedMaxEntries = prefs.clipboardMaxEntries
        prefs.setClipboardMaxEntries(500)
        defer { prefs.setClipboardMaxEntries(savedMaxEntries) }
        let store = ClipboardHistoryStore(persistence: makePersistence())
        let text = ClipboardEntry(type: .text, plainText: "/tmp/example.txt", contentHash: "same-hash")
        let file = ClipboardEntry(type: .file, plainText: "/tmp/example.txt", contentHash: "same-hash")

        store.insertOrUpdate(text)
        store.insertOrUpdate(file)

        XCTAssertEqual(store.entries.count, 2, "The in-memory fallback must preserve the repository's type boundary")
        XCTAssertEqual(store.entry(id: text.id)?.type, .text)
        XCTAssertEqual(store.entry(id: file.id)?.type, .file)
        let loadedIDs = Set(store.entries.map(\.id))

        store.reload()

        XCTAssertEqual(Set(store.entries.map(\.id)), loadedIDs, "A reload must not restore entries lost only from memory")
        XCTAssertEqual(store.entries.count, 2)
    }

    @MainActor
    func testLoadedStoreIsReleasedWhenItsLastOwnerGoesAway() {
        let persistence = makePersistence()
        weak var releasedStore: ClipboardHistoryStore?

        autoreleasepool {
            let store = ClipboardHistoryStore(persistence: persistence)
            releasedStore = store
            store.loadIfNeeded()
            XCTAssertTrue(store.isLoaded)
        }

        XCTAssertNil(releasedStore, "The retention timer must not retain the store after its last owner releases it")
    }
}
