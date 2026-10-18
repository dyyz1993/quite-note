import QuiteNoteSharedStorage
import XCTest
@testable import QuiteNote

/// 剪贴板搜索不能在 SwiftUI body 中触发全量读取；后台结果必须按代际交付。
@MainActor
final class ClipboardSearchViewModelTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TestStorageIsolation.activate
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
        vm.flushSearchForTesting()

        let added = expectation(description: "concurrent add remains visible")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            store.insertOrUpdate(ClipboardEntry(
                type: .text,
                createdAt: Date(),
                plainText: "merge-concurrent",
                contentHash: "merge-concurrent"
            ))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                XCTAssertTrue(vm.visibleEntries.contains { $0.plainText == "merge-concurrent" })
                XCTAssertFalse(vm.isSearching)
                added.fulfill()
            }
        }
        wait(for: [added], timeout: 3)
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

    func testRemoteCoreInsertReloadsFirstPageWithoutManualRefresh() {
        let store = ClipboardHistoryStore()
        store.deleteAllForTesting()
        _ = store.loadIfNeededForTesting()
        let vm = ClipboardHistoryViewModel()
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
}

private extension ClipboardHistoryViewModel {
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
