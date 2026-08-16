import XCTest
import AppKit
@testable import QuiteNote

/// OCR 真实识别精度验证：渲染已知文本 → 跑 Vision → 对比识别结果
/// （使用真实 Vision 引擎，验证语言配置和链路正确性）
@MainActor
final class OCRIntegrationTests: XCTestCase {

    /// 渲染测试图：白底黑字三行（中文/英文/混合），AppKit 左下原点从上往下画
    private func renderTextImage() -> NSImage {
        let size = NSSize(width: 640, height: 240)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        let lines = [
            "会议时间：明天下午三点",
            "QuiteNote OCR Test 1234",
            "版本 v1.3.0 已发布"
        ]
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 28, weight: .regular),
            .foregroundColor: NSColor.black
        ]
        for (index, line) in lines.enumerated() {
            let y = size.height - 60 - CGFloat(index) * 60
            (line as NSString).draw(at: NSPoint(x: 40, y: y), withAttributes: attrs)
        }
        image.unlockFocus()
        return image
    }

    func testRealRecognitionOnRenderedText() {
        let image = renderTextImage()
        let expectation = self.expectation(description: "OCR 完成")

        var recognized: String?
        V2OCRService.shared.recognizeText(in: image) { text in
            recognized = text
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 30)

        let result = recognized ?? ""
        print("🧪 OCR 识别结果:\n\(result)")

        XCTAssertFalse(result.isEmpty, "渲染清晰的文本应能识别出内容")

        // 关键词容错断言（识别结果应包含各行的核心词，允许个别标点/空格差异）
        let normalized = result.replacingOccurrences(of: " ", with: "")
        XCTAssertTrue(normalized.contains("三点") || normalized.contains("3点"), "应识别出中文行关键词，实际: \(result)")
        XCTAssertTrue(normalized.contains("1234"), "应识别出英文数字行，实际: \(result)")
        XCTAssertTrue(normalized.contains("1.3.0"), "应识别出版本号，实际: \(result)")
    }
}
