import AppKit
import XCTest
@testable import QuiteNote

/// 便利贴底色色板：白字可读、六种颜色明度一致、标识色在深色面板上看得见
final class StickyNoteColorTests: XCTestCase {

    /// WCAG 相对亮度
    private func luminance(_ hex: String) -> Double {
        func channel(_ value: UInt32) -> Double {
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        var rgb: UInt32 = 0
        Scanner(string: hex).scanHexInt32(&rgb)
        return 0.2126 * channel((rgb >> 16) & 0xFF) + 0.7152 * channel((rgb >> 8) & 0xFF) + 0.0722 * channel(rgb & 0xFF)
    }

    private func contrast(_ a: String, _ b: String) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private let foregrounds: [(name: String, hex: String)] = [
        ("正文白字", "FFFFFF"),
        ("失焦蒙层标题 gray200", "E5E7EB"),
        ("未勾选待办图标 gray400", "9CA3AF"),
        ("已勾选待办图标 green400", "4ADE80"),
        ("文字色点-红 red400", "F87171"),
        ("文字色点-蓝 blue400", "60A5FA"),
        ("文字色点-绿 green400", "4ADE80"),
        ("文字色点-黄 yellow400", "FACC15"),
    ]

    /// 正文始终是白色：任何底色下都要达到 WCAG AAA（7:1），12pt 小字才看得清、久看不累
    func testWhiteTextMeetsAAAOnEveryBackground() {
        for color in StickyNoteColor.allCases {
            let ratio = contrast(color.backgroundHex, "FFFFFF")
            XCTAssertGreaterThanOrEqual(ratio, 7, "\(color) 白字对比度 \(ratio)")
        }
    }

    /// 工具栏色点、待办图标、失焦标题也压在便签底色上，不能被底色吃掉
    func testSecondaryForegroundsStayReadable() {
        for color in StickyNoteColor.allCases {
            for foreground in foregrounds where !foreground.name.contains("正文") {
                let ratio = contrast(color.backgroundHex, foreground.hex)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(color) 上的\(foreground.name)对比度只有 \(ratio)")
            }
        }
    }

    /// 六种颜色明度一致：换底色不会突然变亮变暗，也不会有哪一种特别抢眼
    func testBackgroundsShareTheSameLightness() {
        let all = StickyNoteColor.allCases
        for i in all.indices {
            for j in all.indices where i < j {
                let ratio = contrast(all[i].backgroundHex, all[j].backgroundHex)
                XCTAssertLessThanOrEqual(ratio, 1.35, "\(all[i]) 与 \(all[j]) 明度差 \(ratio)")
            }
        }
    }

    /// 底色是深色系：都比中灰暗得多，放在深色桌面上不刺眼
    func testBackgroundsAreAllDark() {
        for color in StickyNoteColor.allCases {
            XCTAssertGreaterThan(contrast(color.backgroundHex, "808080"), 3, "\(color) 底色应明显深于中灰")
        }
    }

    /// 记录卡片上的标识色是同色相提亮的，要在深色面板上看得清
    func testAccentsAreVisibleOnTheDarkPanel() {
        for color in StickyNoteColor.allCases {
            XCTAssertGreaterThanOrEqual(contrast(color.accentHex, "111827"), 7, "\(color) 标识色对比度")
        }
    }

    func testDefaultIsTheAppBackgroundBlue() {
        XCTAssertEqual(StickyNoteColor.standard, .blue)
        XCTAssertEqual(StickyNoteColor.blue.backgroundHex, "111827")
    }

    func testFromRawValueFallsBackToDefault() {
        XCTAssertEqual(StickyNoteColor.from("teal"), .teal)
        XCTAssertEqual(StickyNoteColor.from(nil), .blue)
        XCTAssertEqual(StickyNoteColor.from(""), .blue)
        XCTAssertEqual(StickyNoteColor.from("hotpink"), .blue)
    }

    func testColorRoundTripsThroughCodable() throws {
        for color in StickyNoteColor.allCases {
            let data = try JSONEncoder().encode(color)
            XCTAssertEqual(try JSONDecoder().decode(StickyNoteColor.self, from: data), color)
        }
        // 便签里存着将来才有的颜色值：回落到默认，不能让整张便签解码失败
        var note = try JSONDecoder().decode(StickyNoteModel.self, from: Data("{\"color\":\"neon\"}".utf8))
        XCTAssertEqual(note.color, .blue)
        note.color = .violet
        XCTAssertEqual(try JSONDecoder().decode(StickyNoteModel.self, from: JSONEncoder().encode(note)).color, .violet)
    }

    func testHexValuesAreWellFormed() {
        for color in StickyNoteColor.allCases {
            for hex in [color.backgroundHex, color.accentHex] {
                XCTAssertEqual(hex.count, 6)
                XCTAssertTrue(hex.allSatisfy { $0.isHexDigit }, "\(hex) 不是 6 位十六进制")
            }
            XCTAssertNotNil(NSColor(hex: color.backgroundHex))
        }
    }

    // MARK: - 分得清

    /// OKLab 的明度 / 彩度 / 色相（色相 0~360°）
    private func oklch(_ hex: String) -> (lightness: Double, chroma: Double, hue: Double) {
        func cubeRoot(_ value: Double) -> Double { pow(value, 1 / 3) }
        var rgb: UInt32 = 0
        Scanner(string: hex).scanHexInt32(&rgb)
        let r = luminanceChannel((rgb >> 16) & 0xFF), g = luminanceChannel((rgb >> 8) & 0xFF), b = luminanceChannel(rgb & 0xFF)
        let l = cubeRoot(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cubeRoot(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cubeRoot(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        return (lightness, (a * a + bb * bb).squareRoot(), atan2(bb, a) * 180 / .pi)
    }

    private func luminanceChannel(_ value: UInt32) -> Double {
        let c = Double(value) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// 彩度下限。默认深蓝兼任应用背景色，不要求；其余五种最初彩度只有 0.04，
    /// 2026-11-25 测试机实拍：青 / 绿 / 深蓝看上去几乎一样，颜色起不到"帮着记事"的作用
    func testColoredBackgroundsKeepEnoughChroma() {
        for color in StickyNoteColor.allCases where color != .blue {
            XCTAssertGreaterThanOrEqual(oklch(color.backgroundHex).chroma, 0.05, "\(color) 底色彩度太低，和其他颜色分不清")
        }
    }

    /// 六个标识色（工具栏色环、菜单色块、记录卡片色条）两两色相至少差 30°
    func testAccentsAreHueApart() {
        let all = StickyNoteColor.allCases
        for i in all.indices {
            for j in all.indices where i < j {
                let delta = abs(oklch(all[i].accentHex).hue - oklch(all[j].accentHex).hue)
                XCTAssertGreaterThanOrEqual(min(delta, 360 - delta), 30, "\(all[i]) 与 \(all[j]) 的标识色色相太近")
            }
        }
    }

    /// 菜单色块：六个选项的图片同宽（文字才对得齐），只有当前底色的那张带勾
    func testMenuSwatchMarksOnlyTheCurrentColor() throws {
        let images = StickyNoteColor.allCases.map { StickyNoteColor.menuSwatchImage(color: $0, isSelected: $0 == .teal) }
        XCTAssertEqual(Set(images.map(\.size.width)).count, 1)
        for (color, image) in zip(StickyNoteColor.allCases, images) {
            // 带勾的那张，右侧 8pt 里有不透明的像素
            let marked = try Self.hasOpaquePixels(in: image, xRange: (16, 23))
            XCTAssertEqual(marked, color == .teal, "\(color) 的勾画错了")
        }
    }

    /// 图片在横向 xRange（pt）内是否有不透明像素（1x 位图上取点）
    private static func hasOpaquePixels(in image: NSImage, xRange: (CGFloat, CGFloat)) throws -> Bool {
        let width = Int(image.size.width), height = Int(image.size.height)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        for x in Int(xRange.0)..<Int(xRange.1) {
            for y in 0..<height where bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0 > 0.5 {
                return true
            }
        }
        return false
    }
}
