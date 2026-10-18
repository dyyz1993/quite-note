import XCTest
import CoreData
import AppKit
@testable import QuiteNoteSharedStorage

final class ClipboardHistoryRepositoryTests: XCTestCase {
    private func makeRepository() throws -> (ClipboardHistoryRepository, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quitenote-repository-tests-\(UUID().uuidString)", isDirectory: true)
        let database = root.appendingPathComponent("ClipboardHistory.sqlite")
        let persistence = ClipboardHistoryPersistence(databaseURL: database)
        return (ClipboardHistoryRepository(persistence: persistence), database)
    }

    func testInsertDeduplicateUpdateDeleteAndPaginate() throws {
        let (repository, _) = try makeRepository()

        let first = try repository.insertText("hello", sourceApp: "Finder", sourceBundleID: "com.apple.finder")
        XCTAssertTrue(first.inserted)
        XCTAssertFalse(try repository.insertText("hello").inserted)
        XCTAssertTrue(try repository.insertText("https://example.com").inserted)

        XCTAssertEqual(repository.totalCount(), 2)
        XCTAssertEqual(repository.fetchPage(limit: 1, offset: 1).count, 1)

        let updated = repository.update(id: first.entry.id) { entry in
            entry.isPinned = true
        }
        XCTAssertEqual(updated?.isPinned, true)
        XCTAssertEqual(repository.fetchPage(limit: 1, offset: 0).first?.id, first.entry.id)

        XCTAssertEqual(repository.delete(id: first.entry.id)?.id, first.entry.id)
        XCTAssertEqual(repository.totalCount(), 1)
    }

    func testTwoRepositoriesShareStoreAndNotify() throws {
        let (writer, database) = try makeRepository()
        let readerPersistence = ClipboardHistoryPersistence(databaseURL: database)
        let reader = ClipboardHistoryRepository(persistence: readerPersistence)

        let changed = expectation(description: "remote change delivered")
        let observerID = reader.addRemoteChangeObserver {
            changed.fulfill()
        }
        defer { reader.removeRemoteChangeObserver(observerID) }

        XCTAssertTrue(try writer.insertText("cross process").inserted)
        XCTAssertEqual(reader.totalCount(), 1)
        wait(for: [changed], timeout: 3)
    }

    func testConcurrentUpsertsKeepOneRowPerContent() throws {
        let (repository, _) = try makeRepository()
        let operations = 40
        let queue = DispatchQueue(label: "repository-concurrent-upserts", attributes: .concurrent)
        let group = DispatchGroup()

        for index in 0..<operations {
            group.enter()
            queue.async {
                defer { group.leave() }
                do {
                _ = try repository.insertText("concurrent content")
                    _ = try repository.insertText("unique \(index)")
                } catch {
                    XCTFail("concurrent upsert failed: \(error)")
                }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)

        XCTAssertEqual(repository.totalCount(), operations + 1)
        XCTAssertEqual(
            repository.fetchPage(limit: .max, offset: 0)
                .filter { $0.plainText == "concurrent content" }
                .count,
            1
        )
    }

    /// Manual-only proof: two real processes race the same database and payload.
    func testTwoCoreProcessesConcurrentlyUpsertSameContentWithoutDuplicates() throws {
        guard ProcessInfo.processInfo.environment["QN_CORE_CROSS_PROCESS_SMOKE"] == "1" else {
            throw XCTSkip("Set QN_CORE_CROSS_PROCESS_SMOKE=1 to run cross-process races")
        }
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("quitenote-core-race-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let harness = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("tools/dev-core-race-smoke.sh")
        // Two helper processes race shared and unique payloads against one store.
        let output = try runProcess(harness, arguments: [root.path])
        XCTAssertTrue(output.contains("PASS"), output)
    }

    /// Manual-only smoke: QN_CORE_CROSS_PROCESS_SMOKE=1. Avoid changing the user's
    /// pasteboard in ordinary unit-test runs.
    func testRealCoreProcessWriteNotifiesRepositoryReader() throws {
        guard ProcessInfo.processInfo.environment["QN_CORE_CROSS_PROCESS_SMOKE"] == "1" else {
            throw XCTSkip("Set QN_CORE_CROSS_PROCESS_SMOKE=1 to run the pasteboard smoke")
        }
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("quitenote-core-cross-process-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = root.appendingPathComponent("ClipboardHistory.sqlite")
        let state = root.appendingPathComponent("state.json")

        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let executable = packageRoot
            .appendingPathComponent(".build/debug/QuiteNoteCoreService")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw XCTSkip("Core executable is not built at \(executable.path)")
        }

        let reader = ClipboardHistoryRepository(
            persistence: ClipboardHistoryPersistence(databaseURL: database)
        )
        let changed = expectation(description: "reader receives real cross-process remote change")
        let observerID = reader.addRemoteChangeObserver { changed.fulfill() }
        defer { reader.removeRemoteChangeObserver(observerID) }

        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        let payload = "quitenote cross-process \(UUID().uuidString)"
        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "--database", database.path,
            "--state", state.path,
            "--interval", "0.1",
        ]
        try process.run()
        defer {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            pasteboard.clearContents()
            pasteboard.setString(original ?? "", forType: .string)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            pasteboard.setString(payload, forType: .string)
        }
        wait(for: [changed], timeout: 5)

        XCTAssertTrue(
            reader.fetchPage(limit: .max, offset: 0)
                .contains { $0.plainText == payload }
        )
    }

    func testRetentionRemovesOnlyEvictableEntries() throws {
        let (repository, _) = try makeRepository()
        let now = Date()
        _ = try repository.insertText("old", createdAt: now.addingTimeInterval(-40 * 86_400))
        let pinned = try repository.insertText("pinned old", createdAt: now.addingTimeInterval(-40 * 86_400))
        _ = repository.update(id: pinned.entry.id) { $0.isPinned = true }
        _ = try repository.insertText("new", createdAt: now)

        let victims = repository.applyRetention(now: now, retentionDays: 30, maxEntries: 500)
        XCTAssertEqual(victims.map(\.plainText), ["old"])
        XCTAssertEqual(repository.totalCount(), 2)
    }

    private func runProcess(_ url: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, output)
        return output
    }
}
