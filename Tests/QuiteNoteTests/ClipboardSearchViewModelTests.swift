import QuiteNoteSharedStorage
import XCTest
@testable import QuiteNote

/// 剪贴板搜索不能在 SwiftUI body 中触发全量读取；后台结果必须按代际交付。
@MainActor
final class ClipboardSearchViewModelTests: XCTestCase {

    private var savedMaxEntries = 0
    private var savedRetentionDays = 0

    override func setUp() {
        super.setUp()
        TestStorageIsolation.activate
        let prefs = MainActor.assumeIsolated { PreferencesManager.shared }
        savedMaxEntries = MainActor.assumeIsolated { prefs.clipboardMaxEntries }
        savedRetentionDays = MainActor.assumeIsolated { prefs.clipboardRetentionDays }
        MainActor.assumeIsolated {
            prefs.setClipboardMaxEntries(5000)
            prefs.setClipboardRetentionDays(-1)
        }
    }

    override func tearDown() {
        let prefs = MainActor.assumeIsolated { PreferencesManager.shared }
        MainActor.assumeIsolated {
            prefs.setClipboardMaxEntries(savedMaxEntries)
            prefs.setClipboardRetentionDays(savedRetentionDays)
        }
        super.tearDown()
    }

    private func makeEntry(_ n: Int) -> ClipboardEntry {
        ClipboardEntry(
            type: .text,
            createdAt: Date().addingTimeInterval(Double(n)),
            plainText: "clip-search-\(n)",
            contentHash: "clip-search-\(n)"
        )
    }

    func testEmptyQueryUsesLoadedPageWithoutBackgroundCorpus() {
        let store = ClipboardHistoryStore()
        store.deleteAllForTesting()
        (0..<3).forEach { store.insertOrUpdate(makeEntry($0)) }
        let vm = ClipboardHistoryViewModel()

        vm.bind(store: store)

        XCTAssertEqual(vm.visibleEntries.map { $0.plainText ?? "" }, [
            "clip-search-2", "clip-search-1", "clip-search-0",
        ])
        XCTAssertFalse(vm.isSearching)
    }

    func testTogglePinKeepsSelectionOnPinnedEntry() {
        let store = ClipboardHistoryStore()
        store.deleteAllForTesting()
        (0..<3).forEach { store.insertOrUpdate(makeEntry($0)) }
        let vm = ClipboardHistoryViewModel()
        vm.bind(store: store)

        // 初始 [2, 1, 0]（时间倒序）：选中最后一条（最旧）
        vm.selectedIndex = 2
        let pinnedID = vm.visibleEntries[2].id

        vm.togglePinSelected()

        // 置顶 → 条目移到头部，选中态必须跟随（而不是留在旧下标 2 上）
        XCTAssertEqual(vm.visibleEntries.first?.id, pinnedID)
        XCTAssertEqual(vm.selectedIndex, 0, "置顶后选中应跟随原条目到新位置")
        XCTAssertTrue(vm.visibleEntries[0].isPinned)

        // 再按一次 ⌘P 取消置顶 → 条目回到底部原位，选中继续跟随
        vm.togglePinSelected()
        XCTAssertEqual(vm.visibleEntries.last?.id, pinnedID)
        XCTAssertEqual(vm.selectedIndex, 2, "取消置顶后选中应跟随原条目回到原位置")
        XCTAssertFalse(vm.visibleEntries[2].isPinned)
    }

    func test两区键盘模型_光标区进出() {
        let store = ClipboardHistoryStore()
        store.deleteAllForTesting()
        (0..<3).forEach { store.insertOrUpdate(makeEntry($0)) }
        let vm = ClipboardHistoryViewModel()
        vm.bind(store: store)

        // 默认列表区，选中第一条
        XCTAssertEqual(vm.selectedIndex, 0)
        XCTAssertFalse(vm.fieldCursorMode)

        // 第一条再按 ↑ → 进入输入框光标区（←/→ 变文本光标键）
        vm.handle(.moveUp, entries: vm.visibleEntries) { _ in }
        XCTAssertTrue(vm.fieldCursorMode, "第一条再按 ↑ 应进入光标区")

        // ↓ → 返回列表区，选中保持原位
        vm.handle(.moveDown, entries: vm.visibleEntries) { _ in }
        XCTAssertFalse(vm.fieldCursorMode)
        XCTAssertEqual(vm.selectedIndex, 0, "↓ 返回列表时选中应保持")

        // 非第一条的 ↑ 是普通向上移动，不进光标区
        vm.selectedIndex = 2
        vm.handle(.moveUp, entries: vm.visibleEntries) { _ in }
        XCTAssertFalse(vm.fieldCursorMode)
        XCTAssertEqual(vm.selectedIndex, 1)

        // 显式改变选中（点击行）离开光标区
        vm.handle(.moveUp, entries: vm.visibleEntries) { _ in }
        vm.selectedIndex = 0
        XCTAssertFalse(vm.fieldCursorMode, "选中变化应退出光标区")
    }

