import SwiftUI
import AppKit

/// 快捷键录入组件
struct ShortcutRecorderView: View {
    @Binding var shortcut: String
    @Binding var modifiers: Int
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        Button(action: {
            startRecording()
        }) {
            HStack(spacing: 4) {
                if isRecording {
                    Text("请按下快捷键...")
                        .font(.themeCaption)
                        .foregroundColor(.themeBlue400)
                } else {
                    HStack(spacing: 4) {
                        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
                        if flags.contains(.command) { shortcutBadge("⌘") }
                        if flags.contains(.shift) { shortcutBadge("⇧") }
                        if flags.contains(.option) { shortcutBadge("⌥") }
                        if flags.contains(.control) { shortcutBadge("⌃") }
                        
                        if !shortcut.isEmpty {
                            shortcutBadge(shortcut.uppercased())
                        } else {
                            Text("无")
                                .font(.themeCaption)
                                .foregroundColor(.themeTextTertiary)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isRecording ? Color.themeActive : Color.themeInput)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.themeBlue500 : Color.themeBorderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func shortcutBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.themeHoverMedium)
            .cornerRadius(4)
            .foregroundColor(.themeTextPrimary)
    }

    private func startRecording() {
        isRecording = true
        
        // 移除旧的监听器
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        // 添加局部事件监听
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                // 仅修饰键改变，不处理
                return event
            }
            
            if event.type == .keyDown {
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                
                // 忽略单独的 Esc 键（用于取消录制）
                if event.keyCode == 53 { // Escape
                    stopRecording()
                    return nil
                }
                
                // 必须包含至少一个修饰键，或者是功能键
                let hasModifiers = !flags.intersection([.command, .option, .shift, .control]).isEmpty
                
                if hasModifiers, let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
                    self.shortcut = chars.lowercased()
                    self.modifiers = Int(flags.rawValue)
                    stopRecording()
                    return nil
                }
            }
            
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
