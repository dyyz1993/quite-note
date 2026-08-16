import XCTest
import AppKit
@testable import QuiteNote

/// 文本标注元素碰撞框（点击热区）的宽度估算验证
///
/// 背景：宽度按"每字符 0.6 倍字号"估算，这是拉丁字符的平均比例；
/// 中日韩全角字符的实际渲染宽度约为 1.0 倍字号。
/// 对中文标注来说，碰撞框比实际文字窄约 40%，导致点击/拖拽热区偏小、难选中。
final class AnnotationTextHitBoxTests: XCTestCase {

    private func makeTextElement(_ text: String, fontSize: CGFloat = 20) -> DrawingElement {
        DrawingElement(
            tool: .text,
            points: [CGPoint(x: 5, y: 5)],
            color: .red,
            lineWidth: 4,
            text: text,
            fontSize: fontSize
        )
    }

    /// 中文文本：全角字符按 1.0 倍字号计宽
    /// 4 个中文字符 × 20 号 × 1.0 + 16 padding = 96
    func testChineseTextWidthUsesFullWidthRatio() {
        let rect = V2ScreenshotView.textBoundingRect(for: makeTextElement("你好世界"))
        XCTAssertEqual(rect.width, 96, accuracy: 0.01, "中文全角字符应按 1.0 倍字号估算宽度")
    }

    /// 英文文本：半角字符按 0.6 倍字号计宽（保持现状）
    /// 5 个英文字符 × 20 号 × 0.6 + 16 = 76
    func testEnglishTextWidthKeepsNarrowRatio() {
        let rect = V2ScreenshotView.textBoundingRect(for: makeTextElement("Hello"))
        XCTAssertEqual(rect.width, 76, accuracy: 0.01)
    }

    /// 中英混排：全角 1.0、半角 0.6 分别计宽
    /// (1.0 + 0.6 + 1.0) × 20 + 16 = 68
    func testMixedTextWidthCombinesRatios() {
        let rect = V2ScreenshotView.textBoundingRect(for: makeTextElement("你a好"))
        XCTAssertEqual(rect.width, 68, accuracy: 0.01)
    }

    /// 多行文本取最宽行，行高 1.3 倍字号
    func testMultilineUsesWidestLineAndLineHeight() {
        let element = makeTextElement("你\n你好你好")
        let rect = V2ScreenshotView.textBoundingRect(for: element)
        // 最宽行 "你好你好" = 4 × 1.0 × 20 + 16 = 96
        XCTAssertEqual(rect.width, 96, accuracy: 0.01)
        // 2 行 × 20 × 1.3 + 12 = 64
        XCTAssertEqual(rect.height, 64, accuracy: 0.01)
    }
}
