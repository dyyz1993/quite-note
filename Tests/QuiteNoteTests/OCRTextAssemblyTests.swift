import XCTest
import AppKit
@testable import QuiteNote

/// OCR 文本拼装逻辑测试（纯函数，不依赖 Vision 运行时）
final class OCRTextAssemblyTests: XCTestCase {

    /// 多行文本：按基线从上到下排序输出（输入故意乱序）
    func testMultipleLinesSortedTopToBottom() {
        let fragments = [
            V2OCRService.OCRLineFragment(rect: CGRect(x: 0, y: 0.0, width: 0.5, height: 0.05), text: "第三行"),
            V2OCRService.OCRLineFragment(rect: CGRect(x: 0, y: 0.9, width: 0.5, height: 0.05), text: "第一行"),
            V2OCRService.OCRLineFragment(rect: CGRect(x: 0, y: 0.45, width: 0.5, height: 0.05), text: "第二行")
        ]
        let result = V2OCRService.assembleText(fragments)
        XCTAssertEqual(result, "第一行\n第二行\n第三行")
    }

    /// 同一行的左右两个片段：合并为一行，按从左到右排序
    func testSameLineFragmentsMergedLeftToRight() {
        let fragments = [
            V2OCRService.OCRLineFragment(rect: CGRect(x: 0.55, y: 0.5, width: 0.3, height: 0.05), text: "World"),
            V2OCRService.OCRLineFragment(rect: CGRect(x: 0.1, y: 0.5, width: 0.3, height: 0.05), text: "Hello")
        ]
        let result = V2OCRService.assembleText(fragments)
        XCTAssertEqual(result, "Hello World")
    }

    /// minY 差小于行高 60% 视为同一行；跨行不误合并
    func testLineGroupingTolerance() {
        let h: CGFloat = 0.1
        let fragments = [
            // 上行两个片段：基线差 0.04 < 0.1*0.6 → 同行
            V2OCRService.OCRLineFragment(rect: CGRect(x: 0.1, y: 0.80, width: 0.2, height: h), text: "左"),
            V2OCRService.OCRLineFragment(rect: CGRect(x: 0.5, y: 0.84, width: 0.2, height: h), text: "右"),
            // 下行：基线 0.30，与上行差 0.5 → 另起一行
            V2OCRService.OCRLineFragment(rect: CGRect(x: 0.1, y: 0.30, width: 0.8, height: h), text: "下一行")
        ]
        let result = V2OCRService.assembleText(fragments)
        XCTAssertEqual(result, "左 右\n下一行")
    }

    /// 空输入返回空字符串
    func testEmptyInputReturnsEmpty() {
        XCTAssertEqual(V2OCRService.assembleText([]), "")
    }
}
