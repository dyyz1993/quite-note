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
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                // 边框和背景 (如果是吸附状态且开启了背景)
                if showBackground {
                    Rectangle()
                        .fill(Color.yellow.opacity(0.05)) // 极低透明度的背景，增强吸附感
                }
                
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
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.black.opacity(0.8), lineWidth: 1))
                            .position(handle.position(in: rect))
                    }
                }

                // 标签使用 position 定位（与手柄一致）
                // position 是绝对定位，自动居中，不受标签宽度影响
                if let label = label {
                    Text(label)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(opacity))
                        .cornerRadius(2)
                        .position(x: rect.width / 2, y: -11)
                }
            }
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .allowsHitTesting(false) // ✅ 线框区域不接收点击事件，允许穿透
        }
    }
}
