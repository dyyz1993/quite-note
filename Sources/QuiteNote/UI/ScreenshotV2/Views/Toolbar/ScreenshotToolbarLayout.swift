import CoreGraphics

/// 截图工具栏纯函数布局（零 SwiftUI 依赖，只做数学，可单测）
///
/// 解决两个产品需求：
/// 1. 主工具栏动态变宽（选中工具追加颜色/尺寸/倍率控件）时不得出屏，越界则整栏让位；
/// 2. 二级工具栏默认水平中心对齐「被点击的一级工具组按钮」，仅屏幕边界冲突时最小让位；
///    音频弹层保持右对齐主栏的既有交互，同样不得出屏（贴底放不下时翻转到主栏上方）。
///
/// 坐标系约定（与 V2ScreenshotView 挂载工具栏的 overlay 层一致）：
/// - 屏幕与选区同处一个屏幕局部坐标系（原点 = 屏幕左上角，y 向下增长）；
/// - 「主栏局部坐标」以 V2FloatingToolbar 被 GeometryReader 实测的 toolbarContent
///   包围盒（含 horizontal 12 / vertical 8 外边距）左上角为原点，`position` 即该包围盒中心。
enum ScreenshotToolbarLayout {

    // MARK: - 固定几何常量（与 V2FloatingToolbar / V2AnnotationToolbar 视图结构一一对应，改视图时同步）

    enum FixedGeometry {
        /// 一级工具组按钮宽度（V2AnnotationToolbar.groupButton）
        static let primaryButtonWidth: CGFloat = 34
        /// 工具组 HStack 间距
        static let primaryGroupSpacing: CGFloat = 4
        /// 工具组容器内边距
        static let primaryGroupPadding: CGFloat = 4
        /// mainToolbarContent 的 .padding(8)
        static let mainContentPadding: CGFloat = 8
        /// V2FloatingToolbar.toolbarContent 的 .padding(.horizontal, 12)
        static let toolbarOuterPadding: CGFloat = 12
        /// V2FloatingToolbar.toolbarContent 的 .padding(.vertical, 8)
        static let toolbarOuterVerticalPadding: CGFloat = 8
        /// 二级工具栏按钮边长 / 间距 / 容器内边距（subToolbar）
        static let subToolbarButtonSize: CGFloat = 30
        static let subToolbarSpacing: CGFloat = 8
        static let subToolbarPadding: CGFloat = 6
        /// 二级工具栏顶边相对主栏包围盒上缘的挂载偏移（沿表现状 -60）
        static let subToolbarAttachY: CGFloat = -60
        /// 音频弹层顶边相对主栏包围盒上缘的挂载偏移（沿表现状：ZStack 内 +54 + 外边距 8）
        static let audioPickerAttachY: CGFloat = 62
        /// 展开层垂直翻转（默认侧放不下时）到另一侧所用的间隙
        static let flipGap: CGFloat = 8
    }

    // MARK: - 输入

    struct Expansion: Equatable {
        enum Anchor: Equatable {
            /// 水平中心对齐被点击的一级按钮（主栏局部 x，自主栏包围盒左缘量起）
            case buttonCenter(xInMain: CGFloat)
            /// 右对齐主栏包围盒右缘（音频弹层沿表现状）
            case mainTrailing
        }

        let size: CGSize
        let anchor: Anchor
        /// 展开层顶边相对主栏包围盒上缘的 y 偏移；负值 = 悬浮在主栏上方
        let attachY: CGFloat
        /// 垂直翻转到另一侧时与主栏包围盒的间隙
        let flipGap: CGFloat

        init(size: CGSize,
             anchor: Anchor,
             attachY: CGFloat,
             flipGap: CGFloat = FixedGeometry.flipGap) {
            self.size = size
            self.anchor = anchor
            self.attachY = attachY
            self.flipGap = flipGap
        }
    }

    /// 当前打开的展开层组合（二级工具栏与音频弹层可能同时打开）
    struct Specs: Equatable {
        let subToolbar: Expansion?
        let audioPicker: Expansion?
        static let none = Specs(subToolbar: nil, audioPicker: nil)
    }

    struct Input {
        let screen: CGRect
        let selection: CGRect
        let mainSize: CGSize
        var specs = Specs.none
        var margin: CGFloat = 8
        var spacing: CGFloat = 12
        /// 用户拖拽主栏的偏移：只参与展开层最终贴边判断，不改变主栏基准位置（由调用方自行叠加）
        var mainDisplacement: CGPoint = .zero
    }

