import SwiftUI

/// 符号浏览面板 - 点击工具栏按钮展开
struct SymbolBrowserPanel: View {
    @StateObject private var configManager = SymbolConfigManager.shared
    @Binding var isPresented: Bool
    let onSymbolSelected: (SymbolItem) -> Void

    @State private var selectedMenuIndex: Int = 0
    @State private var searchText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // 头部搜索
            headerView

            Divider()
                .background(Color.themeBorder)

            // 分类标签
            categoryTabsView

            Divider()
                .background(Color.themeBorder)

            // 符号网格
            symbolsGridView

            Divider()
                .background(Color.themeBorder)

            // 底部提示
            footerView
        }
        .background(Color.themeBackground)
        .frame(width: 400, height: 360)
        .onAppear {
            selectFirstAvailableMenu()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(Color.themeTextTertiary)

            TextField("搜索符号...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.themeBody)
                .foregroundColor(Color.themeTextPrimary)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color.themeTextTertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Category Tabs

    private var categoryTabsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(displayedMenus.enumerated()), id: \.offset) { index, menu in
                    categoryTab(menu: menu, isSelected: selectedMenuIndex == index) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedMenuIndex = index
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func categoryTab(menu: SymbolMenu, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = menu.icon {
                    Text(icon)
                        .font(.system(size: 11))
                }
                Text(menu.title)
                    .font(.themeCaption)
            }
            .foregroundColor(isSelected ? Color.themeBlue500 : Color.themeTextTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Rectangle()
                    .fill(isSelected ? Color.themeBlue500.opacity(0.1) : Color.clear)
            )
            .overlay(
                Rectangle()
                    .fill(Color.themeBlue500)
                    .frame(height: 2),
                alignment: .bottom
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Symbols Grid

    private var symbolsGridView: some View {
        ScrollView {
            VStack(spacing: 12) {
                if searchText.isEmpty {
                    // 显示选中分类的符号
                    if selectedMenuIndex < displayedMenus.count {
                        let menu = displayedMenus[selectedMenuIndex]
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ], spacing: 8) {
                            ForEach(menu.symbols) { symbol in
                                SymbolGridItem(symbol: symbol) {
                                    onSymbolSelected(symbol)
                                    isPresented = false
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                } else {
                    // 显示搜索结果
                    let results = configManager.searchSymbols(query: searchText)
                    if results.isEmpty {
                        emptySearchResult
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ], spacing: 8) {
                            ForEach(results) { symbol in
                                SymbolGridItem(symbol: symbol) {
                                    onSymbolSelected(symbol)
                                    isPresented = false
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 16)
        }
    }

    private var emptySearchResult: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(Color.themeTextTertiary)

            Text("未找到匹配的符号")
                .font(.themeCaption)
                .foregroundColor(Color.themeTextTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Text("点击符号插入到编辑器")
                .font(.themeCaptionSmall)
                .foregroundColor(Color.themeTextTertiary)

            Spacer()

            Button(action: { isPresented = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundColor(Color.themeTextTertiary)
                    .frame(width: 24, height: 24)
                    .background(Color.themeHoverLight)
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Computed Properties

    private var displayedMenus: [SymbolMenu] {
        configManager.enabledConfigs.flatMap { $0.menus }
            .sorted { $0.sort < $1.sort }
    }

    // MARK: - Helpers

    private func selectFirstAvailableMenu() {
        if !displayedMenus.isEmpty {
            selectedMenuIndex = 0
        }
    }
}

// MARK: - Symbol Grid Item

struct SymbolGridItem: View {
    let symbol: SymbolItem
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 4) {
            Text(symbol.content)
                .font(.system(size: 18))
                .frame(height: 32)

            Text(symbol.desc)
                .font(.themeCaptionSmall)
                .foregroundColor(Color.themeTextTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.themeHoverMedium : Color.themeHoverLight)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.themeBorder, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Preview

#Preview {
    SymbolBrowserPanel(
        isPresented: .constant(true),
        onSymbolSelected: { symbol in
            print("Selected: \(symbol.content)")
        }
    )
}
