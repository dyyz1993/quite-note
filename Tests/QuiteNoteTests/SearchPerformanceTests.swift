import XCTest
@testable import QuiteNote

/// 搜索计算量削减（TDD，2026-08-17 第二轮）
///
/// 目标：大内容记录下尽可能减少计算量——
/// 1. 快扫：走折叠缓存（每条记录的处理结果跨按键复用），前缀命中毫秒级交付，不整段 ICU 扫描
/// 2. 深扫：只在停手（安静期）后跑一轮，打字期间不反复全文扫描；可被新一轮搜索中止
/// 3. 常态（小内容记录）：全部折叠缓存命中，快扫即最终结果，单次交付
final class SearchPerformanceTests: XCTestCase {

    private func makeRecord(_ content: String, title: String? = nil) -> Record {
        Record(id: UUID(), title: title, content: content, createdAt: Date(), hash: UUID().uuidString)
    }

    /// 大内容 + 前缀命中：首个结果必须秒级交付（快扫），而不是等全量 ICU 扫描（旧代码 ~10s+）
    func testLargeContentSearchDeliversPrefixMatchesQuickly() {
        let searcher = RecordSearcher()
        let filler = String(repeating: "中", count: 750_000)
        var records: [Record] = []
        for i in 0..<200 {
            if i % 20 == 0 {
                records.append(makeRecord("前缀区 NEEDLE-\(i) " + filler))
            } else {
                records.append(makeRecord(filler + "no-match"))
            }
        }

        let first = expectation(description: "首个结果快速交付")
        var firstDeliveryAt: TimeInterval = 0
        let start = Date()
        searcher.debouncedSearch("needle", in: records, delay: 0.05) { results in
            firstDeliveryAt = Date().timeIntervalSince(start)
            XCTAssertEqual(results.count, 10, "快扫应找到全部前缀命中（大小写不敏感）")
            first.fulfill()
        }

        wait(for: [first], timeout: 2.5)
        XCTAssertLessThan(firstDeliveryAt, 2.0, "前缀命中应秒级交付，实际 \(firstDeliveryAt)s")

        // 收尾：开启新一轮搜索中止仍在后台跑的深扫，不拖累后续用例
        searcher.debouncedSearch("", in: []) { _ in }
    }

    /// 深处命中：先拿前缀结果（快扫），随后精化交付补上深扫命中
    func testDeepMatchesArriveInRefinedDelivery() {
        let searcher = RecordSearcher()
        let deepRecord = makeRecord(
            String(repeating: "x", count: 650_000) + " DEEPNEEDLE " + String(repeating: "x", count: 49_000))
        let prefixRecord = makeRecord("PREFIXNEEDLE 前缀命中")
        let smallFillers = (0..<50).map { _ in makeRecord("普通小记录 \(UUID().uuidString)") }
        let records = [deepRecord, prefixRecord] + smallFillers

        let fastArrived = expectation(description: "快扫先交付")
        let refined = expectation(description: "精化交付包含深扫命中")
        var deliveries: [Set<UUID>] = []
        searcher.debouncedSearch("needle", in: records, delay: 0.05, deepDelay: 1.5) { results in
            deliveries.append(Set(results.map(\.id)))
            if deliveries.count == 1 { fastArrived.fulfill() }
            if deliveries.count == 2 { refined.fulfill() }
        }

        // 快扫先到：只含前缀命中（旧代码单次全量交付会同时含深扫命中 → 红）
        wait(for: [fastArrived], timeout: 2)
        XCTAssertEqual(deliveries[0], [prefixRecord.id], "快扫只含前缀命中，深处命中不在其中")

        wait(for: [refined], timeout: 10)
        XCTAssertEqual(deliveries.last, [prefixRecord.id, deepRecord.id], "深扫完成后应补上深处命中")
    }

    /// 连续打字期间不得反复启动深扫：精化只发生在停手之后，且只有一轮
    func testDeepScanRunsOnlyOnceAfterTypingSettles() {
        let searcher = RecordSearcher()
        // FINALNEEDLE 藏在 300KB 之后：中间按键态快扫均不命中，只有深扫能找到
        let deep = makeRecord(String(repeating: "y", count: 300_000) + " FINALNEEDLE")
        let records = [deep] + (0..<30).map { _ in makeRecord("小记录") }

        let settled = expectation(description: "停手后单轮精化")
        var callbackCount = 0
        var finalQueryDeliveries = 0
        var refinedAt: TimeInterval = 0
        var lastTypedAt: TimeInterval = 0
        let partials = ["f", "fi", "fin", "final", "finaln", "finalne", "finalneed", "finalneedl", "finalneedle"]

        // 用 asyncAfter 模拟连续按键（不能 Thread.sleep：会阻塞主队列，main.async 的交付无法派发）
        for (index, partial) in partials.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.1) { [weak searcher] in
                guard let searcher else { return }
                if index == partials.count - 1 {
                    lastTypedAt = Date().timeIntervalSinceReferenceDate
                }
                searcher.debouncedSearch(partial, in: records, delay: 0.02, deepDelay: 0.4) { [partial] _ in
                    callbackCount += 1
                    if partial == "finalneedle" {
                        finalQueryDeliveries += 1
                        if finalQueryDeliveries == 2 {
                            refinedAt = Date().timeIntervalSinceReferenceDate
                            settled.fulfill()
                        }
                    }
                }
            }
        }

        wait(for: [settled], timeout: 10)
        XCTAssertEqual(callbackCount, 10, "8 个中间态 + 最终态各快扫一次 + 最终精化一次 = 10")
        XCTAssertGreaterThanOrEqual(refinedAt - lastTypedAt, 0.35,
            "精化交付必须发生在安静期之后（打字期间不启动深扫），实际间隔 \(refinedAt - lastTypedAt)s")
    }

    /// 折叠缓存单元：同键复用不重算、内容变化重折叠、预算逐出
    func testFoldedTextCacheReuseInvalidationAndEviction() {
        let cache = FoldedTextCache(budgetBytes: 64)
        let rec = makeRecord("Hello 世界")

        let key = FoldedTextCache.Key(record: rec, caseSensitive: false)
        let entry = cache.entry(for: key) { FoldedTextCache.Entry(folded: "hello 世界", isPartial: false) }
        _ = cache.entry(for: key) {
            XCTFail("同键第二次访问必须命中缓存")
            return entry
        }
        XCTAssertEqual(cache.hitCount, 1)

        // 内容变化（hash/count 不同）→ 键失效，重新折叠
        let changed = Record(id: rec.id, title: nil, content: "Hello 新世界", createdAt: rec.createdAt, hash: "changed")
        let changedKey = FoldedTextCache.Key(record: changed, caseSensitive: false)
        var remade = false
        _ = cache.entry(for: changedKey) {
            remade = true
            return FoldedTextCache.Entry(folded: "hello 新世界", isPartial: false)
        }
        XCTAssertTrue(remade, "内容变化的记录必须重新折叠")

        // 预算逐出：再放一个超过预算的条目，旧键被挤出，再次访问需重建
        let big = makeRecord(String(repeating: "z", count: 200))
        let bigKey = FoldedTextCache.Key(record: big, caseSensitive: false)
        _ = cache.entry(for: bigKey) { FoldedTextCache.Entry(folded: String(repeating: "z", count: 200), isPartial: false) }
        var evictedAndRemade = false
        _ = cache.entry(for: key) {
            evictedAndRemade = true
            return entry
        }
        XCTAssertTrue(evictedAndRemade, "超出预算后旧条目应被逐出")
    }
}
