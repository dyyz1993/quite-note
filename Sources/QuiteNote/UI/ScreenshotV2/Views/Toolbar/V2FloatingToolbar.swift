import SwiftUI

/// 普通截图模式的浮动工具栏
/// 负责显示标注工具和操作按钮
struct V2FloatingToolbar: View {
    let selection: CGRect
    let screen: NSScreen
    @ObservedObject var stateManager = V2PrimaryScreenStateManager.shared

    var body: some View {
        // 普通截图模式：显示标注工具栏
        V2AnnotationToolbar(stateManager: stateManager)
            .overlay(alignment: .topLeading) {
                if stateManager.isEditing {
                    // 仅在编辑模式显示退出按钮
                    Button(action: { stateManager.setEditing(false) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text("退出")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .onHover { hovering in
                stateManager.isMouseOverUI = hovering
            }
            .position(calculatePosition())
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.3), value: selection)
    }

    /// 计算工具栏位置（添加边界约束防止超出屏幕）
    private func calculatePosition() -> CGPoint {
        let toolbarHeight: CGFloat = 60
        let toolbarWidth: CGFloat = 400  // ✅ 估算工具栏宽度
        let spacing: CGFloat = 12
        let margin: CGFloat = 20  // ✅ 边距

        // 计算允许的 X 坐标范围
        let minX = toolbarWidth / 2 + margin
        let maxX = screen.frame.width - toolbarWidth / 2 - margin
        let constrainedX = max(minX, min(maxX, selection.midX))

        // 1. 优先尝试底部
        let bottomY = selection.maxY + toolbarHeight / 2 + spacing
        if bottomY < screen.frame.height - margin {
            return CGPoint(x: constrainedX, y: bottomY)
        }

        // 2. 尝试顶部
        let topY = selection.minY - toolbarHeight / 2 - spacing
        if topY > margin {
            return CGPoint(x: constrainedX, y: topY)
        }

        // 3. 全屏或空间不足：显示在选区内部底部
        return CGPoint(
            x: constrainedX,
            y: selection.maxY - toolbarHeight / 2 - spacing - 10
        )
    }
}
