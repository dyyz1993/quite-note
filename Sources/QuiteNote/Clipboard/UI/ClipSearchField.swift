import SwiftUI
import AppKit

/// 剪贴板面板搜索框的 AppKit 实现（替代 SwiftUI TextField + @FocusState）
///
/// 为什么：@FocusState 的"记录 true"与"实际生效"在 NSHostingView + accessory 应用
/// 激活节流的场景下会脱节（面板内容重、成为 key window 的时机漂移），多轮补偿
/// 均无法根治（用户实测"根本不行"）。本组件把第一响应者控制权交还 AppKit：
/// 控制器在面板拿到 key 后直接 `panel.makeFirstResponder(textField)`，确定性生效。
struct ClipSearchField: NSViewRepresentable {
    @Binding var text: String
    /// 焦点回调（驱动 SwiftUI 侧的边框高亮等视觉，非聚焦机制本身）
    var onFocusChange: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "输入以搜索剪贴板内容…"
        field.font = .systemFont(ofSize: 15)
        field.textColor = NSColor(ClipboardPalette.textPrimary)
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBordered = false
        field.focusRingType = .none
        field.delegate = context.coordinator
        context.coordinator.field = field
        // 暴露给控制器做 makeFirstResponder（弱引用防环）
        ClipboardHistoryPanelController.shared.searchFieldHandle = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ClipSearchField
        weak var field: NSTextField?

        init(_ parent: ClipSearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            parent.text = field?.stringValue ?? ""
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.onFocusChange?(true)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.onFocusChange?(false)
        }
    }
}
