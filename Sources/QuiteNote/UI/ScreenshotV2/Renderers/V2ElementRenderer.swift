import SwiftUI

// MARK: - Element Renderer Protocol

/// 元素渲染器协议
protocol ElementRenderer {
    /// 渲染元素到 Canvas
    /// - Parameters:
    ///   - element: 要渲染的绘图元素
    ///   - context: Canvas 图形上下文
    ///   - config: 渲染配置
    func render(
        element: DrawingElement,
        in context: inout GraphicsContext,
        config: RendererConfig
    )

    /// 判断是否支持该工具类型
    static func supports(_ tool: AnnotationTool) -> Bool
}

// MARK: - Renderer Configuration

/// 渲染器配置
struct RendererConfig {
    let imageSize: CGSize
    let canvasSize: CGSize
    let baseImage: NSImage?
    let selectionArea: CGRect?  // ✨ 选区信息（用于放大镜等元素）

    static func empty(canvasSize: CGSize) -> RendererConfig {
        return RendererConfig(
            imageSize: .zero,
            canvasSize: canvasSize,
            baseImage: nil,
            selectionArea: nil
        )
    }
}

// MARK: - Renderer Factory

/// 渲染器工厂
struct ElementRendererFactory {
    static func renderer(for tool: AnnotationTool) -> any ElementRenderer {
        switch tool {
        case .rectangle, .circle, .line:
            return ShapeRenderer()
        case .arrow:
            return ArrowRenderer()
        case .pen:
            return PenRenderer()
        case .steps:
            return StepsRenderer()
        case .mosaic:
            return MosaicRenderer()
        case .magnifier:
            return MagnifierRenderer()
        case .spotlight:
            return SpotlightRenderer()
        case .text:
            return V2TextRenderer()
        case .cursor:
            fatalError("Cursor tool should not be rendered")
        }
    }
}

// MARK: - Shared Rendering Utilities

extension ElementRenderer {
    /// 计算元素边界框
    func boundingRect(for element: DrawingElement) -> CGRect {
        guard !element.points.isEmpty else { return .zero }
        let xs = element.points.map { $0.x }
        let ys = element.points.map { $0.y }
        return CGRect(
            x: xs.min()!,
            y: ys.min()!,
            width: xs.max()! - xs.min()!,
            height: ys.max()! - ys.min()!
        )
    }
}
