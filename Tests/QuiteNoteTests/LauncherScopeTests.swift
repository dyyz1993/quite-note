import XCTest
@testable import QuiteNote

/// 范围命令解析（"文件"+空格/↵ 进入文件模式）+ 两层兜底扫描
final class LauncherScopeTests: XCTestCase {

    // MARK: - 范围解析

    func test单独范围词_只亮行不进入() {
        let m = LauncherScopeParser.parse("文件")
        XCTAssertEqual(m?.entered, false)
        XCTAssertEqual(m?.term, "")
    }

    func test范围词加空格加词_直接进入() {
        let m = LauncherScopeParser.parse("文件 报告")
        XCTAssertEqual(m?.entered, true)
        XCTAssertEqual(m?.term, "报告")
        let m2 = LauncherScopeParser.parse("文件 ")
        XCTAssertEqual(m2?.entered, true)
        XCTAssertEqual(m2?.term, "")
    }

    func test英文与拼音关键词() {
        XCTAssertEqual(LauncherScopeParser.parse("file 合同")?.term, "合同")
        XCTAssertEqual(LauncherScopeParser.parse("FILES")?.entered, false)
        XCTAssertEqual(LauncherScopeParser.parse("wj 报告")?.entered, true)
        XCTAssertEqual(LauncherScopeParser.parse("搜文件")?.entered, false)
    }

    func test非范围词不误触() {
        XCTAssertNil(LauncherScopeParser.parse("文件管理器"))      // 前缀但不带空格 → 应用搜索
        XCTAssertNil(LauncherScopeParser.parse("wx"))
        XCTAssertNil(LauncherScopeParser.parse("文"))             // 单字不触发
        XCTAssertNil(LauncherScopeParser.parse("f 报告"))          // 字母前缀已被 IME 废掉，不收
        XCTAssertNil(LauncherScopeParser.parse(""))
    }

    func test进入后term可转文件前缀() {
        // ↵ 进入时 VM 把 searchText 换成 "' " + term，走既有 FileModeParser
        let term = LauncherScopeParser.parse("文件 合同")?.term ?? ""
        let prefixed = "' " + term
        XCTAssertTrue(FileModeParser.isFileMode(prefixed))
        XCTAssertEqual(FileModeParser.fileTerm(prefixed), "合同")
    }

    // MARK: - 两层兜底扫描

    func test兜底扫描_递归两层命中深层文件() throws {
        let home = NSTemporaryDirectory() + "qn-scope-test-\(UUID().uuidString)"
        // 结构：home/Documents/work/2026/合同v3.pdf（2 层深）+ home/顶层文件
        try FileManager.default.createDirectory(atPath: home + "/Documents/work/2026", withIntermediateDirectories: true)
        let deep = home + "/Documents/work/2026/合同v3.pdf"
        try Data("x".utf8).write(to: URL(fileURLWithPath: deep))
        try Data("x".utf8).write(to: URL(fileURLWithPath: home + "/顶层报告.txt"))
        defer { try? FileManager.default.removeItem(atPath: home) }

        let results = LauncherFileSearch.scanCommonDirectories(term: "合同", homePath: home)
        XCTAssertTrue(results.contains { $0.url.path == deep }, "两层深的文件必须能被兜底扫到")

        let top = LauncherFileSearch.scanCommonDirectories(term: "顶层", homePath: home)
        XCTAssertEqual(top.count, 1)
    }

    func test兜底扫描_第五层不递归() throws {
        let home = NSTemporaryDirectory() + "qn-scope-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home + "/Documents/a/b/c/d", withIntermediateDirectories: true)
        try Data("x".utf8).write(to: URL(fileURLWithPath: home + "/Documents/a/b/c/d/超深层文件.txt"))
        defer { try? FileManager.default.removeItem(atPath: home) }

        let results = LauncherFileSearch.scanCommonDirectories(term: "超深层", homePath: home)
        XCTAssertFalse(results.contains { $0.name == "超深层文件.txt" }, "过深的层级不无限递归（3000 项上限 + 层级限制，要全量请开 Spotlight）")
    }
}
