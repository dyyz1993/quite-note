import SwiftUI

// MARK: - Tailwind Color Mapping (Exact RGBA values from note.jsx)
//
// This file provides a complete mapping from Tailwind CSS color names to
// exact RGBA values used in the note.jsx React component, converted for SwiftUI.
//
// Usage:
//   Color.themeGray900    // Background color (bg-gray-900/90)
//   Color.themeBlue500    // Primary accent (blue-500)
//   Color.themePurple500  // AI summary color (purple-500)
//   Color.themeGreen500   // Success state (green-500)
//   Color.themeRed500     // Error state (red-500)
//   Color.themeYellow500  // Warning/hardware (yellow-500)

extension Color {
    // Gray Scale (Tailwind 900-100)
    static let themeGray900 = Color(red: 17/255, green: 24/255, blue: 39/255)     // #111827 (bg-gray-900)
    static let themeGray800 = Color(red: 31/255, green: 41/255, blue: 55/255)     // #1F2937 (bg-gray-800)
    static let themeGray700 = Color(red: 55/255, green: 65/255, blue: 81/255)     // #374151 (bg-gray-700)
    static let themeGray600 = Color(red: 75/255, green: 85/255, blue: 99/255)     // #4B5563 (bg-gray-600)
    static let themeGray500 = Color(red: 107/255, green: 114/255, blue: 128/255)  // #6B7280 (text-gray-500)
    static let themeGray400 = Color(red: 156/255, green: 163/255, blue: 175/255)  // #9CA3AF (text-gray-400)
    static let themeGray300 = Color(red: 209/255, green: 213/255, blue: 221/255)  // #D1D5DB (text-gray-300)
    static let themeGray200 = Color(red: 229/255, green: 231/255, blue: 235/255)  // #E5E7EB (text-gray-200)
    static let themeGray100 = Color(red: 243/255, green: 244/255, blue: 246/255)  // #F3F4F6 (bg-gray-100)

    // Blue Scale (AI/交互色)
    static let themeBlue600 = Color(red: 37/255, green: 99/255, blue: 235/255)    // #2563EB (bg-blue-600)
    static let themeBlue500 = Color(red: 59/255, green: 130/255, blue: 246/255)   // #3B82F6 (blue-500)
    static let themeBlue400 = Color(red: 96/255, green: 165/255, blue: 250/255)   // #60A5FA (blue-400)
    static let themeBlue300 = Color(red: 147/255, green: 197/255, blue: 253/255)  // #93C5FD (blue-300)

    // Purple Scale (AI 总结)
    static let themePurple600 = Color(red: 147/255, green: 51/255, blue: 234/255) // #9333EA (purple-600)
    static let themePurple500 = Color(red: 168/255, green: 85/255, blue: 247/255) // #A855F7 (purple-500)
    static let themePurple400 = Color(red: 192/255, green: 132/255, blue: 252/255) // #C084FC (purple-400)
    static let themePurple300 = Color(red: 216/255, green: 180/255, blue: 254/255) // #D8B4FE (purple-300)

    // Green Scale (成功/确认)
    static let themeGreen900 = Color(red: 2/255, green: 44/255, blue: 22/255)     // #022C16 (自定义深绿)
    static let themeGreen600 = Color(red: 22/255, green: 163/255, blue: 74/255)   // #16A34A (green-600)
    static let themeGreen500 = Color(red: 34/255, green: 197/255, blue: 94/255)   // #22C55E (green-500)
    static let themeGreen400 = Color(red: 74/255, green: 222/255, blue: 128/255)  // #4ADE80 (green-400)
    static let themeGreen300 = Color(red: 132/255, green: 255/255, blue: 173/255) // #84FFAD (green-300)

    // Red Scale (错误/删除)
    static let themeRed600 = Color(red: 185/255, green: 28/255, blue: 28/255)     // #B91C1C (red-600)
    static let themeRed500 = Color(red: 239/255, green: 68/255, blue: 68/255)     // #EF4444 (red-500)
    static let themeRed400 = Color(red: 248/255, green: 113/255, blue: 113/255)   // #F87171 (red-400)
    static let themeRed300 = Color(red: 254/255, green: 172/255, blue: 172/255)   // #FEACAC (red-300)

    // Yellow Scale (警告/硬件)
    static let themeYellow600 = Color(red: 180/255, green: 83/255, blue: 9/255)   // #B45309 (yellow-600)
    static let themeYellow500 = Color(red: 234/255, green: 179/255, blue: 8/255)  // #EAB308 (yellow-500)
    static let themeYellow400 = Color(red: 250/255, green: 204/255, blue: 21/255) // #FACC15 (yellow-400)
    static let themeYellow300 = Color(red: 253/255, green: 230/255, blue: 138/255) // #FDE68A (yellow-300)

    // Transparent variants (Tailwind bg-white/5, border-white/10, etc.)
    static let themeWhite5  = Color.white.opacity(0.02)   // bg-white/5
    static let themeWhite10 = Color.white.opacity(0.04)   // bg-white/10
    static let themeWhite20 = Color.white.opacity(0.08)   // bg-white/20
    static let themeWhite30 = Color.white.opacity(0.12)   // bg-white/30
    static let themeWhite50 = Color.white.opacity(0.20)   // bg-white/50
    static let themeWhite80 = Color.white.opacity(0.32)   // bg-white/80
    static let themeWhite90 = Color.white.opacity(0.36)   // bg-white/90

