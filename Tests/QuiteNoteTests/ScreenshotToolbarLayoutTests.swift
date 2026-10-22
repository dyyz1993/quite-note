import XCTest
@testable import QuiteNote

/// 截图工具栏纯函数布局单测：钉死三条产品约束——
/// ① 主栏（含动态变宽）+ 展开层 union 不出屏；
/// ② 二级工具栏默认中心对齐被点击的一级按钮，边界冲突时整体最小让位（锚定关系保持）；
/// ③ 音频弹层右对齐主栏 + 底部选区/贴底时翻转到主栏上方，全程不出屏。
final class ScreenshotToolbarLayoutTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let mainSize = CGSize(width: 520, height: 66)
    private let subSize = CGSize(width: 156, height: 42) // effect 组 4 个二级工具
    private let audioSize = CGSize(width: 240, height: 320)
    private let margin: CGFloat = 8
    private let spacing: CGFloat = 12

    // MARK: - 无边界冲突：锚定即所得

    func testNoEdgeConflict_SubToolbarCentersOnPrimaryButton() {
        let selection = CGRect(x: 600, y: 300, width: 240, height: 200)
        let out = compute(selection: selection, specs: specs(subAnchorIndex: 3))

        // 主栏：选区下方居中（既有行为不变）
        XCTAssertEqual(out.mainCenter.x, selection.midX, accuracy: 0.01)
        XCTAssertEqual(out.mainCenter.y, selection.maxY + spacing + mainSize.height / 2, accuracy: 0.01)

        // 二级工具栏中心 == 被点击一级按钮中心（主栏局部坐标）
        let frame = unwrap(out.subToolbarFrameInMain)
        XCTAssertEqual(frame.midX, anchorX(3), accuracy: 0.01)
        XCTAssertEqual(frame.minY, ScreenshotToolbarLayout.FixedGeometry.subToolbarAttachY, accuracy: 0.01)
    }

    func testNoExpansion_PreservesLegacyPositioning() {
        let selection = CGRect(x: 200, y: 120, width: 300, height: 160)
        let out = compute(selection: selection, specs: .none)

        XCTAssertEqual(out.mainCenter.x, selection.midX, accuracy: 0.01)
        XCTAssertEqual(out.mainCenter.y, selection.maxY + spacing + mainSize.height / 2, accuracy: 0.01)
        XCTAssertNil(out.subToolbarFrameInMain)
        XCTAssertNil(out.audioPickerFrameInMain)
    }

    // MARK: - 左边缘：union 整体右移，偏移最小、锚定保持

    func testLeftEdge_UnionShiftsRightMinimallyAndKeepsAnchor() {
        // 选区贴左：主栏自身已被钳到左界（mainLeft = 8）
        let selection = CGRect(x: 10, y: 100, width: 60, height: 60)
        let out = compute(selection: selection, specs: specs(subAnchorIndex: 0))

        // 未展开时主栏中心 = 8 + 260 = 268；展开后按 union 越界量(29)整体右移到 305
        XCTAssertEqual(out.mainCenter.x, 305, accuracy: 0.01)

        // 二级工具栏：锚定关系保持（局部中心 == 一级按钮中心）
        let frame = unwrap(out.subToolbarFrameInMain)
        XCTAssertEqual(frame.midX, anchorX(0), accuracy: 0.01)

        // 屏幕空间：左缘恰好贴住可用左界（8），不多让 1pt —— 偏移最小
        let subScreen = screenFrame(of: frame, mainCenter: out.mainCenter)
        XCTAssertEqual(subScreen.minX, screen.minX + margin, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(subScreen.maxX, subScreen.minX)
        XCTAssertTrue(withinScreen(subScreen))
        XCTAssertTrue(withinScreen(mainFrame(mainCenter: out.mainCenter)))
    }

    // MARK: - 右边缘：主栏变宽后整体左移，最右按钮完整可见

    func testRightEdge_WidenedMainShiftsLeft_RightmostButtonFullyVisible() {
        // 选区贴右：未变宽(520)时主栏钳在右界，中心 1172
        let selection = CGRect(x: 1380, y: 100, width: 40, height: 60)
        let widened = CGSize(width: 650, height: 66)

        let out = compute(selection: selection, mainSize: widened, specs: specs(subAnchorIndex: 5))

        // 变宽(650)后钳位右移到 1107 —— 相对旧中心 1172 整体左移 65，右缘仍完整可见
        XCTAssertEqual(out.mainCenter.x, 1107, accuracy: 0.01)
        let main = mainFrame(mainCenter: out.mainCenter, size: widened)
        XCTAssertEqual(main.maxX, screen.maxX - margin, accuracy: 0.01)
        XCTAssertTrue(withinScreen(main))

        // 二级工具栏锚定不破坏且不出屏
        let frame = unwrap(out.subToolbarFrameInMain)
        XCTAssertEqual(frame.midX, anchorX(5), accuracy: 0.01)
        XCTAssertTrue(withinScreen(screenFrame(of: frame, mainCenter: out.mainCenter, size: widened)))
    }

    func testRightEdge_UnionOverflowShiftsWholeAssemblyLeft() {
        // 窄屏 + 靠右锚点（合成场景：锚点位于主栏右侧的展开层越右界）
        let narrowScreen = CGRect(x: 0, y: 0, width: 800, height: 600)
        let selection = CGRect(x: 700, y: 80, width: 60, height: 60)
        let synthetic = ScreenshotToolbarLayout.Expansion(
            size: CGSize(width: 200, height: 42),
            anchor: .buttonCenter(xInMain: 500),
            attachY: ScreenshotToolbarLayout.FixedGeometry.subToolbarAttachY)

        let out = ScreenshotToolbarLayout.compute(.init(
            screen: narrowScreen, selection: selection, mainSize: mainSize,
            specs: .init(subToolbar: synthetic, audioPicker: nil),
            margin: margin, spacing: spacing))

        // 未展开时中心钳在 532；展开层右缘越界 80 → 整体左移 80（锚定保持），主栏仍在自身合法区间
        XCTAssertEqual(out.mainCenter.x, 452, accuracy: 0.01)
        let frame = unwrap(out.subToolbarFrameInMain)
        XCTAssertEqual(frame.midX, 500, accuracy: 0.01)

        let subScreen = screenFrame(of: frame, mainCenter: out.mainCenter)
        XCTAssertEqual(subScreen.maxX, narrowScreen.maxX - margin, accuracy: 0.01)
        XCTAssertTrue(withinScreen(subScreen, screen: narrowScreen))
        XCTAssertTrue(withinScreen(mainFrame(mainCenter: out.mainCenter), screen: narrowScreen))
    }

    // MARK: - 音频弹层：右对齐 + 贴底翻转

    func testAudioPicker_RightAlignedBelowToolbar() {
        let selection = CGRect(x: 600, y: 100, width: 240, height: 150)
        let out = compute(selection: selection, specs: specs(audio: true))

        // 右对齐主栏右缘、悬浮主栏下方（沿表现状挂载位）
        let frame = unwrap(out.audioPickerFrameInMain)
        XCTAssertEqual(frame.midX, mainSize.width - audioSize.width / 2, accuracy: 0.01)
        XCTAssertEqual(frame.minY, ScreenshotToolbarLayout.FixedGeometry.audioPickerAttachY, accuracy: 0.01)
        XCTAssertTrue(withinScreen(screenFrame(of: frame, mainCenter: out.mainCenter)))
    }

    func testFullScreenSelection_AudioPickerFlipsAboveWhenPinnedToBottom() {
        // 全屏选区：下方/上方都放不下 → 主栏贴底，音频弹层默认下方必越下界 → 翻到主栏上方
        let selection = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let out = compute(selection: selection, specs: specs(audio: true))

        // 主栏贴底（既有行为）
        XCTAssertEqual(out.mainCenter.y, screen.maxY - margin - mainSize.height / 2, accuracy: 0.01)

        // 弹层翻转到主栏上方：局部顶边 = -(高度 + 翻转间隙)
        let frame = unwrap(out.audioPickerFrameInMain)
        XCTAssertEqual(frame.minY, -(audioSize.height + ScreenshotToolbarLayout.FixedGeometry.flipGap), accuracy: 0.01)
        XCTAssertTrue(withinScreen(screenFrame(of: frame, mainCenter: out.mainCenter)))
    }

    // MARK: - 底部选区：主栏上移，展开层也不越界

    func testBottomSelection_MainMovesAboveAndExpansionsStayOnScreen() {
        // 选区贴底：下方放不下 → 主栏移到选区上方
        let selection = CGRect(x: 620, y: 830, width: 200, height: 60)
        let out = compute(selection: selection, specs: specs(subAnchorIndex: 5, audio: true))

        XCTAssertEqual(out.mainCenter.y, selection.minY - spacing - mainSize.height / 2, accuracy: 0.01)

        // 二级工具栏（默认上方）锚定保持且不出屏
        let sub = unwrap(out.subToolbarFrameInMain)
        XCTAssertEqual(sub.midX, anchorX(5), accuracy: 0.01)
        XCTAssertTrue(withinScreen(screenFrame(of: sub, mainCenter: out.mainCenter)))

        // 音频弹层（默认下方）越下界 → 翻到主栏上方，不出屏
        let audio = unwrap(out.audioPickerFrameInMain)
        XCTAssertEqual(audio.minY, -(audioSize.height + ScreenshotToolbarLayout.FixedGeometry.flipGap), accuracy: 0.01)
        XCTAssertTrue(withinScreen(screenFrame(of: audio, mainCenter: out.mainCenter)))
    }

    // MARK: - 极端兜底

    func testMainWiderThanScreen_SubToolbarStillClampedOnScreen() {
        // 主栏比屏幕还宽（理论极端）：主栏居中尽力而为，二级工具栏仍完整在屏内
        let huge = CGSize(width: 1500, height: 66)
        let selection = CGRect(x: 640, y: 300, width: 160, height: 120)
        let out = compute(selection: selection, mainSize: huge, specs: specs(subAnchorIndex: 0))

        XCTAssertEqual(out.mainCenter.x, screen.midX, accuracy: 0.01)
        let sub = unwrap(out.subToolbarFrameInMain)
        let subScreen = screenFrame(of: sub, mainCenter: out.mainCenter, size: huge)
        XCTAssertEqual(subScreen.minX, screen.minX + margin, accuracy: 0.01)
        XCTAssertTrue(withinScreen(subScreen))
    }

    /// 底部被 Dock 占据时，贴底定位的工具栏必须整体抬到 Dock 之上（2026-10-22 实拍回归）
    func testBottomInset_LiftsToolbarAboveDock() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        // 选区贴底 -> 主栏贴底
        let selection = CGRect(x: 600, y: 820, width: 200, height: 60)
        let mainSize = CGSize(width: 520, height: 66)
        let dockInset: CGFloat = 78  // Dock 高度

        let withoutInset = ScreenshotToolbarLayout.compute(.init(
            screen: screen, selection: selection, mainSize: mainSize, specs: .none,
            margin: 8, spacing: 12))
        let withInset = ScreenshotToolbarLayout.compute(.init(
            screen: screen, selection: selection, mainSize: mainSize, specs: .none,
            margin: 8, spacing: 12, bottomInset: dockInset))

        // 两种口径下工具栏底边都不得进入 Dock 区域（屏幕底往上 dockInset）
        let dockTop = screen.maxY - dockInset
        XCTAssertLessThanOrEqual(withoutInset.mainCenter.y + mainSize.height / 2, dockTop + 0.01,
                                 "无 inset 时工具栏不应沉进 Dock")
        XCTAssertLessThanOrEqual(withInset.mainCenter.y + mainSize.height / 2, dockTop - 8 + 0.01,
                                 "有 inset 时工具栏应整体抬到 Dock 之上")
    }

    /// 实拍回归：选区在 Dock 附近（下方无空间），工具栏必须整体在 Dock 之上
    func testSelectionJustAboveDock_ToolbarStaysAboveDock() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let dockTop: CGFloat = 822           // Dock 顶
        let selection = CGRect(x: 600, y: dockTop - 40, width: 200, height: 30)  // 选区紧贴 Dock 上方
        let mainSize = CGSize(width: 520, height: 66)
        let out = ScreenshotToolbarLayout.compute(.init(
            screen: screen, selection: selection, mainSize: mainSize, specs: .none,
            margin: 8, spacing: 12, bottomInset: 900 - dockTop))
        XCTAssertLessThanOrEqual(out.mainCenter.y + mainSize.height / 2, dockTop,
                                 "底部选区时工具栏不得进入 Dock 区域")
    }

    /// 顶部被菜单栏占据时，贴顶定位的工具栏必须整体下移
    func testTopInset_LowersToolbarBelowMenuBar() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let selection = CGRect(x: 600, y: 4, width: 200, height: 40)  // 贴顶
        let mainSize = CGSize(width: 520, height: 66)
        let menuBar: CGFloat = 25

        let withInset = ScreenshotToolbarLayout.compute(.init(
            screen: screen, selection: selection, mainSize: mainSize, specs: .none,
            margin: 8, spacing: 12, topInset: menuBar))
        XCTAssertGreaterThanOrEqual(withInset.mainCenter.y - mainSize.height / 2, menuBar + 8 - 0.01)
    }

    // MARK: - 确定性推导

    func testPrimaryButtonCenterXDerivation() {
        // 24(12 外边距 + 8 内容边距 + 4 组内边距) + i*38 + 17
        XCTAssertEqual(ScreenshotToolbarLayout.primaryButtonCenterX(groupIndex: 0), 41, accuracy: 0.01)
        XCTAssertEqual(ScreenshotToolbarLayout.primaryButtonCenterX(groupIndex: 1), 79, accuracy: 0.01)
        XCTAssertEqual(ScreenshotToolbarLayout.primaryButtonCenterX(groupIndex: 5), 231, accuracy: 0.01)
    }

    func testSubToolbarSizeDerivation() {
        XCTAssertEqual(ScreenshotToolbarLayout.subToolbarSize(toolCount: 0), .zero)
        // 4*2 内边距 + n*30 按钮 + (n-1)*4 间距
        XCTAssertEqual(ScreenshotToolbarLayout.subToolbarSize(toolCount: 2), CGSize(width: 72, height: 38))
        XCTAssertEqual(ScreenshotToolbarLayout.subToolbarSize(toolCount: 4), CGSize(width: 140, height: 38))
    }

    // MARK: - 辅助

    private func anchorX(_ index: Int) -> CGFloat {
        ScreenshotToolbarLayout.primaryButtonCenterX(groupIndex: index)
    }

    private func specs(subAnchorIndex index: Int? = nil, audio: Bool = false)
        -> ScreenshotToolbarLayout.Specs {
        let sub = index.map {
            ScreenshotToolbarLayout.Expansion(
                size: subSize,
                anchor: .buttonCenter(xInMain: anchorX($0)),
                attachY: ScreenshotToolbarLayout.FixedGeometry.subToolbarAttachY)
        }
        let picker = audio
            ? ScreenshotToolbarLayout.Expansion(
                size: audioSize,
                anchor: .mainTrailing,
                attachY: ScreenshotToolbarLayout.FixedGeometry.audioPickerAttachY)
            : nil
        return .init(subToolbar: sub, audioPicker: picker)
    }

    private func compute(selection: CGRect,
                         mainSize: CGSize? = nil,
                         specs: ScreenshotToolbarLayout.Specs) -> ScreenshotToolbarLayout.Output {
        ScreenshotToolbarLayout.compute(.init(
            screen: screen, selection: selection, mainSize: mainSize ?? self.mainSize,
            specs: specs, margin: margin, spacing: spacing))
    }

    private func mainFrame(mainCenter: CGPoint, size: CGSize? = nil) -> CGRect {
        let s = size ?? mainSize
        return CGRect(x: mainCenter.x - s.width / 2, y: mainCenter.y - s.height / 2,
                      width: s.width, height: s.height)
    }

    /// 主栏局部 frame → 屏幕空间
    private func screenFrame(of local: CGRect, mainCenter: CGPoint, size: CGSize? = nil) -> CGRect {
        let main = mainFrame(mainCenter: mainCenter, size: size)
        return local.offsetBy(dx: main.minX, dy: main.minY)
    }

    private func withinScreen(_ frame: CGRect, screen: CGRect? = nil) -> Bool {
        let scr = screen ?? self.screen
        return frame.minX >= scr.minX + margin - 0.01
            && frame.maxX <= scr.maxX - margin + 0.01
            && frame.minY >= scr.minY + margin - 0.01
            && frame.maxY <= scr.maxY - margin + 0.01
    }

    private func unwrap(_ frame: CGRect?) -> CGRect {
        guard let frame else {
            XCTFail("展开层 frame 不应为 nil")
            return .zero
        }
        return frame
    }
}

