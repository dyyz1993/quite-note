import SwiftUI
import Combine

/// 增强的搜索栏组件，支持搜索历史、高级搜索选项和AI总结
struct EnhancedSearchBar: View {
    @ObservedObject var store: RecordStore
    @Binding var searchTerm: String
    @State private var showHistory = false
    @State private var showAdvancedOptions = false

    @FocusState private var isSearchFieldFocused: Bool
    
    // 防抖处理相关
    @State private var debouncedSearchTerm: String = ""
    @State private var searchWorkItem: DispatchWorkItem?
    private let searchDebounceInterval: TimeInterval = 0.3
    
    var body: some View {
        VStack(spacing: 0) {
            searchBarView
            searchHistoryView
            advancedOptionsView
        }
        .onAppear {
            isSearchFieldFocused = true
            debouncedSearchTerm = searchTerm
        }
        .onOutsideTap {
            showHistory = false
            showAdvancedOptions = false
        }
        .onChange(of: searchTerm) { newValue in
            // 防抖处理，避免大量数据粘贴时卡死
            searchWorkItem?.cancel()
            
            // 立即更新UI状态
            if !newValue.isEmpty {
                showHistory = true
                showAdvancedOptions = false
            } else {
                showHistory = false
            }
            
            // 使用防抖更新实际搜索词
            let workItem = DispatchWorkItem {
                DispatchQueue.main.async {
                    debouncedSearchTerm = newValue
                }
            }
            
            searchWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + searchDebounceInterval, execute: workItem)
        }
        .onChange(of: debouncedSearchTerm) { newValue in
            // 只有当防抖后的搜索词与实际搜索词不同时才更新
            if newValue != searchTerm {
                searchTerm = newValue
            }
        }
    }
    
    /// 主搜索栏视图
    private var searchBarView: some View {
        HStack {
            LucideView(name: .search, size: 16, color: .themeTextSecondary)
            
            TextField("搜索标题或内容...", text: $searchTerm)
                .textFieldStyle(.plain)
                .font(.themeBody)
                .foregroundColor(.themeTextPrimary)
                .focused($isSearchFieldFocused)
                .onSubmit {
                    performSearch()
                }
                .onChange(of: searchTerm) { newValue in
                    if !newValue.isEmpty {
                        showHistory = true
                        showAdvancedOptions = false
                    } else {
                        showHistory = false
                    }
                }
            
            // 清空按钮
            if !searchTerm.isEmpty {
                Button(action: {
                    searchWorkItem?.cancel()
                    searchTerm = ""
                    debouncedSearchTerm = ""
                    showHistory = false
                }) {
                    LucideView(name: .circleX, size: 14, color: .themeTextSecondary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("清空搜索")
            }
            
            // 高级搜索按钮
            Button(action: {
                showAdvancedOptions.toggle()
                if showAdvancedOptions {
                    showHistory = false
                }
            }) {
                LucideView(name: .slidersHorizontal, size: 14, color: showAdvancedOptions ? .themeBlue500 : .themeTextSecondary)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("高级搜索选项")
            

        }
        .padding(ThemeSpacing.px3)
        .background(Color.black.opacity(0.1))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.themeBorder).allowsHitTesting(false), alignment: .bottom)
    }
    
    /// 搜索历史下拉视图
    @ViewBuilder
    private var searchHistoryView: some View {
        if showHistory && !store.searchHistory.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(store.searchHistory.prefix(5), id: \.self) { historyItem in
                        historyItemView(historyItem)
                    }
                    
                    // 清空历史按钮
                    Button(action: {
                        store.clearSearchHistory()
                        showHistory = false
                    }) {
                        HStack {
                            LucideView(name: .trash2, size: 12, color: .themeRed500)
                            Text("清空搜索历史")
                                .font(.themeCaption)
                                .foregroundColor(.themeRed500)
                            Spacer()
                        }
                        .padding(.horizontal, ThemeSpacing.px3.rawValue)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
            .frame(maxHeight: 200)
            .background(Color.themeBackground)
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
            .padding(.top, 4)
            .transition(.opacity.combined(with: .scale))
            .zIndex(10)
        }
    }
    
    /// 单个历史记录项视图
    private func historyItemView(_ historyItem: String) -> some View {
        HStack {
            LucideView(name: .clock, size: 12, color: .themeTextSecondary)
            Text(historyItem)
                .font(.themeBody)
                .foregroundColor(.themeTextPrimary)
                .lineLimit(1)
            Spacer()
            Button(action: {
                searchWorkItem?.cancel()
                searchTerm = historyItem
                debouncedSearchTerm = historyItem
                showHistory = false
            }) {
                LucideView(name: .arrowLeft, size: 12, color: .themeTextSecondary)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(.horizontal, ThemeSpacing.px3.rawValue)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            searchWorkItem?.cancel()
            searchTerm = historyItem
            debouncedSearchTerm = historyItem
            showHistory = false
        }
        .onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
    
    /// 高级搜索选项视图
    @ViewBuilder
    private var advancedOptionsView: some View {
        if showAdvancedOptions {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("搜索选项")
                        .font(.themeH2)
                        .foregroundColor(.themeTextPrimary)
                    
                    Divider()
                        .background(Color.themeBorder)
                    
                    // 搜索范围
                    VStack(alignment: .leading, spacing: 6) {
                        Text("搜索范围")
                            .font(.themeCaption)
                            .foregroundColor(.themeTextSecondary)
                        
                        ToggleRow(title: "标题", subtitle: "", isOn: $store.searchInTitles)
                        ToggleRow(title: "内容", subtitle: "", isOn: $store.searchInContent)
                        ToggleRow(title: "AI总结", subtitle: "", isOn: $store.searchInSummaries)
                    }
                    
                    Divider()
                        .background(Color.themeBorder)
                    
                    // 搜索选项
                    VStack(alignment: .leading, spacing: 6) {
                        Text("搜索选项")
                            .font(.themeCaption)
                            .foregroundColor(.themeTextSecondary)
                        
                        ToggleRow(title: "区分大小写", subtitle: "", isOn: $store.searchCaseSensitive)
                        ToggleRow(title: "正则表达式", subtitle: "", isOn: $store.searchUseRegex)
                    }
                }
                .padding(ThemeSpacing.px4)
            }
            .frame(maxHeight: 250) // 限制最大高度，确保内容可滚动
            .background(Color.themeBackground)
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.themeBorder, lineWidth: 0.5)
            )
            .padding(.top, 4)
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
            .zIndex(20)
        }
    }
    

    
    /// 执行搜索
    private func performSearch() {
        showHistory = false
        // 立即更新防抖搜索词，确保搜索立即执行
        searchWorkItem?.cancel()
        debouncedSearchTerm = searchTerm
    }
    

}

/// 扩展View以支持点击外部区域
extension View {
    func onOutsideTap(perform action: @escaping () -> Void) -> some View {
        self.background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    action()
                }
        )
    }
}