    // MARK: - 输出

    struct Output: Equatable {
        /// 主栏包围盒中心（屏幕坐标系，与选区同空间）
        let mainCenter: CGPoint
        /// 二级工具栏 frame（主栏局部坐标；nil = 未展开）
        let subToolbarFrameInMain: CGRect?
        /// 音频弹层 frame（主栏局部坐标；nil = 未展开）
        let audioPickerFrameInMain: CGRect?
    }

    // MARK: - 布局

    static func compute(_ input: Input) -> Output {
        let mainSize = input.mainSize
        let halfW = mainSize.width / 2
        let halfH = mainSize.height / 2
        let scr = input.screen
        let availLeft = scr.minX + input.margin
        let availRight = scr.maxX - input.margin
        let availTop = scr.minY + input.margin
        let availBottom = scr.maxY - input.margin

        // 1. 垂直：选区下方 → 上方 → 贴底（沿用既有优先级与开闭边界，不改变现状行为）
        let belowCenterY = input.selection.maxY + input.spacing + halfH
        let aboveCenterY = input.selection.minY - input.spacing - halfH
        let centerY: CGFloat
        if belowCenterY + halfH < scr.maxY - input.margin {
            centerY = belowCenterY
        } else if aboveCenterY - halfH > scr.minY + input.margin {
            centerY = aboveCenterY
        } else {
            centerY = scr.maxY - input.margin - halfH
        }

        // 2. 水平：主栏先按自身尺寸落位（选区居中 + 自身不出屏，现状行为）
        var centerX = clamped(input.selection.midX, availLeft + halfW, availRight - halfW)

        // 3. union 整体水平 clamp：主栏 + 全部展开层的理想 hull 越左右界 → 整体平移最小补偿量
        //    （锚定关系随整体平移保持；平移后主栏仍回钳自身合法区间，保证主栏永不越界）
        var idealExtras: [CGRect] = []
        if let sub = input.specs.subToolbar {
            idealExtras.append(idealFrame(sub, centerX: centerX, centerY: centerY, mainSize: mainSize))
        }
        if let audio = input.specs.audioPicker {
            idealExtras.append(idealFrame(audio, centerX: centerX, centerY: centerY, mainSize: mainSize))
        }
        if !idealExtras.isEmpty {
            var unionMinX = centerX - halfW
            var unionMaxX = centerX + halfW
            for frame in idealExtras {
                unionMinX = min(unionMinX, frame.minX)
                unionMaxX = max(unionMaxX, frame.maxX)
            }
            var shift: CGFloat = 0
            if unionMinX < availLeft {
                shift = availLeft - unionMinX
            } else if unionMaxX > availRight {
                shift = availRight - unionMaxX
            }
            if shift != 0 {
                centerX = clamped(centerX + shift, availLeft + halfW, availRight - halfW)
            }
        }

        // 4. 展开层最终 frame：按（含拖拽的）最终主栏位置重算理想位，再做最小让位 clamp
        let finalMainOriginX = centerX + input.mainDisplacement.x - halfW
        let finalMainOriginY = centerY + input.mainDisplacement.y - halfH

        let clampArgs = ExpansionClampArgs(availLeft: availLeft, availRight: availRight,
                                           availTop: availTop, availBottom: availBottom,
                                           mainSize: mainSize,
                                           finalMainOriginY: finalMainOriginY)
        let subFrame = input.specs.subToolbar.map {
            finalFrame($0, centerX: centerX, centerY: centerY, displacement: input.mainDisplacement, args: clampArgs)
        }
        let audioFrame = input.specs.audioPicker.map {
            finalFrame($0, centerX: centerX, centerY: centerY, displacement: input.mainDisplacement, args: clampArgs)
        }

        return Output(
            mainCenter: CGPoint(x: centerX, y: centerY),
            subToolbarFrameInMain: subFrame.map { $0.offsetBy(dx: -finalMainOriginX, dy: -finalMainOriginY) },
            audioPickerFrameInMain: audioFrame.map { $0.offsetBy(dx: -finalMainOriginX, dy: -finalMainOriginY) }
        )
    }

    // MARK: - 确定性推导（与视图固定布局对应，不读运行时几何）

