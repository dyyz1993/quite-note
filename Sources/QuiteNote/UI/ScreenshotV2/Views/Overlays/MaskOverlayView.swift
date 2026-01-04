import SwiftUI

/// 蒙层叠加层 - 实现挖孔效果，高亮选中区域
struct V2MaskOverlayView: View {
    let isReleased: Bool
    let screenSize: CGSize
    let dragStartPoint: CGPoint?
    let dragCurrentPoint: CGPoint?
    let localSelectedArea: CGRect?
    let snappedRect: CGRect?
    let isCurrentlyPrimary: Bool
    let hasPrimaryScreen: Bool

    var body: some View {
        if isReleased {
            EmptyView()
        } else {
            // ⚠️ 核心逻辑：动态计算当前需要"变亮"的区域（挖孔）
            let holeRect = calculatedHoleRect
            let overlayOpacity = calculatedOpacity

            maskContent(holeRect: holeRect, opacity: overlayOpacity)
        }
    }

    // MARK: - 计算属性

    /// 计算需要挖孔的区域
    private var calculatedHoleRect: CGRect? {
        // 1. 如果正在拖拽，挖拖拽的孔
        if let start = dragStartPoint, let current = dragCurrentPoint {
            return CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
        }
        // 2. 如果已有选区，挖选区的孔
        if let selection = localSelectedArea {
            return selection
        }
        // 3. 如果有吸附矩形，挖吸附的孔
        return snappedRect
    }

    /// 计算蒙层透明度
    private var calculatedOpacity: Double {
        // 如果是主屏幕，蒙层更透明；否则蒙层更不透明
        if isCurrentlyPrimary {
            return V2ColorConstants.maskPrimaryOpacity
        } else if hasPrimaryScreen {
            return V2ColorConstants.maskInactiveOpacity
        } else {
            return V2ColorConstants.maskInitialOpacity
        }
    }

    // MARK: - 子视图

    @ViewBuilder
    private func maskContent(holeRect: CGRect?, opacity: Double) -> some View {
        ZStack(alignment: .topLeading) {
            // 使用 Shape 挖孔比 blendMode 更可靠
            Color.black.opacity(opacity)
                .mask(
                    InvertedRectangle(hole: holeRect)
                        .fill(style: FillStyle(eoFill: true))
                )
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: V2TimeConstants.holeAnimationDuration), value: holeRect)
        .animation(.easeInOut(duration: V2TimeConstants.opacityAnimationDuration), value: opacity)
    }
}
