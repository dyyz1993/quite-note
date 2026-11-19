import SwiftUI
import AppKit

/// 启动器搜索框的 AppKit 实现（同 ClipSearchField 的动机：@FocusState 的"记录 true"
/// 与"实际生效"在 NSHostingView + accessory 应用激活节流下会脱节——面板晚拿到
/// key window 时无人补焦，打字落空。本组件把第一响应者控制权交还 AppKit：
/// 控制器在 key 就位后直接 `panel.makeFirstResponder(textField)`，确定性生效）
struct LauncherSearchField: NSViewRepresentable {
    @Binding var text: String
    var accessibilityIdentifier: String = "launcher.search_field"

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "搜索应用…"
        field.font = .systemFont(ofSize: 17, weight: .medium)
        field.textColor = NSColor(Color.themeTextPrimary)
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBordered = false
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier(accessibilityIdentifier)
        field.setAccessibilityLabel("应用启动器搜索")
        context.coordinator.field = field
        // 暴露给控制器做 makeFirstResponder（弱引用防环）
        AppLauncherPanelController.shared.searchFieldHandle = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LauncherSearchField
        weak var field: NSTextField?

        init(_ parent: LauncherSearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            parent.text = field?.stringValue ?? ""
        }
    }
}
