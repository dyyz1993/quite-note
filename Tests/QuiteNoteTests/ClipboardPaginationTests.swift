import XCTest
@testable import QuiteNote

/// 剪贴板历史按需分页加载（防大库全量物化）
///
/// 用 QN_TEST_STORAGE_ROOT 隔离的真实 CoreData 库：注入 1200 条 →
/// 首屏只加载 500 → loadMore 翻页 → loadAllIfNeeded 补齐，搜索覆盖全量。
final class ClipboardPaginationTests: XCTestCase {

    private var store: ClipboardHistoryStore!
    private var savedMaxEntries = 0
    private var savedRetentionDays = 0

    override func setUp() {
        super.setUp()
        TestStorageIsolation.activate
        // 保留策略默认上限 500，会在 seed 过程中清理测试数据——测试期临时调大并保存原值
        let prefs = MainActor.assumeIsolated { PreferencesManager.shared }
        savedMaxEntries = MainActor.assumeIsolated { prefs.clipboardMaxEntries }
        savedRetentionDays = MainActor.assumeIsolated { prefs.clipboardRetentionDays }
        MainActor.assumeIsolated {
            prefs.setClipboardMaxEntries(5000)
            prefs.setClipboardRetentionDays(-1)
        }
        store = MainActor.assumeIsolated { ClipboardHistoryStore() }
        // 隔离库在同一测试进程内跨用例共享，清掉上一用例的残留
        MainActor.assumeIsolated { store.deleteAllForTesting() }
    }

    override func tearDown() {
        store = nil
        let prefs = MainActor.assumeIsolated { PreferencesManager.shared }
        MainActor.assumeIsolated {
            prefs.setClipboardMaxEntries(savedMaxEntries)
            prefs.setClipboardRetentionDays(savedRetentionDays)
        }
        super.tearDown()
    }

    @MainActor
    private func seed(_ n: Int) {
        let base = Date().addingTimeInterval(-Double(n) * 60)
        for i in 0..<n {
            store.insertOrUpdate(ClipboardEntry(
                type: .text,
                createdAt: base.addingTimeInterval(Double(i) * 60),
                plainText: "PAGETEST\(String(format: "%04d", n - i)) 条",
                sourceApp: "Pagetest", sourceBundleID: "com.pagetest",
                contentHash: "pagetest-\(n)-\(i)"
            ))
        }
    }

    @MainActor
    func test首页500_hasMore_翻页补齐() {
        seed(1200)
        store.reload()

        // 首屏只物化 500 条（置顶优先 + 时间倒序）
        XCTAssertEqual(store.entries.count, ClipboardHistoryStore.pageSize)
        XCTAssertEqual(store.entries.first?.plainText?.hasPrefix("PAGETEST0001"), true, "最新条目在顶部（seed: i=n-1 → 文本 0001）")
        XCTAssertTrue(store.hasMore)

        // 翻一页 → 1000
        store.loadMore()
        XCTAssertEqual(store.entries.count, 1000)
        XCTAssertTrue(store.hasMore)

        // 翻到底 → 全部，hasMore 归 false
        store.loadMore()
        store.loadMore()
        XCTAssertEqual(store.entries.count, 1200)
        XCTAssertFalse(store.hasMore)
        // 最后加载的是最旧条目
        XCTAssertEqual(store.entries.last?.plainText?.hasPrefix("PAGETEST1200"), true)
    }

    @MainActor
    func test小库_单页装下_无翻页() {
        seed(120)
        store.reload()
        XCTAssertEqual(store.entries.count, 120)
        XCTAssertFalse(store.hasMore)
        store.loadMore()
        XCTAssertEqual(store.entries.count, 120, "无更多时 loadMore 必须是空操作")
    }

    @MainActor
    func test搜索前补齐全量_覆盖未加载页() {
        seed(1200)
        store.reload()
        // 未加载页里的旧条目（第 1100 条），首屏搜索也要能命中
        XCTAssertEqual(store.entries.count, 500)
        store.loadAllIfNeeded()
        XCTAssertEqual(store.entries.count, 1200)
        XCTAssertFalse(store.hasMore)
        let hit = store.entries.filter { ($0.plainText ?? "").contains("PAGETEST1100") }
        XCTAssertEqual(hit.count, 1, "补齐后旧条目必须可搜")
    }
}
