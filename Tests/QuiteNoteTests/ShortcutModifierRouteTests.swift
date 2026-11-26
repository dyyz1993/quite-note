import XCTest
import AppKit
@testable import QuiteNote

/// ⌥⌘ / ⌥⌘⇧ 修饰键路由的事件级单测（handleKeyEvent 修饰键分支必须全等匹配）
///
/// 背景：两个分支曾是 contains 写法，⌥⌘ 分支先命中把 ⌥⌘⇧* 吞掉——Carbon 全局
/// 热键正常时被系统先拦截无感，⌥⌘⇧R/⌥⌘⇧A 一旦注册失败走本地兜底，「强制居中」
/// 会错触发成「切换面板」、「批量提炼」错成「切换 AI」。
///
/// 实例不调用 start() / refresh()（那会走真实 Carbon 注册），只用合成 NSEvent
/// 直接驱动 handleKeyEvent(isGlobal: true)，不触达窗口、firstResponder 与存储。
@MainActor
final class ShortcutModifierRouteTests: XCTestCase {

    private var manager: KeyboardShortcutManager!
    private var counters: [String: Int] = [:]

    override func setUp() {
        super.setUp()
        TestStorageIsolation.activate
        manager = KeyboardShortcutManager()
        counters = [:]
        for key in ["togglePanel", "toggleAI", "forceCenter", "bulkSummarize", "capture", "stopRecording"] {
            counters[key] = 0
        }
        manager.onTogglePanel = { self.counters["togglePanel"]! += 1 }
        manager.onToggleAI = { self.counters["toggleAI"]! += 1 }
        manager.onForceCenter = { self.counters["forceCenter"]! += 1 }
        manager.onBulkSummarize = { self.counters["bulkSummarize"]! += 1 }
        manager.onCaptureClipboard = { self.counters["capture"]! += 1 }
        manager.onStopRecording = { self.counters["stopRecording"]! += 1 }
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    /// 合成 keyDown（handleKeyEvent 按 charactersIgnoringModifiers 匹配）
    private func keyDown(_ char: String, modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: char,
            charactersIgnoringModifiers: char,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    private func fire(_ char: String, modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> Bool {
        manager.handleKeyEvent(keyDown(char, modifiers: modifiers, keyCode: keyCode), isGlobal: true)
    }

    /// 回归主场景：⌥⌘⇧R 必须触发「强制居中」，而不是被 ⌥⌘ 分支吞成「切换面板」
    func testOptionCommandShiftR触发强制居中而非切换面板() {
        let consumed = fire("r", modifiers: [.command, .option, .shift], keyCode: 15)
        XCTAssertTrue(consumed, "⌥⌘⇧R 应被消费")
        XCTAssertEqual(counters["forceCenter"], 1)
        XCTAssertEqual(counters["togglePanel"], 0, "⌥⌘⇧R 不得落进 ⌥⌘R 的「切换面板」")
    }

    func testOptionCommandR仍是切换面板() {
        let consumed = fire("r", modifiers: [.command, .option], keyCode: 15)
        XCTAssertTrue(consumed)
        XCTAssertEqual(counters["togglePanel"], 1)
        XCTAssertEqual(counters["forceCenter"], 0, "⌥⌘R 不得触发强制居中")
    }

    /// 回归主场景：⌥⌘⇧A 必须触发「批量提炼」，而不是被 ⌥⌘ 分支吞成「切换 AI」
    func testOptionCommandShiftA触发批量提炼而非切换AI() {
        let consumed = fire("a", modifiers: [.command, .option, .shift], keyCode: 0)
        XCTAssertTrue(consumed)
        XCTAssertEqual(counters["bulkSummarize"], 1)
        XCTAssertEqual(counters["toggleAI"], 0, "⌥⌘⇧A 不得落进 ⌥⌘A 的「切换 AI」")
    }

    func testOptionCommandA仍是切换AI() {
        let consumed = fire("a", modifiers: [.command, .option], keyCode: 0)
        XCTAssertTrue(consumed)
        XCTAssertEqual(counters["toggleAI"], 1)
        XCTAssertEqual(counters["bulkSummarize"], 0)
    }

    /// ⌥⌘⇧ + 未注册字母（C/E 等）：全等匹配后不再被 ⌥⌘ 分支吞掉，事件放行
    func testOptionCommandShift未注册组合不消费() {
        XCTAssertFalse(fire("c", modifiers: [.command, .option, .shift], keyCode: 8), "⌥⌘⇧C 没有注册动作，不得吞键")
        XCTAssertEqual(counters["capture"], 0)
        XCTAssertFalse(fire("e", modifiers: [.command, .option, .shift], keyCode: 14))
    }

    /// ⌥⌘ 组合的其他动作不受影响（⌥⌘C 捕获 / ⌥⌘. 停止录屏）
    func testOptionCommand其余组合不受影响() {
        XCTAssertTrue(fire("c", modifiers: [.command, .option], keyCode: 8))
        XCTAssertEqual(counters["capture"], 1)
        XCTAssertTrue(fire(".", modifiers: [.command, .option], keyCode: 47))
        XCTAssertEqual(counters["stopRecording"], 1)
    }
}