// MARK: - 性质测试与回归等价（任意输入下的不变式，比手挑用例更强的数学保证）

extension ScreenshotToolbarLayoutTests {

    /// 不变式 1（出屏）：任意随机输入（含 ±300 拖拽位移）下，主栏基准位与全部展开层
    /// （自身不超可用宽度时）永远在屏幕 margin 内——拖拽可把主栏拖出屏（沿表现状），
    /// 但展开层被 clamp 在屏内
    func testProperty_NeverOffScreen() {
        var rng = Lcg(seed: 20261021)
        for _ in 0..<500 {
            let scr = randomScreen(&rng)
            let mainW = rng.uniform(300...900)
            let mainH = rng.uniform(50...80)
            let selection = randomSelection(&rng, in: scr)
            let specs = randomSpecs(&rng, mainWidth: mainW)
            let displacement = CGPoint(x: rng.uniform(-300...300), y: rng.uniform(-300...300))
            let out = ScreenshotToolbarLayout.compute(.init(
                screen: scr, selection: selection,
                mainSize: CGSize(width: mainW, height: mainH),
                specs: specs, margin: 8, spacing: 12,
                mainDisplacement: displacement))

            let availW = scr.width - 16
            if mainW <= availW {
                let main = CGRect(x: out.mainCenter.x - mainW / 2, y: out.mainCenter.y - mainH / 2,
                                  width: mainW, height: mainH)
                XCTAssertTrue(withinScreen(main, screen: scr), "主栏出屏: \(describe(scr, selection, mainW, specs))")
            }
            // 展开层的局部原点 = 含位移的最终主栏位（渲染时挂在被拖拽的主栏内部）
            let origin = CGPoint(x: out.mainCenter.x + displacement.x - mainW / 2,
                                 y: out.mainCenter.y + displacement.y - mainH / 2)
            for (name, frame) in [("二级", out.subToolbarFrameInMain), ("音频", out.audioPickerFrameInMain)] {
                guard let f = frame, f.width <= availW, f.height <= scr.height - 16 else { continue }
                let onScreen = f.offsetBy(dx: origin.x, dy: origin.y)
                XCTAssertTrue(withinScreen(onScreen, screen: scr),
                              "\(name)弹层出屏: \(describe(scr, selection, mainW, specs)) " +
                              "mainH=\(mainH) mainCenter=\(out.mainCenter) disp=\(displacement) " +
                              "local=\(f) 重建origin=\(origin) 屏幕frame=\(onScreen)")
            }
        }
    }

