import XCTest
import SwiftUI
import AppKit
@testable import QuiteNote

/// 马赛克渲染的端到端像素级验证
///
/// 不只验证坐标公式，而是把完整的渲染管线跑一遍：
/// 合成底图 → SwiftUI Canvas 绘制 → MosaicRenderer.render → ImageRenderer 输出成品 → 采样像素
///
/// 期望行为：画布上半部打的马赛克，成品像素必须是上半部内容的颜色（红），
/// 而不是从镜像位置采来的颜色（蓝）。修复前（裁剪 Y 翻转 + 格子反排）这里会是蓝色。
@MainActor
final class MosaicEndToEndTests: XCTestCase {

    private let canvasWidth: CGFloat = 40
    private let canvasHeight: CGFloat = 20

    /// 上红下蓝的底图（CGImage 第 0 行 = 视觉顶部 = 红）
    private func makeTwoToneNSImage() -> NSImage {
        let ctx = CGContext(
            data: nil,
            width: Int(canvasWidth),
            height: Int(canvasHeight),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // CGContext 数学坐标原点在左下角：y: 10~20 是视觉上半部 → 红
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: canvasHeight / 2, width: canvasWidth, height: canvasHeight / 2))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight / 2))
        let cg = ctx.makeImage()!
        return NSImage(cgImage: cg, size: NSSize(width: canvasWidth, height: canvasHeight))
    }

    /// 用真实渲染管线在指定区域打马赛克，返回成品图
    private func renderMosaic(baseImage: NSImage, mosaicRect: CGRect) -> NSImage? {
        struct MosaicCanvas: View {
            let baseImage: NSImage
            let mosaicRect: CGRect

            var body: some View {
                Canvas { context, size in
                    context.draw(Image(nsImage: baseImage), in: CGRect(origin: .zero, size: size))
                    let element = DrawingElement(
                        tool: .mosaic,
                        points: [mosaicRect.origin, CGPoint(x: mosaicRect.maxX, y: mosaicRect.maxY)],
                        color: .clear,
                        lineWidth: 4,
                        fontSize: 5 // 马赛克格子 5px
                    )
                    MosaicRenderer().render(
                        element: element,
                        in: &context,
                        config: RendererConfig(
                            imageSize: size,
                            canvasSize: size,
                            baseImage: baseImage,
                            selectionArea: nil
                        )
                    )
                }
                .frame(width: 40, height: 20)
            }
        }

        let renderer = ImageRenderer(content: MosaicCanvas(baseImage: baseImage, mosaicRect: mosaicRect))
        renderer.scale = 1
        return renderer.nsImage
    }

    /// 读取成品图指定坐标（左上原点）1x1 像素的红色通道
    private func redChannel(at point: CGPoint, in image: NSImage) -> CGFloat {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return -1 }
        let rect = CGRect(x: point.x, y: point.y, width: 1, height: 1)
        guard let pixel = cg.cropping(to: rect),
              let data = pixel.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return -1 }
        return CGFloat(ptr[0])
    }

    /// 画布上半部打马赛克 → 成品上半部必须是红色块（原位采样），下半部保持蓝
    func testMosaicOnTopHalfRendersTopContentColors() {
        let base = makeTwoToneNSImage()
        let output = renderMosaic(baseImage: base, mosaicRect: CGRect(x: 0, y: 0, width: 40, height: 10))
        XCTAssertNotNil(output, "ImageRenderer 应能产出成品图")

        guard let output else { return }

        // (22, 7) 位于上半部马赛克块内部（避开边框线）
        XCTAssertGreaterThan(
            redChannel(at: CGPoint(x: 22, y: 7), in: output), 200,
            "上半部马赛克的成品像素应为红色（原位采样）；若是蓝色说明仍在从镜像位置取色"
        )
        // (22, 17) 下半部未打码，保持蓝色
        XCTAssertLessThan(
            redChannel(at: CGPoint(x: 22, y: 17), in: output), 50,
            "未打码的下半部应保持蓝色"
        )
    }

    /// 画布下半部打马赛克 → 成品下半部必须是蓝色块
    func testMosaicOnBottomHalfRendersBottomContentColors() {
        let base = makeTwoToneNSImage()
        let output = renderMosaic(baseImage: base, mosaicRect: CGRect(x: 0, y: 10, width: 40, height: 10))
        XCTAssertNotNil(output)
        guard let output else { return }

        // (22, 12) 位于下半部马赛克块内部
        XCTAssertLessThan(
            redChannel(at: CGPoint(x: 22, y: 12), in: output), 50,
            "下半部马赛克的成品像素应为蓝色（原位采样）；若是红色说明仍在从镜像位置取色"
        )
        // (22, 2) 上半部未打码，保持红色
        XCTAssertGreaterThan(
            redChannel(at: CGPoint(x: 22, y: 2), in: output), 200,
            "未打码的上半部应保持红色"
        )
    }

    /// 诊断用：打印底图元数据 + NSImage.cgImage 的方向 + 成品像素分布图
    func testZZDiagnostics() {
        let base = makeTwoToneNSImage()
        print("🧪 base.size=\(base.size), reps=\(base.representations.count)")
        for rep in base.representations {
            print("🧪 rep=\(type(of: rep)) pixels=\(rep.pixelsWide)x\(rep.pixelsHigh)")
        }
        if let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            print("🧪 NSImage.cgImage \(cg.width)x\(cg.height)")
            if let top = cg.cropping(to: CGRect(x: 0, y: 0, width: cg.width, height: 2)),
               let d = top.dataProvider?.data, let p = CFDataGetBytePtr(d) {
                print("🧪 NSImage.cgImage 顶部行 R=\(p[0]) B=\(p[2])（红顶应为 R=255 B=0）")
            }
        }

        // 上半部打码的成品 R 通道分布图（R=红 b=蓝）
        if let output = renderMosaic(baseImage: base, mosaicRect: CGRect(x: 0, y: 0, width: 40, height: 10)) {
            print("🧪 成品像素分布（上半部打码）:")
            for y in 0..<20 {
                var line = ""
                for x in stride(from: 0, to: 40, by: 2) {
                    line += redChannel(at: CGPoint(x: CGFloat(x), y: CGFloat(y)), in: output) > 128 ? "R" : "b"
                }
                print("🧪 y\(String(format: "%02d", y)) \(line)")
            }
        }
    }
}
