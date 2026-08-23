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
        didSet { selectedIndex = 0 }
    }
    @Published var selectedIndex = 0

    /// ←→ 循环切换筛选类型
    func switchFilter(_ forward: Bool) {
        let all = ClipboardFilter.allCases
        guard let idx = all.firstIndex(of: filter) else { return }
        let next = (idx + (forward ? 1 : -1) + all.count) % all.count
        filter = all[next]
    }

    // MARK: - 行可见性跟踪（↑↓ 时选中行必须可见，但已可见则不滚动）

    /// 各行在滚动视口坐标里的位置（index → (minY, maxY)），由行的 GeometryReader 上报
    var rowFrames: [Int: (minY: CGFloat, maxY: CGFloat)] = [:]
    /// 列表视口高度
    var viewportHeight: CGFloat = 0

    /// 选中行是否移出了视口；移出则返回应滚动对齐的 anchor，可见返回 nil（不滚）
    func visibilityAnchor(for index: Int) -> UnitPoint? {
        guard viewportHeight > 0, let frame = rowFrames[index] else { return nil }
        if frame.maxY > viewportHeight { return .bottom }  // 超出底部 → 对齐到底
        if frame.minY < 0 { return .top }                   // 超出顶部 → 对齐到顶
        return nil
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
    }

    private func scheduleSearchDebounce() {
        workItem?.cancel()
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = DispatchWorkItem { [weak self] in
            self?.debouncedQuery = text
            self?.selectedIndex = 0
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }
}