    /// 不变式 2（锚定最小让位）：二级工具栏屏幕中心要么恰好 == 锚定按钮中心（无冲突），
    /// 要么恰好贴住左/右可用边界（冲突时的最小补偿，没有第三种状态）
    func testProperty_AnchorExactOrEdgePinned() {
        var rng = Lcg(seed: 8036)
        for _ in 0..<500 {
            let scr = CGRect(x: 0, y: 0, width: rng.uniform(800...2560), height: rng.uniform(600...1440))
            let mainW = rng.uniform(300...900)
            let mainH = rng.uniform(50...80)
            let xInMain = rng.uniform(0...mainW)
            let subW = ScreenshotToolbarLayout.subToolbarSize(toolCount: 4).width
            guard subW <= scr.width - 16 else { continue }
            let selection = randomSelection(&rng, in: scr)
            let out = ScreenshotToolbarLayout.compute(.init(
                screen: scr, selection: selection,
                mainSize: CGSize(width: mainW, height: mainH),
                specs: .init(subToolbar: .init(
                    size: .init(width: subW, height: 42),
                    anchor: .buttonCenter(xInMain: xInMain),
                    attachY: ScreenshotToolbarLayout.FixedGeometry.subToolbarAttachY), audioPicker: nil),
                margin: 8, spacing: 12))

            let mainOriginX = out.mainCenter.x - mainW / 2
            guard let sub = out.subToolbarFrameInMain else {
                XCTFail("二级工具栏 frame 缺失"); continue
            }
            let onScreen = sub.offsetBy(dx: mainOriginX, dy: 0)
            let anchored = abs(onScreen.midX - (mainOriginX + xInMain)) < 0.01
            let pinnedLeft = abs(onScreen.minX - (scr.minX + 8)) < 0.01
            let pinnedRight = abs(onScreen.maxX - (scr.maxX - 8)) < 0.01
            XCTAssertTrue(anchored || pinnedLeft || pinnedRight,
                          "既不锚定也不贴边: \(describe(scr, selection, mainW, .none)) xInMain=\(xInMain) 实际midX=\(onScreen.midX)")
        }
    }

