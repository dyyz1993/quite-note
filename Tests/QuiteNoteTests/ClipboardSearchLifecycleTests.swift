import Combine
import CoreData
import QuiteNoteSharedStorage
import XCTest
@testable import QuiteNote

/// Control corpus delivery to exercise races, rather than only checking the input string.
@MainActor
final class ClipboardSearchLifecycleTests: XCTestCase {
    private func makeStore(_ entries: [ClipboardEntry]) throws -> ClipboardHistoryStore {
        TestStorageIsolation.activate
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quitenote-search-lifecycle-\(UUID().uuidString)", isDirectory: true)
        let persistence = ClipboardHistoryPersistence(databaseURL: root.appendingPathComponent("history.sqlite"))
        addTeardownBlock {
            let context = persistence.context
            await context.perform(schedule: .enqueued) {
                context.reset()
            }
            let coordinator = persistence.container.persistentStoreCoordinator
            try coordinator.performAndWait {
                for persistentStore in coordinator.persistentStores {
                    try coordinator.remove(persistentStore)
                }
            }
            try FileManager.default.removeItem(at: root)
        }
        let repository = ClipboardHistoryRepository(persistence: persistence)
        for entry in entries { _ = try repository.insertOrUpdate(entry) }
        let store = ClipboardHistoryStore(persistence: persistence)
        store.reload()
        return store
    }

    private func entry(_ text: String, type: ClipboardEntryType = .text) -> ClipboardEntry {
        ClipboardEntry(type: type, plainText: text, contentHash: "\(type.rawValue)-\(text)")
    }

    private func waitForSearch(_ vm: ClipboardHistoryViewModel, file: StaticString = #filePath, line: UInt = #line) async {
        guard vm.isSearching else { return }
        let finished = expectation(description: "current search publishes its result")
        let subscription = vm.$isSearching.dropFirst().filter { !$0 }.prefix(1).sink { _ in
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 3)
        withExtendedLifetime(subscription) {}
        XCTAssertFalse(vm.isSearching, file: file, line: line)
    }

    private func drainMainQueue() async {
        let drained = expectation(description: "queued store notifications delivered")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
    }

    func testTypingDuringPreloadWaitsForFullCorpus() async throws {
        let loaded = entry("recent clipboard item")
        let archived = entry("archived needle")
        let store = try makeStore([loaded])
        var completions: [([ClipboardEntry]) -> Void] = []
        let vm = ClipboardHistoryViewModel { requestedStore, completion in
            XCTAssertTrue(requestedStore === store, "Search must use its bound store, not the singleton")
            completions.append(completion)
        }
        vm.bind(store: store)
        vm.preloadSearchIndex(store: store)

        vm.searchText = "archived"

        XCTAssertTrue(vm.isSearching)
        XCTAssertTrue(vm.visibleEntries.isEmpty, "Previous results must not remain actionable")
        XCTAssertEqual(completions.count, 1, "Typing should reuse the pending corpus read")
        // The full corpus can include an older page absent from store.entries.
        try XCTUnwrap(completions.first)([loaded, archived])
        await waitForSearch(vm)
        XCTAssertEqual(vm.visibleEntries.map(\.id), [archived.id])
    }

    func testLatestQueryWinsWhileCorpusIsLoading() async throws {
        let first = entry("first result")
        let second = entry("second result")
        let store = try makeStore([first, second])
        var completions: [([ClipboardEntry]) -> Void] = []
        let vm = ClipboardHistoryViewModel { _, completion in completions.append(completion) }
        vm.bind(store: store)

        vm.searchText = "first"
        vm.searchText = "second"

        XCTAssertEqual(completions.count, 1)
        try XCTUnwrap(completions.first)(store.entries)
        await waitForSearch(vm)
        XCTAssertEqual(vm.debouncedQuery, "second")
        XCTAssertEqual(vm.visibleEntries.map(\.id), [second.id])
    }

    func testClearingQueryPreventsPendingResultFromReplacingHistory() async throws {
        let store = try makeStore([entry("needle"), entry("other history")])
        var completions: [([ClipboardEntry]) -> Void] = []
        let vm = ClipboardHistoryViewModel { _, completion in completions.append(completion) }
        vm.bind(store: store)
        vm.searchText = "needle"
        vm.searchText = ""

        XCTAssertEqual(vm.visibleEntries, store.entries)
        XCTAssertFalse(vm.isSearching)
        let staleResult = expectation(description: "cleared search must not publish stale rows")
        staleResult.isInverted = true
        let subscription = vm.$visibleEntries.dropFirst().sink { _ in staleResult.fulfill() }
        try XCTUnwrap(completions.first)(store.entries)
        await fulfillment(of: [staleResult], timeout: 0.2)
        withExtendedLifetime(subscription) {}
        XCTAssertEqual(vm.visibleEntries, store.entries)
        XCTAssertFalse(vm.isSearching)
    }

    func testLatePreviousFilterCannotOverwriteCurrentResults() async throws {
        let text = entry("shared text")
        let image = entry("shared image", type: .image)
        let store = try makeStore([text, image])
        var completions: [([ClipboardEntry]) -> Void] = []
        let vm = ClipboardHistoryViewModel { _, completion in completions.append(completion) }
        vm.bind(store: store)
        vm.searchText = "shared"
        vm.filter = .image

        XCTAssertEqual(completions.count, 2)
        try XCTUnwrap(completions.dropFirst().first)(store.entries)
        await waitForSearch(vm)
        XCTAssertEqual(vm.visibleEntries.map(\.id), [image.id])

        try XCTUnwrap(completions.first)(store.entries)
        await drainMainQueue()
        XCTAssertEqual(vm.visibleEntries.map(\.id), [image.id])
        XCTAssertFalse(vm.isSearching)
    }

