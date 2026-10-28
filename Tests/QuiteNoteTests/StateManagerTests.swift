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

    /// 文字输入结束（失焦/点击其他区域）后，非空文本应保持选中并切到箭头工具。
    func testFinishTextEditingKeepsElementSelectedAndSwitchesToCursor() {
        let element = DrawingElement(
            tool: .text,
            points: [CGPoint(x: 20, y: 30)],
            color: .red,
            lineWidth: 4,
            text: "标注文字"
        )
        manager.elements = [element]
        manager.selectedTool = .text
        manager.selectedElementId = element.id

        manager.finishEditingTextElement(id: element.id)

        XCTAssertEqual(manager.selectedTool, .cursor)
        XCTAssertEqual(manager.selectedElementId, element.id)
        XCTAssertEqual(manager.elements.count, 1)
    }

    /// 空文本结束编辑时应删除，不留下一个不可见的选中元素。
    func testFinishEmptyTextEditingRemovesElementAndClearsSelection() {
        let element = DrawingElement(
            tool: .text,
            points: [CGPoint(x: 20, y: 30)],
            color: .red,
            lineWidth: 4,
            text: "   \n"
        )
        manager.elements = [element]
        manager.selectedTool = .text
        manager.selectedElementId = element.id

        manager.finishEditingTextElement(id: element.id)

        XCTAssertEqual(manager.selectedTool, .cursor)
        XCTAssertNil(manager.selectedElementId)
        XCTAssertTrue(manager.elements.isEmpty)
    }

    /// 选中元素后的 ⌘C/⌘V 走截图会话内部剪贴板，不覆盖系统截图。
    func testCopyAndPasteSelectedAnnotationCreatesOffsetDuplicate() {
        manager.updateSelection(
            CGRect(x: 0, y: 0, width: 300, height: 300),
            on: nil
        )
        let element = DrawingElement(
            tool: .rectangle,
            points: [CGPoint(x: 20, y: 30), CGPoint(x: 60, y: 80)],
            color: .blue,
            lineWidth: 5
        )
        manager.addElement(element)

        XCTAssertTrue(manager.copySelectedAnnotation())
        XCTAssertTrue(manager.hasCopiedAnnotation)
        XCTAssertTrue(manager.pasteCopiedAnnotation())

        XCTAssertEqual(manager.elements.count, 2)
        let pasted = manager.elements[1]
        XCTAssertNotEqual(pasted.id, element.id)
        XCTAssertEqual(pasted.tool, .rectangle)
        XCTAssertEqual(pasted.lineWidth, 5)
        XCTAssertEqual(pasted.points[0], CGPoint(x: 32, y: 42))
        XCTAssertEqual(pasted.points[1], CGPoint(x: 72, y: 92))
        XCTAssertEqual(manager.selectedElementId, pasted.id)
        XCTAssertEqual(manager.selectedTool, .cursor)
    }

    /// 文本编辑器聚焦时，⌘C/⌘V 必须交给 TextField，不能复制标注或截图。
    func testTextEditingRoutesClipboardShortcutsToNativeTextField() {
        let element = DrawingElement(
            tool: .text,
            points: [CGPoint(x: 20, y: 30)],
            color: .red,
            lineWidth: 4,
            text: "可编辑文字"
        )
        manager.elements = [element]
        manager.selectedTool = .text
        manager.selectedElementId = element.id

        XCTAssertTrue(manager.isEditingTextAnnotation)
        XCTAssertFalse(manager.copySelectedAnnotation())
        XCTAssertFalse(manager.pasteCopiedAnnotation())
    }

    /// 只在模型里残留 selectedElementId、但工具不是箭头时，不算可见选中态。
    func testInactiveDrawingToolDoesNotExposeCopyableSelection() {
        let element = DrawingElement(
            tool: .rectangle,
            points: [CGPoint(x: 20, y: 30)],
            color: .blue,
            lineWidth: 5
        )
        manager.elements = [element]
        manager.selectedTool = .rectangle
        manager.selectedElementId = element.id

        XCTAssertFalse(manager.hasSelectedAnnotation)
        XCTAssertFalse(manager.copySelectedAnnotation())
    }
}
