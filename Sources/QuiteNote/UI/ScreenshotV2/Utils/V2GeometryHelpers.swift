import SwiftUI

/// V2 截图功能的几何计算辅助扩展
extension V2ScreenshotView {
    /// 计算元素的边界框（用于交互检测）
    /// - Parameters:
    ///   - element: 要计算的绘图元素
    ///   - selection: 当前选区
    ///   - screenSize: 屏幕尺寸
    /// - Returns: 元素的边界矩形
    func elementBoundingRect(_ element: DrawingElement, selection: CGRect?, screenSize: CGSize) -> CGRect {
        switch element.tool {
        case .magnifier:
            return boundingRectForMagnifier(element, selection: selection, screenSize: screenSize)
        default:
            return boundingRectForPoints(element.points)
        }
    }

    // MARK: - 私有辅助方法

    /// 计算放大镜元素的边界框
    private func boundingRectForMagnifier(_ element: DrawingElement, selection: CGRect?, screenSize: CGSize) -> CGRect {
        let radius = element.fontSize * 2.5
        let padding: CGFloat = 20
        let baseX: CGFloat
        let baseY: CGFloat
        let bounds: CGRect

        if let selection = selection {
            baseX = selection.maxX
            baseY = selection.minY
            bounds = selection
        } else {
            baseX = screenSize.width
            baseY = 0
            bounds = CGRect(origin: .zero, size: screenSize)
        }

        let defaultEnd = CGPoint(x: baseX - radius - padding, y: baseY + radius + padding)
        let rawEnd = CGPoint(
            x: defaultEnd.x + element.magnifierOffset.width,
            y: defaultEnd.y + element.magnifierOffset.height
        )

        // 应用边界约束
        let minX = bounds.minX + radius
        let maxX = bounds.maxX - radius
        let minY = bounds.minY + radius
        let maxY = bounds.maxY - radius

        let end = CGPoint(
            x: max(minX, min(maxX, rawEnd.x)),
            y: max(minY, min(maxY, rawEnd.y))
        )

        let circleRect = CGRect(x: end.x - radius, y: end.y - radius, width: radius * 2, height: radius * 2)

        // 包含源点小圆圈的热区
        if let start = element.points.first {
            let dotRect = CGRect(x: start.x - 15, y: start.y - 15, width: 30, height: 30)
            return circleRect.union(dotRect)
        }

        return circleRect
    }

    /// 计算点集的边界框
    private func boundingRectForPoints(_ points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .zero }

        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        let minX = xs.min()!
        let minY = ys.min()!

        return CGRect(
            x: minX,
            y: minY,
            width: max(2, xs.max()! - minX),
            height: max(2, ys.max()! - minY)
        )
    }
}
