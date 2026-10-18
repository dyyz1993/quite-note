import XCTest
@testable import QuiteNoteCoreService

final class CoreServiceConfigurationTests: XCTestCase {
    func testParseExplicitPathsAndInterval() throws {
        let configuration = try CoreServiceConfiguration.parse(
            arguments: ["--database", "/tmp/qn.sqlite", "--state", "/tmp/qn-state.json", "--interval", "1"],
            environment: [:]
        )
        XCTAssertEqual(configuration.databaseURL.path, "/tmp/qn.sqlite")
        XCTAssertEqual(configuration.stateURL.path, "/tmp/qn-state.json")
        XCTAssertEqual(configuration.pollInterval, 1)
    }

    func testStateFallsBackToEnvironment() throws {
        let configuration = try CoreServiceConfiguration.parse(
            arguments: ["--database", "/tmp/qn.sqlite"],
            environment: ["QN_CORE_STATE_PATH": "/tmp/core.json"]
        )
        XCTAssertEqual(configuration.stateURL.path, "/tmp/core.json")
    }

    func testMissingDatabaseAndBadIntervalFailClosed() {
        XCTAssertThrowsError(try CoreServiceConfiguration.parse(arguments: [], environment: [:]))
        XCTAssertThrowsError(
            try CoreServiceConfiguration.parse(arguments: ["--database", "/tmp/qn.sqlite", "--interval", "0"], environment: [:])
        )
    }

    func testCoreServiceStatusHeartbeatAndErrorFieldsRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let started = Date(timeIntervalSince1970: 1_791_973_496)
        let heartbeat = Date(timeIntervalSince1970: 1_791_973_502)
        let captured = Date(timeIntervalSince1970: 1_791_973_503)
        let status = CoreServiceStatus(
            running: true,
            startedAt: started,
            heartbeatAt: heartbeat,
            capturedCount: 2,
            lastCapturedAt: captured,
            databasePath: "/tmp/ClipboardHistory-Debug.sqlite",
            pid: 65_535,
            lastError: nil
        )

        let data = try encoder.encode(status)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CoreServiceStatus.self, from: data)

        XCTAssertEqual(decoded, status)
        XCTAssertEqual(decoded.heartbeatAt.map(\.timeIntervalSince1970), heartbeat.timeIntervalSince1970)
        XCTAssertNil(decoded.lastError)
    }
}
