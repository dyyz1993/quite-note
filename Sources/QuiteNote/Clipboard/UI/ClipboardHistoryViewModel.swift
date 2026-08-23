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
