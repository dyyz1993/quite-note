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
}
