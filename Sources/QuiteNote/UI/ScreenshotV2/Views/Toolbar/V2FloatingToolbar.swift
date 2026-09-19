import SwiftUI

/// 截图工具栏：跟随选区定位 + 可拖拽微调
///
/// 定位规则（用户定义 2026-09-15 终版）：
///   理想位置 = 选区下方，工具栏水平中心对齐选区水平中心
///   硬约束   = **工具栏实际尺寸**不得超出屏幕（优先级最高，用 GeometryReader 实测宽度）
///   Y 轴降级 = 下方没空间 → 上方 → 全屏时内部贴底
struct V2FloatingToolbar: View {
    let selection: CGRect
    let screen: NSScreen
    @ObservedObject var stateManager = V2PrimaryScreenStateManager.shared

    @State private var dragOffset: CGSize = .zero
    @State private var isBeingDragged = false
    /// 工具栏实际尺寸（GeometryReader 实测，首帧后回填）
    @State private var actualSize: CGSize = .zero

    private let estimatedWidth: CGFloat = 500
    private let estimatedHeight: CGFloat = 48
    private let spacing: CGFloat = 12
    private let margin: CGFloat = 8

    var body: some View {
        toolbarContent
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { actualSize = geo.size }
                        .onChange(of: geo.size) { actualSize = $0 }
                }
            )
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
        let base = clampedPosition
        return CGPoint(x: base.x + dragOffset.width, y: base.y + dragOffset.height)
    }

    private var clampedPosition: CGPoint {
        let screenSize = screen.frame.size
        // 用实际尺寸（首帧前用估算值兜底）
        let size = actualSize.width > 0 ? actualSize : CGSize(width: estimatedWidth, height: estimatedHeight)
        let halfW = size.width / 2
        let halfH = size.height / 2

        // 硬约束优先：clamp X 不出屏
        let idealX = selection.midX
        let x = max(halfW + margin, min(screenSize.width - halfW - margin, idealX))

        // Y：选区下方 → 上方 → 全屏内部贴底
        let belowY = selection.maxY + spacing + halfH
        if belowY + halfH < screenSize.height - margin {
            return CGPoint(x: x, y: belowY)
        }

        let aboveY = selection.minY - spacing - halfH
        if aboveY - halfH > margin {
            return CGPoint(x: x, y: aboveY)
        }

        return CGPoint(x: x, y: screenSize.height - halfH - margin)
    }
}