    /// 不变式 3（新旧等价，回归保护）：specs = .none 时输出必须与回滚前的旧 clampedPosition
    /// 公式逐位一致——不展开任何弹层时行为零变化，把"修 A 坏 B"的风险隔离在展开态
    func testProperty_LegacyEquivalenceWhenNoExpansion() {
        var rng = Lcg(seed: 2114)
        for _ in 0..<400 {
            let scr = CGRect(x: 0, y: 0, width: rng.uniform(800...2560), height: rng.uniform(600...1440))
            let mainW = rng.uniform(300...900)
            let mainH = rng.uniform(50...80)
            // 主栏超宽时旧公式 min/max 顺序未定义良好，等价性只覆盖正常宽域
            guard mainW <= scr.width - 16 else { continue }
            let selection = randomSelection(&rng, in: scr)
            let size = CGSize(width: mainW, height: mainH)
            let out = ScreenshotToolbarLayout.compute(.init(
                screen: scr, selection: selection, mainSize: size, specs: .none, margin: 8, spacing: 12))
            let legacy = legacyClampedPosition(selection: selection, size: size, screen: scr, margin: 8, spacing: 12)
            XCTAssertEqual(out.mainCenter.x, legacy.x, accuracy: 0.01,
                           "X 不等价: \(describe(scr, selection, mainW, .none))")
            XCTAssertEqual(out.mainCenter.y, legacy.y, accuracy: 0.01,
                           "Y 不等价: \(describe(scr, selection, mainW, .none))")
        }
    }

