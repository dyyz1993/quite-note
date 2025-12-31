import SwiftUI

/// 工具栏按钮组件
struct ToolbarButton: View {
    let icon: String
    let color: Color
    let label: String
    var isPrimary: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: isPrimary ? 20 : 16, weight: .medium))
                    .foregroundColor(color)

                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(width: 44, height: 44)
            .background(isHovered ? Color.white.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
