import XCTest
@testable import QuiteNote

/// 搜索卡死回归测试（TDD，2026-08-17 建立）
///
/// 复现两类用户可感知的"搜索输入卡死"：
/// 1. 全量扫描跑在主线程 —— 大内容记录搜索时 UI 冻结数秒
/// 2. 正则灾难性回溯 —— ICU 正则无超时，特定模式让主线程永久挂死
final class RecordSearcherTests: XCTestCase {

    private func makeRecord(_ content: String,
                            title: String? = nil,
                            summary: String? = nil,
                            tags: [String] = []) -> Record {
        Record(id: UUID(), title: title, content: content, createdAt: Date(),
               hash: UUID().uuidString, summary: summary, tags: tags)
    }

    // MARK: - 语义守卫（修复不得改变搜索语义）

    func testSearchFindsMatchesAcrossFieldsCaseInsensitive() {
        let searcher = RecordSearcher()
        let records = [
            makeRecord("plain body text", title: "Hello World"),
            makeRecord("another record", tags: ["Swift", "macos"]),
            makeRecord("带中文的记录")
        ]

        XCTAssertEqual(searcher.search("hello", in: records).count, 1, "标题命中（大小写不敏感）")
        XCTAssertEqual(searcher.search("body", in: records).count, 1, "内容命中")
        XCTAssertEqual(searcher.search("SWIFT", in: records).count, 1, "标签命中（大小写不敏感）")
        XCTAssertEqual(searcher.search("中文", in: records).count, 1, "中文命中")
        XCTAssertTrue(searcher.search("zzz-nomatch", in: records).isEmpty, "未命中返回空")
    }

    func testEmptyQueryReturnsAllRecords() {
        let searcher = RecordSearcher()
        let records = [makeRecord("a"), makeRecord("b")]
        XCTAssertEqual(searcher.search("", in: records).count, 2)
    }

    func testRegexSearchMatchesValidPatternAndFallsBackOnInvalid() {
        let searcher = RecordSearcher()
        searcher.searchUseRegex = true
        let records = [makeRecord("body", title: "Hello World")]

        XCTAssertEqual(searcher.search("Wor.d", in: records).count, 1, "合法正则应命中")

        // 非法正则（未闭合括号）回退为字面匹配，不崩溃
        let paren = [makeRecord("contains (paren here")]
        XCTAssertEqual(searcher.search("(paren", in: paren).count, 1, "非法正则回退字面匹配")
    }

    // MARK: - 卡死复现（红测试）

    /// 大内容全量搜索期间，主线程必须保持响应（探针按时执行）
    func testHeavySearchDoesNotBlockMainThread() {
        let searcher = RecordSearcher()
        // 200 条 × ~750KB 多字节内容 ≈ 150MB 扫描量，模拟真实"复制整个网页后搜索"
        let big = String(repeating: "中", count: 250_000) + "needle-not-here"
        let records = Array(repeating: makeRecord(big), count: 200)

        // 主线程探针：期望在搜索进行期间（防抖 0.1s 后开始）仍按时执行
        let probeExpectation = expectation(description: "主线程探针按时执行")
        let probeScheduledFire = Date().addingTimeInterval(0.6)
        var probeDelay: TimeInterval = -1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            probeDelay = Date().timeIntervalSince(probeScheduledFire)
            probeExpectation.fulfill()
        }

        let completionExpectation = expectation(description: "搜索最终完成")
        searcher.debouncedSearch("zzz-no-match", in: records, delay: 0.1) { _ in
            completionExpectation.fulfill()
        }

        wait(for: [probeExpectation], timeout: 20)
        XCTAssertLessThan(probeDelay, 1.0,
            "搜索期间主线程被阻塞超过 1 秒：全量扫描跑在主线程导致输入卡死，实际延迟 \(probeDelay)s")

        // 等后台搜索结束，避免拖累后续用例
        wait(for: [completionExpectation], timeout: 30)
    }

    /// 灾难性正则（指数回溯）必须在时限内回退，而不是无限挂死
    func testCatastrophicRegexDoesNotHangForever() {
        let searcher = RecordSearcher()
        searcher.searchUseRegex = true
        // (a+)+b 对 a^n 文本是经典指数回溯用例，n=34 时任何机器都不可能在几秒内完成
        let bomb = String(repeating: "a", count: 34)
        let records = [makeRecord(bomb), makeRecord("normal content")]

        // 在后台线程执行 + 3 秒观察窗：有 bug 时让断言失败，而不是挂死整个测试进程
        let done = expectation(description: "搜索在时限内返回")
        var elapsed: TimeInterval = 0
        DispatchQueue.global().async {
            let start = Date()
            let results = searcher.search("(a+)+b", in: records)
            elapsed = Date().timeIntervalSince(start)
            DispatchQueue.main.async { done.fulfill() }
            XCTAssertTrue(results.isEmpty, "回退字面匹配后 '(a+)+b' 不是 'aaaa...' 的子串，应为空结果")
        }
        wait(for: [done], timeout: 3.0)

        XCTAssertLessThan(elapsed, 2.5, "灾难性正则必须在软时限内回退字面匹配，实际耗时 \(elapsed)s")

        // 超时过的 query 应被拉黑，重复搜索直接走字面快速路径
        let againStart = Date()
        let again = searcher.search("(a+)+b", in: records)
        XCTAssertLessThan(Date().timeIntervalSince(againStart), 0.5, "超时拉黑后的重复搜索应立即返回")
        XCTAssertTrue(again.isEmpty)
    }

    // MARK: - 结果时效守卫

    /// 新一轮搜索开启后，旧搜索的迟到结果不得覆盖新结果
    func testNewSearchInvalidatesStaleResults() {
        let searcher = RecordSearcher()
        let big = String(repeating: "中", count: 300_000)
        let slowRecords = Array(repeating: makeRecord(big), count: 50)
        let allRecords = [makeRecord("one"), makeRecord("two")]

        var deliveries: [(query: String, count: Int)] = []
        let expectation = expectation(description: "等待观察窗口结束")
        expectation.isInverted = true

        searcher.debouncedSearch("zzz", in: slowRecords, delay: 0.05) { _ in
            deliveries.append(("slow", -1))
        }
        // 立即清空搜索：应同步拿到全量列表，且之后不允许 slow 的迟到回调再进来
        searcher.debouncedSearch("", in: allRecords) { results in
            deliveries.append(("empty", results.count))
        }

        wait(for: [expectation], timeout: 1.2)

        XCTAssertEqual(deliveries.last?.query, "empty", "最后一次交付必须是清空搜索的全量结果")
        XCTAssertEqual(deliveries.last?.count, 2)
        XCTAssertFalse(deliveries.contains { $0.query == "slow" }, "被新一轮搜索取代的任务不得交付结果")
    }
}
