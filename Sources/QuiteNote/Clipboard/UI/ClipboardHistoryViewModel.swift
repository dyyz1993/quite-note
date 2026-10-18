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
    @Published private(set) var isSearching = false

    // MARK: - 可见条目（计算/DB 读取都不进入 SwiftUI body）

    private var searchGeneration = 0
    private var visibleEntriesKey = ""
    private var storeCancellable: AnyCancellable?
    private let searchIndex = ClipboardIndex()
    private var indexedStoreVersion = 0
    private var indexedFilter: ClipboardFilter?

    /// 面板打开时接入 store。store 变化在事件回调里重算，避免 body 副作用。
    func bind(store: ClipboardHistoryStore) {
        guard storeCancellable == nil else { return }
        storeCancellable = store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak store] _ in
                guard let self, let store else { return }
                self.recomputeVisibleEntries(store: store)
            }
        recomputeVisibleEntries(store: store)
    }

    func recomputeVisibleEntries(store: ClipboardHistoryStore? = nil) {
        let store = store ?? ClipboardHistoryStore.shared
        let query = debouncedQuery
        let filter = filter
        let key = "\(filter.rawValue)|\(query)|\(store.entries.count)|\(store.entriesVersion)"
        guard key != visibleEntriesKey else { return }
        visibleEntriesKey = key

        if query.isEmpty {
            visibleEntries = store.entries.filter { filter.matches($0) }
            isSearching = false
            visibleEntriesKey = key
            return
        }

        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        let token = DiagnosticCenter.beginMeasure("Clipboard", "历史搜索", threshold: 0.15)
        let storeVersionAtRequest = store.entriesVersion
        // 同一 store 版本 + 筛选下，语料建档一次；连续输入复用索引。
        if indexedStoreVersion == storeVersionAtRequest && indexedFilter == filter {
            runSearch(
                query: query,
                filter: filter,
                generation: generation,
                store: store,
                token: token
            )
        } else {
            store.loadAllEntriesInBackground { allEntries in
                // 统一索引负责快照匹配/排序/分页；内存增量仍即时合并，保证搜索期间的新剪贴板可见。
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.searchIndex.rebuild(using: {
                        allEntries
                            .filter { filter.matches($0) }
                            .map(Self.indexDocument)
                    }) { [weak self] _ in
                        guard let self else { return }
                        self.indexedStoreVersion = storeVersionAtRequest
                        self.indexedFilter = filter
                        self.runSearch(
                            query: query,
                            filter: filter,
                            generation: generation,
                            store: store,
                            token: token
                        )
                    }
                }
            }
        }
    }

    private func runSearch(
        query: String,
        filter: ClipboardFilter,
        generation: Int,
        store: ClipboardHistoryStore,
        token: DiagnosticCenter.MeasureToken
    ) {
        guard searchGeneration == generation else { return }
        searchIndex.search(query, limit: 300) { [weak self] page in
            guard let self, self.searchGeneration == generation else { return }
            let results = page.documents.map(\.payload)
            let resultIDs = Set(results.map(\.id))
            let incremental = store.entries.filter {
                filter.matches($0) && !resultIDs.contains($0.id) &&
                ClipboardSearchService.matchScore(query: query, entry: $0) > 0
            }
            self.visibleEntries = results + incremental
            self.isSearching = false
            token.end()
        }
    }

    private nonisolated static func indexDocument(_ entry: ClipboardEntry) -> SearchIndexDocument<ClipboardEntry> {
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
