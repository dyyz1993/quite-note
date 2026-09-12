import Foundation
import SwiftUI
import Combine

/// 剪贴板历史面板的输入状态（搜索/筛选/选中）
///
/// 用 class（引用语义）承载：struct View 捕获副本上的延迟回调写 @State
/// 在 NSHostingView 场景不可靠（实测搜索过滤不生效），防抖 workItem 也需要稳定的持有者。
@MainActor
final class ClipboardHistoryViewModel: ObservableObject {
    @Published var searchText = "" {
        didSet {
            // 同值写入守卫：输入框删空后继续按 Delete 会重复写 ""，
            // @Published 即便同值也会触发 objectWillChange → 整棵视图无谓重算（卡顿源之一）
            guard oldValue != searchText else { return }
            scheduleSearchDebounce()
        }
    }
    @Published private(set) var debouncedQuery = ""
    @Published var filter: ClipboardFilter = .all {
        didSet {
            selectedIndex = 0
            resetViewport()
        }
    }
    @Published var selectedIndex = 0

    // MARK: - 可见条目记忆化（每次按键 body 重算多次读取，不能每次都全量过滤+排序）

    private var cachedVisible: [ClipboardEntry] = []
    private var cacheKey = ""

    /// 当前可见条目：类型筛选 → 防抖搜索。按 (filter, debouncedQuery, entries.count,
    /// entriesVersion) 记忆化——同一轮按键内多次读取只算一次
    func visibleEntries(in store: ClipboardHistoryStore) -> [ClipboardEntry] {
        let key = "\(filter.rawValue)|\(debouncedQuery)|\(store.entries.count)|\(store.entriesVersion)"
        if key == cacheKey { return cachedVisible }
        let filtered = store.entries.filter { filter.matches($0) }
        let result = ClipboardSearchService.search(debouncedQuery, in: filtered)
        cachedVisible = result
        cacheKey = key
        return result
    }

    /// ←→ 循环切换筛选类型
    func switchFilter(_ forward: Bool) {
        let all = ClipboardFilter.allCases
        guard let idx = all.firstIndex(of: filter) else { return }
        let next = (idx + (forward ? 1 : -1) + all.count) % all.count
        filter = all[next]
    }

    private var workItem: DispatchWorkItem?
    /// PRD 9.2：搜索输入 150–300ms 防抖
    private let debounceInterval: TimeInterval = 0.2

    /// 重置输入（面板每次打开时调用）
    func resetInput() {
        searchText = ""
        debouncedQuery = ""
        filter = .all
        selectedIndex = 0
        resetViewport()
    }

    private func scheduleSearchDebounce() {
        workItem?.cancel()
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = DispatchWorkItem { [weak self] in
            self?.debouncedQuery = text
            self?.selectedIndex = 0
            self?.resetViewport()
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
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
