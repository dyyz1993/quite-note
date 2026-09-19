import SwiftUI

/// 截图工具栏：自动跟随选区定位 + 可拖拽微调
///
/// 坐标系：selectedArea 和 .position() 均为当前屏幕的局部坐标（原点左上，y 向下）。
///
/// X 轴规则（保证工具栏百分百不出屏）：
///   - 选区在左半边 → 工具栏左边对齐选区左边
///   - 选区在右半边 → 工具栏右边对齐选区右边
///   - 选区在中间 → 工具栏中心对齐选区中心
///
/// Y 轴规则：
///   - 优先选区下方（选区下边的下方）
///   - 下方没空间 → 选区上方（选区上边的上方）
///   - 只有全屏（上下都没空间）→ 选区内部、贴屏幕底边上方
struct V2FloatingToolbar: View {
    let selection: CGRect
    let screen: NSScreen
    @ObservedObject var stateManager = V2PrimaryScreenStateManager.shared

    @State private var dragOffset: CGSize = .zero
    @State private var isBeingDragged = false

    private let toolbarHeight: CGFloat = 48
    private let toolbarWidth: CGFloat = 420
    private let spacing: CGFloat = 12
    private let margin: CGFloat = 8

    var body: some View {
        toolbarContent
            .overlay(alignment: .top) { dragHandle }
            .position(position)
    }

    private var toolbarContent: some View {
        V2AnnotationToolbar(stateManager: stateManager)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .onHover { hovering in
                stateManager.isMouseOverUI = hovering
            }
    }

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(isBeingDragged ? 0.4 : 0.12))
            .frame(width: 60, height: 5)
            .padding(.top, 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isBeingDragged = true
                        dragOffset = value.translation
                    }
                    .onEnded { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            isBeingDragged = false
                        }
                    }
            )
            .onHover { h in
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }

    private var position: CGPoint {
        let base = autoPosition
        return CGPoint(x: base.x + dragOffset.width, y: base.y + dragOffset.height)
    }

    // MARK: - 自动定位（局部坐标，原点左上，y 向下）

    private var autoPosition: CGPoint {
        CGPoint(x: autoX, y: autoY)
    }

    /// X 轴：选区在哪边就往哪边对齐，保证不出屏
    private var autoX: CGFloat {
        let screenSize = screen.frame.size
        let halfW = toolbarWidth / 2

        // 选区左边缘在屏幕左半边 → 工具栏左对齐选区左边
        if selection.minX < screenSize.width / 2 - halfW {
            return halfW + margin
        }

        // 选区右边缘在屏幕右半边 → 工具栏右对齐选区右边
        if selection.maxX > screenSize.width / 2 + halfW {
            return screenSize.width - halfW - margin
        }

        // 中间 → 对齐选区中心（clamp 在屏幕内）
        return max(halfW + margin, min(screenSize.width - halfW - margin, selection.midX))
    }

    /// Y 轴：下方 → 上方 → 全屏内部贴底
    private var autoY: CGFloat {
        let screenSize = screen.frame.size
        let halfH = toolbarHeight / 2

        // 1. 优先选区下方
        let belowY = selection.maxY + spacing + halfH
        if belowY + halfH < screenSize.height - margin {
            return belowY
        }

        // 2. 下方没空间 → 选区上方
        let aboveY = selection.minY - spacing - halfH
        if aboveY - halfH > margin {
            return aboveY
        }

        // 3. 全屏 → 选区内部、贴屏幕底边上方
        return screenSize.height - halfH - margin
    }
}
