import CoreData
import XCTest
@testable import QuiteNoteSharedStorage

final class ClipboardHistoryRepositoryRegressionTests: XCTestCase {
    private func makeRepository() -> ClipboardHistoryRepository {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quitenote-history-regression-\(UUID().uuidString)", isDirectory: true)
        let persistence = ClipboardHistoryPersistence(
            databaseURL: root.appendingPathComponent("ClipboardHistory.sqlite")
        )
        addTeardownBlock {
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
        return ClipboardHistoryRepository(persistence: persistence)
    }

    func testFileAndPathTextRemainDistinctRegardlessOfCaptureOrder() throws {
        let path = "/tmp/quite-note-example.txt"
        for fileFirst in [true, false] {
            let repository = makeRepository()
            let file = ClipboardEntry(
                type: .file,
                plainText: path,
                contentHash: ClipboardContentHasher.hash("file:\(path):42"),
                byteSize: 42
            )
            let text = ClipboardEntry(
                type: .text,
                plainText: path,
                contentHash: ClipboardContentHasher.hash(path)
            )

            let first = try repository.insertOrUpdate(fileFirst ? file : text)
            let second = try repository.insertOrUpdate(fileFirst ? text : file)

            XCTAssertTrue(first.inserted)
            XCTAssertTrue(second.inserted, "Copying a path as text must not replace the file reference")
            XCTAssertNotEqual(first.entry.id, second.entry.id)
            let entries = repository.fetchPage(limit: 10, offset: 0)
            XCTAssertEqual(entries.count, 2)
            XCTAssertEqual(entries.first { $0.id == file.id }?.type, .file)
            XCTAssertEqual(entries.first { $0.id == text.id }?.type, .text)
        }
    }

    func testRecapturingFileUpdatesFileWithoutReplacingMatchingText() throws {
        let repository = makeRepository()
        let path = "/tmp/quite-note-example.txt"
        let original = try repository.insertOrUpdate(ClipboardEntry(
            type: .file,
            plainText: path,
            contentHash: ClipboardContentHasher.hash("file:\(path):42"),
            byteSize: 42
        ))
        let text = try repository.insertText(path)

        let recaptured = try repository.insertOrUpdate(ClipboardEntry(
            type: .file,
            plainText: path,
            contentHash: ClipboardContentHasher.hash("file:\(path):84"),
            byteSize: 84
        ))

        XCTAssertFalse(recaptured.inserted)
        XCTAssertEqual(recaptured.entry.id, original.entry.id)
        XCTAssertEqual(recaptured.entry.type, .file)
        XCTAssertEqual(recaptured.entry.byteSize, 84)
        XCTAssertEqual(repository.totalCount(), 2)
        XCTAssertEqual(repository.fetchPage(limit: 10, offset: 0).first { $0.id == text.entry.id }?.type, .text)
    }

    func testSameTypeLegacyHashDeduplicationPreservesUserMetadata() throws {
        let repository = makeRepository()
        let savedRecordID = UUID()
        let legacy = ClipboardEntry(
            type: .text,
            plainText: "Saved clipboard content",
            sourceApp: "Old app",
            contentHash: "legacy-content-hash",
            pasteCount: 7,
            isPinned: true,
            savedRecordID: savedRecordID
        )
        _ = try repository.insertOrUpdate(legacy)

        let recaptured = try repository.insertText("Saved clipboard content", sourceApp: "New app")

        XCTAssertFalse(recaptured.inserted)
        XCTAssertEqual(repository.totalCount(), 1)
        XCTAssertEqual(recaptured.entry.id, legacy.id)
        XCTAssertEqual(recaptured.entry.type, .text)
        XCTAssertEqual(recaptured.entry.sourceApp, "New app")
        XCTAssertTrue(recaptured.entry.isPinned)
        XCTAssertEqual(recaptured.entry.pasteCount, 7)
        XCTAssertEqual(recaptured.entry.savedRecordID, savedRecordID)
    }

    func testRetentionAppliesCountLimitAfterExpiryWithoutCountingProtectedEntries() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let expired = makeEntry("expired", createdAt: now.addingTimeInterval(-40 * 86_400))
        let recent = (0..<5).map {
            makeEntry("recent-\($0)", createdAt: now.addingTimeInterval(Double($0 - 5) * 60))
        }
        var pinned = makeEntry("pinned", createdAt: expired.createdAt)
        pinned.isPinned = true
        var saved = makeEntry("saved", createdAt: expired.createdAt)
        saved.savedRecordID = UUID()
        let entries = [expired, pinned, saved] + recent

        let victims = ClipboardHistoryRepository.retentionVictims(
            entries, now: now, retentionDays: 30, maxEntries: 3
        )

        XCTAssertEqual(victims, Set([expired.id, recent[0].id, recent[1].id]))
        let survivors = entries.filter { !victims.contains($0.id) }
        XCTAssertEqual(survivors.filter { !$0.isPinned && $0.savedRecordID == nil }.count, 3)
        XCTAssertTrue(survivors.contains { $0.id == pinned.id })
        XCTAssertTrue(survivors.contains { $0.id == saved.id })
        XCTAssertTrue(ClipboardHistoryRepository.retentionVictims(
            survivors, now: now, retentionDays: 30, maxEntries: 3
        ).isEmpty, "One retention pass must satisfy both policies")
    }

    func testZeroCountLimitStillRemovesFreshEntriesAfterExpiry() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let expired = makeEntry("expired", createdAt: now.addingTimeInterval(-40 * 86_400))
        let fresh = makeEntry("fresh", createdAt: now)

        let victims = ClipboardHistoryRepository.retentionVictims(
            [expired, fresh], now: now, retentionDays: 30, maxEntries: 0
        )

        XCTAssertEqual(victims, Set([expired.id, fresh.id]))
    }

    private func makeEntry(_ text: String, createdAt: Date) -> ClipboardEntry {
        ClipboardEntry(
            type: .text,
            createdAt: createdAt,
            plainText: text,
            contentHash: ClipboardContentHasher.hash(text)
        )
    }
}
