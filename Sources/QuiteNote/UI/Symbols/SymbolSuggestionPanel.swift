import SwiftUI
import AppKit

/// 符号联想面板 - 输入触发词时自动弹出
struct SymbolSuggestionPanel: View {
    let triggerText: String
    let suggestions: [SymbolItem]
    @Binding var selectedIndex: Int
    let onSelect: (SymbolItem) -> Void

    @FocusState private var isFocused: Bool

    init(triggerText: String, suggestions: [SymbolItem], selectedIndex: Binding<Int>, onSelect: @escaping (SymbolItem) -> Void) {
        self.triggerText = triggerText
        self.suggestions = suggestions
        self._selectedIndex = selectedIndex
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 0) {
            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, symbol in
                        Button(action: {
                            // ⭐ 调试日志：验证点击事件是否触发
                            print("[SymbolSuggestionPanel] ✅ Button clicked: \(symbol.content) - \(symbol.desc)")
                            onSelect(symbol)
                        }) {
                            SuggestionRow(
                                symbol: symbol,
                                triggerText: triggerText,
                                isSelected: index == selectedIndex
                            )
                            // ⭐ 确保整个区域可点击
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onHover { isHovering in
                            if isHovering {
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    selectedIndex = index
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.themeGray800)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.themeBlue500, lineWidth: 1)
                )
                .shadow(color: Color.themeShadowMedium, radius: 12, x: 0, y: 4)
            } else {
                // 无结果提示
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(Color.themeTextTertiary)
                    Text("未找到匹配的符号")
                        .font(.themeCaption)
                        .foregroundColor(Color.themeTextTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.themeGray800)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
                .shadow(color: Color.themeShadowMedium, radius: 8, x: 0, y: 4)
            }

            // 底部提示
            if !suggestions.isEmpty {
                HStack(spacing: 12) {
                    Text("↕ 切换")
                        .font(.themeCaptionSmall)
                        .foregroundColor(Color.themeTextTertiary)
                    Text("Enter 确认")
                        .font(.themeCaptionSmall)
                        .foregroundColor(Color.themeTextTertiary)
                    Text("Esc 取消")
                        .font(.themeCaptionSmall)
                        .foregroundColor(Color.themeTextTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.themeGray700.opacity(0.5))
            }
        }
        .frame(minWidth: 280, maxWidth: 320)
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - Suggestion Row

struct SuggestionRow: View {
    let symbol: SymbolItem
    let triggerText: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // 符号内容
            Text(symbol.content)
                .font(.system(size: 16))
                .frame(width: 28, alignment: .center)

            // 描述和匹配的触发词
            VStack(alignment: .leading, spacing: 2) {
                Text(highlightedDesc)
                    .font(.themeCaption)
                    .foregroundColor(isSelected ? Color.themeTextPrimary : Color.themeTextSecondary)

                if let matchedTrigger = matchedTrigger {
                    Text("触发词: \(matchedTrigger)")
                        .font(.themeCaptionSmall)
                        .foregroundColor(Color.themeTextTertiary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            isSelected ?
                Color.themeBlue500.opacity(0.2) :
                Color.clear
        )
    }

    private var highlightedDesc: AttributedString {
        var desc = AttributedString(symbol.desc)

        if let range = desc.range(of: symbol.desc, options: .caseInsensitive) {
            if let matchRange = symbol.desc.range(
                of: triggerText,
                options: .caseInsensitive,
                range: nil,
                locale: nil
            ) {
                let nsRange = NSRange(matchRange, in: symbol.desc)
                if let attributedRange = Range(nsRange, in: desc) {
                    desc[attributedRange].foregroundColor = Color.themeBlue500
                    desc[attributedRange].font = Font.system(size: 11, weight: .semibold)
                }
            }
        }

        return desc
    }

    private var matchedTrigger: String? {
        symbol.triggers.first { $0.lowercased().contains(triggerText.lowercased()) }
    }
}

// MARK: - Preview

#Preview("有结果") {
    SymbolSuggestionPanel(
        triggerText: "bug",
        suggestions: [
            SymbolItem(triggers: ["bug", "err"], content: "🐛", desc: "BUG/程序错误"),
            SymbolItem(triggers: ["build"], content: "🔨", desc: "构建/编译")
        ],
        selectedIndex: .constant(0),
        onSelect: { _ in }
    )
}

#Preview("无结果") {
    SymbolSuggestionPanel(
        triggerText: "xyz",
        suggestions: [],
        selectedIndex: .constant(0),
        onSelect: { _ in }
    )
}
