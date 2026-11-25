import AppKit
import SwiftUI

/// 便利贴底色。
///
/// 深色系柔和色：六种颜色明度一致（切换底色不会突然变亮变暗），正文保持白色——
/// 白字对比度 13~18:1，连最淡的红色文字点也有 4.8:1（见 StickyNoteColorTests）。
/// 彩度定在"深色底上分得清青 / 绿 / 蓝"的下限之上（OKLCH C ≥ 0.05；再低三种颜色看上去
/// 几乎一样，颜色就起不到"帮着记事"的作用），同时都还很暗，久看不累。
/// 存的是标识而不是色值，以后微调色板不影响用户已经选好的颜色。
enum StickyNoteColor: String, Codable, CaseIterable, Identifiable {
    /// 默认：应用主背景同款的深蓝（#111827）
    case blue
    case teal
    case green
    case amber
    case brick
    case violet

    static let standard: StickyNoteColor = .blue

    var id: String { rawValue }

    /// 便签底色
    var backgroundHex: String {
        switch self {
        case .blue: return "111827"
        case .teal: return "003636"
        case .green: return "19351A"
        case .amber: return "402903"
        case .brick: return "48211F"
        case .violet: return "342646"
        }
    }

    /// 记录卡片、列表上的标识色：同一色相提亮，在深色面板里才看得见
    var accentHex: String {
        switch self {
        case .blue: return "A5BDF2"
        case .teal: return "58D4D3"
        case .green: return "8BD28D"
        case .amber: return "EBB25F"
        case .brick: return "F3A7A0"
        case .violet: return "CDADF2"
        }
    }

    /// 色名在字符串表里的键（两份 Localizable.strings 的 sticky.color.*）
    var nameKey: String { "sticky.color.\(rawValue)" }

    var name: String {
        switch self {
        case .blue: return L(nameKey, fallback: "Deep blue")
        case .teal: return L(nameKey, fallback: "Teal")
        case .green: return L(nameKey, fallback: "Green")
        case .amber: return L(nameKey, fallback: "Amber")
        case .brick: return L(nameKey, fallback: "Brick")
        case .violet: return L(nameKey, fallback: "Violet")
        }
    }

    var background: Color { Self.color(backgroundHex) }
    var accent: Color { Self.color(accentHex) }

    private static var menuSwatchCache: [String: NSImage] = [:]

    /// 原生菜单项里的色块（菜单项只认得图片）。AppKit 的菜单项里图片和勾选标记占同一列
    /// （有图片就不画勾），所以当前底色的勾直接画进图片右侧，六个选项的图片同宽、文字才对得齐
    static func menuSwatchImage(color: StickyNoteColor, isSelected: Bool) -> NSImage {
        let key = "\(color.rawValue)-\(isSelected)"
        if let cached = menuSwatchCache[key] {
            return cached
        }
        let diameter: CGFloat = 14
        let swatch = NSImage(size: NSSize(width: 23, height: diameter), flipped: false) { rect in
            ringSwatchImage(backgroundHex: color.backgroundHex, accentHex: color.accentHex, diameter: diameter)
                .draw(in: NSRect(x: 0, y: 0, width: diameter, height: diameter))
            if isSelected {
                let check = NSBezierPath()
                check.move(to: NSPoint(x: rect.width - 7.5, y: rect.midY + 0.5))
                check.line(to: NSPoint(x: rect.width - 5, y: rect.midY - 2))
                check.line(to: NSPoint(x: rect.width - 1, y: rect.midY + 4))
                check.lineWidth = 1.8
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                NSColor.labelColor.withAlphaComponent(0.9).setStroke()
                check.stroke()
            }
            return true
        }
        swatch.isTemplate = false
        return swatch
    }

    /// 画一个带浅描边的实心圆，给菜单项当色块用（文字颜色用：那四种颜色本身鲜亮）
    static func circleSwatch(hex: String, diameter: CGFloat = 14) -> NSImage {
        let swatch = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            (NSColor(hex: hex) ?? .black).setFill()
            circle.fill()
            NSColor.white.withAlphaComponent(0.55).setStroke()
            circle.lineWidth = 1
            circle.stroke()
            return true
        }
        swatch.isTemplate = false
        return swatch
    }

    /// 菜单项里和 SwiftUI 色环同款的底色色块（外环标识色 + 内芯底色）
    static func ringSwatchImage(backgroundHex: String, accentHex: String, diameter: CGFloat = 14) -> NSImage {
        let swatch = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            let outer = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            (NSColor(hex: accentHex) ?? .white).setFill()
            outer.fill()
            let ring = Self.ringWidth(forDiameter: diameter)
            let inner = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5 + ring, dy: 0.5 + ring))
            (NSColor(hex: backgroundHex) ?? .black).setFill()
            inner.fill()
            return true
        }
        swatch.isTemplate = false
        return swatch
    }

    /// 色环宽度随直径缩放：菜单里的 14pt 用 2pt，设置页的 22pt 用 3pt
    static func ringWidth(forDiameter diameter: CGFloat) -> CGFloat {
        max(1.5, diameter / 7)
    }

    private static func color(_ hex: String) -> Color {
        Color(NSColor(hex: hex) ?? .black)
    }

    /// 从记录 / 偏好里存的值还原；缺省或无法识别的回落到默认
    static func from(_ raw: String?) -> StickyNoteColor {
        raw.flatMap(StickyNoteColor.init(rawValue:)) ?? .standard
    }
}

/// 便签底色的色块：外环是标识色，内芯是便签的真实底色。
///
/// 只画底色不行——六种底色都是深色，放在深色的工具栏 / 菜单 / 设置页上要么看不见
/// （默认深蓝的那个按钮在工具栏上直接隐形），要么六个看起来差不多。外环负责一眼认出
/// 是哪种颜色，内芯如实预览便签的样子；标识色和记录卡片上的色条是同一个。
struct StickyNoteColorRing: View {
    let color: StickyNoteColor
    var diameter: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().fill(color.accent)
            Circle()
                .fill(color.background)
                .padding(StickyNoteColor.ringWidth(forDiameter: diameter))
        }
        .frame(width: diameter, height: diameter)
    }
}
