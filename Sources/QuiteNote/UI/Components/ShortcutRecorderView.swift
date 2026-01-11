import SwiftUI
import AppKit

/// 快捷键录入组件
struct ShortcutRecorderView: View {
    @Binding var shortcut: String
    @Binding var modifiers: Int
    @State private var isRecording = false
    
    var body: some View {
        Button(action: {
            isRecording = true
        }) {
            HStack(spacing: 4) {
                if isRecording {
                    Text("请按下快捷键...")
                        .font(Font.system(size: 11))
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
            .frame(minWidth: 120, minHeight: 24)
            .background(isRecording ? Color.themeActive : Color.themeInput)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.themeBlue500 : Color.themeBorderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .overlay {
            if isRecording {
                // 使用较大的 frame 并使用 fixedSize 确保不被父容器裁剪
                // 虽然 overlay 默认受限，但在 macOS NSViewRepresentable 中，
                // 我们可以通过背景色和点击事件来捕获更大范围
                ShortcutCaptureView(shortcut: $shortcut, modifiers: $modifiers, isRecording: $isRecording)
                    .frame(width: 1000, height: 1000)
                    .background(Color.black.opacity(0.01))
                    .allowsHitTesting(true)
            }
        }
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
}

/// 负责捕获键盘事件的底层 NSView
struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var shortcut: String
    @Binding var modifiers: Int
    @Binding var isRecording: Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = ShortcutNSView()
        view.onCaptured = { newShortcut, newModifiers in
            print("[DEBUG ShortcutRecorderView] 回调 onCaptured: \(newShortcut)")
            self.shortcut = newShortcut
            self.modifiers = newModifiers
            self.isRecording = false
        }
        view.onCancel = {
            print("[DEBUG ShortcutRecorderView] 回调 onCancel")
            self.isRecording = false
        }
        // 确保视图创建后立即尝试获取焦点
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = view.window {
                print("[DEBUG ShortcutRecorderView] 尝试设置第一响应者: \(window.title)")
                let success = window.makeFirstResponder(view)
                print("[DEBUG ShortcutRecorderView] 设置第一响应者结果: \(success)")
            } else {
                print("[DEBUG ShortcutRecorderView] 视图尚未进入窗口，无法设置第一响应者")
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // 每次更新都尝试重新获取焦点，防止焦点丢失
        if isRecording {
            DispatchQueue.main.async {
                if let window = nsView.window, window.firstResponder != nsView {
                    window.makeFirstResponder(nsView)
                }
            }
        }
    }
    
    class ShortcutNSView: NSView {
        var onCaptured: ((String, Int) -> Void)?
        var onCancel: (() -> Void)?
        private var localMonitor: Any?
        
        override var acceptsFirstResponder: Bool { true }
        
        // 增加点击获取焦点，防止焦点丢失
        override func mouseDown(with event: NSEvent) {
            self.window?.makeFirstResponder(self)
        }
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                print("[DEBUG ShortcutRecorderView] 视图已进入窗口，开始监听事件")
                setupMonitor()
                // 强制请求焦点
                DispatchQueue.main.async {
                    self.window?.makeFirstResponder(self)
                }
            } else {
                print("[DEBUG ShortcutRecorderView] 视图离开窗口，移除监听")
                removeMonitor()
            }
        }
        
        private func setupMonitor() {
            removeMonitor()
            // 使用 LocalMonitor 捕获所有按键，比 keyDown 更可靠
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] (event: NSEvent) -> NSEvent? in
                guard let self = self else { return event }
                
                // ⚠️ 关键：如果当前不是第一响应者，不处理事件，防止干扰其他输入框
                guard self.window?.firstResponder == self else {
                    return event
                }
                
                if event.type == .flagsChanged {
                    // 仅记录修饰键变化不触发保存
                    return event
                }
                
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                
                // Esc 键取消
                if event.keyCode == 53 {
                    print("[DEBUG ShortcutRecorderView] 按下 Esc，取消录制")
                    self.onCancel?()
                    return nil
                }
                
                // 必须包含修饰键，或者是功能键（F1-F12 等）
                let hasModifiers = !flags.intersection([.command, .option, .shift, .control]).isEmpty
                let isFunctionKey = (event.keyCode >= 96 && event.keyCode <= 101) || (event.keyCode >= 103 && event.keyCode <= 111) || (event.keyCode >= 113 && event.keyCode <= 122)
                
                if (hasModifiers || isFunctionKey), let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
                    let shortcutChar = chars.lowercased()
                    print("[DEBUG ShortcutRecorderView] 录入成功: \(shortcutChar), flags: \(flags.rawValue)")
                    self.onCaptured?(shortcutChar, Int(flags.rawValue))
                    return nil // 消费事件
                }
                
                // 如果是录制状态下的其他按键（如普通字符），由于我们是第一响应者且在录制，
                // 我们应该拦截它并发出声效（或不处理），而不是让它传给其他地方
                if event.type == .keyDown {
                    NSSound.beep()
                    return nil
                }
                
                return event
            }
        }
        
        private func removeMonitor() {
            if let monitor = localMonitor {
                NSEvent.removeMonitor(monitor)
                localMonitor = nil
            }
        }
        
        override func resignFirstResponder() -> Bool {
            print("[DEBUG ShortcutRecorderView] 失去焦点，取消录制")
            // 如果失去焦点，自动停止录制
            DispatchQueue.main.async {
                self.onCancel?()
            }
            return true
        }
        
        deinit {
            removeMonitor()
        }
    }
}
