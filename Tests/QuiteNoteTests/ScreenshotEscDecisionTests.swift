import XCTest
import AppKit
@testable import QuiteNote

/// ESC 后退的阶段性决策测试（TDD，2026-08-18）
/// 场景来自用户报告：进入截图/框选后按 ESC"后退"有时无效、卡死在遮罩里。
/// 阶段决策必须满足：
/// 1. 有标注 → 双击 ESC 才退出（防误触），窗口 2 秒
/// 2. 无标注但有选区 → 第一次 ESC 只清选区（阶段后退），再按才退出
/// 3. 什么都没有 → 立即退出
@MainActor
final class ScreenshotEscDecisionTests: XCTestCase {

    private let now = Date()

    /// 刚进入截图、什么都没画：ESC 必须立即退出——"卡死在遮罩里"不可接受
    func testFreshEntryWithoutSelectionExitsImmediately() {
        XCTAssertEqual(
            V2ScreenshotController.escDecision(hasElements: false, lastEscPress: nil, now: now, hasSelection: false),
            .exitNow)
    }

    /// 框选之后（无标注）：第一次后退是清选区，不是退出
    func testSelectionStageStepsBackBeforeExit() {
        XCTAssertEqual(
            V2ScreenshotController.escDecision(hasElements: false, lastEscPress: nil, now: now, hasSelection: true),
            .clearSelection)
    }

    /// 有标注（防误触双击 ESC）：
    func testAnnotationsRequireDoublePressWithinWindow() {
        // 第一次按：武装双击确认，不退出
        XCTAssertEqual(
            V2ScreenshotController.escDecision(hasElements: true, lastEscPress: nil, now: now, hasSelection: true),
            .requireDoublePress)
        // 2 秒内第二次：退出
        XCTAssertEqual(
            V2ScreenshotController.escDecision(hasElements: true, lastEscPress: now.addingTimeInterval(-1.5), now: now, hasSelection: true),
            .exitNow)
        // 超过 2 秒的"第二次"：视为新的第一次，重新武装
        XCTAssertEqual(
            V2ScreenshotController.escDecision(hasElements: true, lastEscPress: now.addingTimeInterval(-2.5), now: now, hasSelection: true),
            .requireDoublePress)
    }

    /// 有标注 + 有选区：标注优先（双击确认），不能被选区分支截胡
    func testElementsTakePrecedenceOverSelection() {
        XCTAssertEqual(
            V2ScreenshotController.escDecision(hasElements: true, lastEscPress: nil, now: now, hasSelection: true),
            .requireDoublePress)
        XCTAssertEqual(
            V2ScreenshotController.escDecision(hasElements: true, lastEscPress: now.addingTimeInterval(-1.0), now: now, hasSelection: true),
            .exitNow)
    }
}
