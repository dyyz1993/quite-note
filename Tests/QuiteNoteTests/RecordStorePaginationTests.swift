import XCTest
@testable import QuiteNote

/// 主列表翻页：RecordStore 是翻页状态的唯一真值（canLoadMoreRecords / fetchedRowCount），
/// UI 只读不写。夹具用私有库，记录在建 store 之前 saveSync 写入，避免 AI/去重逻辑干扰。
/// 写入的记录 createdAt 依次递减且都不收藏——库内排序与写入顺序一致，"第 N 条"即 ids[N-1]
@MainActor
final class RecordStorePaginationTests: StickyNoteTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("qn-store-pagination-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - 夹具

    /// 建私有库并预写 count 条记录，等首屏落地。store 首屏加载只弱引用自己，
    /// 断言期间要用 withExtendedLifetime 保住
    private func makeStore(initialRecordCount count: Int) -> (store: RecordStore, repository: RecordRepository, recordIDs: [UUID]) {
        let repository = RecordRepository(stack: CoreDataStack(databaseURL: tempDirectory.appendingPathComponent("QuiteNote.sqlite")))
        var ids: [UUID] = []
        for index in 0..<count {
            let id = UUID()
            let record = QuiteNote.Record(
                id: id,
                content: "第 \(index) 条",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000 - TimeInterval(index)),
                hash: "pagination-\(index)"
            )
            XCTAssertNoThrow(try repository.saveSync(record))
            ids.append(id)
        }
        let store = RecordStore(repository: repository)
        waitUntil { store.records.count == min(count, 100) }
        return (store, repository, ids)
    }

    // MARK: - 用例

    func testLoadMoreFetchesTheRestOfASmallLibraryAndThenStops() {
        let (store, _, ids) = makeStore(initialRecordCount: 130)
        withExtendedLifetime(store) {
            XCTAssertEqual(store.records.count, 100)
            XCTAssertTrue(store.canLoadMoreRecords, "首屏取满一页，库里还有旧记录")

            var completionValue: Bool?
            store.loadMoreRecords { completionValue = $0 }
            XCTAssertTrue(waitUntil { completionValue != nil }, "翻页完成必须回调")
            XCTAssertEqual(store.records.count, 130, "130 条的库翻一页后应全部进内存")
            XCTAssertEqual(completionValue, store.canLoadMoreRecords)
            XCTAssertFalse(store.canLoadMoreRecords, "最后一页没取满，不该再有下一页")

            XCTAssertEqual(Set(store.records.map(\.id)), Set(ids), "第 101–130 条原记录一条不少")

            let countAfterLoad = store.records.count
            var secondValue: Bool?
            store.loadMoreRecords { secondValue = $0 }
            XCTAssertEqual(secondValue, false, "没有更多记录时立即以 false 收尾")
            XCTAssertEqual(store.records.count, countAfterLoad, "再调不应增长")
        }
    }

    func testPaginationStopsAtTheInMemoryWindowCap() {
        let (store, _, _) = makeStore(initialRecordCount: 260)
        withExtendedLifetime(store) {
            XCTAssertEqual(store.records.count, 100)

            var first: Bool?
            store.loadMoreRecords { first = $0 }
            XCTAssertTrue(waitUntil { first != nil })
            XCTAssertEqual(store.records.count, 150)
            XCTAssertEqual(first, true)
            XCTAssertEqual(store.canLoadMoreRecords, true)

            var second: Bool?
            store.loadMoreRecords { second = $0 }
            XCTAssertTrue(waitUntil { second != nil })
            XCTAssertEqual(store.records.count, 200, "内存窗口上限 200 条")
            XCTAssertEqual(second, false)
            XCTAssertEqual(store.canLoadMoreRecords, false, "总取数已到窗口上限，不再有下一页")

            // 库里还有 60 条旧记录，但窗口已满：不再加载
            let countAtCap = store.records.count
            store.loadMoreRecords { _ in }
            XCTAssertEqual(store.records.count, countAtCap)
        }
    }

    /// offset 稳定性：两次翻页之间新进一条记录（库里 +1、内存顶部 +1），下一页
    /// 不能因为 offset 被顶偏而漏掉最旧的记录
    func testOffsetSurvivesARecordAddedBetweenPages() throws {
        let (store, repository, ids) = makeStore(initialRecordCount: 130)
        try withExtendedLifetime(store) {
            let concurrent = QuiteNote.Record(
                id: UUID(),
                content: "翻页间新增",
                createdAt: Date(),
                hash: "pagination-concurrent"
            )
            XCTAssertNoThrow(try repository.saveSync(concurrent))
            store.replaceRecordsForTesting([concurrent] + store.records)
            XCTAssertEqual(store.records.count, 101)

            var completionValue: Bool?
            store.loadMoreRecords { completionValue = $0 }
            XCTAssertTrue(waitUntil { completionValue != nil })

            XCTAssertEqual(store.records.count, 131, "库里 131 条应全部进内存")
            XCTAssertEqual(Set(store.records.map(\.id)), Set(ids + [concurrent.id]),
                           "新记录进了内存，第 101–130 条原记录也要一条不少")
        }
    }

    func testCompletionMatchesCanLoadMoreAndDuplicateCallsDoNotFetchTwice() {
        let (store, _, _) = makeStore(initialRecordCount: 260)
        withExtendedLifetime(store) {
            var completions: [Bool] = []
            store.loadMoreRecords { completions.append($0) }
            store.loadMoreRecords { completions.append($0) } // 加载期间重复调用：不并发取页
            XCTAssertTrue(waitUntil { !completions.isEmpty })
            XCTAssertEqual(completions.count, 1, "加载期间的重复调用不应再取页、不再回调")
            XCTAssertEqual(completions[0], store.canLoadMoreRecords, "回调值与落地后的 canLoadMoreRecords 一致")
            XCTAssertEqual(store.records.count, 150)
            XCTAssertFalse(store.isLoadingMoreRecords, "取页落地后加载标志复位")

            store.loadMoreRecords { completions.append($0) }
            XCTAssertTrue(waitUntil { completions.count == 2 })
            store.loadMoreRecords { completions.append($0) }
            XCTAssertTrue(waitUntil { completions.count == 3 })
            // 第二页把窗口填满（fetched 200），这一页的回调值就是 false；第三次调用已无更多
            XCTAssertEqual(completions, [true, false, false], "回调值逐页与 canLoadMoreRecords 一致")
            XCTAssertEqual(store.records.count, 200)
            XCTAssertFalse(store.isLoadingMoreRecords)
        }
    }
}
