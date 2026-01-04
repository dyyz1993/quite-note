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
                // ✨ 修复：仅在非导出模式下过滤掉正在编辑的元素，避免“双重显示”
                if !isExporting {
                    // 只有在【文本工具】模式下且选中该元素时，才跳过 Canvas 渲染
                    // 因为这种情况下我们会显示 AnnotationTextEditorView
                    if element.id == stateManager.selectedElementId && stateManager.selectedTool == .text {
                        continue
                    }
                }
                
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
            
            // 基础选中框
            // 💡 关键修复：马赛克工具不需要额外的 inset，因为它本身就是一个精准的填充区域
            // 其他工具（如画笔、形状）需要稍微扩大一点以便选中
            var rect: CGRect
            if element.tool == .mosaic {
                rect = baseRect
            } else {
                rect = baseRect.insetBy(dx: -4, dy: -4)
            }
            
            // 约束选中框在线框（选区）内
            if let selection = stateManager.selectedArea {
                rect = rect.intersection(selection)
            }
            
            // ✨ 序号工具使用圆形选中框，其他工具使用矩形
            if element.tool == .steps {
                context.stroke(Path(ellipseIn: rect), with: .color(.blue.opacity(0.5)), lineWidth: 1)
            } else {
                context.stroke(Path(rect), with: .color(.blue.opacity(0.5)), lineWidth: 1)
            }
            
            // 绘制四个角的控制点
            // ✨ 序号工具不需要控制点（因为它是固定大小的点击标注）
            if element.tool != .steps {
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

        // ✨ 特殊处理文本：估算文本边界框以便选中
        if element.tool == .text {
            guard let start = element.points.first else { return .zero }
            
            // 使用更精确的估算方法，或者通过 Text 测量（这里采用更稳健的估算）
            let lines = element.text.components(separatedBy: .newlines)
            let maxChars = lines.map { $0.count }.max() ?? 0
            let width = CGFloat(maxChars) * (element.fontSize * 0.65) + 30 // 增加 padding 容错
            let height = CGFloat(lines.count) * (element.fontSize * 1.3) + 20
            
            return CGRect(x: start.x, y: start.y, width: max(width, 40), height: max(height, 40))
        }

        // ✨ 特殊处理序号：边界框应为背景圆圈的范围
        if element.tool == .steps {
            guard let start = element.points.first else { return .zero }
            let radius: CGFloat = 12 // 需与 V2StepsRenderer.swift 保持一致
            return CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2)
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
