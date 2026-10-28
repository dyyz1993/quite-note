import QuiteNoteSharedStorage
import Foundation
import SwiftUI
import Combine

/// 剪贴板历史面板的输入状态（搜索/筛选/选中）
///
/// 用 class（引用语义）承载：struct View 捕获副本上的延迟回调写 @State
/// 在 NSHostingView 场景不可靠（实测搜索过滤不生效），搜索状态也需要稳定的持有者。
@MainActor
final class ClipboardHistoryViewModel: ObservableObject {
    private typealias ClipboardIndex = SearchIndexService<SearchIndexDocument<ClipboardEntry>>

    @Published var searchText = "" {
        didSet {
            // 同值写入守卫：输入框删空后继续按 Delete 会重复写 ""，
            // @Published 即便同值也会触发 objectWillChange → 整棵视图无谓重算（卡顿源之一）
            guard oldValue != searchText else { return }
            scheduleSearchDebounce()
        }
    }
    @Published var debouncedQuery = ""
    @Published var filter: ClipboardFilter = .all {
        didSet {
            selectedIndex = 0
            resetViewport()
            recomputeVisibleEntries()
        }
    }
    @Published var selectedIndex = 0
    @Published private(set) var visibleEntries: [ClipboardEntry] = []
    /// Revision of the displayed snapshot, including searches with equal result counts.
    @Published private(set) var visibleEntriesRevision = 0
    @Published private(set) var isSearching = false

    // MARK: - 可见条目（计算/DB 读取都不进入 SwiftUI body）

    private var searchGeneration = 0
    private var visibleEntriesKey = ""
    private weak var boundStore: ClipboardHistoryStore?
    private var storeCancellable: AnyCancellable?
    private let searchIndex = ClipboardIndex()
    private struct IndexRequest: Equatable {
        let storeVersion: Int
        let filter: ClipboardFilter
    }
    private var indexedRequest: IndexRequest?
    private var pendingIndexRequest: IndexRequest?
    private var indexPreloadGeneration = 0

    typealias EntryLoader = (ClipboardHistoryStore, @escaping ([ClipboardEntry]) -> Void) -> Void
    private let loadEntries: EntryLoader

    init(loadEntries: @escaping EntryLoader = { store, completion in
        store.loadAllEntriesInBackground(completion: completion)
    }) {
        self.loadEntries = loadEntries
    }

