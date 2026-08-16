import XCTest
import AppKit
@testable import QuiteNote

/// 数据隔离红线：测试进程启动时把存储根重定向到临时目录
/// 必须在任何存储单例（FileCoordinator / CoreDataStack / DiagnosticCenter）首次访问前调用
enum TestStorageIsolation {
    static let activate: Void = {
        let root = NSTemporaryDirectory() + "qn-isolated-storage-\(UUID().uuidString)"
        setenv("QN_TEST_STORAGE_ROOT", root, 1)
        print("🧪 测试存储隔离已激活: \(root)")
    }()
}

/// 守卫测试：确保测试进程中的所有存储都落在隔离目录，绝不触碰真实生产数据
final class StorageIsolationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TestStorageIsolation.activate
    }

    func testFileCoordinatorUsesIsolatedRoot() {
        let prodRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.quitenote.app").path

        let screenshotDir = FileCoordinator.shared.getDirectoryURL(for: .screenshot).path
        XCTAssertFalse(screenshotDir.hasPrefix(prodRoot),
                       "测试中的 FileCoordinator 绝不能指向生产目录，实际: \(screenshotDir)")
        XCTAssertTrue(screenshotDir.contains("qn-isolated-storage"),
                      "应落在 QN_TEST_STORAGE_ROOT 隔离目录内，实际: \(screenshotDir)")
    }

    func testDiagnosticCenterUsesIsolatedRoot() {
        let center = DiagnosticCenter()
        let logDir = center.logDirectoryURL.path
        XCTAssertFalse(logDir.hasPrefix(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.path),
                       "测试中的日志目录必须离开 Application Support，实际: \(logDir)")
        XCTAssertTrue(logDir.contains("qn-isolated-storage"),
                      "应落在隔离目录内，实际: \(logDir)")
    }
}
