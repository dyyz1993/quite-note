import XCTest
@testable import QuiteNote

/// 剪贴板内容类型识别（纯函数）
final class ClipboardTypeDetectionTests: XCTestCase {

    func testPureURLDetection() {
        XCTAssertTrue(ClipboardTypeDetector.isPureURL("https://example.com/path?q=1"))
        XCTAssertTrue(ClipboardTypeDetector.isPureURL("http://localhost:8080"))
        XCTAssertFalse(ClipboardTypeDetector.isPureURL("看这个 https://example.com 很棒")) // 夹带内容
        XCTAssertFalse(ClipboardTypeDetector.isPureURL("ftp://example.com")) // 非 http(s)
        XCTAssertFalse(ClipboardTypeDetector.isPureURL("普通文本"))
        XCTAssertFalse(ClipboardTypeDetector.isPureURL("https://example.com\n第二行"))
    }

    func testDomainExtraction() {
        XCTAssertEqual(ClipboardTypeDetector.domain(ofURL: "https://www.github.com/dyyz1993/quite-note"), "github.com")
        XCTAssertEqual(ClipboardTypeDetector.domain(ofURL: "https://apple.com/mac"), "apple.com")
        XCTAssertNil(ClipboardTypeDetector.domain(ofURL: "不是链接"))
    }

    func testDetectPriority() {
        // 文件 > 图片 > 链接 > 文本
        XCTAssertEqual(ClipboardTypeDetector.detect(hasFileURL: true, hasImage: true, text: "https://a.com"), .file)
        XCTAssertEqual(ClipboardTypeDetector.detect(hasFileURL: false, hasImage: true, text: "https://a.com"), .image)
        XCTAssertEqual(ClipboardTypeDetector.detect(hasFileURL: false, hasImage: false, text: "https://a.com"), .link)
        XCTAssertEqual(ClipboardTypeDetector.detect(hasFileURL: false, hasImage: false, text: "hello"), .text)
        XCTAssertEqual(ClipboardTypeDetector.detect(hasFileURL: false, hasImage: false, text: nil), .text)
    }
}

/// 剪贴板历史搜索：范围 + 匹配度排序（PRD 9）
final class ClipboardSearchRankingTests: XCTestCase {

    private func entry(_ type: ClipboardEntryType = .text,
                       text: String? = nil, url: String? = nil, ocr: String? = nil,
                       app: String? = nil, createdAt: Date = Date(),
                       pinned: Bool = false) -> ClipboardEntry {
        ClipboardEntry(
            type: type,
            createdAt: createdAt,
            plainText: text,
            sourceURL: url,
            sourceApp: app,
            contentHash: ClipboardService.sha1("\(type)-\(text ?? "")-\(url ?? "")-\(ocr ?? "")"),
            ocrText: ocr,
            isPinned: pinned
        )
    }

    func testMatchScoreRanking() {
        let full = entry(text: "swift")
        let prefix = entry(text: "swiftui 教程")
        let contains = entry(text: "学习 swift 语言")
        let none = entry(text: "完全无关")

        XCTAssertEqual(ClipboardSearchService.matchScore(query: "swift", entry: full), 3)
        XCTAssertEqual(ClipboardSearchService.matchScore(query: "swift", entry: prefix), 2)
        XCTAssertEqual(ClipboardSearchService.matchScore(query: "swift", entry: contains), 1)
        XCTAssertEqual(ClipboardSearchService.matchScore(query: "swift", entry: none), 0)
    }

    func testSearchOrderingFullBeforePrefixBeforeContains() {
        let older = Date(timeIntervalSinceNow: -100)
        let contains = entry(text: "学习 swift 语言", createdAt: older)
        let prefix = entry(text: "swiftui 教程", createdAt: older)
        let full = entry(text: "swift", createdAt: older)

        let results = ClipboardSearchService.search("swift", in: [contains, prefix, full])
        XCTAssertEqual(results.map(\.plainText), ["swift", "swiftui 教程", "学习 swift 语言"])
    }

    func testSameScoreSortedByRecency() {
        let old = entry(text: "swift 基础", createdAt: Date(timeIntervalSinceNow: -1000))
        let new = entry(text: "swift 进阶", createdAt: Date())
        let results = ClipboardSearchService.search("swift", in: [old, new])
        XCTAssertEqual(results.first?.plainText, "swift 进阶")
    }

    func testSearchCoversOCRDomainAndSourceApp() {
        let image = entry(.image, ocr: "发票金额 350 元")
        let link = entry(.link, url: "https://www.github.com/dyyz1993/quite-note")
        let fromApp = entry(app: "Safari")

        XCTAssertGreaterThan(ClipboardSearchService.matchScore(query: "发票", entry: image), 0)
        XCTAssertGreaterThan(ClipboardSearchService.matchScore(query: "github", entry: link), 0)
        XCTAssertGreaterThan(ClipboardSearchService.matchScore(query: "safari", entry: fromApp), 0)
    }