    /// 一级工具组按钮中心 x（主栏局部坐标，自主栏包围盒左缘量起）。
    /// 工具组永远在主栏 HStack 首位，选中工具追加的控件只向尾部增长，
    /// 因此该局部坐标在主栏变宽前后保持不变。
    static func primaryButtonCenterX(groupIndex: Int) -> CGFloat {
        let leadingInset = FixedGeometry.toolbarOuterPadding
            + FixedGeometry.mainContentPadding
            + FixedGeometry.primaryGroupPadding
        return leadingInset
            + CGFloat(groupIndex) * (FixedGeometry.primaryButtonWidth + FixedGeometry.primaryGroupSpacing)
            + FixedGeometry.primaryButtonWidth / 2
    }

    /// 二级工具栏尺寸：n 个 30pt 按钮、间距 8、容器内边距 6
    static func subToolbarSize(toolCount: Int) -> CGSize {
        guard toolCount > 0 else { return .zero }
        let count = CGFloat(toolCount)
        let width = FixedGeometry.subToolbarPadding * 2
            + count * FixedGeometry.subToolbarButtonSize
            + (count - 1) * FixedGeometry.subToolbarSpacing
        let height = FixedGeometry.subToolbarPadding * 2 + FixedGeometry.subToolbarButtonSize
        return CGSize(width: width, height: height)
    }

    // MARK: - 私有计算

    private struct ExpansionClampArgs {
        let availLeft: CGFloat
        let availRight: CGFloat
        let availTop: CGFloat
        let availBottom: CGFloat
        let mainSize: CGSize
        let finalMainOriginY: CGFloat
    }

    /// 展开层理想 frame（屏幕坐标）：锚定 + 挂载偏移，未做任何 clamp
    private static func idealFrame(_ expansion: Expansion,
                                   centerX: CGFloat,
                                   centerY: CGFloat,
                                   mainSize: CGSize) -> CGRect {
        let cx: CGFloat
        switch expansion.anchor {
        case .buttonCenter(let xInMain):
            cx = centerX - mainSize.width / 2 + xInMain
        case .mainTrailing:
            cx = centerX + mainSize.width / 2 - expansion.size.width / 2
        }
        let topY = centerY - mainSize.height / 2 + expansion.attachY
        return CGRect(x: cx - expansion.size.width / 2,
                      y: topY,
                      width: expansion.size.width,
                      height: expansion.size.height)
    }

    /// 展开层最终 frame：理想位叠加拖拽位移后，水平最小让位、垂直默认侧越界则翻转（仍越界则钳入屏内）
    private static func finalFrame(_ expansion: Expansion,
                                   centerX: CGFloat,
                                   centerY: CGFloat,
                                   displacement: CGPoint,
                                   args: ExpansionClampArgs) -> CGRect {
        let ideal = idealFrame(expansion, centerX: centerX, centerY: centerY, mainSize: args.mainSize)
            .offsetBy(dx: displacement.x, dy: displacement.y)
        let w = expansion.size.width
        let h = expansion.size.height

        let x = clamped(ideal.minX, args.availLeft, args.availRight - w)
        var y = ideal.minY
        // 翻转位必须完整落在可用区内（主栏被拖出屏时翻转位自身也可能越界），否则回退到屏内 clamp
        func flipFits(_ top: CGFloat) -> Bool {
            top >= args.availTop && top + h <= args.availBottom
        }
        if y < args.availTop {
            // 默认在上方且越上界 → 翻到主栏下方；翻转位也放不下 → 把原位钳入屏内
            let flippedTop = args.finalMainOriginY + args.mainSize.height + expansion.flipGap
            y = flipFits(flippedTop) ? flippedTop : clamped(y, args.availTop, args.availBottom - h)
        } else if y + h > args.availBottom {
            // 默认在下方且越下界 → 翻到主栏上方；翻转位也放不下 → 把原位钳入屏内
            let flippedTop = args.finalMainOriginY - expansion.flipGap - h
            y = flipFits(flippedTop) ? flippedTop : clamped(y, args.availTop, args.availBottom - h)
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// 区间放不下（lower > upper）时取中点，避免 min/max 反转产生越界值
    private static func clamped(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        if lower >= upper { return (lower + upper) / 2 }
        return min(max(value, lower), upper)
    }
}
