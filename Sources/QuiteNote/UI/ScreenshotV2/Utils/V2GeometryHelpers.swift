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
        case .text:
            return boundingRectForText(element)
        case .steps:
            return boundingRectForSteps(element)
        default:
            return boundingRectForPoints(element.points)
        }
    }

    // MARK: - 私有辅助方法

    /// 计算步骤元素的边界框
    private func boundingRectForSteps(_ element: DrawingElement) -> CGRect {
        guard let start = element.points.first else { return .zero }
        let radius: CGFloat = 12 // 与 V2StepsRenderer 中的 radius 一致
        return CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2)
    }

    /// 计算文本元素的边界框
    private func boundingRectForText(_ element: DrawingElement) -> CGRect {
        Self.textBoundingRect(for: element)
    }

    /// 文本元素边界框（静态实现，便于单元测试）
    /// ✅ 修复（TDD 验证）：宽度按字符类型分别估算——全角字符（中日韩）约 1.0 倍字号，
    /// 半角字符约 0.6 倍字号；旧实现统一按 0.6 估算，中文标注的点击热区偏窄约 40%
    static func textBoundingRect(for element: DrawingElement) -> CGRect {
        guard let start = element.points.first else { return .zero }

        let lines = element.text.components(separatedBy: .newlines)
        let lineHeight = element.fontSize * 1.3

        // 取最宽行的估算宽度（空文本也保留水平 padding 的最小宽度）
        let widestLine = lines.map { estimatedLineWidth($0, fontSize: element.fontSize) }.max() ?? 0
        let estimatedWidth = widestLine + 16 // 16 是 padding.horizontal
        let totalHeight = CGFloat(max(1, lines.count)) * lineHeight + 12 // 12 是 padding.vertical

        return CGRect(x: start.x, y: start.y, width: estimatedWidth, height: totalHeight)
    }

    /// 估算一行文本的渲染宽度
    static func estimatedLineWidth(_ line: String, fontSize: CGFloat) -> CGFloat {
        var units: CGFloat = 0
        for scalar in line.unicodeScalars {
            units += isFullWidthScalar(scalar) ? 1.0 : 0.6
        }
        return units * fontSize
    }

    /// 判断 Unicode 标量是否为全角字符（CJK 表意文字、假名、韩文、全角形式等）
    static func isFullWidthScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F,  // 谚文字母 (Hangul Jamo)
             0x2E80...0x303E,  // CJK 部首、康熙部首
             0x3041...0x33FF,  // 平假名、片假名、注音、CJK 兼容
             0x3400...0x4DBF,  // CJK 扩展 A
             0x4E00...0x9FFF,  // CJK 统一表意文字（简繁中文）
             0xA000...0xA4CF,  // 彝文
             0xAC00...0xD7A3,  // 韩文音节
             0xF900...0xFAFF,  // CJK 兼容表意
             0xFE30...0xFE4F,  // CJK 兼容形式
             0xFF00...0xFF60,  // 全角 ASCII、全角标点
             0xFFE0...0xFFE6:  // 全角符号
            return true
        default:
            return false
        }
    }

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