    func testEmptyQuery直通不重排() {
        // 2026-09-12 契约变更：空查询免排序直通（每次按键 O(n log n) 重排是打字
        // 卡顿主因）；「置顶优先+时间倒序」不变式由 store 的装载/插入/移动端维护
        let pinnedOld = entry(text: "置顶的旧内容", createdAt: Date(timeIntervalSinceNow: -9999), pinned: true)
        let recent = entry(text: "最新", createdAt: Date())
        let older = entry(text: "较旧", createdAt: Date(timeIntervalSinceNow: -100))

        let input = [pinnedOld, recent, older]   // store 顺序（不变式已排好）
        let results = ClipboardSearchService.search("", in: input)
        XCTAssertEqual(results.map(\.plainText), ["置顶的旧内容", "最新", "较旧"], "空查询必须原样直通")
    }

    func testCaseAndDiacriticInsensitive() {
        let e = entry(text: "Café Latte")
        XCTAssertEqual(ClipboardSearchService.matchScore(query: "CAFE", entry: e), 2) // 前缀（音调归一化后）
        XCTAssertEqual(ClipboardSearchService.matchScore(query: "café latte", entry: e), 3) // 完整
        XCTAssertEqual(ClipboardSearchService.matchScore(query: "LATTE", entry: e), 1) // 包含
    }
}

/// 保留策略：过期 + 上限 + 置顶/闪记豁免（PRD 4.3）
final class ClipboardRetentionTests: XCTestCase {

    private func entry(createdAt: Date, pinned: Bool = false, saved: Bool = false) -> ClipboardEntry {
        ClipboardEntry(
            type: .text,
            createdAt: createdAt,
            plainText: "内容",
            contentHash: ClipboardService.sha1("\(createdAt.timeIntervalSince1970)-\(pinned)-\(saved)"),
            isPinned: pinned,
            savedRecordID: saved ? UUID() : nil
        )
    }

    func testExpiredEntriesRemoved() {
        let now = Date()
        let fresh = entry(createdAt: now.addingTimeInterval(-3600))
        let stale = entry(createdAt: now.addingTimeInterval(-40 * 86400)) // 40 天前

        let victims = ClipboardHistoryStore.retentionVictims([fresh, stale], now: now, retentionDays: 30, maxEntries: 500)
        XCTAssertEqual(victims, [stale.id])
    }

    func testPinnedAndSavedNeverExpired() {
        let now = Date()
        let old = now.addingTimeInterval(-100 * 86400)
        let pinned = entry(createdAt: old, pinned: true)
        let saved = entry(createdAt: old, saved: true)

        let victims = ClipboardHistoryStore.retentionVictims([pinned, saved], now: now, retentionDays: 30, maxEntries: 500)
        XCTAssertTrue(victims.isEmpty)
    }

    func testZeroRetentionDaysMeansNever() {
        let now = Date()
        let ancient = entry(createdAt: now.addingTimeInterval(-3650 * 86400))
        let victims = ClipboardHistoryStore.retentionVictims([ancient], now: now, retentionDays: 0, maxEntries: 500)
        XCTAssertTrue(victims.isEmpty)
    }

    func testMaxEntriesEvictsOldestUnpinned() {
        let now = Date()
        // 5 条可清理（从旧到新）+ 1 条置顶 + 1 条已加闪记，上限 3
        let oldest = entry(createdAt: now.addingTimeInterval(-500))
        let second = entry(createdAt: now.addingTimeInterval(-400))
        let third = entry(createdAt: now.addingTimeInterval(-300))
        let fourth = entry(createdAt: now.addingTimeInterval(-200))
        let newest = entry(createdAt: now.addingTimeInterval(-100))
        let pinned = entry(createdAt: now.addingTimeInterval(-999), pinned: true)
        let saved = entry(createdAt: now.addingTimeInterval(-999), saved: true)

        let victims = ClipboardHistoryStore.retentionVictims(
            [oldest, second, third, fourth, newest, pinned, saved],
            now: now, retentionDays: 0, maxEntries: 3
        )
        // 可清理 5 条 → 保留最新 3 条（third/fourth/newest），淘汰 oldest/second
        XCTAssertEqual(victims, [oldest.id, second.id])
    }

    func testPinnedDoesNotCountAgainstLimit() {
        let now = Date()
        let pinned = entry(createdAt: now.addingTimeInterval(-999), pinned: true)
        var entries = [pinned]
        for i in 0..<5 {
            entries.append(entry(createdAt: now.addingTimeInterval(Double(-i))))
        }
        // 上限 3：淘汰最旧 2 条未置顶的；置顶条目不受影响
        let victims = ClipboardHistoryStore.retentionVictims(entries, now: now, retentionDays: 0, maxEntries: 3)
        XCTAssertEqual(victims.count, 2)
        XCTAssertFalse(victims.contains(pinned.id))
    }
}
