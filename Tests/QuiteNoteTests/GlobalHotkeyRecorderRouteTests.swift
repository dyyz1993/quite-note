import XCTest
import AppKit
@testable import QuiteNote

/// 录制快捷键期间的热键路由 + 空格探针
///
/// 路由：Carbon 触发已注册热键时路由给录制器而非执行原动作（Carbon 在输入法之前
/// 拦截，⌥空格 可原样重录）。探针：录制期间额外注册「空格×修饰键」组合，
/// 保证**未注册状态**（如清除后重录）下 ⌥空格 不被搜狗/系统吃掉、始终可采。
final class GlobalHotkeyRecorderRouteTests: XCTestCase {

    func test录制态热键路由到录制器而不执行原动作() throws {
        let manager = GlobalHotkeyManager.shared
        var actionRan = false
        guard manager.register(key: " ", modifiers: [.option], id: 4001, handler: { actionRan = true }) else {
            throw XCTSkip("测试环境无法注册 Carbon 热键，跳过")
        }
        defer { manager.unregister(id: 4001) }

        // 录制态：触发热键 → 捕获 (key, modifiers)，原动作不执行
        var captured: (String, NSEvent.ModifierFlags)?
        manager.recorderCaptureHandler = { key, mods in captured = (key, mods) }
        manager.dispatchHotkey(manager.hotkeyInfo(forTestID: 4001)!)
        XCTAssertEqual(captured?.0, " ")
        XCTAssertEqual(captured?.1, [.option])
        XCTAssertFalse(actionRan, "录制态下原动作不得执行")

        // 非录制态：触发热键 → 正常执行原动作
        manager.recorderCaptureHandler = nil
        manager.dispatchHotkey(manager.hotkeyInfo(forTestID: 4001)!)
        XCTAssertTrue(actionRan)
    }

    func test探针注册与注销闭环() throws {
        let manager = GlobalHotkeyManager.shared
        let baseline = manager.registeredCount

        manager.beginRecordingCapture { _, _ in }
        XCTAssertTrue(manager.isRecordingCaptureActive)
        // 15 个空格×修饰键组合中至少大部分应注册成功（⌘空格 可能被 Spotlight 占用）
        let probeCount = manager.registeredCount - baseline
        XCTAssertGreaterThanOrEqual(probeCount, 10, "空格探针注册数异常")

        manager.endRecordingCapture()
        XCTAssertFalse(manager.isRecordingCaptureActive)
        XCTAssertEqual(manager.registeredCount, baseline, "结束后探针必须全部注销")
    }

    func test探针态下refresh守卫生效() throws {
        let manager = GlobalHotkeyManager.shared
        let baseline = manager.registeredCount

        manager.beginRecordingCapture { _, _ in }
        // 探针态下 refresh 不得注销/重注册任何热键（避免按键落进重注册空窗）
        KeyboardShortcutManager().refresh()
        XCTAssertEqual(manager.registeredCount - baseline, manager.probeCountForTest)

        manager.endRecordingCapture()
        XCTAssertEqual(manager.registeredCount, baseline)
    }
}
