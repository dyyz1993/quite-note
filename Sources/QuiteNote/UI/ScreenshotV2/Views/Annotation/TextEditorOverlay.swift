import SwiftUI

/// 文本输入覆盖层 - 提供 SwiftUI 的文本编辑界面
struct TextEditorOverlay: View {
    @ObservedObject var stateManager: V2PrimaryScreenStateManager
    let editState: TextEditState
    let onFinish: () -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(stateManager: V2PrimaryScreenStateManager, editState: TextEditState, onFinish: @escaping () -> Void) {
        self.stateManager = stateManager
        self.editState = editState
        self.onFinish = onFinish
        self._text = State(initialValue: editState.text)
    }

    var body: some View {
        let rect = editState.boundingRect()

        VStack(spacing: 0) {
            // 文本输入框
            TextEditor(text: $text)
                .font(.system(size: editState.fontSize))
                .foregroundColor(editState.color)
                .background(Color.white.opacity(0.95))
                .frame(width: rect.width, height: rect.height)
                .border(Color.blue, width: 2)
                .focused($isFocused)
                .onAppear {
                    isFocused = true
                }
                .onChange(of: text) { newValue in
                    TextEditController.shared.updateText(newValue, stateManager: stateManager)
                }

            // 快捷操作提示
            HStack(spacing: 12) {
                Text("⌘+↙️ 完成").font(.caption).foregroundColor(.white)
                Text("ESC 取消").font(.caption).foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.7))
            .cornerRadius(4)
        }
        .position(x: rect.midX, y: rect.midY)
        .onSubmit {
            finishEditing()
        }
        .onExitCommand {
            cancelEditing()
        }
        /*
        // 监听快捷键
        .onKeyPress(.init("s"), modifiers: .command) {
            finishEditing()
            return .handled
        }
        */
    }

    private func finishEditing() {
        TextEditController.shared.finishEditing(stateManager: stateManager, newText: text)
        onFinish()
    }

    private func cancelEditing() {
        TextEditController.shared.cancelEditing(stateManager: stateManager)
        onFinish()
    }
}