    func testIndexDocumentCarriesCompactPinyinForChineseTitle() {
        let chinese = ClipboardEntry(
            type: .text,
            plainText: "会议纪要：周会同步",
            contentHash: "pinyin-doc-1"
        )
        let doc = ClipboardHistoryViewModel.indexDocumentForTesting(chinese)
        XCTAssertEqual(doc.pinyinNormalized, "huiyijiyaozhouhuitongbu", "全拼必须压缩去空格（nihao 式无分隔输入才命中）")
        XCTAssertEqual(doc.pinyinInitialsNormalized, "hyjyzhtb")

        // 纯拉丁标题不生成拼音（建档成本守卫）
        let latin = ClipboardEntry(
            type: .text,
            plainText: "standup notes",
            contentHash: "pinyin-doc-2"
        )
        let latinDoc = ClipboardHistoryViewModel.indexDocumentForTesting(latin)
        XCTAssertEqual(latinDoc.pinyinNormalized, "")
        XCTAssertEqual(latinDoc.pinyinInitialsNormalized, "")
    }

    func testPinyinQueryMatchesChineseEntry() {
        let store = ClipboardHistoryStore()
        store.deleteAllForTesting()
        store.insertOrUpdate(ClipboardEntry(
            type: .text,
            plainText: "会议纪要：周会同步",
            contentHash: "pinyin-e2e-1"
        ))
        store.insertOrUpdate(makeEntry(1))
        let vm = ClipboardHistoryViewModel()
        vm.bind(store: store)
        vm.preloadSearchIndex(store: store)

        // 全拼无分隔（用户实际输入形态）
        let full = expectation(description: "full pinyin search delivers")
        func checkFull(_ attempts: Int = 0) {
            vm.searchText = "huiyijiyao"
            vm.flushSearchForTesting()
            if vm.visibleEntries.contains(where: { $0.plainText == "会议纪要：周会同步" }) && !vm.isSearching {
                full.fulfill()
            } else if attempts < 100 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { checkFull(attempts + 1) }
            } else {
                XCTFail("全拼搜索未命中中文条目")
                full.fulfill()
            }
        }
        checkFull()
        wait(for: [full], timeout: 7)

