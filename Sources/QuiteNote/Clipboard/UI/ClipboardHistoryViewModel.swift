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
            DiagnosticCenter.info("ClipboardUI", "searchText → \(searchText)")
            scheduleSearchDebounce()
        }
    }
    @Published private(set) var debouncedQuery = "" {
        didSet {
            DiagnosticCenter.info("ClipboardUI", "debouncedQuery → \(debouncedQuery)")
        }
    }
    @Published var filter: ClipboardFilter = .all {
        didSet {
            selectedIndex = 0
            pageAnchor = 0
        }
    }
    @Published var selectedIndex = 0

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
        pageAnchor = 0
    }

    private func scheduleSearchDebounce() {
        workItem?.cancel()
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = DispatchWorkItem { [weak self] in
            self?.debouncedQuery = text
            self?.selectedIndex = 0
            self?.pageAnchor = 0
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }

    // MARK: - 分页序号模型（Alfred 式：⌘1–⌘9 永远锚定当前视口的前 9 行）

    /// 每页行数 = ⌘N 快捷键数
    static let pageSize = 9
    /// 当前页首的数据索引（序号 1 = visibleEntries[pageAnchor]）
    @Published var pageAnchor = 0

    /// 选中/搜索/筛选变化后归一化页：跨页时更新 pageAnchor（视图监听后 scrollTo 翻页）
    func normalizePage() {
        let anchor = max(0, selectedIndex / Self.pageSize * Self.pageSize)
        if anchor != pageAnchor { pageAnchor = anchor }
    }

    /// ⌘N → 数据索引（页内第 N 条）
    func dataIndex(forCommandDigit digit: Int) -> Int {
        pageAnchor + digit - 1
    }

    /// 行显示序号：页内 1–9 返回 n；否则 nil（调用方淡化显示数据序号）
    func displayNumber(forIndex index: Int) -> Int? {
        let n = index - pageAnchor + 1
        return (1...Self.pageSize).contains(n) ? n : nil
    }
}
