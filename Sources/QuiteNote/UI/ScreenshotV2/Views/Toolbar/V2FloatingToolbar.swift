import SwiftUI

/// Screenshot toolbar - auto-positions and supports dragging
struct V2FloatingToolbar: View {
    let selection: CGRect
    let screen: NSScreen
    @ObservedObject var stateManager = V2PrimaryScreenStateManager.shared

    @State private var dragOffset: CGSize = .zero
    @State private var isBeingDragged = false

    var body: some View {
        toolbarContent
            .overlay(alignment: .top) { dragHandle }
            .position(positionInScreen)
            // 实时跟随选区（不用 spring——快速拖拽时 spring 会追不上）
    }

    private var toolbarContent: some View {
        V2AnnotationToolbar(stateManager: stateManager)
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
            .gesture(dragGesture)
            .onHover { h in
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isBeingDragged = true
                // value.translation 是相对手势起点的总位移，直接使用
                dragOffset = value.translation
            }
            .onEnded { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    isBeingDragged = false
                }
            }
    }

    private var positionInScreen: CGPoint {
        let base = calculatePosition()
        return CGPoint(x: base.x + dragOffset.width, y: base.y + dragOffset.height)
    }

    private func calculatePosition() -> CGPoint {
        let toolbarHeight: CGFloat = 48
        let toolbarWidth: CGFloat = 420
        let spacing: CGFloat = 12
        let margin: CGFloat = 16

        let visibleFrame = screen.visibleFrame
        let minX = visibleFrame.minX + toolbarWidth / 2 + margin
        let maxX = visibleFrame.maxX - toolbarWidth / 2 - margin
        let constrainedX = max(minX, min(maxX, selection.midX))

        let bottomY = selection.maxY + toolbarHeight / 2 + spacing
        if bottomY + toolbarHeight / 2 < visibleFrame.maxY - margin {
            return CGPoint(x: constrainedX, y: bottomY)
        }

        let topY = selection.minY - toolbarHeight / 2 - spacing
        if topY - toolbarHeight / 2 > visibleFrame.minY + margin {
            return CGPoint(x: constrainedX, y: topY)
        }

        let innerY = min(
            selection.maxY - toolbarHeight / 2 - spacing - 10,
            visibleFrame.maxY - toolbarHeight / 2 - margin
        )
        return CGPoint(
            x: constrainedX,
            y: max(visibleFrame.minY + toolbarHeight / 2 + margin, innerY)
        )
    }
}
