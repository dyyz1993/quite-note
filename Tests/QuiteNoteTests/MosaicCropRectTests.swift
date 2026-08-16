import XCTest
import CoreGraphics
@testable import QuiteNote

/// 马赛克采样区域裁剪的正确性验证
///
/// 背景：generateFinalImage 中已确认「CGImage.cropping 的坐标系原点在左上角」
/// 并移除了 Y 轴翻转；但 MosaicRenderer.pixelCropRect 仍保留翻转写法，
/// 怀疑马赛克从垂直镜像位置取色（上半屏的格子采到下半屏的像素）。
///
/// 测试策略：构造一张上红下蓝的合成图，用真实 CGImage.cropping 验证
/// 「画布上半部的马赛克必须采到图的上半部」这一期望行为。
final class MosaicCropRectTests: XCTestCase {

    private let canvasSize = CGSize(width: 20, height: 10)

    /// 上半红、下半蓝的测试图（CGImage 第 0 行 = 顶部 = 红）
    private func makeTwoToneImage() -> CGImage {
        let ctx = CGContext(
            data: nil,
            width: Int(canvasSize.width),
            height: Int(canvasSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // CGContext 原点在左下角：上半部分（y: 5~10）填红
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: canvasSize.height / 2, width: canvasSize.width, height: canvasSize.height / 2))
        // 下半部分（y: 0~5）填蓝
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height / 2))
        return ctx.makeImage()!
    }

    /// 读取图片中心 1x1 像素的红色通道值（0~255）
    private func centerRedChannel(_ image: CGImage) -> CGFloat {
        let center = CGRect(x: image.width / 2, y: image.height / 2, width: 1, height: 1)
        guard let pixel = image.cropping(to: center),
              let data = pixel.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else {
            return -1
        }
        return CGFloat(ptr[0])
    }

    /// 画布上半部的马赛克区域，必须采到图的上半部（红）
    func testMosaicOnTopHalfSamplesTopPixels() {
        let image = makeTwoToneImage()
        let topRect = CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height / 2)

        let cropRect = MosaicRenderer.pixelCropRect(for: topRect, canvasSize: canvasSize, scaleX: 1, scaleY: 1)
        let cropped = image.cropping(to: cropRect)!

        // 期望：采样到红色区域（R 通道接近 255）
        XCTAssertGreaterThan(
            centerRedChannel(cropped), 200,
            "画布上半部的马赛克应采到图的上半部（红），实际采到了下半部（蓝）——Y 轴翻转 bug"
        )
    }

    /// 画布下半部的马赛克区域，必须采到图的下半部（蓝）
    func testMosaicOnBottomHalfSamplesBottomPixels() {
        let image = makeTwoToneImage()
        let bottomRect = CGRect(x: 0, y: canvasSize.height / 2, width: canvasSize.width, height: canvasSize.height / 2)

        let cropRect = MosaicRenderer.pixelCropRect(for: bottomRect, canvasSize: canvasSize, scaleX: 1, scaleY: 1)
        let cropped = image.cropping(to: cropRect)!

        // 期望：采样到蓝色区域（R 通道接近 0）
        XCTAssertLessThan(
            centerRedChannel(cropped), 50,
            "画布下半部的马赛克应采到图的下半部（蓝），实际采到了上半部（红）——Y 轴翻转 bug"
        )
    }

    /// Retina 2x 缩放下的坐标换算（无翻转，直接缩放）
    func testScaleConversionWithoutFlip() {
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        let result = MosaicRenderer.pixelCropRect(for: rect, canvasSize: CGSize(width: 100, height: 100), scaleX: 2, scaleY: 2)

        XCTAssertEqual(result.minX, 20, accuracy: 0.01)
        XCTAssertEqual(result.minY, 40, accuracy: 0.01, "Y 应直接缩放，不应做 (canvasHeight - maxY) 翻转")
        XCTAssertEqual(result.width, 60, accuracy: 0.01)
        XCTAssertEqual(result.height, 80, accuracy: 0.01)
    }
}
