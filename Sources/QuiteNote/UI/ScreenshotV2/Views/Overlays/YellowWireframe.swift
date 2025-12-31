import SwiftUI

/// 统一的黄色虚线框组件
struct YellowWireframe: View {
    let rect: CGRect
    let label: String?
    let isDashed: Bool
    let showBackground: Bool
    let isEditing: Bool // 传入编辑状态
    let isLongScreenshotMode: Bool // 传入长图模式
    var opacity: Double = 1.0
    var showHandles: Bool = false // 是否显示 8 个调整手柄

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 边框
            Rectangle()
                .stroke(
                    Color.yellow.opacity(opacity),
                    style: StrokeStyle(
                        lineWidth: 2,
                        dash: isDashed ? [6, 3] : []
                    )
                )

            // 8 个调整手柄 (仅在非编辑模式和非长图模式下显示)
            if showHandles && !isEditing && !isLongScreenshotMode {
                ForEach(SelectionHandle.allCases, id: \.self) { handle in
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 10, height: 10) // 稍微大一点，更好看
                        .overlay(Circle().stroke(Color.black.opacity(0.8), lineWidth: 1))
                        .position(handle.position(in: rect))
                }
            }

            // 标签
            if let label = label {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.yellow.opacity(opacity))
                    .cornerRadius(2)
                    .offset(y: -22) // 放在边框上方
            }
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }
}
