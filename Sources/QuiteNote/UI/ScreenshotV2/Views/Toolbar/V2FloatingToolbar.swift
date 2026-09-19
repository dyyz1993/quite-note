import SwiftUI

/// 截图工具栏：跟随选区定位 + 可拖拽微调
///
/// 定位规则（用户定义 2026-09-15 终版）：
///   理想位置 = 选区下方，工具栏水平中心对齐选区水平中心
///   硬约束   = 坐标不得超出屏幕；超出才 clamp（不做任何主动对齐策略）
///   Y 轴降级 = 下方没空间 → 上方 → 全屏时内部贴底
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
        let base = idealPosition
        return CGPoint(x: base.x + dragOffset.width, y: base.y + dragOffset.height)
    }

    /// 理想位置 + clamp 不出屏
    private var idealPosition: CGPoint {
        let screenSize = screen.frame.size
        let halfW = toolbarWidth / 2
        let halfH = toolbarHeight / 2

        // 理想 X：工具栏水平中心对齐选区水平中心
        let idealX = selection.midX
        // clamp：不出屏
        let x = max(halfW + margin, min(screenSize.width - halfW - margin, idealX))

        // Y：优先选区下方
        let belowY = selection.maxY + spacing + halfH
        if belowY + halfH < screenSize.height - margin {
            return CGPoint(x: x, y: belowY)
        }

        // 下方没空间 → 选区上方
        let aboveY = selection.minY - spacing - halfH
        if aboveY - halfH > margin {
            return CGPoint(x: x, y: aboveY)
        }

        // 全屏 → 选区内部、贴屏幕底边上方
        return CGPoint(x: x, y: screenSize.height - halfH - margin)
    }
}
