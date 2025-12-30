import SwiftUI

/// V2 文本编辑浮层 - 用于编辑标注文本
struct V2TextEditOverlay: View {
    @ObservedObject var stateManager: V2PrimaryScreenStateManager
    let screenSize: CGSize
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
            .focusable()  // ✅ 关键：参与 SwiftUI 焦点系统
            .font(.system(size: element.fontSize, weight: .bold))
            .foregroundColor(element.color)
            .disableAutocorrection(true)
            .focused($isFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 300, alignment: .leading)
            .background(Color.clear)  // ✨ 透明背景
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        element.color,
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])  // ✨ 虚线边框
                    )
            )
            .contentShape(Rectangle())  // 确保可点击
            .onTapGesture {
                isFocused = true
            }
            // ✨ 使用 position 中心定位，添加边界约束防止超出屏幕
            .position(
                x: min(max(position.x + 150, 150), screenSize.width - 150),
                y: min(max(position.y + 20, 30), screenSize.height - 30)
            )
            .zIndex(200)  // 确保在最顶层
            // ✨ 鼠标悬停时通知状态管理器，防止 InteractionLayer 拦截事件
            .onHover { hovering in
                stateManager.isMouseOverUI = hovering
            }
            .onSubmit {
                onFinish()
            }
            .onAppear {
                // ✅ 激活窗口以接收键盘输入
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.keyWindow ?? NSApp.windows.first {
                    window.makeKey()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                }
            }
        }
    }
}
