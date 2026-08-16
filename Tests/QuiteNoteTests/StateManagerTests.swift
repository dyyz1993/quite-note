import XCTest
import AppKit
@testable import QuiteNote

/// 截图状态管理器的交互逻辑测试（undo、reset、序号分配、尺寸档位）
@MainActor
final class StateManagerTests: XCTestCase {

    private var manager: V2PrimaryScreenStateManager {
        V2PrimaryScreenStateManager.shared
    }

    override func setUp() {
        super.setUp()
        manager.reset()
    }

    /// 撤销最后一个元素后，选中态不能悬空指向已删除的元素
    /// （悬空会导致颜色/线宽同步、尺寸调节静默失效等交互怪象）
    func testUndoLastElementClearsDanglingSelection() {
        let element = DrawingElement(tool: .pen, points: [CGPoint(x: 0, y: 0)], color: .red, lineWidth: 4)
        manager.addElement(element) // addElement 会自动选中
        XCTAssertEqual(manager.selectedElementId, element.id)

        manager.undoLastElement()

        XCTAssertTrue(manager.elements.isEmpty)
        XCTAssertNil(manager.selectedElementId, "撤销被选中的元素后 selectedElementId 应清空，不能悬空")
    }

    /// reset 必须清掉 Toast，否则上一次会话的提示会残留到下一次截图
    func testResetClearsToast() {
        manager.postToast("再按一次退出", type: "info")
        XCTAssertNotNil(manager.toastMessage)

        manager.reset()

        XCTAssertNil(manager.toastMessage, "reset 应清除 toastMessage，避免跨截图会话的残留提示")
    }

    /// 步骤序号分配：空缺补齐（回归测试，记录现有正确行为）
    func testNextStepNumberFillsGap() {
        // 空 → 1
        XCTAssertEqual(manager.getNextStepNumber(), 1)

        // {1, 3} → 补齐 2
        manager.elements = [
            DrawingElement(tool: .steps, points: [CGPoint(x: 0, y: 0)], color: .red, lineWidth: 4, stepNumber: 1),
            DrawingElement(tool: .steps, points: [CGPoint(x: 0, y: 0)], color: .red, lineWidth: 4, stepNumber: 3)
        ]
        XCTAssertEqual(manager.getNextStepNumber(), 2)

        // {1, 2} → 3
        manager.elements = [
            DrawingElement(tool: .steps, points: [CGPoint(x: 0, y: 0)], color: .red, lineWidth: 4, stepNumber: 1),
            DrawingElement(tool: .steps, points: [CGPoint(x: 0, y: 0)], color: .red, lineWidth: 4, stepNumber: 2)
        ]
        XCTAssertEqual(manager.getNextStepNumber(), 3)
    }

    /// 尺寸档位越界时必须收敛到最小/最大档，不能数组越界崩溃
    /// （注意：此测试在修复前会触发 index out of range 崩溃，故命名排序到最后执行）
    func testZUpdateElementSizeClampsOutOfRangeLevel() {
        let element = DrawingElement(tool: .text, points: [CGPoint(x: 0, y: 0)], color: .red, lineWidth: 4, text: "测试")
        manager.elements = [element]

        // level 0 → 收敛到最小档 16（现状：sizes[-1] 直接崩溃）
        manager.updateElementSize(element.id, level: 0)
        XCTAssertEqual(manager.elements[0].fontSize, 16)

        // level 4 → 收敛到最大档 36（现状：sizes[3] 越界崩溃）
        manager.updateElementSize(element.id, level: 4)
        XCTAssertEqual(manager.elements[0].fontSize, 36)

        // 正常档位不受影响
        manager.updateElementSize(element.id, level: 2)
        XCTAssertEqual(manager.elements[0].fontSize, 24)
    }
}
