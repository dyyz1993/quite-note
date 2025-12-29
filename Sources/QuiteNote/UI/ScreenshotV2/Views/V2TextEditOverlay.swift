import SwiftUI

/// V2 文本编辑浮层 - 用于编辑标注文本
struct V2TextEditOverlay: View {
    @ObservedObject var stateManager: V2PrimaryScreenStateManager
    let onFinish: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        if let editingId = stateManager.editingTextId,
           let index = stateManager.elements.firstIndex(where: { (element: DrawingElement) in element.id == editingId }) {
            let element = stateManager.elements[index]
            let position = element.points.first ?? .zero

            // ✨ 使用绝对定位，让文本开头在点击位置
            TextField("", text: Binding(
                get: { stateManager.elements[index].text },
                set: { newValue in
                    stateManager.elements[index].text = newValue
                }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: element.fontSize, weight: .bold))
            .foregroundColor(element.color)
            .disableAutocorrection(true)
            .focused($isFocused)
            .frame(width: 300, height: 40, alignment: .leading)  // ✨ 文本左对齐
            .background(Color.clear)  // ✨ 完全透明背景
            .contentShape(Rectangle())  // 确保可点击
            .onTapGesture {
                isFocused = true
            }
            // ✨ 使用 offset 将 TextField 的左上角对齐到点击位置
            .offset(x: position.x, y: position.y)
            .zIndex(200)  // 确保在最顶层
            .onSubmit {
                onFinish()
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                }
            }
        }
    }
}
