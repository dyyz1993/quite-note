import AppKit
import SwiftUI

/// 窗口高亮视图 - 使用 NSView + CAShapeLayer 直接渲染（绕过 SwiftUI 渲染限制）
@available(macOS 10.15, *)
final class WindowHighlightView: NSView {
    private var highlightLayer: CAShapeLayer?
    private var fillLayer: CAShapeLayer?

    var highlightedBounds: CGRect = .zero {
        didSet {
            needsLayout = true
        }
    }

    var highlightColor: NSColor = .blue {
        didSet {
            highlightLayer?.strokeColor = highlightColor.cgColor
            fillLayer?.fillColor = highlightColor.withAlphaComponent(0.15).cgColor
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    private func setupLayers() {
        wantsLayer = true
        layer = CALayer()

        // 填充层
        let fill = CAShapeLayer()
        fill.fillColor = highlightColor.withAlphaComponent(0.15).cgColor
        layer?.addSublayer(fill)
        fillLayer = fill

        // 边框层
        let border = CAShapeLayer()
        border.strokeColor = highlightColor.cgColor
        border.fillColor = .clear
        border.lineWidth = 4
        layer?.addSublayer(border)
        highlightLayer = border
    }

    override func layout() {
        super.layout()

        guard highlightedBounds != .zero else { return }

        let path = NSBezierPath(roundedRect: highlightedBounds, xRadius: 8, yRadius: 8)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // 兼容 macOS 13+ 的 path 转换
        if #available(macOS 14.0, *) {
            fillLayer?.path = path.cgPath
            highlightLayer?.path = path.cgPath
        } else {
            // macOS 13 及更早版本使用 CGPath
            fillLayer?.path = path.toCGPath()
            highlightLayer?.path = path.toCGPath()
        }

        CATransaction.commit()
    }
}

// NSBezierPath to CGPath conversion for macOS 13+
extension NSBezierPath {
    func toCGPath() -> CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)

        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            case .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            @unknown default:
                break
            }
        }
        return path
    }
}

/// SwiftUI 包装器
struct WindowHighlightViewRepresentable: NSViewRepresentable {
    let bounds: CGRect
    let color: Color

    func makeNSView(context: Context) -> WindowHighlightView {
        let view = WindowHighlightView(frame: .zero)
        view.highlightedBounds = bounds
        view.highlightColor = NSColor(color)
        return view
    }

    func updateNSView(_ nsView: WindowHighlightView, context: Context) {
        nsView.highlightedBounds = bounds
        nsView.highlightColor = NSColor(color)
    }
}
