import SwiftUI

/// V2 标注画布 - 纯渲染层，不处理任何事件
/// ⚠️ 符合架构设计：只负责渲染，事件由 Layer 3 处理
struct V2AnnotationCanvas: View {
    @ObservedObject var stateManager: V2PrimaryScreenStateManager
    let canvasSize: CGSize
    let baseImage: NSImage?
    var isExporting: Bool = false // ✨ 新增：是否处于导出模式（导出时隐藏选择框等辅助 UI）

    var body: some View {
        Canvas { context, size in
            // 渲染已有元素
            for element in stateManager.elements {
                // 如果正在编辑该文字，则不在画布上重复渲染（编辑框由 Overlay 提供）
                if element.tool == .text && stateManager.editingTextId == element.id && !isExporting { continue }
                renderElement(element, in: &context, size: size)
            }

            // 渲染正在绘制的元素
            if let current = stateManager.currentElement {
                renderElement(current, in: &context, size: size)
            }
        }
        .allowsHitTesting(false)
    }

    /// 渲染单个标注元素
    /// - Parameters:
    ///   - element: 标注元素
    ///   - context: 图形上下文
    ///   - size: 画布尺寸
    private func renderElement(_ element: DrawingElement, in context: inout GraphicsContext, size: CGSize) {
        let renderer = ElementRendererFactory.renderer(for: element.tool)
        renderer.render(
            element: element,
            in: &context,
            config: RendererConfig(
                imageSize: baseImage?.size ?? .zero,
                canvasSize: size,
                baseImage: baseImage,
                selectionArea: stateManager.selectedArea
            )
        )

        // ✨ 仅在非导出模式下显示选中框和手柄
        if !isExporting && element.id == stateManager.selectedElementId && stateManager.selectedTool == .cursor {
            let baseRect = elementBoundingRect(element, config: RendererConfig(
                imageSize: baseImage?.size ?? .zero,
                canvasSize: size,
                baseImage: baseImage,
                selectionArea: stateManager.selectedArea
            ))
            
            // 基础选中框（稍微扩大一点）
            var rect = baseRect.insetBy(dx: -4, dy: -4)
            
            // 约束选中框在线框（选区）内
            if let selection = stateManager.selectedArea {
                rect = rect.intersection(selection)
            }
            
            context.stroke(Path(rect), with: .color(.blue.opacity(0.5)), lineWidth: 1)

            // 绘制四个角的控制点
            let corners = [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.maxX, y: rect.maxY)
            ]
            for corner in corners {
                context.fill(Path(ellipseIn: CGRect(x: corner.x - 3, y: corner.y - 3, width: 6, height: 6)), with: .color(.white))
                context.stroke(Path(ellipseIn: CGRect(x: corner.x - 3, y: corner.y - 3, width: 6, height: 6)), with: .color(.blue), lineWidth: 1)
            }
        }
    }

    private func elementBoundingRect(_ element: DrawingElement, config: RendererConfig) -> CGRect {
        // ✨ 特殊处理放大镜：返回放大镜的显示位置，且包含源点热区
        if element.tool == .magnifier {
            let radius = element.fontSize * 2.5
            let padding: CGFloat = 20

            // ✨ 如果有选区，使用选区右上角；否则使用 canvas 右上角
            let baseX: CGFloat
            let baseY: CGFloat
            let bounds: CGRect

            if let selection = config.selectionArea {
                baseX = selection.maxX
                baseY = selection.minY
                bounds = selection
            } else {
                baseX = config.canvasSize.width
                baseY = 0
                bounds = CGRect(origin: .zero, size: config.canvasSize)
            }

            let defaultEnd = CGPoint(
                x: baseX - radius - padding,
                y: baseY + radius + padding
            )
            
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

            // 返回放大镜的圆形区域
            let circleRect = CGRect(x: end.x - radius, y: end.y - radius, width: radius * 2, height: radius * 2)
            
            // 包含源点小圆圈的热区
            if let start = element.points.first {
                let dotRect = CGRect(x: start.x - 15, y: start.y - 15, width: 30, height: 30) // 增大热区
                return circleRect.union(dotRect)
            }
            
            return circleRect
        }
        
        if element.tool == .text {
            let point = element.points.first ?? .zero
            let width: CGFloat = element.text.isEmpty ? 100 : CGFloat(element.text.count * 12 + 20)
            return CGRect(x: point.x, y: point.y, width: width, height: element.fontSize * 1.5)
        }

        // 其他工具使用原有逻辑
        let points = element.points
        guard !points.isEmpty else { return .zero }
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        let minX = xs.min()!
        let minY = ys.min()!
        let width = max(2, xs.max()! - minX)
        let height = max(2, ys.max()! - minY)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }
}