    /// 面板打开时接入 store。store 变化在事件回调里重算，避免 body 副作用。
    func bind(store: ClipboardHistoryStore) {
        guard storeCancellable == nil else { return }
        boundStore = store
        storeCancellable = store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak store] _ in
                guard let self, let store else { return }
                self.recomputeVisibleEntries(store: store)
                self.preloadSearchIndex(store: store)
            }
        recomputeVisibleEntries(store: store)
    }

    /// Build the corpus index before typing so the first keystroke can reuse it.
    func preloadSearchIndex(store: ClipboardHistoryStore) {
        let request = IndexRequest(storeVersion: store.entriesVersion, filter: filter)
        guard indexedRequest != request, pendingIndexRequest != request else { return }
        indexPreloadGeneration += 1
        let generation = indexPreloadGeneration
        pendingIndexRequest = request
        loadEntries(store) { [weak self, weak store] allEntries in
            DispatchQueue.main.async { [weak self, weak store] in
                guard let self, let store, self.indexPreloadGeneration == generation else { return }
                self.pendingIndexRequest = nil
                guard request.storeVersion == store.entriesVersion, request.filter == self.filter else {
                    self.preloadSearchIndex(store: store)
                    return
                }
                let documents = allEntries.filter { request.filter.matches($0) }.map(Self.indexDocument)
                self.searchIndex.rebuild(documents: documents)
                self.indexedRequest = request
                // A pending read is not a ready index. Once it is ready, rerun the
                // current query even though its text and store version are unchanged.
                if !self.debouncedQuery.isEmpty {
                    self.visibleEntriesKey = ""
                    self.recomputeVisibleEntries(store: store)
                }
            }
        }
    }

    func recomputeVisibleEntries(store: ClipboardHistoryStore? = nil) {
        let store = store ?? boundStore ?? ClipboardHistoryStore.shared
        let query = debouncedQuery
        let filter = filter
        let key = "\(filter.rawValue)|\(query)|\(store.entries.count)|\(store.entriesVersion)"
        guard key != visibleEntriesKey else { return }
        visibleEntriesKey = key
        // Clearing the query and switching filters must also invalidate pending work.
        searchGeneration += 1
        let generation = searchGeneration

        if query.isEmpty {
            publishEntries(store.entries.filter { filter.matches($0) })
            isSearching = false
            return
        }

        isSearching = true
        // Do not leave the previous query's rows actionable while a new search runs.
        publishEntries([])
        let request = IndexRequest(storeVersion: store.entriesVersion, filter: filter)
        // 同一 store 版本 + 筛选下，语料建档一次；连续输入复用索引。
        if indexedRequest == request {
            runSearch(
                query: query,
                request: request,
                generation: generation,
                store: store
            )
        } else {
            preloadSearchIndex(store: store)
        }
    }

    private func publishEntries(_ entries: [ClipboardEntry]) {
        guard entries != visibleEntries else { return }
        visibleEntries = entries
        visibleEntriesRevision += 1
        selectedIndex = min(max(0, selectedIndex), max(0, entries.count - 1))
    }

    /// Only the current generation may publish results; stale background work is dropped.
    private func runSearch(
        query: String,
        request: IndexRequest,
        generation: Int,
        store: ClipboardHistoryStore
    ) {
        guard searchGeneration == generation else { return }
        let token = DiagnosticCenter.beginMeasure("Clipboard", "历史搜索", threshold: 0.15)
        searchIndex.search(query, limit: 300) { [weak self] page in
            token.end()
            guard let self,
                  self.searchGeneration == generation,
                  self.debouncedQuery == query,
                  self.filter == request.filter,
                  store.entriesVersion == request.storeVersion else { return }
            self.publishEntries(page.documents.map(\.payload))
            self.isSearching = false
        }
    }

    nonisolated static func indexDocument(_ entry: ClipboardEntry) -> SearchIndexDocument<ClipboardEntry> {
        let fields = ClipboardSearchService.searchableFields(entry)
        let title = entry.plainText ?? entry.sourceURL ?? entry.sourceApp ?? ""
        return SearchIndexDocument(
            id: entry.id.uuidString,
            source: .clipboard,
            payload: entry,
            normalizedTitle: SearchIndexText.normalize(String(title.prefix(300))),
            normalizedBody: SearchIndexText.normalize(fields.joined(separator: "\u{1f}")),
            normalizedKeywords: [entry.sourceApp, entry.sourceBundleID].compactMap { $0 }.map(SearchIndexText.normalize),
            createdAt: entry.createdAt,
            isPinned: entry.isPinned
        )
    }

    /// ←→ 循环切换筛选类型
    func switchFilter(_ forward: Bool) {
        let all = ClipboardFilter.allCases
        guard let idx = all.firstIndex(of: filter) else { return }
        let next = (idx + (forward ? 1 : -1) + all.count) % all.count
        filter = all[next]
        preloadSearchIndex(store: boundStore ?? ClipboardHistoryStore.shared)
    }

    /// 重置输入（面板每次打开时调用）
    func resetInput() {
        searchText = ""
        commitQuery("")
        filter = .all
        recomputeVisibleEntries()
    }

    private func scheduleSearchDebounce() {
        commitQuery(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func commitQuery(_ text: String) {
        debouncedQuery = text
        selectedIndex = 0
        resetViewport()
        recomputeVisibleEntries()
    }

    // MARK: - 视口锚定序号（用户模型）：⌘1 永远是视口最顶行，与选中态无关
    //
    // 滚动（滚轮/键盘引发的滚动都一样）时序号跟随视口：新顶上来的行继承 ⌘1，
    // ⌘1–⌘9 永远在可视范围内、永远可直接粘贴当前看到的前 9 条。

    /// 每页行数 = ⌘N 快捷键数
    static let pageSize = 9
    /// 当前视口顶部第一个可见行的数据索引（序号 1 对应它）。
    /// ⚠️ 故意不用 @Published：滚动时每 tick 发布会触发整棵 SwiftUI 重算 +
    /// NSTableView 全表 reloadData（实测滚动卡顿的元凶）。⌘N 序号由列表的
    /// Coordinator 自绘（不依赖 SwiftUI），此值仅供 ⌘N 命中时静默读取
    private(set) var viewportTopIndex = 0
    /// 各行在视口坐标里的位置（index → (minY, maxY)，由行上报）
    private var rowFrames: [Int: (minY: CGFloat, maxY: CGFloat)] = [:]
    private var viewportHeight: CGFloat = 0

    /// 行位置上报（onAppear + onChange 双通道；滚动会更新 GeometryReader 读数）
    func updateRowFrame(index: Int, minY: CGFloat, maxY: CGFloat) {
        rowFrames[index] = (minY, maxY)
        recomputeTopIndex()
    }

    func updateViewportHeight(_ height: CGFloat) {
        viewportHeight = height
        recomputeTopIndex()
    }

    /// 可见首行变化（NSTableView 原生检测上报）
    func viewportTopChanged(_ top: Int) {
        if top != viewportTopIndex {
            viewportTopIndex = top
        }
    }

    /// 顶行 = minY ≥ -15（容差）中最靠上的可见行
    private func recomputeTopIndex() {
        guard !rowFrames.isEmpty else { return }
        let top = rowFrames
            .filter { $0.value.minY > -15 && $0.value.maxY > 0 }
            .min { $0.key < $1.key }?
            .key ?? viewportTopIndex
        if top != viewportTopIndex {
            viewportTopIndex = top
        }
    }

    /// 视口重置（面板重开/搜索/筛选变化后视口回顶）
    func resetViewport() {
        rowFrames.removeAll()
        viewportTopIndex = 0
    }

    /// ⌘N → 数据索引（视口顶 + N - 1）
    func dataIndex(forCommandDigit digit: Int) -> Int {
        viewportTopIndex + digit - 1
    }

    /// 行显示序号：视口内第 1–9 个返回 n；第 10 个及以后（一屏 >9 行时）返回 nil（淡化）
    func displayNumber(forIndex index: Int) -> Int? {
        let n = index - viewportTopIndex + 1
        return (1...Self.pageSize).contains(n) ? n : nil
    }
}
