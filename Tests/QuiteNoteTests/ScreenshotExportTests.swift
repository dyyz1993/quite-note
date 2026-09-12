import XCTest
import AppKit
@testable import QuiteNote

/// 截图文件导出（exportImageFile）的行为测试：文件落盘、命名格式、重名冲突
@MainActor
final class ScreenshotExportTests: XCTestCase {

    private var tempDir: String!
    private var savedOldPreference: Any?
    private var savedOldBookmark: Any?

    override func setUp() {
        super.setUp()
        // 保存旧偏好，测试结束后恢复，不污染用户真实设置
        savedOldPreference = UserDefaults.standard.object(forKey: "screenshotSaveDirectory")
        savedOldBookmark = UserDefaults.standard.object(forKey: UserExportDirectory.bookmarkKey)

        tempDir = NSTemporaryDirectory() + "qn-export-tests-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        XCTAssertTrue(PreferencesManager.shared.setScreenshotSaveDirectory(
            URL(fileURLWithPath: tempDir, isDirectory: true)))
    }

    override func tearDown() {
        _ = PreferencesManager.shared.setScreenshotSaveDirectory(nil)
        if let old = savedOldPreference {
            UserDefaults.standard.set(old, forKey: "screenshotSaveDirectory")
        } else {
            UserDefaults.standard.removeObject(forKey: "screenshotSaveDirectory")
        }
        if let old = savedOldBookmark {
            UserDefaults.standard.set(old, forKey: UserExportDirectory.bookmarkKey)
        } else {
            UserDefaults.standard.removeObject(forKey: UserExportDirectory.bookmarkKey)
        }
        try? FileManager.default.removeItem(atPath: tempDir)
        super.tearDown()
    }

    /// 生成一张纯色小图
    private func makeSolidImage(width: CGFloat = 8, height: CGFloat = 8) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: NSSize(width: width, height: height)).fill()
        image.unlockFocus()
        return image
    }

    /// 导出必须落到配置目录，文件名带中文前缀 + 时间戳
    func testExportWritesPNGIntoConfiguredDirectory() {
        let path = ScreenshotService.shared.exportImageFile(makeSolidImage())

        XCTAssertNotNil(path, "导出应返回文件路径")
        guard let path else { return }

        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "导出文件必须真实落盘")

        let fileName = (path as NSString).lastPathComponent
        XCTAssertTrue(fileName.hasPrefix("QuiteNote_"), "文件名应以 QuiteNote_ 开头，实际: \(fileName)")
        XCTAssertTrue(fileName.hasSuffix(".png"), "文件名应为 .png，实际: \(fileName)")
        guard case .success(let configuredDirectory) = UserExportDirectory.configuredDirectory() else {
            return XCTFail("测试配置的导出目录应保持可访问")
        }
        XCTAssertTrue(path.hasPrefix(configuredDirectory.path), "文件必须落在配置的保存目录内")
    }

    /// 同一秒内连续导出两个文件：不能互相覆盖，两个都要在
    func testExportCollisionDoesNotOverwrite() {
        let path1 = ScreenshotService.shared.exportImageFile(makeSolidImage())
        let path2 = ScreenshotService.shared.exportImageFile(makeSolidImage())

        XCTAssertNotNil(path1)
        XCTAssertNotNil(path2)
        guard let path1, let path2 else { return }

        XCTAssertNotEqual(path1, path2, "连续导出的文件名不能相同")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path1), "第一个文件不能被第二个覆盖")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path2))
    }

    /// 导出的 PNG 必须可被系统读回（数据完整）
    func testExportedFileIsReadableImage() {
        guard let path = ScreenshotService.shared.exportImageFile(makeSolidImage()) else {
            XCTFail("导出失败")
            return
        }
        let image = NSImage(contentsOfFile: path)
        XCTAssertNotNil(image, "导出的 PNG 必须能被 NSImage 读回")
    }

    /// 旧版本仅保存字符串路径时，不能绕过沙盒授权而把文件写到一个猜测路径。
    func testLegacyPathWithoutBookmarkIsRejectedInsteadOfFallingBack() {
        UserDefaults.standard.set(tempDir, forKey: "screenshotSaveDirectory")
        UserDefaults.standard.removeObject(forKey: UserExportDirectory.bookmarkKey)

        XCTAssertEqual(
            UserExportDirectory.configuredDirectory(),
            .failure(.authorizationUnavailable),
            "没有安全作用域书签的旧路径必须要求用户重新选择，不能悄悄写入容器或原始路径"
        )
    }
}