    // Black transparent
    static let themeBlack20 = Color.black.opacity(0.20)   // bg-black/20
    static let themeBlack30 = Color.black.opacity(0.30)   // bg-black/30
    static let themeBlack40 = Color.black.opacity(0.40)   // bg-black/40
    static let themeBlack50 = Color.black.opacity(0.50)   // bg-black/50

    // Semantic colors (从 note.jsx 映射)
    static let themeBackground   = themeGray900          // bg-gray-900/90
    static let themeCard         = themeWhite5           // bg-white/5
    static let themeBorder       = themeWhite10          // border-white/10
    static let themeBorderSubtle = themeWhite5           // border-white/5 (subtle borders)
    static let themeItem         = themeWhite5           // bg-white/5 (items)
    static let themeHover        = themeWhite20          // hover:bg-white/10
    static let themeInput        = themeBlack40          // bg-black/40 (inputs)
    static let themePanel        = themeBlack20          // bg-black/20 (sidebars/panels)
    static let themeTextPrimary  = themeGray200          // text-gray-200
    static let themeTextSecondary = themeGray400         // text-gray-400
    static let themeTextTertiary  = themeGray500         // text-gray-500

    // 动态透明度版本（用于悬停效果）
    func withAlpha(_ alpha: Double) -> Color {
        return self.opacity(alpha)
    }
}

// MARK: - Convenience Extensions for Tailwind-like Usage
//
// These extensions provide helper methods to convert Tailwind CSS syntax
// directly to SwiftUI Colors, making migration from React easier.
//
// Usage:
//   Color.fromTailwindAlpha(colorName: "white", alpha: 5)     // bg-white/5
//   Color.fromTailwindColorWithAlpha(baseColor: "gray-900", alpha: 90)  // bg-gray-900/90

extension Color {
    /// 从 note.jsx 的 bg-white/5 等语法转换
    /// - Parameters:
    ///   - colorName: "white" 或 "black"
    ///   - alpha: 5, 10, 20, 50, 80, 90 等
    static func fromTailwindAlpha(colorName: String, alpha: Int) -> Color {
        let baseColor: Color = colorName == "white" ? .white : .black
        let alphaValue = Double(alpha) / 1000.0 // 5 -> 0.005, 10 -> 0.01, 20 -> 0.02
        return baseColor.opacity(alphaValue)
    }

    /// 从 note.jsx 的 bg-gray-900/90 等语法转换
    /// - Parameters:
    ///   - baseColor: "gray-900", "blue-500" 等
    ///   - alpha: 50, 80, 90 等
    static func fromTailwindColorWithAlpha(baseColor: String, alpha: Int) -> Color {
        let baseColorValue: Color
        switch baseColor {
        case "gray-900": baseColorValue = .themeGray900
        case "gray-800": baseColorValue = .themeGray800
        case "gray-700": baseColorValue = .themeGray700
        case "gray-600": baseColorValue = .themeGray600
        case "gray-500": baseColorValue = .themeGray500
        case "gray-400": baseColorValue = .themeGray400
        case "gray-300": baseColorValue = .themeGray300
        case "gray-200": baseColorValue = .themeGray200
        case "gray-100": baseColorValue = .themeGray100
        case "blue-600": baseColorValue = .themeBlue600
        case "blue-500": baseColorValue = .themeBlue500
        case "blue-400": baseColorValue = .themeBlue400
        case "blue-300": baseColorValue = .themeBlue300
        case "purple-600": baseColorValue = .themePurple600
        case "purple-500": baseColorValue = .themePurple500
        case "purple-400": baseColorValue = .themePurple400
        case "purple-300": baseColorValue = .themePurple300
        case "green-600": baseColorValue = .themeGreen600
        case "green-500": baseColorValue = .themeGreen500
        case "green-400": baseColorValue = .themeGreen400
        case "green-300": baseColorValue = .themeGreen300
        case "red-600": baseColorValue = .themeRed600
        case "red-500": baseColorValue = .themeRed500
        case "red-400": baseColorValue = .themeRed400
        case "red-300": baseColorValue = .themeRed300
        case "yellow-600": baseColorValue = .themeYellow600
        case "yellow-500": baseColorValue = .themeYellow500
        case "yellow-400": baseColorValue = .themeYellow400
        case "yellow-300": baseColorValue = .themeYellow300
        default: baseColorValue = .themeGray400
        }
        return baseColorValue.opacity(Double(alpha) / 100.0)
    }
}

// MARK: - Color Utilities
//
// Additional utility methods for working with colors in the theme system.

extension Color {
    /// Create a color with a specific hex value
    /// - Parameter hex: Hex string like "#FF0000" or "FF0000"
    static func fromHex(_ hex: String) -> Color {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexString = hexString.replacingOccurrences(of: "#", with: "")

        if hexString.count == 3 {
            // Expand shorthand hex like #RGB to #RRGGBB
            let chars = Array(hexString)
            hexString = "\(chars[0])\(chars[0])\(chars[1])\(chars[1])\(chars[2])\(chars[2])"
        }

        var rgbValue: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgbValue)

        let red = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgbValue & 0x0000FF) / 255.0

        return Color(red: red, green: green, blue: blue)
    }

    /// Create a color with alpha from hex
    /// - Parameters:
    ///   - hex: Hex string
    ///   - alpha: Alpha value 0.0-1.0
    static func fromHex(_ hex: String, alpha: Double) -> Color {
        return fromHex(hex).opacity(alpha)
    }
}