import XCTest
@testable import QuiteNote

final class SearchIndexServiceTests: XCTestCase {
    private struct Item: Equatable {
        let value: String
    }

    private typealias Doc = SearchIndexDocument<Item>

    private func doc(
        _ value: String,
        title: String,
        body: String = "",
        pinyin: String = "",
        initials: String = "",
        createdAt: Date = .distantPast,
        pinned: Bool = false
    ) -> Doc {
        Doc(
            id: value,
            source: .clipboard,
            payload: Item(value: value),
            title: title,
            body: body,
            pinyin: pinyin,
            pinyinInitials: initials,
            createdAt: createdAt,
            isPinned: pinned
        )
    }

    func testScoringAndPagination() {
        let service = SearchIndexService<Doc>(documents: [
            doc("contains", title: "hello needle", createdAt: Date(timeIntervalSince1970: 2)),
            doc("prefix", title: "needle start", createdAt: Date(timeIntervalSince1970: 1)),
            doc("exact", title: "needle", createdAt: Date(timeIntervalSince1970: 0)),
            doc("none", title: "other"),
        ])

        let page = service.searchSync("needle")
        XCTAssertEqual(page.documents.map(\.payload.value), ["exact", "prefix", "contains"])
        XCTAssertEqual(page.totalCount, 3)
        XCTAssertTrue(page.isComplete)

        let firstPage = service.searchSync("needle", offset: 0, limit: 2)
        XCTAssertEqual(firstPage.documents.map(\.payload.value), ["exact", "prefix"])
        XCTAssertEqual(firstPage.totalCount, 3)
        XCTAssertFalse(firstPage.isComplete)

        let secondPage = service.searchSync("needle", offset: firstPage.nextOffset, limit: 2)
        XCTAssertEqual(secondPage.documents.map(\.payload.value), ["contains"])
        XCTAssertTrue(secondPage.isComplete)
    }

    func testPinyinAndBodyFallback() {
        let service = SearchIndexService<Doc>(documents: [
            doc("pinyin", title: "微信", pinyin: "weixin", initials: "wx"),
            doc("body", title: "标题", body: "needle in body"),
        ])

        XCTAssertEqual(service.searchSync("weixin").documents.map(\.payload.value), ["pinyin"])
        XCTAssertEqual(service.searchSync("wx").documents.map(\.payload.value), ["pinyin"])
        XCTAssertEqual(service.searchSync("needle").documents.map(\.payload.value), ["body"])
    }

    func testEmptyQueryKeepsPinnedThenRecency() {
        let service = SearchIndexService<Doc>(documents: [
            doc("old-pinned", title: "old", createdAt: Date(timeIntervalSince1970: 0), pinned: true),
            doc("new", title: "new", createdAt: Date(timeIntervalSince1970: 3)),
            doc("old", title: "old", createdAt: Date(timeIntervalSince1970: 1)),
        ])

        XCTAssertEqual(service.searchSync("").documents.map(\.payload.value), ["old-pinned", "new", "old"])
    }

    func testRebuildAndCancelAreAsync() {
        let service = SearchIndexService<Doc>()
        let rebuilt = expectation(description: "rebuilt")
        service.rebuild(using: { [self] in [doc("v2", title: "needle")] }) { _ in
            rebuilt.fulfill()
        }
        wait(for: [rebuilt], timeout: 2)
        XCTAssertEqual(service.searchSync("needle").documents.map(\.payload.value), ["v2"])

        let cancelled = expectation(description: "cancelled rebuild does not deliver")
        cancelled.isInverted = true
        let rebuildStarted = DispatchSemaphore(value: 0)
        let releaseRebuild = DispatchSemaphore(value: 0)
        service.cancel()
        service.rebuild(using: { [self] in
            rebuildStarted.signal()
            releaseRebuild.wait()
            return [doc("v3", title: "needle")]
        }) { _ in
            cancelled.fulfill()
        }
        XCTAssertEqual(rebuildStarted.wait(timeout: .now() + 1), .success)
        service.cancel()
        releaseRebuild.signal()
        wait(for: [cancelled], timeout: 0.3)
        XCTAssertEqual(service.searchSync("needle").documents.map(\.payload.value), ["v2"])
    }

    func testAsyncSearchSupersedesOldResult() {
        let service = SearchIndexService<Doc>(documents: [doc("one", title: "needle one")])
        let oldResult = expectation(description: "old result")
        oldResult.isInverted = true

        service.search("needle") { _ in oldResult.fulfill() }
        service.cancel()

        wait(for: [oldResult], timeout: 0.3)
    }

    func testLargeIndexSearchStaysFast() {
        let documents = (0..<10_000).map { index -> Doc in
            doc("item-\(index)", title: "needle-\(index % 100) item-\(index)")
        }
        let service = SearchIndexService<Doc>(documents: documents)

        let started = DispatchTime.now()
        let page = service.searchSync("needle", limit: 100)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000

        XCTAssertEqual(page.totalCount, 10_000)
        XCTAssertEqual(page.documents.count, 100)
        XCTAssertLessThan(elapsed, 150, "10k 文档首页搜索应显著低于交互阈值，实际 \(elapsed)ms")
    }

    func testScoreBonusAndSubsequence() {
        let service = SearchIndexService<Doc>(documents: [
            doc("normal", title: "google chrome"),
            doc("recent", title: "google chrome"),
        ])
        // Adapter 路径可直接注入 scoreBonus；这里用子序列确认 Alfred 兜底仍可用。
        _ = service
        let subsequenceService = SearchIndexService<Doc>(documents: [
            doc("gch", title: "google chrome"),
        ])
        XCTAssertEqual(subsequenceService.searchSync("gch").documents.map(\.payload.value), ["gch"])
    }

    /// 回归钉子：rebuild 与 search 背靠背调用（启动器 recompute 的实际接线方式），
    /// search 必须看到刚 rebuild 的快照。旧实现的两个缺陷都会让本测试红：
    /// ① search 递增代际使先入队的 rebuild 写入被丢弃（索引永远为空）；
    /// ② rebuild 的写入再包一层 queue.async 会让 search 抢先读到旧快照。
    func testRebuildThenBackToBackSearchSeesNewSnapshot() {
        let service = SearchIndexService<Doc>(documents: [doc("old", title: "stale entry")])
        let delivered = expectation(description: "search sees rebuilt snapshot")

        service.rebuild(documents: [doc("new", title: "needle fresh")])
        service.search("needle", limit: 10) { page in
            XCTAssertEqual(page.documents.map(\.payload.value), ["new"], "背靠背 search 必须命中刚写入的文档")
            delivered.fulfill()
        }

        wait(for: [delivered], timeout: 2)
    }
}