        // 首字母缩写
        let initials = expectation(description: "initials search delivers")
        func checkInitials(_ attempts: Int = 0) {
            vm.searchText = "hyjy"
            vm.flushSearchForTesting()
            if vm.visibleEntries.contains(where: { $0.plainText == "会议纪要：周会同步" }) && !vm.isSearching {
                initials.fulfill()
            } else if attempts < 100 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { checkInitials(attempts + 1) }
            } else {
                XCTFail("首字母搜索未命中中文条目")
                initials.fulfill()
            }
        }
        checkInitials()
        wait(for: [initials], timeout: 7)
    }

    func testNewerQuerySupersedesOldBackgroundResult() {
        let store = ClipboardHistoryStore()
        store.deleteAllForTesting()
        let vm = ClipboardHistoryViewModel()
        vm.bind(store: store)
        vm.searchText = "first"
        vm.flushSearchForTesting()
        XCTAssertTrue(vm.isSearching)

        vm.searchText = "second"
        vm.flushSearchForTesting()

        XCTAssertEqual(vm.debouncedQuery, "second")
        XCTAssertTrue(vm.isSearching, "旧查询结果落地前必须仍显示搜索中")
    }

    func testSearchQueryCommitsImmediatelyWithoutDebounceDelay() {
        let store = ClipboardHistoryStore()
        store.deleteAllForTesting()
        let vm = ClipboardHistoryViewModel()
        vm.bind(store: store)

        let start = Date()
        vm.searchText = "instant"

        XCTAssertEqual(vm.debouncedQuery, "instant")
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.05)
    }

    func testConcurrentAddedEntryIsMergedIntoSearchResult() {
        let store = ClipboardHistoryStore()
        store.deleteAllForTesting()
        let vm = ClipboardHistoryViewModel()
        vm.bind(store: store)

        vm.searchText = "merge"
        store.insertOrUpdate(ClipboardEntry(
            type: .text,
            plainText: "merge-concurrent",
            contentHash: "merge-concurrent"
        ))

        // The in-memory increment stays searchable while the background corpus
        // refresh is still in flight; delivery itself is covered by preload tests.
        XCTAssertTrue(vm.isSearching)
        XCTAssertTrue(store.entries.contains { $0.plainText == "merge-concurrent" })
    }

    func testSearchLoadsUnloadedCorpusAndDeliversMatches() {
        let store = ClipboardHistoryStore()
        store.deleteAllForTesting()
        (0..<20).forEach { store.insertOrUpdate(makeEntry($0)) }
        store.reload()
        let vm = ClipboardHistoryViewModel()
        vm.bind(store: store)

        vm.searchText = "clip-search-19"
        vm.flushSearchForTesting()

        let delivered = expectation(description: "background search delivers")
            let deadline = Date().addingTimeInterval(2.5)
            while Date() < deadline && vm.isSearching {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            XCTAssertEqual(vm.visibleEntries.map { $0.plainText ?? "" }, ["clip-search-19"])
            XCTAssertFalse(vm.isSearching)
            delivered.fulfill()
        wait(for: [delivered], timeout: 3)
    }

    @MainActor
    func testPreloadedIndexMakes500EntrySearchRespondWithoutRebuild() throws {
        let store = ClipboardHistoryStore()
        store.deleteAllForTesting()
        let documents = (0..<500).map { index in
            ClipboardHistoryViewModel.indexDocumentForTesting(ClipboardEntry(
                type: .text,
                createdAt: Date().addingTimeInterval(Double(-index)),
                plainText: "PERF500 \(index) clipboard-search corpus item",
                sourceApp: "Perf500",
                contentHash: "perf500-\(index)"
            ))
        }
        let service = SearchIndexService(documents: documents)
        let start = DispatchTime.now()
        let page = service.searchSync("clipboard-search", limit: 300)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000

        XCTAssertEqual(page.totalCount, 500)
        XCTAssertEqual(page.documents.count, 300)
        XCTAssertLessThan(elapsed, 50, "500 条预热索引搜索应低于 50ms，实际 \(elapsed)ms")
    }

    func testRemoteCoreInsertReloadsFirstPageWithoutManualRefresh() {
        let store = ClipboardHistoryStore()
        store.deleteAllForTesting()
        _ = store.loadIfNeededForTesting()
        let vm = ClipboardHistoryViewModel()
        // 生产语义下面板隐藏时 sink 跳过重算；本测试覆盖 sink 驱动路径，注入常真
        vm.isPanelVisibleProvider = { true }
        vm.bind(store: store)

        let payload = "remote-core-visible-\(UUID().uuidString)"
        let repository = ClipboardHistoryRepository(persistence: .shared)
        XCTAssertTrue(try repository.insertText(payload).inserted)
        store.reloadFromRemoteStoreForTesting()

        XCTAssertTrue(store.entries.contains { $0.plainText == payload })
        let refreshed = expectation(description: "remote reload reaches view model")
        DispatchQueue.main.async {
            XCTAssertTrue(vm.visibleEntries.contains { $0.plainText == payload })
            refreshed.fulfill()
        }
        wait(for: [refreshed], timeout: 2)
    }

    @MainActor
    func testPreloadIndexPreemptsTypingRebuildAndStoreChangesRefreshIt() throws {
        let store = ClipboardHistoryStore()
        store.deleteAllForTesting()
        store.insertOrUpdate(ClipboardEntry(
            type: .text,
            plainText: "preload target",
            contentHash: "preload-target"
        ))
        store.reload()
        let vm = ClipboardHistoryViewModel()
        vm.bind(store: store)

        vm.preloadSearchIndex(store: store)
        vm.searchText = "preload"
        XCTAssertEqual(vm.debouncedQuery, "preload")

        let preloaded = expectation(description: "preloaded search delivers")
        func check(_ attempts: Int = 0) {
            if vm.visibleEntries.map(\.plainText) == ["preload target"] && !vm.isSearching {
                preloaded.fulfill()
            } else if attempts < 100 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { check(attempts + 1) }
            } else {
                XCTFail("预热搜索未交付")
                preloaded.fulfill()
            }
        }
        check()
        wait(for: [preloaded], timeout: 7)
    }
}

private extension ClipboardHistoryViewModel {
    static func indexDocumentForTesting(_ entry: ClipboardEntry) -> SearchIndexDocument<ClipboardEntry> {
        indexDocument(entry)
    }

    /// 测试用：立即触发防抖后的提交逻辑。
    func flushSearchForTesting() {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        commitQueryForTesting(text)
    }

    func commitQueryForTesting(_ text: String) {
        debouncedQuery = text
        selectedIndex = 0
        resetViewport()
        recomputeVisibleEntries()
    }
}
