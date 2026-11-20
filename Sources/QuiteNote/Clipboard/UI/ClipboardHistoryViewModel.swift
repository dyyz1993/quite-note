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
    @Published var selectedIndex = 0 {
        didSet {
            // 选中被显式改变（点击行/↑↓/搜索重置）即离开输入框光标区
            if oldValue != selectedIndex { fieldCursorMode = false }
        }
    }

    // MARK: 两区键盘模型（用户约定 2026-11-20，Alfred 式）
    // 列表区（默认）：←/→ 切筛选 tab、↑↓ 移动选中；
    // 选中已在第一条再按 ↑ → 进入输入框光标区（←/→ 变文本光标键、↓ 返回列表）。
    // 进入是显式的——避免"有没有搜索词"这种隐式规则左右键语义漂移。
    /// setter 供 handle 扩展/视图接线使用；用户直接改没有副作用（守卫只读它）
    @Published var fieldCursorMode = false
    @Published private(set) var visibleEntries: [ClipboardEntry] = [] {
        // 表格数据签名用 VM 版本号（不再直接用 store.entriesVersion）：隐藏期跳过
        // 重算后 visibleEntries 不变，store 版本却在每次系统剪贴板捕获时 bump——
        // 旧签名会因版本号变化对**隐藏的表格**做全表 reloadData（每捕获一次刷一次）
        didSet { visibleEntriesVersion += 1 }
    }
    /// 表格 O(1) 数据签名版本（visibleEntries 每次发布 +1；语义与旧 store 版本号
    /// 等价——置顶/OCR/增删/翻页都会经 recompute 反映到 visibleEntries）
    private(set) var visibleEntriesVersion = 0
    @Published private(set) var isSearching = false

    /// 列表重排后选中态要跟随的条目 ID（⌘P 置顶触发）：selectedIndex 是纯下标，
    /// 置顶/取消置顶会移动条目位置，选中必须按 ID 找回原条目的新下标，
    /// 否则选中态漂移到别的条目上（Enter 粘贴错内容的根源）
    private var pendingSelectionID: UUID?

    // MARK: - 可见条目（计算/DB 读取都不进入 SwiftUI body）

    private var searchGeneration = 0
    private var visibleEntriesKey = ""
    private var storeCancellable: AnyCancellable?
    private weak var boundStore: ClipboardHistoryStore?
    private let searchIndex = ClipboardIndex()
    private var indexedStoreVersion = 0
    private var indexedFilter: ClipboardFilter?
    private var indexPreloadGeneration = 0
    private var indexPreloadVersions: Set<Int> = []

    /// 面板可见性判定（bind 的隐藏期跳过用）；测试注入常真以覆盖 sink 驱动路径
    var isPanelVisibleProvider: () -> Bool = { ClipboardHistoryPanelController.shared.isVisible }

    /// 面板打开时接入 store。store 变化在事件回调里重算，避免 body 副作用。
    ///
    /// ⚠️ 面板隐藏期间全部跳过：视图常驻不销毁（orderOut 不拆视图树），旧实现在
    /// 隐藏期对**每次系统剪贴板捕获**都全量重载语料 + 主线程重建索引（生产日志
    /// 实锤：面板关闭状态下捕获后 471ms 主线程"历史搜索"，全天候发生）。面板
    /// 再次打开时 didShow → resetInput/recompute 按最新 store 重算，无状态损失。
    func bind(store: ClipboardHistoryStore) {
        boundStore = store
        guard storeCancellable == nil else { return }
        storeCancellable = store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak store] _ in
                guard let self, let store else { return }
                guard self.isPanelVisibleProvider() else { return }
                self.recomputeVisibleEntries(store: store)
                self.preloadSearchIndex(store: store)
            }
        recomputeVisibleEntries(store: store)
    }

    /// Build the corpus index before typing so the first keystroke can reuse it.
    func preloadSearchIndex(store: ClipboardHistoryStore) {
        let storeVersion = store.entriesVersion
        guard indexedStoreVersion != storeVersion || indexedFilter != filter else { return }
        indexPreloadGeneration += 1
        let generation = indexPreloadGeneration
        let filter = filter
        indexPreloadVersions.insert(storeVersion)
        store.loadAllEntriesInBackground { [weak self] allEntries in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.indexPreloadGeneration == generation else { return }
                self.rebuildIndex(
                    allEntries: allEntries,
                    storeVersion: storeVersion,
                    filter: filter,
                    store: store
                )
                self.recomputeVisibleEntries(store: store)
            }
        }
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
            applyPendingSelection()
            return
        }

        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        let token = DiagnosticCenter.beginMeasure("Clipboard", "历史搜索", threshold: 0.15)
        let storeVersionAtRequest = store.entriesVersion
        // 同一 store 版本 + 筛选下，语料建档一次；连续输入复用索引。
        let indexIsReady = indexedStoreVersion == storeVersionAtRequest && indexedFilter == filter
        if indexIsReady || indexPreloadVersions.contains(storeVersionAtRequest) {
            // ⚠️ indexPreloadVersions 命中时索引可能仍在后台重建中（rebuild(using:)
            // 的写入排在后入队的 search 之后——SearchIndexService 内层 async 的重排坑），
            // 由 rebuildIndex 完成回调兜底重搜，这里先跑当前快照
            runSearch(
                query: query,
                filter: filter,
                generation: generation,
                store: store,
                token: token
            )
            if !indexIsReady {
                // 快照尚未落盘：挂一个重建完成后的重搜（generation 守卫自动丢弃过期）
                indexReadyCallbacks[storeVersionAtRequest] = { [weak self] in
                    guard let self, self.searchGeneration == generation else { return }
                    self.runSearch(
                        query: query,
                        filter: filter,
                        generation: generation,
                        store: store,
                        token: token
                    )
                }
            }
        } else {
            store.loadAllEntriesInBackground { [weak self] allEntries in
                // 统一索引负责快照匹配/排序/分页；内存增量仍即时合并，保证搜索期间的新剪贴板可见。
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.rebuildIndex(
                        allEntries: allEntries,
                        storeVersion: storeVersionAtRequest,
                        filter: filter,
                        store: store,
                        onReady: { [weak self] in
                            // 重建写入完成后才搜（读快照的时序不再依赖队列顺序）
                            self?.runSearch(
                                query: query,
                                filter: filter,
                                generation: generation,
                                store: store,
                                token: token
                            )
                        }
                    )
                }
            }
        }
    }

    /// 索引重建完成后的待触发回调（key = storeVersion；重建竞态下只保留最新语义）
    private var indexReadyCallbacks: [Int: () -> Void] = [:]

    private func rebuildIndex(
        allEntries: [ClipboardEntry],
        storeVersion: Int,
        filter: ClipboardFilter,
        store: ClipboardHistoryStore,
        onReady: (() -> Void)? = nil
    ) {
        let currentStoreVersion = store.entriesVersion
        guard currentStoreVersion == storeVersion else {
            indexPreloadVersions.remove(storeVersion)
            indexReadyCallbacks.removeValue(forKey: storeVersion)
            onReady?()
            return
        }
        // 建档（3× normalize + CJK 拼音 CFStringTransform）是重活，500 条在主线程
        // 实测 400ms+——必须走 rebuild(using:) 让 filter+map 在索引串行队列执行，
        // 主线程零成本（生产日志"历史搜索 454ms"的元凶）。
        // ⚠️ onReady 只能在完成回调里触发：rebuild(using:) 内层 async 会把写入排到
        // 后入队 search 之后（先搜后写 = 搜到空快照），不能依赖队列顺序
        searchIndex.rebuild(using: {
            allEntries.filter { filter.matches($0) }.map(Self.indexDocument)
        }, completion: { [weak self] _ in
            guard let self else { return }
            self.indexedStoreVersion = storeVersion
            self.indexedFilter = filter
            self.indexPreloadVersions.remove(storeVersion)
            let callback = self.indexReadyCallbacks.removeValue(forKey: storeVersion)
            onReady?()
            callback?()
        })
    }

    /// Only the current generation may publish results; stale background work is dropped.
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
            // 增量合并只在库超过首页（索引语料未覆盖内存页之外的条目）时才需要；
            // ≤500 条的库每键白跑 500×matchScore（2026-11-20 打字卡顿主因之一）
            var final = results
            if store.hasMore {
                let resultIDs = Set(results.map(\.id))
                final += store.entries.filter {
                    filter.matches($0) && !resultIDs.contains($0.id) &&
                    ClipboardSearchService.matchScore(query: query, entry: $0) > 0
                }
            }
            self.visibleEntries = final
            self.isSearching = false
            self.applyPendingSelection()
            token.end()
        }
    }

    nonisolated static func indexDocument(_ entry: ClipboardEntry) -> SearchIndexDocument<ClipboardEntry> {
        let fields = ClipboardSearchService.searchableFields(entry)
        let title = String((entry.plainText ?? entry.sourceURL ?? entry.sourceApp ?? "").prefix(300))
        let pinyin = Self.titlePinyin(title)
        return SearchIndexDocument(
            id: entry.id.uuidString,
            source: .clipboard,
            payload: entry,
            normalizedTitle: SearchIndexText.normalize(title),
            normalizedBody: SearchIndexText.normalize(fields.joined(separator: "\u{1f}")),
            normalizedKeywords: [entry.sourceApp, entry.sourceBundleID].compactMap { $0 }.map(SearchIndexText.normalize),
            normalizedPinyin: pinyin.compact,
            normalizedPinyinInitials: pinyin.initials,
            createdAt: entry.createdAt,
            isPinned: entry.isPinned
        )
    }

    /// 标题拼音（建档时一次生成，打字搜索零转换成本）：
    /// - 纯拉丁标题直接跳过（CFStringTransform 有成本，剪贴板语料大多是英文/URL）
    /// - 全拼压缩去空格存储："你好" → "nihao"。用户输入无分隔符，
    ///   带空格的 "ni hao" 永远命中不了压缩查询
    nonisolated private static func titlePinyin(_ title: String) -> (compact: String, initials: String) {
        guard title.unicodeScalars.contains(where: PinyinTransformer.isCJK) else { return ("", "") }
        let result = PinyinTransformer.transliterate(title)
        return (result.full.replacingOccurrences(of: " ", with: ""), result.initials)
    }

    /// footer 进度（第 N / M 条）；空列表返回 nil（视图隐藏进度文本）。
    /// selectedIndex 越界（删除后的暂态）时钳制到最后一条
    var selectionProgress: (current: Int, total: Int)? {
        guard !visibleEntries.isEmpty else { return nil }
        return (min(selectedIndex + 1, visibleEntries.count), visibleEntries.count)
    }

    /// ←→ 循环切换筛选类型
    func switchFilter(_ forward: Bool) {
        let all = ClipboardFilter.allCases
        guard let idx = all.firstIndex(of: filter) else { return }
        let next = (idx + (forward ? 1 : -1) + all.count) % all.count
        filter = all[next]
        preloadSearchIndex(store: ClipboardHistoryStore.shared)
    }

    /// ⌘P 置顶/取消置顶当前选中条目，选中态跟随原条目移动
    func togglePinSelected() {
        guard visibleEntries.indices.contains(selectedIndex) else { return }
        let id = visibleEntries[selectedIndex].id
        let store = boundStore ?? ClipboardHistoryStore.shared
        store.togglePin(id: id)
        pendingSelectionID = id
        // store 同步重排完成，立即重算可见列表：空查询路径同步完成选中跟随；
        // 搜索路径在 runSearch 完成回调里按 ID 补一次
        recomputeVisibleEntries(store: store)
    }

    /// 按 ID 把选中态恢复到 pendingSelectionID 指向条目的新下标
    private func applyPendingSelection() {
        guard let id = pendingSelectionID else { return }
        guard let idx = visibleEntries.firstIndex(where: { $0.id == id }) else { return }
        pendingSelectionID = nil
        if selectedIndex != idx {
            selectedIndex = idx
        }
    }

    /// 重置输入（面板每次打开时调用）
    func resetInput() {
        fieldCursorMode = false
        searchText = ""
        commitQuery("")
        filter = .all
        recomputeVisibleEntries()
    }

    private func scheduleSearchDebounce() {
        commitQuery(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func commitQuery(_ text: String) {
        fieldCursorMode = false
        debouncedQuery = text
        selectedIndex = 0
        pendingSelectionID = nil
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
