import XCTest
import AppKit
@testable import QuiteNote

/// 剪贴板 OCR 的后台读盘加载器（ClipboardOCRQueue.loadFullResolutionCGImage）：
/// 代码生成的 PNG（已知像素尺寸、带 alpha）解出的 CGImage 尺寸必须与源像素一致。
///
/// 尺寸断言用非整倍数（123×77）：NSImage 的 representation 在 Retina 环境下会把
/// 点尺寸报告成 2 倍像素（马赛克三连 bug 的老坑），加载器必须以真实像素为准、
/// 不做任何缩放——降采样会改变识别结果。
final class OCRImageLoadingTests: XCTestCase {

    /// 生成已知像素尺寸的 PNG（半透明红块，带 alpha 通道），写入临时目录
    private func makePNG(pixelWidth: Int, pixelHeight: Int) throws -> URL {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.red.withAlphaComponent(0.5).setFill()
        NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight).fill()
        NSGraphicsContext.restoreGraphicsState()

        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qn-ocr-load-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }

    func test解码尺寸与源像素一致且保留alpha() throws {
        let url = try makePNG(pixelWidth: 123, pixelHeight: 77)
        defer { try? FileManager.default.removeItem(at: url) }

        let cg = try XCTUnwrap(ClipboardOCRQueue.loadFullResolutionCGImage(at: url))
        XCTAssertEqual(cg.width, 123, "宽度必须等于源像素（Retina 下不得翻倍）")
        XCTAssertEqual(cg.height, 77, "高度必须等于源像素（Retina 下不得翻倍）")
        XCTAssertNotEqual(cg.alphaInfo, CGImageAlphaInfo.none, "PNG 的 alpha 通道应保留")
    }

    func test大图全分辨率不缩放() throws {
        let url = try makePNG(pixelWidth: 640, pixelHeight: 240)
        defer { try? FileManager.default.removeItem(at: url) }

        let cg = try XCTUnwrap(ClipboardOCRQueue.loadFullResolutionCGImage(at: url))
        XCTAssertEqual(cg.width, 640)
        XCTAssertEqual(cg.height, 240)
    }

    func test文件缺失返回nil() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qn-ocr-missing-\(UUID().uuidString).png")
        XCTAssertNil(ClipboardOCRQueue.loadFullResolutionCGImage(at: url))
    }
}
