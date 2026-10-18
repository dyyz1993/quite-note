import XCTest
@testable import QuiteNoteSharedStorage

final class DevCoreMonitorReportTests: XCTestCase {
    func testReportRejectsShortAndUnhealthyEvidence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quitenote-core-report-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = packageRoot().appendingPathComponent("tools/report-quitenote-dev-core.sh")
        let csv = root.appendingPathComponent("monitor.csv")
        defer { try? FileManager.default.removeItem(at: root) }

        try """
        timestamp,pid,runs,rss_kb,cpu_percent,wal_bytes,state_running,heartbeat_age_seconds,captured_count,last_error
        2026-10-14T00:00:00Z,1,1,100,0.1,0,true,1,0,
        2026-10-14T00:10:00Z,1,1,200,0.1,0,true,10,0,
        """.write(to: csv, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path, csv.path]
        process.environment = [
            "QN_CORE_REPORT_MIN_DURATION": "600",
            "QN_CORE_REPORT_MAX_GAP": "601",
            "QN_CORE_REPORT_MAX_HEARTBEAT_AGE": "5",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        XCTAssertEqual(process.terminationStatus, 1)
        XCTAssertTrue(output.contains("stale-heartbeat-samples"))
    }

    func testReportAcceptsCompleteHealthyEvidence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quitenote-core-report-positive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = packageRoot().appendingPathComponent("tools/report-quitenote-dev-core.sh")
        let csv = root.appendingPathComponent("monitor.csv")
        defer { try? FileManager.default.removeItem(at: root) }

        try """
        timestamp,pid,runs,rss_kb,cpu_percent,wal_bytes,state_running,heartbeat_age_seconds,captured_count,last_error
        2026-10-14T00:00:00Z,1,1,100,0.1,0,true,1,0,
        2026-10-14T00:10:00Z,1,1,120,0.1,0,true,1,1,
        """.write(to: csv, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path, csv.path]
        process.environment = [
            "QN_CORE_REPORT_MIN_DURATION": "600",
            "QN_CORE_REPORT_MAX_GAP": "601",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        XCTAssertEqual(process.terminationStatus, 0, output)
        XCTAssertTrue(output.contains("PASS"))
        XCTAssertTrue(output.contains("remaining_seconds=0"))
    }

    func testReportRejectsPidChange() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quitenote-core-report-pid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = packageRoot().appendingPathComponent("tools/report-quitenote-dev-core.sh")
        let csv = root.appendingPathComponent("monitor.csv")
        defer { try? FileManager.default.removeItem(at: root) }

        try """
        timestamp,pid,runs,rss_kb,cpu_percent,wal_bytes,state_running,heartbeat_age_seconds,captured_count,last_error
        2026-10-14T00:00:00Z,1,1,100,0.1,0,true,1,0,
        2026-10-14T00:10:00Z,2,1,120,0.1,0,true,1,1,
        """.write(to: csv, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path, csv.path]
        process.environment = [
            "QN_CORE_REPORT_MIN_DURATION": "600",
            "QN_CORE_REPORT_MAX_GAP": "601",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        XCTAssertEqual(process.terminationStatus, 1)
        XCTAssertTrue(output.contains("pid-changed"))
        XCTAssertTrue(output.contains("eta_utc="))
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
