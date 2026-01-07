import SwiftUI
import Combine

/// 增强的搜索栏组件，支持搜索历史、高级搜索选项和AI总结
struct EnhancedSearchBar: View {
    @ObservedObject var store: RecordStore
    @Binding var searchTerm: String
    @State private var showHistory = false
    @State private var showAdvancedOptions = false

    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchBarWidth: CGFloat = 0
    
    // 防抖处理相关
    @State private var debouncedSearchTerm: String = ""
    @State private var searchWorkItem: DispatchWorkItem?
    private let searchDebounceInterval: TimeInterval = 0.3
    
    var body: some View {
        searchBarView
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            searchBarWidth = proxy.size.width
                        }
                        .onChange(of: proxy.size.width) { newValue in
                            searchBarWidth = newValue
                        }
                }
            )
            .overlay(
                ZStack(alignment: .topLeading) {
                    if showHistory || showAdvancedOptions {
                        // 点击外部区域自动关闭的透明层
                        Color.black.opacity(0.001)
                            .frame(width: 3000, height: 3000)
                            .onTapGesture {
                                withAnimation(.spring) {
                                    showHistory = false
                                    showAdvancedOptions = false
                                }
                            }
                        
                        // 浮层内容
                        VStack(spacing: 0) {
                            // 顶部分隔线，使其与搜索框融合
                            Rectangle()
                                .fill(Color.themeBorder)
                                .frame(height: 1)
                            
                            ScrollView {
                                VStack(spacing: 0) {
                                    if showHistory {
                                        searchHistoryContent
                                    }
                                    if showAdvancedOptions {
                                        advancedOptionsContent
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .frame(maxHeight: 350)
                        }
                        .frame(width: searchBarWidth) // 完全对齐搜索栏宽度
                        .background(Color.themeBackground)
                        .clipShape(RoundedCorner(radius: 12, corners: [.bottomLeft, .bottomRight]))
                        .shadow(color: Color.themeShadowMedium, radius: 15, x: 0, y: 10)
                        .overlay(
                            RoundedCorner(radius: 12, corners: [.bottomLeft, .bottomRight])
                                .stroke(Color.themeBorder, lineWidth: 1)
                        )
                        .offset(y: 40) // 调整到搜索栏下方
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -5)),
                            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                        ))
                    }
                },
                alignment: .topLeading
            )
            .zIndex(100)
            .onAppear {
                isSearchFieldFocused = true
                debouncedSearchTerm = searchTerm
            }
        .onChange(of: searchTerm) { newValue in
            // 防抖处理，避免大量数据粘贴时卡死
            searchWorkItem?.cancel()

            // 立即更新UI状态 - 不显示历史面板，直接搜索
            withAnimation(.spring) {
                if !newValue.isEmpty {
                    showHistory = false  // 改为 false，不显示历史面板
                    showAdvancedOptions = false
                } else {
                    showHistory = false
                }
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
                    // 手动输入时也不显示历史面板，直接搜索
                    if !newValue.isEmpty {
                        showHistory = false
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
                withAnimation(.spring) {
                    showAdvancedOptions.toggle()
                    if showAdvancedOptions {
                        showHistory = false
                    }
                }
            }) {
                LucideView(name: .slidersHorizontal, size: 14, color: showAdvancedOptions ? .themeBlue500 : .themeTextSecondary)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("高级搜索选项")
            

        }
        .padding(ThemeSpacing.px3)
        .background(Color.themeShadowLight)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.themeBorder).allowsHitTesting(false), alignment: .bottom)
    }
    
    /// 搜索历史下拉视图内容
    private var searchHistoryContent: some View {
        Group {
            if !store.searchHistory.isEmpty {
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
            }
        }
    }
    
    /// 高级搜索选项视图内容
    private var advancedOptionsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 搜索范围
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    LucideView(name: .filter, size: 12, color: .themeTextSecondary)
                    Text("搜索范围")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextSecondary)
                }
                
                HStack(spacing: 8) {
                    ChipItem(title: "标题", isOn: $store.searchInTitles)
                    ChipItem(title: "内容", isOn: $store.searchInContent)
                    ChipItem(title: "AI总结", isOn: $store.searchInSummaries)
                }
            }
            .padding(.horizontal, 4)
            
            Divider()
                .background(Color.themeHoverLight)
            
            // 搜索配置
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    LucideView(name: .settings2, size: 12, color: .themeTextSecondary)
                    Text("搜索配置")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextSecondary)
                }
                
                VStack(spacing: 2) {
                    SelectionRow(title: "区分大小写", icon: .caseSensitive, isOn: $store.searchCaseSensitive)
                    SelectionRow(title: "正则表达式", icon: .regex, isOn: $store.searchUseRegex)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(ThemeSpacing.px4)
    }
    
    /// Chip 样式选择项
    struct ChipItem: View {
        let title: String
        @Binding var isOn: Bool
        @State private var isHovering = false
        
        var body: some View {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isOn ? Color.themeBlue500.opacity(0.9) : (isHovering ? Color.themeHoverMedium : Color.themeHoverLight))
                )
                .foregroundColor(isOn ? .white : .themeTextSecondary)
                .onTapGesture {
                    withAnimation(.spring(response: 0.3)) {
                        isOn.toggle()
                    }
                }
                .onHover { isHovering = $0 }
                .pointingHandCursor()
        }
    }
    
    /// 简单的流式布局容器
    struct FlowLayout: View {
        let spacing: CGFloat
        let content: [AnyView]
        
        init<Views>(spacing: CGFloat, @ViewBuilder content: () -> Views) where Views: View {
            self.spacing = spacing
            // 这里为了简单，我们直接用 HStack。如果项很多，可以使用更复杂的 Flow 实现。
            // 对于 3 个项，HStack 足够了。
            self.content = [] // 这种方式在 SwiftUI 中不太好用，改用普通布局
        }
        
        var body: some View {
            EmptyView()
        }
    }
    
    /// 搜索范围/选项选择行
    struct SelectionRow: View {
        let title: String
        let icon: IconName
        @Binding var isOn: Bool
        @State private var isHovering = false
        
        var body: some View {
            HStack(spacing: 12) {
                LucideView(name: icon, size: 14, color: isOn ? .themeBlue500 : .themeTextSecondary)
                
                Text(title)
                    .font(.themeBody)
                    .foregroundColor(isOn ? .themeTextPrimary : .themeTextSecondary)
                
                Spacer()
                
                if isOn {
                    LucideView(name: .check, size: 12, color: .themeBlue500)
                } else {
                    Circle()
                        .stroke(Color.themeHoverMedium, lineWidth: 1)
                        .frame(width: 12, height: 12)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? Color.themeHoverLight : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) {
                    isOn.toggle()
                }
            }
            .onHover { isHovering = $0 }
            .pointingHandCursor()
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
    
    /// 搜索历史下拉视图 (保留兼容性，但不再直接使用)
    @ViewBuilder
    private var searchHistoryView: some View {
        EmptyView()
    }
    
    /// 高级搜索选项视图 (保留兼容性，但不再直接使用)
    @ViewBuilder
    private var advancedOptionsView: some View {
        EmptyView()
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