    // MARK: 性质测试辅助

    /// 确定性线性同余随机数：失败时种子固定、输入可复现
    struct Lcg {
        var seed: UInt64
        mutating func next() -> UInt64 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return seed
        }
        mutating func uniform(_ range: ClosedRange<CGFloat>) -> CGFloat {
            let r = CGFloat(Double(next() % 1_000_000) / 1_000_000)
            return range.lowerBound + r * (range.upperBound - range.lowerBound)
        }
    }

    private func randomScreen(_ rng: inout Lcg) -> CGRect {
        CGRect(x: 0, y: 0, width: rng.uniform(800...2560), height: rng.uniform(600...1440))
    }

    private func randomSelection(_ rng: inout Lcg, in scr: CGRect) -> CGRect {
        let w = rng.uniform(40...max(60, scr.width * 0.9))
        let h = rng.uniform(30...max(50, scr.height * 0.9))
        return CGRect(x: rng.uniform(0...max(1, scr.width - w)),
                      y: rng.uniform(0...max(1, scr.height - h)), width: w, height: h)
    }

    private func randomSpecs(_ rng: inout Lcg, mainWidth: CGFloat) -> ScreenshotToolbarLayout.Specs {
        let sub = rng.next() % 2 == 0 ? ScreenshotToolbarLayout.Expansion(
            size: ScreenshotToolbarLayout.subToolbarSize(toolCount: 2 + Int(rng.next() % 3)),
            anchor: .buttonCenter(xInMain: rng.uniform(0...mainWidth)),
            attachY: ScreenshotToolbarLayout.FixedGeometry.subToolbarAttachY) : nil
        let audio = rng.next() % 2 == 0 ? ScreenshotToolbarLayout.Expansion(
            size: CGSize(width: 240, height: rng.uniform(200...500)),
            anchor: .mainTrailing,
            attachY: ScreenshotToolbarLayout.FixedGeometry.audioPickerAttachY) : nil
        return .init(subToolbar: sub, audioPicker: audio)
    }

    private func describe(_ scr: CGRect, _ sel: CGRect, _ mainW: CGFloat,
                          _ specs: ScreenshotToolbarLayout.Specs) -> String {
        "screen=\(scr) sel=\(sel) mainW=\(mainW) sub=\(specs.subToolbar != nil) audio=\(specs.audioPicker != nil)"
    }

    /// 回滚前 V2FloatingToolbar.clampedPosition 的原式（照抄 8036fde 版本数学，作等价基准）
    private func legacyClampedPosition(selection: CGRect, size: CGSize,
                                       screen: CGRect, margin: CGFloat, spacing: CGFloat) -> CGPoint {
        let halfW = size.width / 2
        let halfH = size.height / 2
        let x = max(halfW + margin, min(screen.width - halfW - margin, selection.midX))
        let belowY = selection.maxY + spacing + halfH
        if belowY + halfH < screen.height - margin {
            return CGPoint(x: x, y: belowY)
        }
        let aboveY = selection.minY - spacing - halfH
        if aboveY - halfH > margin {
            return CGPoint(x: x, y: aboveY)
        }
        return CGPoint(x: x, y: screen.height - halfH - margin)
    }
}
