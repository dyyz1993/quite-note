import XCTest
@testable import QuiteNote
import AppKit

/// Carbon 全局兜底热键规格（ClipboardGlobalFallback）——面板可见但非 key 的
/// 窗口期键盘可靠性就靠这组注册，分层语义（⌘ 常驻 / 裸导航仅未 key 时）必须钉死
final class ClipboardGlobalFallbackTests: XCTestCase {
    func testKey状态_始终注册命令组合() {
        let specs = ClipboardGlobalFallback.specs(panelIsKey: true)
        // ⌘1–9 + ⌘S/⌘P/⌘F = 12 条
        XCTAssertEqual(specs.count, 12)
        XCTAssertTrue(specs.allSatisfy { $0.modifiers == .command })
        let actions = specs.map(\.action)
        (1...9).forEach { n in
            XCTAssertTrue(actions.contains(.pasteIndex(n)), "⌘\(n) 缺失")
        }
        XCTAssertTrue(actions.contains(.saveToFlash))
        XCTAssertTrue(actions.contains(.togglePin))
        XCTAssertTrue(actions.contains(.focusSearch))
    }

    func test非Key状态_额外注册裸导航键() {
        let keySpecs = ClipboardGlobalFallback.specs(panelIsKey: true)
        let nonKeySpecs = ClipboardGlobalFallback.specs(panelIsKey: false)
        // 12 条命令 + ↑/↓/回车/Tab/⇧Tab/←/→ = 19 条
        XCTAssertEqual(nonKeySpecs.count, keySpecs.count + 7)
        let nav = ClipboardGlobalFallback.navigationSpecs
        XCTAssertEqual(nav.map(\.action), [
            .moveUp, .moveDown, .pasteSelected, .switchFilterRight, .switchFilterLeft,
            .switchFilterLeft, .switchFilterRight,   // ←/→（2026-11-20 用户要求键盘左右切 tab）
        ])
        // 裸导航键必须无修饰键（有修饰键会误伤系统组合）
        XCTAssertTrue(nav.allSatisfy { $0.modifiers.isEmpty || $0.modifiers == .shift })
    }

    func test全部id唯一且在注销清单内() {
        let all = ClipboardGlobalFallback.specs(panelIsKey: false)
        let ids = all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "id 冲突会互相顶掉注册")
        // allIDs 必须覆盖两档全部 id（hide() 靠它兜底注销干净）
        XCTAssertTrue(ids.allSatisfy { ClipboardGlobalFallback.allIDs().contains($0) })
    }

    func test命令数字键与动作一一对应() {
        let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
        for spec in ClipboardGlobalFallback.commandSpecs {
            if case .pasteIndex(let n) = spec.action {
                XCTAssertEqual(spec.key, digits[n - 1], "⌘\(n) 的键名必须对应数字键")
            }
        }
    }
}
