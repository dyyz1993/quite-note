import SwiftUI

/// ✨ 放大镜倍率调节控件：显示倍数 (1.0x - 5.0x)，支持垂直拖拽调节
struct V2MagnifierScaleControl: View {
    @ObservedObject var stateManager: V2PrimaryScreenStateManager
    
    @State private var isDragging: Bool = false
    @State private var dragStartY: CGFloat = 0
    @State private var initialValue: CGFloat = 0
    
    private let range: (min: CGFloat, max: CGFloat) = (1.0, 5.0)
    
    var body: some View {
        let currentValue = stateManager.magnifierScale
            
        VStack(spacing: 2) {
            ZStack {
                // 背景图标
                LucideView(name: .zoomIn, size: 14, color: isDragging ? .themeBlue500 : .themeTextTertiary)
                    .frame(width: 18, height: 18)
            }
            .frame(height: 20)
            
            // 底部倍率文字
            Text(String(format: "%.1fx", currentValue))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(isDragging ? .themeBlue500 : .themeTextPrimary)
                .frame(height: 10)
        }
        .frame(width: 38, height: 34)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartY = value.location.y
                        initialValue = currentValue
                    }
                    
                    let deltaY = dragStartY - value.location.y
                    let sensitivity: CGFloat = 100.0 // 调节灵敏度
                    let newValue = (initialValue + deltaY / sensitivity * (range.max - range.min)).clamped(to: range.min...range.max)
                    
                    stateManager.magnifierScale = newValue
                    
                    // 如果有选中的元素，同步更新它
                    if let selectedId = stateManager.selectedElementId,
                       let index = stateManager.elements.firstIndex(where: { $0.id == selectedId }),
                       stateManager.elements[index].tool == .magnifier {
                        stateManager.elements[index].magnifierScale = newValue
                        stateManager.objectWillChange.send()
                    }
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .help("上下拖拽调节放大倍率 (1x - 5x)")
    }
}
