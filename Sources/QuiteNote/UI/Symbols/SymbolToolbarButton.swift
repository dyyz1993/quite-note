import SwiftUI
import AppKit

// MARK: - Symbol Toolbar Button

/// 符号工具栏按钮 - StickyNote 工具栏中的符号入口
struct SymbolToolbarButton: View {
    private var configManager: SymbolConfigManager { SymbolConfigManager.shared }

    var body: some View {
        Button(action: {
            // TODO: 实现符号浏览器功能
            print("[DEBUG] SymbolToolbarButton clicked")
        }) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 11))
                .foregroundColor(.themeTextSecondary)
        }
        .buttonStyle(.plain)
        .help("符号浏览器")
    }
}
