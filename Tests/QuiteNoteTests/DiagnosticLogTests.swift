import XCTest
import AppKit
@testable import QuiteNote

/// 诊断中心核心逻辑测试：文件日志写入、过期清理、会话异常退出检测
/// （不调用 start()，避免在测试进程安装信号处理器/看门狗线程）
final class DiagnosticLogTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("qn-diag-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func todayLogContent() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let url = tempDir.appendingPathComponent("app-\(f.string(from: Date())).log")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// 日志行必须带时间戳 + 级别 + 分类 + 内容，中文内容不能丢失
    func test_log_writesLineWithTimestampLevelAndCategory() {
        let dc = DiagnosticCenter(logDirectory: tempDir)
        dc.writeLine(level: .info, category: "Test", message: "你好 diagnostics")

        let content = todayLogContent()
        XCTAssertTrue(content.hasPrefix("20"), "日志行应以时间戳开头，实际: \(content)")
        XCTAssertTrue(content.contains("[INFO][Test] 你好 diagnostics"), "日志应包含级别/分类/内容，实际: \(content)")
    }

    /// 超过保留期的日志被清理，保留期内的不动
    func test_cleanupRemovesExpiredLogsButKeepsRecent() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let oldDate = Date().addingTimeInterval(-8 * 86400)

        let old = tempDir.appendingPathComponent("app-\(f.string(from: oldDate)).log")
        FileManager.default.createFile(atPath: old.path, contents: "old".data(using: .utf8))
        // 清理按内容修改时间判断，把旧文件的 mtime 设为 8 天前
        try? FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: old.path)

        let recent = tempDir.appendingPathComponent("app-\(f.string(from: Date())).log")
        FileManager.default.createFile(atPath: recent.path, contents: "new".data(using: .utf8))

        let removed = DiagnosticCenter(logDirectory: tempDir).cleanupOldLogs(keepDays: 7)

        XCTAssertEqual(removed, 1, "只应删除 1 个过期日志")
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path), "超过保留期的日志应被删除")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path), "保留期内的日志不应被删除")
    }

    /// 上次会话标记为 running（无正常退出）→ 判为异常退出并写入告警；clean_exit 不告警
    func test_abnormalPreviousSessionDetected() {
        let dc = DiagnosticCenter(logDirectory: tempDir)
        try? "running".write(toFile: dc.sessionStateURL.path, atomically: true, encoding: .utf8)

        XCTAssertTrue(dc.checkPreviousSession(), "标记为 running 的上次会话应判为异常退出")
        XCTAssertTrue(todayLogContent().contains("异常退出"), "异常退出应写入日志告警")

        try? "clean_exit".write(toFile: dc.sessionStateURL.path, atomically: true, encoding: .utf8)
        let dc2 = DiagnosticCenter(logDirectory: tempDir)
        XCTAssertFalse(dc2.checkPreviousSession(), "clean_exit 不应判为异常退出")
    }
}
