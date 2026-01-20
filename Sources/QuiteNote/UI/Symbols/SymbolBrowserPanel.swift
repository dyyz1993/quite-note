import SwiftUI

/// 符号浏览器面板 - 重新设计的简洁版本
struct SymbolBrowserPanel: View {
    let menus: [SymbolMenu]
    @Binding var currentMenuIndex: Int
    @Binding var selectedIndex: Int
    let onClose: () -> Void
    let onSelect: (SymbolItem) -> Void

    var currentMenu: SymbolMenu {
        guard currentMenuIndex < menus.count else { return menus[0] }
        return menus[currentMenuIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部：分组标签行
            tabBar

            Divider()

            // 中间：符号网格
            symbolGrid

            Divider()

            // 底部：快捷键提示
            footer
        }
        .frame(width: 320, height: 360)
        .background(Color.themeGray800)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.themeBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.themeShadowMedium, radius: 16, x: 0, y: 4)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(menus.enumerated()), id: \.element.id) { index, menu in
                        tabButton(for: menu, at: index)
                            .id(index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
            .frame(height: 48)
            .background(Color.themeGray900)
            .onChange(of: currentMenuIndex) { newIndex in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    private func tabButton(for menu: SymbolMenu, at index: Int) -> some View {
        Button(action: {
            currentMenuIndex = index
        }) {
            VStack(spacing: 2) {
                Text(menu.icon ?? "📁")
                    .font(.system(size: 18))

                Text(menu.title)
                    .font(.system(size: 9))
                    .foregroundColor(index == currentMenuIndex ? .themeTextPrimary : .themeTextTertiary)
                    .lineLimit(1)
            }
            .frame(width: 48, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(index == currentMenuIndex
                        ? Color.themeBlue500.opacity(0.2)
                        : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(index == currentMenuIndex
                        ? Color.themeBlue500
                        : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("\(menu.title) - \(menu.symbols.count)个符号")
    }

    // MARK: - Symbol Grid

    private var symbolGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    // ⭐ 关键修复：直接使用 currentMenuIndex 获取数据，而不是通过计算属性
                    let currentSymbols = currentMenuIndex < menus.count ? menus[currentMenuIndex].symbols : []
                    ForEach(Array(currentSymbols.enumerated()), id: \.element.id) { index, symbol in
                        symbolCell(for: symbol, at: index)
                            .id("menu_\(currentMenuIndex)_\(index)")  // ⭐ 使用复合 ID 确保唯一性
                    }
                }
                .padding(16)
            }
            .onChange(of: selectedIndex) { newIndex in
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo("menu_\(currentMenuIndex)_\(newIndex)", anchor: .center)
                }
            }
            .onChange(of: currentMenuIndex) { newIndex in
                // 切换分组时，选中中间的符号
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let symbolCount = menus[newIndex].symbols.count
                    let centerIndex = max(0, symbolCount / 2)
                    selectedIndex = centerIndex
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo("menu_\(newIndex)_\(centerIndex)", anchor: .center)
                    }
                }
            }
        }
    }

    private func symbolCell(for symbol: SymbolItem, at index: Int) -> some View {
        Button(action: { onSelect(symbol) }) {
            Text(symbol.content)
                .font(.system(size: 24))
                .frame(width: 64, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(index == selectedIndex
                            ? Color.themeBlue500.opacity(0.25)
                            : Color.themeHoverLight)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(index == selectedIndex
                            ? Color.themeBlue500
                            : Color.clear, lineWidth: 1.5)
                )
                .help(symbol.desc)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 20) {
            footerItem(icon: "arrow.left.arrow.right", text: "Tab 切换")
            footerItem(icon: "arrow.up.and.down.and.arrow.left.and.right.right", text: "方向键")
            footerItem(icon: "return", text: "Enter 插入")
            footerItem(icon: "escape", text: "Esc 关闭")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.themeGray700.opacity(0.5))
    }

    private func footerItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.themeTextTertiary)
            Text(text)
                .font(.themeCaptionSmall)
                .foregroundColor(.themeTextTertiary)
        }
    }
}
