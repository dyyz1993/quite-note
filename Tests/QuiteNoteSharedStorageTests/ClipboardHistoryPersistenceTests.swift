import XCTest
@testable import QuiteNoteSharedStorage

final class ClipboardHistoryPersistenceTests: XCTestCase {
    func testDatabaseOpenFailureIsReportedInsteadOfBeingSwallowed() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("quitenote-persistence-open-error-\(UUID().uuidString)", isDirectory: true)
        let database = parent.appendingPathComponent("nested/ClipboardHistory.sqlite")

        // Create a regular file where the parent directory should be. Opening the
        // SQLite store must fail rather than silently yielding an empty container.
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try Data("not-a-directory".utf8).write(to: parent.appendingPathComponent("nested"))

        XCTAssertThrowsError(try CoreClipboardStore(databaseURL: database)) { error in
            XCTAssertEqual(error as? SharedStorageError, .databaseUnavailable("ClipboardHistory store failed to open"))
        }

        let persistence = ClipboardHistoryPersistence(databaseURL: database)
        XCTAssertNotNil(persistence.storageLoadErrorDescription)
    }
}