    func testClearingQueryRejectsAlreadyQueuedIndexSearch() async throws {
        let store = try makeStore([entry("needle"), entry("other history")])
        let vm = ClipboardHistoryViewModel { _, completion in completion(store.entries) }
        vm.bind(store: store)
        vm.searchText = "needle"
        await waitForSearch(vm)

        vm.searchText = "other"
        XCTAssertTrue(vm.isSearching)
        vm.searchText = ""

        let staleResult = expectation(description: "queued index search must not replace restored history")
        staleResult.isInverted = true
        let subscription = vm.$visibleEntries.dropFirst().sink { _ in staleResult.fulfill() }
        await fulfillment(of: [staleResult], timeout: 0.2)
        withExtendedLifetime(subscription) {}
        XCTAssertEqual(vm.visibleEntries, store.entries)
        XCTAssertFalse(vm.isSearching)
    }

    func testReturningToReadyFilterIgnoresOtherFiltersPendingLoad() async throws {
        let text = entry("shared text")
        let image = entry("shared image", type: .image)
        let store = try makeStore([text, image])
        var completions: [([ClipboardEntry]) -> Void] = []
        let vm = ClipboardHistoryViewModel { _, completion in completions.append(completion) }
        vm.bind(store: store)
        vm.searchText = "shared"
        try XCTUnwrap(completions.first)(store.entries)
        await waitForSearch(vm)

        vm.filter = .image
        vm.filter = .all
        await waitForSearch(vm)
        XCTAssertEqual(Set(vm.visibleEntries.map(\.id)), Set([text.id, image.id]))

        XCTAssertEqual(completions.count, 2)
        try XCTUnwrap(completions.dropFirst().first)(store.entries)
        await drainMainQueue()
        XCTAssertFalse(vm.isSearching)
        XCTAssertEqual(Set(vm.visibleEntries.map(\.id)), Set([text.id, image.id]))
    }

    func testEqualCountSearchResultsPublishDifferentSnapshots() async throws {
        let first = entry("first result")
        let second = entry("second result")
        let store = try makeStore([first, second])
        let vm = ClipboardHistoryViewModel { _, completion in completion(store.entries) }
        vm.bind(store: store)
        vm.searchText = "first"
        await waitForSearch(vm)
        let firstRevision = vm.visibleEntriesRevision
        XCTAssertEqual(vm.visibleEntries.map(\.id), [first.id])

        vm.searchText = "second"
        await waitForSearch(vm)

        XCTAssertEqual(vm.visibleEntries.map(\.id), [second.id])
        XCTAssertGreaterThan(vm.visibleEntriesRevision, firstRevision)
    }

    func testEqualCountFilterResultsAdvanceRevisionButUnchangedSnapshotDoesNot() async throws {
        let text = entry("text result")
        let image = entry("image result", type: .image)
        let store = try makeStore([text, image])
        let vm = ClipboardHistoryViewModel()
        vm.bind(store: store)
        vm.filter = .text
        let textRevision = vm.visibleEntriesRevision
        XCTAssertEqual(vm.visibleEntries.map(\.id), [text.id])

        vm.filter = .image

        XCTAssertEqual(vm.visibleEntries.map(\.id), [image.id])
        XCTAssertGreaterThan(vm.visibleEntriesRevision, textRevision,
                             "NSTableView must reload when equal-sized result sets differ")
        let imageRevision = vm.visibleEntriesRevision
        vm.recomputeVisibleEntries()
        XCTAssertEqual(vm.visibleEntriesRevision, imageRevision,
                       "Unchanged snapshots should not cause full-table reloads")
    }

    func testStoreChangeDuringLoadDeliversNewEntryAndRejectsOldSnapshot() async throws {
        let original = entry("match original")
        let added = entry("match new")
        let store = try makeStore([original])
        var completions: [([ClipboardEntry]) -> Void] = []
        let vm = ClipboardHistoryViewModel { _, completion in completions.append(completion) }
        vm.bind(store: store)
        vm.searchText = "match"

        store.insertOrUpdate(added)
        await drainMainQueue()

        XCTAssertGreaterThanOrEqual(completions.count, 2)
        try XCTUnwrap(completions.first)([original])
        await drainMainQueue()
        XCTAssertTrue(vm.isSearching, "An outdated store snapshot must not finish the current search")
        try XCTUnwrap(completions.last)(store.entries)
        await waitForSearch(vm)
        XCTAssertEqual(Set(vm.visibleEntries.map(\.id)), Set([original.id, added.id]))
    }

    func testSameRowMetadataUpdateAdvancesDisplayedRevision() async throws {
        let item = entry("metadata update")
        let store = try makeStore([item])
        let vm = ClipboardHistoryViewModel { _, completion in completion(store.entries) }
        vm.bind(store: store)
        let revision = vm.visibleEntriesRevision

        store.markPasted(id: item.id)
        await drainMainQueue()

        XCTAssertEqual(vm.visibleEntries.first?.pasteCount, 1)
        XCTAssertGreaterThan(vm.visibleEntriesRevision, revision,
                             "Detail metadata should refresh even when the selected ID is unchanged")
    }
}
