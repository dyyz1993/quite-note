import SwiftUI

/// V2 文本编辑层 - 使用 TextEditor 而非独立窗口
struct V2TextEditLayer: View {
    @ObservedObject var stateManager: V2PrimaryScreenStateManager

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ZStack {
            ForEach($stateManager.elements) { $element in
                if element.id == stateManager.editingTextId {
                    // ✨ 使用 TextEditor 而不是 TextField
                    TextEditor(text: $element.text)
                        .font(.system(size: element.fontSize, weight: .bold))
                        .foregroundColor(element.color)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .cornerRadius(4)
                        .focused($isTextFieldFocused)
                        .frame(minWidth: 100, maxWidth: 400, minHeight: 40)
                        .fixedSize(horizontal: false, vertical: true)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(
                                    element.color,
                                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                                )
                        )
                        .position(
                            x: (element.points.first?.x ?? 0),
                            y: (element.points.first?.y ?? 0)
                        )
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isTextFieldFocused = true
                            }
                        }
                }
            }
        }
    }
}
