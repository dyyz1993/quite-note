import QuiteNoteSharedStorage
import XCTest
@testable import QuiteNote

final class ClipboardHistoryStoreRegressionTests: XCTestCase {
    @MainActor
    func testSameHashAcrossTypesDoesNotOverwriteLoadedEntry() {
        TestStorageIsolation.activate
        let prefs = PreferencesManager.shared
        let savedMaxEntries = prefs.clipboardMaxEntries
        prefs.setClipboardMaxEntries(500)
        defer { prefs.setClipboardMaxEntries(savedMaxEntries) }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quitenote-history-store-regression-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let store = ClipboardHistoryStore(
            persistence: ClipboardHistoryPersistence(
                databaseURL: root.appendingPathComponent("ClipboardHistory.sqlite")
            )
        )
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
}
