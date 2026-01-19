import SwiftUI
import AppKit

/// 符号联想面板 - 输入触发词时自动弹出
struct SymbolSuggestionPanel: View {
    let triggerText: String
    let suggestions: [MatchedSymbolItem]
    @Binding var selectedIndex: Int
    let onSelect: (MatchedSymbolItem) -> Void

    @FocusState private var isFocused: Bool

    init(triggerText: String, suggestions: [MatchedSymbolItem], selectedIndex: Binding<Int>, onSelect: @escaping (MatchedSymbolItem) -> Void) {
        self.triggerText = triggerText
        self.suggestions = suggestions
        self._selectedIndex = selectedIndex
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 0) {
            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, item in
                        Button(action: {
                            // ⭐ 调试日志：验证点击事件是否触发
                            print("[SymbolSuggestionPanel] ✅ Button clicked: \(item.content) - \(item.desc)")
                            onSelect(item)
                        }) {
                            SuggestionRow(
                                item: item,
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
    let item: MatchedSymbolItem
    let triggerText: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // 符号内容
            Text(item.content)
                .font(.system(size: 16))
                .frame(width: 28, alignment: .center)

            // 描述和匹配的触发词
            VStack(alignment: .leading, spacing: 2) {
                Text(highlightedDesc)
                    .font(.themeCaption)
                    .foregroundColor(isSelected ? Color.themeTextPrimary : Color.themeTextSecondary)

                if !item.matchedTrigger.isEmpty {
                    Text("触发词: \(item.matchedTrigger)")
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
        var desc = AttributedString(item.desc)

        if let range = desc.range(of: item.desc, options: .caseInsensitive) {
            if let matchRange = item.desc.range(
                of: triggerText,
                options: .caseInsensitive,
                range: nil,
                locale: nil
            ) {
                let nsRange = NSRange(matchRange, in: item.desc)
                if let attributedRange = Range(nsRange, in: desc) {
                    desc[attributedRange].foregroundColor = Color.themeBlue500
                    desc[attributedRange].font = Font.system(size: 11, weight: .semibold)
                }
            }
        }

        return desc
    }
}

// MARK: - Preview

#Preview("有结果") {
    SymbolSuggestionPanel(
        triggerText: "sd",
        suggestions: [
            MatchedSymbolItem(symbol: SymbolItem(triggers: ["sad", "伤心"], content: "😢", desc: "伤心"), matchedTrigger: "sad"),
            MatchedSymbolItem(symbol: SymbolItem(triggers: ["cry", "哭泣"], content: "😭", desc: "哭泣"), matchedTrigger: "cry")
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
