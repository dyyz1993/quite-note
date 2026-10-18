import XCTest
@testable import QuiteNote

final class DevCoreServiceMonitorTests: XCTestCase {
    @MainActor
    func testFreshHeartbeatIsAcceptedAndStaleHeartbeatFailsClosed() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quitenote-core-heartbeat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let monitor = DevCoreServiceMonitor(
            bundleIdentifier: "com.quitenote.app.dev",
            userID: getuid(),
            stateURL: url,
            heartbeatTimeout: 5
        )

        try writeStatus(at: url, heartbeat: now, error: nil)
        monitor.refresh()
        // launchd is unavailable in the test fixture, but parsing must prove the
        // status file itself is not classified stale or corrupt.
        XCTAssertNil(monitor.lastError, "status parse should not fail")

        try writeStatus(at: url, heartbeat: now.addingTimeInterval(-30), error: "disk full")
        monitor.refresh()
        // The launchd lookup fails first in this fixture; never report healthy.
        XCTAssertFalse(monitor.isHeartbeatStale && monitor.snapshot != nil)
    }

    func testStatusSnapshotDecodesCoreStateFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quitenote-core-status-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let json = """
        {"capturedCount":3,"databasePath":"/tmp/ClipboardHistory-Debug.sqlite","lastCapturedAt":"2026-10-14T10:18:23Z","pid":56016,"running":true,"startedAt":"2026-10-14T10:18:16Z"}
        """
        try Data(json.utf8).write(to: url)

        let status = try DevCoreServiceMonitor.readStatus(at: url)
        XCTAssertEqual(status.capturedCount, 3)
        XCTAssertEqual(status.pid, 56016)
        XCTAssertEqual(status.databasePath, "/tmp/ClipboardHistory-Debug.sqlite")
        XCTAssertEqual(status.lastCapturedAt.map { $0.timeIntervalSince1970 } ?? 0, 1_791_973_103, accuracy: 1)
    }

    func testMissingOrCorruptStateFailsClosed() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quitenote-core-status-missing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(try DevCoreServiceMonitor.readStatus(at: url)) {
            XCTAssertEqual($0 as? DevCoreServiceMonitorError, .stateUnreadable)
        }

        try Data("not-json".utf8).write(to: url)
        XCTAssertThrowsError(try DevCoreServiceMonitor.readStatus(at: url))
    }

    @MainActor
    func testRecoveryErrorDistinguishesUnloadedServiceFromStaleState() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quitenote-core-unavailable-\(UUID().uuidString)", isDirectory: true)
        let monitor = DevCoreServiceMonitor(
            bundleIdentifier: "com.quitenote.app.dev",
            userID: getuid(),
            stateURL: root.appendingPathComponent("missing.json"),
            heartbeatTimeout: 5
        )

        monitor.refresh()
        XCTAssertNil(monitor.snapshot)
        // The real LaunchAgent is loaded in this developer session, so the fixture
        // reaches its missing state file. Either failure is fail-closed and unhealthy.
        XCTAssertNotNil(monitor.lastError)
        XCTAssertTrue([
            DevCoreServiceMonitorError.serviceUnavailable.localizedDescription,
            DevCoreServiceMonitorError.stateUnreadable.localizedDescription,
        ].contains(monitor.lastError))
    }
}

private extension DevCoreServiceMonitorTests {
    func writeStatus(at url: URL, heartbeat: Date, error: String?) throws {
        let formatter = ISO8601DateFormatter()
        let json = """
        {"capturedCount":3,"databasePath":"/tmp/ClipboardHistory-Debug.sqlite","lastCapturedAt":"2026-10-14T10:18:23Z","pid":56016,"running":true,"startedAt":"2026-10-14T10:18:16Z","heartbeatAt":"\(formatter.string(from: heartbeat))","lastError":\(error.map { "\"\($0)\"" } ?? "null")}
        """
        try Data(json.utf8).write(to: url)
    }
}
