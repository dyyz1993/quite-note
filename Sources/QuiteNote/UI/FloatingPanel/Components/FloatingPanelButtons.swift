import SwiftUI

/// 悬停按钮 - 带悬停效果的按钮
struct HoverButton: View {
    let icon: IconName
    let size: CGFloat
    var isActive: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            LucideView(name: icon, size: size, color: isActive ? .white : (hovering ? .white : .themeGray400))
                .padding(6)
                .background(isActive ? Color.white.opacity(0.2) : (hovering ? Color.white.opacity(0.1) : Color.clear))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .pointingHandCursor()
    }
}

/// 关闭按钮 - 红色圆形按钮
struct CloseButton: View {
    let onClose: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        Circle()
            .fill(Color.themeRed500.opacity(hovering ? 1.0 : 0.8)) // bg-red-500/80
            .frame(width: 12, height: 12)
            .onTapGesture { onClose?() }
            .onHover { hovering = $0 }
            .pointingHandCursor()
            .help("关闭")
    }
}

/// 缩小按钮 - 黄色圆形按钮（缩小到浮球）
struct ShrinkButton: View {
    let onMinimize: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        Circle()
            .fill(Color.themeYellow500.opacity(hovering ? 1.0 : 0.8)) // bg-yellow-500/80
            .frame(width: 12, height: 12)
            .onTapGesture { onMinimize?() }
            .onHover { hovering = $0 }
            .pointingHandCursor()
            .help("缩小到浮球")
    }
}

/// 图标按钮 - 带悬停缩放效果的圆形图标按钮
struct IconButton: View {
    let icon: IconName
    let color: Color
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            LucideView(name: icon, size: 14, color: color)
                .frame(width: 24, height: 24)
                .background(isHovering ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .focusable(false)
        .onHover { isHovering = $0 }
        .scaleEffect(isHovering ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

/// 标签视图 - 可点击的标签
struct TagView: View {
    let text: String
    let color: Color
    let bgColor: Color
    let action: () -> Void

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(bgColor)
            .foregroundColor(color)
            .cornerRadius(3)
            .onTapGesture(perform: action)
            .pointingHandCursor()
    }
}
