import SwiftUI

/// 截图工具栏：跟随选区定位 + 可拖拽微调
///
/// 定位规则（用户定义 2026-09-15 终版）：
///   理想位置 = 选区下方，工具栏水平中心对齐选区水平中心
///   硬约束   = **工具栏实际尺寸**不得超出屏幕（优先级最高，用 GeometryReader 实测宽度）
///   Y 轴降级 = 下方没空间 → 上方 → 全屏时内部贴底
struct V2FloatingToolbar: View {
    let selection: CGRect
    let screen: NSScreen
    @ObservedObject var stateManager = V2PrimaryScreenStateManager.shared

    @State private var dragOffset: CGSize = .zero
    @State private var isBeingDragged = false
    /// 工具栏实际尺寸（GeometryReader 实测，首帧后回填）
    @State private var actualSize: CGSize = .zero
    /// 子视图上报的展开层规格（二级工具栏 / 音频弹层），参与主栏 union clamp
    @State private var expansionSpecs: ScreenshotToolbarLayout.Specs = .none

    private let estimatedWidth: CGFloat = 500
    private let estimatedHeight: CGFloat = 48
    private let spacing: CGFloat = 12
    private let margin: CGFloat = 8

    var body: some View {
        toolbarContent
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { actualSize = geo.size }
                        .onChange(of: geo.size) { actualSize = $0 }
                }
            )
            .overlay(alignment: .top) { dragHandle }
            .position(position)
    }

    private var toolbarContent: some View {
        V2AnnotationToolbar(
            stateManager: stateManager,
            expansionPlacements: expansionPlacements,
            onExpansionChange: { expansionSpecs = $0 }
        )
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onHover { hovering in
            stateManager.isMouseOverUI = hovering
        }
    }

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(isBeingDragged ? 0.4 : 0.12))
            .frame(width: 60, height: 5)
            .padding(.top, 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isBeingDragged = true
                        dragOffset = value.translation
                    }
                    .onEnded { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            isBeingDragged = false
                        }
                    }
            )
            .onHover { h in
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }

    private var position: CGPoint {
        let base = clampedPosition
        return CGPoint(x: base.x + dragOffset.width, y: base.y + dragOffset.height)
    }

    private var clampedPosition: CGPoint {
        layoutOutput.mainCenter
    }

    /// 纯函数布局：垂直沿用「下方 → 上方 → 贴底」，水平把展开层纳入 union clamp；
    /// 拖拽偏移只参与展开层贴边判断（position 处自行叠加），主栏基准不受拖拽影响
    private var layoutOutput: ScreenshotToolbarLayout.Output {
        // 用实际尺寸（首帧前用估算值兜底）
        let size = actualSize.width > 0 ? actualSize : CGSize(width: estimatedWidth, height: estimatedHeight)
        // 屏幕上下被菜单栏 / Dock 占据的区域：贴底定位时必须避开，
        // 否则底部选区的工具栏会沉在 Dock 后面（2026-10-22 实拍）。
        let frame = screen.frame
        let visible = screen.visibleFrame
        let bottomInset = max(0, frame.maxY - visible.maxY)
        let topInset = max(0, visible.minY - frame.minY)
        return ScreenshotToolbarLayout.compute(.init(
            screen: CGRect(origin: .zero, size: frame.size),
            selection: selection,
            mainSize: size,
            specs: expansionSpecs,
            margin: margin,
            spacing: spacing,
            bottomInset: bottomInset,
            topInset: topInset,
            mainDisplacement: CGPoint(x: dragOffset.width, y: dragOffset.height)
        ))
    }

    /// 展开层 offset（V2AnnotationToolbar overlay 内坐标）：
    /// V2FloatingToolbar 用 .position() 定位，position 容器的子视图坐标以 position
    /// 点为原点，所以 offset = 目标 frame 的左上角 - 主栏中心点。
    private var expansionPlacements: V2AnnotationToolbar.ExpansionPlacements {
        func toOffset(_ frame: CGRect?) -> CGSize? {
            frame.map {
                CGSize(width: $0.minX - layoutOutput.mainSize.width / 2,
                       height: $0.minY - layoutOutput.mainSize.height / 2)
            }
        }
        return .init(
            subToolbar: toOffset(layoutOutput.subToolbarFrameInMain),
            audioPicker: toOffset(layoutOutput.audioPickerFrameInMain)
        )
    }
}
