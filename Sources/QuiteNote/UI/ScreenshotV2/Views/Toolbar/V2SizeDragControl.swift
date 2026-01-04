import SwiftUI

/// ✨ 交互式 Size 调节控件：大圆套小圆，支持垂直拖拽调节
struct V2SizeDragControl: View {
    @ObservedObject var stateManager: V2PrimaryScreenStateManager
    
    @State private var isDragging: Bool = false
    @State private var dragStartY: CGFloat = 0
    @State private var initialValue: CGFloat = 0
    
    private let outerSize: CGFloat = 18 // 缩小外圆以适应 34x34 容器
    private let maxInnerSize: CGFloat = 14
    private let minInnerSize: CGFloat = 3
    
    var body: some View {
        let activeTool = getActiveTool()
        let range = activeTool.sizeRange
        let currentValue = activeTool == .text || activeTool == .mosaic || activeTool == .magnifier 
            ? stateManager.fontSize 
            : stateManager.lineWidth
            
        VStack(spacing: 2) {
            ZStack {
                // 外圆背景
                Circle()
                    .stroke(isDragging ? Color.blue : Color.white.opacity(0.3), lineWidth: 1.2)
                    .frame(width: outerSize, height: outerSize)
                
                // 内圆（指示当前大小）
                Circle()
                    .fill(isDragging ? Color.blue : Color.white.opacity(0.8))
                    .frame(width: calculateInnerSize(currentValue: currentValue, range: range), 
                           height: calculateInnerSize(currentValue: currentValue, range: range))
            }
            .frame(height: 20) // 给圆圈固定高度
            
            // 底部固定数字
            Text("\(Int(currentValue))")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(isDragging ? .blue : .white.opacity(0.6))
                .frame(height: 10)
        }
        .frame(width: 34, height: 34) // 整体尺寸与其他图标对齐
        .contentShape(Rectangle()) // 增大热区
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartY = value.location.y
                        initialValue = currentValue
                    }
                    
                    let deltaY = dragStartY - value.location.y
                    let sensitivity: CGFloat = 150.0 // 增加灵敏度跨度，让微调更精准
                    let percentChange = deltaY / sensitivity
                    let rangeSpan = range.max - range.min
                    
                    let newValue = (initialValue + percentChange * rangeSpan).clamped(to: range.min...range.max)
                    updateValue(newValue)
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .help("上下拖拽调节大小")
    }
    
    private func calculateInnerSize(currentValue: CGFloat, range: (min: CGFloat, max: CGFloat, default: CGFloat)) -> CGFloat {
        let percent = (currentValue - range.min) / (range.max - range.min)
        return minInnerSize + (maxInnerSize - minInnerSize) * percent
    }
    
    private func getActiveTool() -> AnnotationTool {
        if stateManager.selectedTool == .cursor,
           let id = stateManager.selectedElementId,
           let element = stateManager.elements.first(where: { $0.id == id }) {
            return element.tool
        }
        return stateManager.selectedTool
    }
    
    private func updateValue(_ value: CGFloat) {
        let tool = getActiveTool()
        if tool == .text || tool == .mosaic || tool == .magnifier {
            stateManager.fontSize = value
        } else {
            stateManager.lineWidth = value
        }
        
        // 如果有选中的元素，同步更新它
        if let selectedId = stateManager.selectedElementId {
            stateManager.updateElementSizeContinuous(selectedId, value: value)
        }
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
