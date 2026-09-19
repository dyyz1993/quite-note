import SwiftUI

/// 截图工具栏：自动跟随选区定位 + 可拖拽微调
///
/// 坐标系：selectedArea 和 .position() 均为当前屏幕的局部坐标（原点左上，y 向下）。
/// 定位规则（用户定义 2026-09-15）：
///   1. 选区下方有空间 → 工具栏在选区正下方，X 对齐选区中心（clamp 在屏幕内）
///   2. 选区下方没空间（全屏/贴底）→ 工具栏在选区内部、贴选区底边
///   3. 手动拖拽把手可微调位置（offset 叠加在自动定位之上）
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

    /// 最终位置 = 自动定位 + 手动拖拽偏移
    private var position: CGPoint {
        let base = autoPosition
        return CGPoint(x: base.x + dragOffset.width, y: base.y + dragOffset.height)
    }

    /// 自动定位（局部坐标系：原点左上，y 向下）
    private var autoPosition: CGPoint {
        let screenSize = screen.frame.size

        // X：对齐选区中心，clamp 在屏幕内
        let x = max(
            toolbarWidth / 2 + margin,
            min(screenSize.width - toolbarWidth / 2 - margin, selection.midX)
        )

        // Y：优先选区下方
        let belowY = selection.maxY + spacing + toolbarHeight / 2
        if belowY + toolbarHeight / 2 < screenSize.height - margin {
            return CGPoint(x: x, y: belowY)
        }

        // 选区下方没空间 → 在选区内部、贴选区底边
        let insideY = selection.maxY - toolbarHeight / 2 - spacing
        // clamp 到屏幕底边上方
        let clampedY = min(insideY, screenSize.height - toolbarHeight / 2 - margin)
        return CGPoint(x: x, y: max(toolbarHeight / 2 + margin, clampedY))
    }
}
