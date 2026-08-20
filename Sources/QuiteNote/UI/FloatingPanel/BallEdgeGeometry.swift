import Foundation
import CoreGraphics

/// 浮球边缘几何（纯函数，可单测）
///
/// 背景：拖拽时球心直接跟随鼠标，鼠标可以进入菜单栏/Dock/屏幕凹槽区域，
/// 80×80 的承载窗口会被摆到部分出屏的位置；macOS 在窗口 order front 时会把
/// 带标题栏的窗口推回可视区域，与拖拽的 setFrame 互相拉扯 → 边缘来回闪跳。
/// 因此拖拽全程和松手吸附都必须把球心钳制在可视区域内。
enum BallEdgeGeometry {
    /// 拖拽钳制：窗口边缘离 visibleFrame 的最小余量
    static let dragWindowMargin: CGFloat = 4

    /// 松手吸附后：球体视觉边缘（56pt 直径）离屏幕边缘的间距。
    /// 原为 16——窗口仅 4pt 在屏内，鼠标贴边滑行会反复进出悬停区造成抖动，加大到 24
    static let snapVisualGap: CGFloat = 24

    struct ScreenBounds {
        var frame: CGRect
        var visibleFrame: CGRect

        init(frame: CGRect, visibleFrame: CGRect) {
            self.frame = frame
            self.visibleFrame = visibleFrame
        }
    }

    /// 选出点所在的屏幕；不在任何屏幕内时取几何距离最近的，保证钳制结果可预期
    static func screen(containing point: CGPoint, in screens: [ScreenBounds]) -> ScreenBounds? {
        guard !screens.isEmpty else { return nil }
        if let hit = screens.first(where: { $0.frame.contains(point) }) { return hit }
        return screens.min {
            distance(from: point, to: $0.frame) < distance(from: point, to: $1.frame)
        }
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    /// 拖拽中的实时钳制：保证整扇承载窗口（默认 80pt）留在 visibleFrame 内
    static func clampDrag(center: CGPoint, windowSize: CGFloat, screens: [ScreenBounds]) -> CGPoint {
        guard let screen = screen(containing: center, in: screens) else { return center }
        let inset = windowSize / 2 + dragWindowMargin
        let bounds = screen.visibleFrame.insetBy(dx: inset, dy: inset)
        guard bounds.width > 0, bounds.height > 0 else { return center }
        return CGPoint(
            x: min(max(center.x, bounds.minX), bounds.maxX),
            y: min(max(center.y, bounds.minY), bounds.maxY)
        )
    }

    /// 松手吸附：球心距 visibleFrame 各边缘 ≥ visualRadius + snapVisualGap
    static func snapCenter(_ center: CGPoint, visualRadius: CGFloat, screens: [ScreenBounds]) -> CGPoint {
        guard let screen = screen(containing: center, in: screens) else { return center }
        let margin = visualRadius + snapVisualGap
        return CGPoint(
            x: min(max(center.x, screen.visibleFrame.minX + margin), screen.visibleFrame.maxX - margin),
            y: min(max(center.y, screen.visibleFrame.minY + margin), screen.visibleFrame.maxY - margin)
        )
    }
}
