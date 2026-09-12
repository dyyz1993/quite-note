import XCTest
@testable import QuiteNote

/// 录屏文件落盘测试：命名、重名去重、跨目录移动
/// 只写测试自建的临时目录，不触碰应用存储（数据隔离红线）
final class RecordingFileFinalizerTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("RecordingFinalizerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }

    private func makeTempRecording() throws -> URL {
        // 模拟引擎产出的临时 mp4（真实文件，验证的是移动而非拷贝）
        let url = tempDir.appendingPathComponent("QuiteNote-Recording-\(UUID().uuidString).mp4")
        try Data("fake-mp4".utf8).write(to: url)
        return url
    }

    func testFinalizeMovesFileWithRecordingName() throws {
        let temp = try makeTempRecording()
        let saveDir = tempDir.appendingPathComponent("保存目录")
        let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

        let result = try V2RecordingFileFinalizer.finalize(
            tempURL: temp, directory: saveDir, date: fixedDate)

        XCTAssertTrue(result.path.hasSuffix(".mp4"))
        XCTAssertTrue(result.lastPathComponent.hasPrefix("录屏 "))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path),
                       "临时文件应被移动（而非拷贝）到目标目录")
    }

    func testFinalizeDoesNotOverwriteExistingFile() throws {
        let saveDir = tempDir.appendingPathComponent("重名目录")
        let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

        let first = try V2RecordingFileFinalizer.finalize(
            tempURL: try makeTempRecording(), directory: saveDir, date: fixedDate)
        let second = try V2RecordingFileFinalizer.finalize(
            tempURL: try makeTempRecording(), directory: saveDir, date: fixedDate)

        XCTAssertNotEqual(first.path, second.path, "同一秒的两次录制不能互相覆盖")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path), "先保存的文件必须原样保留")
        XCTAssertTrue(second.lastPathComponent.contains("-2"), "重名应加 -2 后缀")
    }

    func testFinalizeCreatesMissingDirectory() throws {
        let deepDir = tempDir
            .appendingPathComponent("不存在/a/b")
        let result = try V2RecordingFileFinalizer.finalize(
            tempURL: try makeTempRecording(), directory: deepDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path),
                      "目标目录不存在时应自动创建")
    }

    func testFinalizeEditedKeepsSourceAndUsesDistinctName() throws {
        let source = tempDir.appendingPathComponent("录屏 2026-08-18 13.00.00.mp4")
        try Data("source".utf8).write(to: source)
        let edited = try makeTempRecording()

        let exportDirectory = tempDir.appendingPathComponent("导出目录")
        let result = try V2RecordingFileFinalizer.finalizeEdited(
            tempURL: edited, sourceURL: source, directory: exportDirectory)

        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path),
                      "剪辑导出不能删除原始录屏")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
        XCTAssertEqual(result.deletingLastPathComponent().path.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                       exportDirectory.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                       "快剪导出必须使用当前配置的导出目录")
        XCTAssertTrue(result.lastPathComponent.contains("剪辑版"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: edited.path))
    }

    func testFinalizeEditedDoesNotOverwritePreviousEdit() throws {
        let source = tempDir.appendingPathComponent("录屏 2026-08-18 13.00.00.mp4")
        try Data("source".utf8).write(to: source)

        let exportDirectory = tempDir.appendingPathComponent("导出目录")
        let first = try V2RecordingFileFinalizer.finalizeEdited(
            tempURL: try makeTempRecording(), sourceURL: source, directory: exportDirectory)
        let second = try V2RecordingFileFinalizer.finalizeEdited(
            tempURL: try makeTempRecording(), sourceURL: source, directory: exportDirectory)

        XCTAssertNotEqual(first.path, second.path)
        XCTAssertTrue(second.lastPathComponent.contains("剪辑版-2"))
    }
}
