import SwiftUI
import AppKit

// MARK: - Button Position PreferenceKey

/// 用于获取按钮位置的 PreferenceKey
struct ButtonPositionKey: PreferenceKey {
    typealias Value = CGRect
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - Symbol Toolbar Button

/// 符号工具栏按钮 - StickyNote 工具栏中的符号入口
///
/// 使用 SymbolBrowserPanelManager 单例管理面板状态和键盘事件
struct SymbolToolbarButton: View {
    // 使用单例而不是创建新实例
    private let manager = SymbolBrowserPanelManager.shared
    @State private var buttonFrame: CGRect = .zero

    var body: some View {
        Button(action: {
            print("[SymbolToolbarButton] Button clicked")
            print("[SymbolToolbarButton] buttonFrame: \(buttonFrame)")
            print("[SymbolToolbarButton] keyWindow: \(String(describing: NSApp.keyWindow))")

            if let window = NSApp.keyWindow as? StickyNoteWindow {
                print("[SymbolToolbarButton] Calling togglePanel for window UUID: \(window.uuid.uuidString)")
                manager.togglePanel(from: window, at: buttonFrame)
            } else {
                print("[SymbolToolbarButton] ⚠️ keyWindow is not a StickyNoteWindow")
            }
        }) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 11))
                .foregroundColor(.themeTextSecondary)
        }
        .buttonStyle(.plain)
        .help("符号浏览器")
        .background(
            // 用于获取按钮位置
            GeometryReader { geo in
                Color.clear.preference(key: ButtonPositionKey.self, value: geo.frame(in: .global))
            }
        )
        .onPreferenceChange(ButtonPositionKey.self) { frame in
            buttonFrame = frame
        }
        // 监听 StickyNote 失焦事件，关闭面板
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StickyNoteBlur"))) { _ in
            manager.closePanel()
        }
    }
}
