import SwiftUI
import Combine

/// 增强的搜索栏组件，支持搜索历史、高级搜索选项和AI总结
struct EnhancedSearchBar: View {
    @ObservedObject var store: RecordStore
    @Binding var searchTerm: String
    @State private var showHistory = false
    @State private var showAdvancedOptions = false
    @State private var showAISummary = false
    @State private var aiSummary: String? = nil
    @State private var isGeneratingSummary = false
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
            aiSummaryView
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
                    } else {
                        showHistory = false
                    }
                }
            
            // 高级搜索按钮
            Button(action: { showAdvancedOptions.toggle() }) {
                LucideView(name: .settings, size: 14, color: showAdvancedOptions ? .themeBlue500 : .themeTextSecondary)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("高级搜索选项")
            
            // AI总结按钮
            if !searchTerm.isEmpty && store.enableAI {
                Button(action: { generateAISummary() }) {
                    if isGeneratingSummary {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .themeBlue500))
                    } else {
                        LucideView(name: .sparkles, size: 14, color: .themeBlue500)
                    }
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("生成搜索结果AI总结")
                .disabled(isGeneratingSummary)
            }
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
            VStack(alignment: .leading, spacing: 12) {
                Text("搜索选项")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
                
                // 搜索范围
                VStack(alignment: .leading, spacing: 8) {
                    Text("搜索范围")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextSecondary)
                    
                    ToggleRow(title: "标题", subtitle: "", isOn: $store.searchInTitles)
                    ToggleRow(title: "内容", subtitle: "", isOn: $store.searchInContent)
                    ToggleRow(title: "AI总结", subtitle: "", isOn: $store.searchInSummaries)
                }
                
                // 搜索选项
                VStack(alignment: .leading, spacing: 8) {
                    Text("搜索选项")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextSecondary)
                    
                    ToggleRow(title: "区分大小写", subtitle: "", isOn: $store.searchCaseSensitive)
                    ToggleRow(title: "正则表达式", subtitle: "", isOn: $store.searchUseRegex)
                }
            }
            .padding(16)
            .background(Color.black.opacity(0.2))
            .cornerRadius(8)
            .padding(.top, 8)
            .transition(.opacity.combined(with: .scale))
        }
    }
    
    /// AI总结显示视图
    @ViewBuilder
    private var aiSummaryView: some View {
        if showAISummary, let summary = aiSummary {
            HStack(alignment: .top, spacing: 12) {
                LucideView(name: .sparkles, size: 16, color: .themeBlue500)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("搜索结果总结")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextSecondary)
                    
                    Text(summary)
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                }
                
                Spacer()
                
                Button(action: {
                    showAISummary = false
                    aiSummary = nil
                }) {
                    LucideView(name: .x, size: 14, color: .themeTextSecondary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            .padding(12)
            .background(Color.themeBlue500.opacity(0.1))
            .cornerRadius(8)
            .padding(.top, 8)
            .transition(.opacity.combined(with: .scale))
        }
    }
    
    /// 执行搜索
    private func performSearch() {
        showHistory = false
        // 立即更新防抖搜索词，确保搜索立即执行
        searchWorkItem?.cancel()
        debouncedSearchTerm = searchTerm
    }
    
    /// 生成AI总结
    private func generateAISummary() {
        isGeneratingSummary = true
        // 使用防抖后的搜索词，确保是基于实际搜索内容生成总结
        store.generateSearchSummary(for: debouncedSearchTerm) { summary in
            self.isGeneratingSummary = false
            self.aiSummary = summary
            self.showAISummary = true
        }
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