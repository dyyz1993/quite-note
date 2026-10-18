import XCTest
@testable import QuiteNoteSharedStorage

final class DevCoreLaunchAgentTests: XCTestCase {
    func testDevLaunchAgentTemplateUsesKeepAliveAndIsolatedDebugPaths() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let template = root
            .appendingPathComponent("cloud/quitenote-core/com.quitenote.app.dev.core.plist")
        let data = try Data(contentsOf: template)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]

        XCTAssertEqual(plist?["Label"] as? String, "com.quitenote.app.dev.core")
        XCTAssertEqual(plist?["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist?["KeepAlive"] as? Bool, true)
        XCTAssertEqual(plist?["ThrottleInterval"] as? Int, 10)

        let arguments = plist?["ProgramArguments"] as? [String] ?? []
        XCTAssertTrue(arguments.contains("/Users/DEV/Library/Application Support/QuiteNote-Debug/ClipboardHistory-Debug.sqlite"))
        XCTAssertTrue(arguments.contains("/Users/DEV/Library/Application Support/com.quitenote.app.dev/CoreService/state.json"))
        XCTAssertFalse(arguments.contains { $0.contains("/QuiteNote/ClipboardHistory.sqlite") })
    }

    func testManagerExposesMonitorAndReportCommands() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("tools/manage-quitenote-dev-core.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: script.path))
        let contents = try String(contentsOf: script, encoding: .utf8)
        for command in ["monitor-start", "monitor-stop", "monitor-status", "report"] {
            XCTAssertTrue(contents.contains(command), "missing manager command: \(command)")
        }
    }
}

private extension Sequence where Element == String {
    func contains(_ predicate: (Element) -> Bool) -> Bool {
        contains(where: predicate)
    }
}
