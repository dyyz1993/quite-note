import XCTest
@testable import QuiteNote

/// 文件模式前缀解析 + 文件条目模型
final class LauncherFileTests: XCTestCase {

    func test文件模式判定() {
        // 标点前缀（IME 直通，主路径）
        XCTAssertTrue(FileModeParser.isFileMode("'报告"))
        XCTAssertTrue(FileModeParser.isFileMode("~报告"))
        XCTAssertTrue(FileModeParser.isFileMode("\u{2018}报告"))   // 全角左引号（搜狗中文标点实测输出）
        XCTAssertTrue(FileModeParser.isFileMode("\u{2019}报告"))   // 全角右引号
        XCTAssertTrue(FileModeParser.isFileMode("\u{FF5E}报告"))   // 全角波浪号
        XCTAssertTrue(FileModeParser.isFileMode("'"))              // 已输前缀还没输词
        // f 前缀（英文模式兜底）
        XCTAssertTrue(FileModeParser.isFileMode("f 报告"))
        XCTAssertTrue(FileModeParser.isFileMode("F 报告"))
        XCTAssertFalse(FileModeParser.isFileMode("f"))             // 单独 f 不劫持（还能搜 Finder）
        XCTAssertFalse(FileModeParser.isFileMode("firefox"))
        XCTAssertFalse(FileModeParser.isFileMode("报告 f"))
        XCTAssertFalse(FileModeParser.isFileMode(""))
    }

    func test文件查询词提取() {
        XCTAssertEqual(FileModeParser.fileTerm("'报告 q4"), "报告 q4")
        XCTAssertEqual(FileModeParser.fileTerm("~合同.pdf  "), "合同.pdf")
        XCTAssertEqual(FileModeParser.fileTerm("\u{2019}合同"), "合同")
        XCTAssertEqual(FileModeParser.fileTerm("f 报告"), "报告")
        XCTAssertEqual(FileModeParser.fileTerm("'"), "")
        XCTAssertEqual(FileModeParser.fileTerm("f"), "")
    }

    func test文件条目徽标与身份() {
        let url = URL(fileURLWithPath: "/Users/x/Docs/合同.pdf")
        let file = LauncherFile(name: "合同.pdf", url: url,
                                kindDescription: "PDF 文档", modifiedDate: nil, isDirectory: false)
        XCTAssertEqual(file.badgeText, "PDF 文档")
        XCTAssertEqual(file.id, url.path)

        let noKind = LauncherFile(name: "x.dat", url: url, kindDescription: "",
                                  modifiedDate: nil, isDirectory: false)
        XCTAssertEqual(noKind.badgeText, "文件")

        let dir = LauncherFile(name: "项目", url: url, kindDescription: "",
                               modifiedDate: nil, isDirectory: true)
        XCTAssertEqual(dir.badgeText, "文件夹")
    }

    func testLauncherItem文件身份() {
        let file = LauncherFile(name: "a.txt", url: URL(fileURLWithPath: "/tmp/a.txt"),
                                kindDescription: "", modifiedDate: nil, isDirectory: false)
        XCTAssertEqual(LauncherItem.file(file).id, "file:/tmp/a.txt")
    }

    // MARK: - 兜底扫描集成（只读真实家目录，不写任何存储）

    func test兜底扫描_家目录Applications必命中() throws {
        // 确定性夹具（不依赖真机家目录状态——真机的扫描上限可能被大目录吃掉，
        // 曾导致本用例随机红）
        let home = NSTemporaryDirectory() + "qn-fallback-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home + "/Applications", withIntermediateDirectories: true)
        try Data("x".utf8).write(to: URL(fileURLWithPath: home + "/普通文件.txt"))
        defer { try? FileManager.default.removeItem(atPath: home) }

        let results = LauncherFileSearch.scanCommonDirectories(term: "applications", homePath: home)
        XCTAssertTrue(results.contains { $0.url.path == home + "/Applications" })
        // 大小写不敏感 + 隐藏排除同场验证
        let upper = LauncherFileSearch.scanCommonDirectories(term: "APPLICATIONS", homePath: home)
        XCTAssertFalse(upper.isEmpty)
        XCTAssertFalse(upper.contains { $0.name.hasPrefix(".") })
    }
}
