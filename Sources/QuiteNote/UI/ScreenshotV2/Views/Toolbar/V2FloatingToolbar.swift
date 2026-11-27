import SwiftUI

/// 截图工具栏：跟随选区定位 + 可拖拽微调
///
/// 定位规则（用户定义 2026-09-15 终版）：
///   理想位置 = 选区下方，工具栏水平中心对齐选区水平中心
///   硬约束   = **工具栏实际尺寸**不得超出屏幕（优先级最高，用 GeometryReader 实测宽度）
///   Y 轴降级 = 下方没空间 → 上方 → 全屏时内部贴底
///   X 轴锚定 = 以默认态（cursor 工具）的居中位定左缘，换工具变宽只向右生长，
///              避免整栏重居中导致指针下的按钮横移（实测平移 117~148pt，2026-11-27）
struct V2FloatingToolbar: View {
    let selection: CGRect
    let screen: NSScreen
    @ObservedObject var stateManager = V2PrimaryScreenStateManager.shared

    @State private var dragOffset: CGSize = .zero
    @State private var isBeingDragged = false
    /// 工具栏实际尺寸（GeometryReader 实测，首帧后回填）
    @State private var actualSize: CGSize = .zero
    /// 主栏默认态（cursor 工具、未选中放大镜元素）的实测宽度：左缘锚定的基准宽，
    /// 其余工具态的宽度都以此为参照向右生长（该态控件最少、宽度最窄）
    @State private var cursorToolWidth: CGFloat = 0
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
                        .onAppear {
                            actualSize = geo.size
                            recordCursorToolWidth(geo.size)
                        }
                        .onChange(of: geo.size) {
                            actualSize = $0
                            recordCursorToolWidth($0)
                        }
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
        // 首帧按估算宽 500 定位、实测宽回来后横跳 ~75pt：实测前整栏隐藏
        // （opacity 不影响布局与命中测试，GeometryReader 照常量到尺寸）
        .opacity(actualSize.width > 0 ? 1 : 0)
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
        // 左缘锚点（屏幕局部坐标，与选区同空间）：用默认态宽度复现现状的选区水平居中位，
        // 再退回半宽得到左缘——换工具变宽后主栏左缘钉死在该位、只向右生长；
        // 选区移动 / 重选时锚点跟随选区重算（现状的重定位行为保留），越界钳制交给 compute 兜底
        let baseWidth = cursorToolWidth > 0 ? cursorToolWidth : size.width
        let anchorHalf = baseWidth / 2
        let leadingAnchorX = min(max(selection.midX, margin + anchorHalf),
                                 frame.width - margin - anchorHalf) - anchorHalf
        return ScreenshotToolbarLayout.compute(.init(
            screen: CGRect(origin: .zero, size: frame.size),
            selection: selection,
            mainSize: size,
            specs: expansionSpecs,
            margin: margin,
            spacing: spacing,
            bottomInset: bottomInset,
            topInset: topInset,
            mainDisplacement: CGPoint(x: dragOffset.width, y: dragOffset.height),
            leadingAnchorX: leadingAnchorX
        ))
    }

    /// 记录默认态基准宽：只在 cursor 工具且选中元素（若有）非放大镜时回填——
    /// 放大镜元素选中态会追加倍率控件组，宽度偏大，不得覆盖基准
    private func recordCursorToolWidth(_ size: CGSize) {
        guard stateManager.selectedTool == .cursor, !isSelectedElementMagnifier else { return }
        cursorToolWidth = size.width
    }

    /// 与 V2AnnotationToolbar.isSelectedElementMagnifier 同口径：选中的元素（若有）是放大镜元素
    private var isSelectedElementMagnifier: Bool {
        if let id = stateManager.selectedElementId,
           let element = stateManager.elements.first(where: { $0.id == id }) {
            return element.tool == .magnifier
        }
        return false
    }

    /// 展开层 offset（V2AnnotationToolbar overlay 内坐标）：
    /// overlay 挂在 mainToolbarContent 上（对齐 .topLeading），其局部原点为
    /// toolbarContent 扣除外层 padding (horizontal 12, vertical 8) 后的左上角。
    private var expansionPlacements: V2AnnotationToolbar.ExpansionPlacements {
        func toOffset(_ frame: CGRect?) -> CGSize? {
            frame.map {
                CGSize(width: $0.minX - ScreenshotToolbarLayout.FixedGeometry.toolbarOuterPadding,
                       height: $0.minY - ScreenshotToolbarLayout.FixedGeometry.toolbarOuterVerticalPadding)
            }
        }
        return .init(
            subToolbar: toOffset(layoutOutput.subToolbarFrameInMain),
            audioPicker: toOffset(layoutOutput.audioPickerFrameInMain)
        )
    }
}
