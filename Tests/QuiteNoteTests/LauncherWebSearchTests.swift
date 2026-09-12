import XCTest
@testable import QuiteNote

/// 网页搜索预设解析 + 退出应用关键词
final class LauncherWebSearchTests: XCTestCase {

    func test中文关键词_Google搜索() {
        let q = LauncherWebSearch.parse("搜索 swift 泛型")
        XCTAssertEqual(q?.presetName, "Google")
        XCTAssertEqual(q?.term, "swift 泛型")
        XCTAssertTrue(q?.url.absoluteString.contains("google.com/search?q=") == true)
    }

    func test中文关键词_百度() {
        let q = LauncherWebSearch.parse("百度 快捷键怎么按")
        XCTAssertEqual(q?.presetName, "百度")
        XCTAssertTrue(q?.url.absoluteString.contains("baidu.com/s?wd=") == true)
    }

    func test英文关键词_github与npm() {
        XCTAssertEqual(LauncherWebSearch.parse("gh swift ui")?.presetName, "GitHub")
        XCTAssertEqual(LauncherWebSearch.parse("npm alamofire")?.presetName, "npm")
    }

    func testURL转义中文() {
        let q = LauncherWebSearch.parse("搜索 中文 词汇")
        XCTAssertTrue(q?.url.absoluteString.contains("%20") == true, "空格必须转义")
    }

    func test无空格或无词不触发() {
        XCTAssertNil(LauncherWebSearch.parse("搜索"))          // 只有关键词没词
        XCTAssertNil(LauncherWebSearch.parse("搜索 "))         // 关键词+空格但词空
        XCTAssertNil(LauncherWebSearch.parse("搜索swift"))     // 无空格（避免误伤应用搜索）
        XCTAssertNil(LauncherWebSearch.parse("wx"))
    }

    func test英文词加空格触发搜索是预期行为() {
        // "google chrome"：google+空格 → 在 Google 搜索 chrome（Alfred 同款语义）
        let q = LauncherWebSearch.parse("google chrome")
        XCTAssertEqual(q?.presetName, "Google")
        XCTAssertEqual(q?.term, "chrome")
    }
}

/// 退出运行中应用：触发词解析（不依赖真实运行状态的部分）
final class LauncherQuitServiceTests: XCTestCase {

    @MainActor
    func test退出关键词触发() {
        // "退出" 单独 → 列出运行中应用（至少 Finder 在跑）
        let targets = LauncherQuitService.parse("退出")
        XCTAssertFalse(targets?.isEmpty ?? true, "至少应列出 Finder 等运行中应用")
        // "退出 finder" → 命中访达（中文系统显示名，bundleID 含 finder）
        let hits = LauncherQuitService.parse("退出 finder")
        XCTAssertTrue(hits?.contains { $0.bundleID.contains("finder") } == true)
    }

    @MainActor
    func test无匹配返回空数组而非nil() {
        // 触发但无匹配 → 空数组（区别于 nil=未触发）
        let hits = LauncherQuitService.parse("退出 不存在的应用zzz")
        XCTAssertEqual(hits?.count, 0)
    }

    @MainActor
    func test未触发返回nil() {
        XCTAssertNil(LauncherQuitService.parse("wx"))
        XCTAssertNil(LauncherQuitService.parse("退出微信"))  // 无空格不触发（同网页搜索规则）
    }
}
