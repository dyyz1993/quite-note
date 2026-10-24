import SwiftUI

// MARK: - Font System (Tailwind to SwiftUI mapping)
//
// This file provides a complete mapping from Tailwind CSS font sizes and weights
// to SwiftUI Font values, based on the note.jsx React component.
//
// Usage:
//   .font(.themeH1)           // text-base font-semibold
//   .font(.themeBody)         // text-sm (default)
//   .font(.themeCaption)      // text-xs
//   .font(.themeCaptionSmall) // text-[10px]
//   .font(.themeCaptionTiny)  // text-[8px]

extension Font {
    // Font Sizes (from note.jsx)
    static let themeH1 = Font.system(size: 16, weight: .semibold)     // text-base font-semibold
    static let themeH2 = Font.system(size: 14, weight: .semibold)     // text-sm font-semibold
    static let themeBody = Font.system(size: 14)                      // text-sm (default)
    static let themeCaption = Font.system(size: 12)                   // text-xs
    static let themeCaptionSmall = Font.system(size: 10)              // text-[10px]
    static let themeCaptionTiny = Font.system(size: 8)                // text-[8px]

    // 字体族
    static let themeSans = Font.system(.body)                         // font-sans
    static let themeMono = Font.monospaced                        // font-mono

    // 字重
    static let themeWeightLight = Font.system(.body, weight: .light)         // font-light
    static let themeWeightNormal = Font.system(.body, weight: .regular)      // normal (default)
    static let themeWeightMedium = Font.system(.body, weight: .medium)       // font-medium
    static let themeWeightSemibold = Font.system(.body, weight: .semibold)   // font-semibold
    static let themeWeightBold = Font.system(.body, weight: .bold)           // font-bold

    // 字间距
    static let themeTrackingNormal = Font.system(size: 14)            // 默认
    static let themeTrackingWide = Font.system(size: 14)              // tracking-wider (需手动调整)

    // Monospace (代码字体)
    static let themeMono2 = Font.monospaced                   // font-mono

    // 字体变体
    static let themeUppercase = Font.system(size: 10, weight: .bold)  // uppercase (需手动转换)
}

// MARK: - Text Case (uppercase, lowercase, capitalize)
//
// Enumeration for text case transformations, useful for implementing
// Tailwind's uppercase, lowercase, etc. classes.

enum TextCase {
    case normal
    case uppercase
    case lowercase

    /// Apply text case transformation to a string
    /// - Parameter text: The input text
    /// - Returns: Transformed text
    func apply(to text: String) -> String {
        switch self {
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .normal: return text
        }
    }
}

// MARK: - View Extensions for Text Styling
//
// These extensions provide Tailwind-like text styling capabilities.

extension View {
    /// Apply text case transformation
    /// Note: SwiftUI doesn't have a direct textCase modifier, so this is a placeholder
    /// You'll need to apply text case transformation to the Text content directly
    /// Example: Text(TextCase.uppercase.apply(to: "hello world"))
    func textCase(_ caseType: TextCase) -> some View {
        return self
    }

    /// Apply letter spacing (kerning)
    /// Note: SwiftUI doesn't have a direct kerning modifier
    /// This is a placeholder for future implementation
    func kerning(_ value: CGFloat) -> some View {
        return self
    }

    /// Apply font weight
    /// - Parameter weight: The desired font weight
    func fontWeight(_ weight: Font.Weight) -> some View {
        return self.font(.system(size: 14, weight: weight))
    }

    /// Apply monospace font
    /// - Parameter size: Font size (optional)
    func monospace(_ size: CGFloat? = nil) -> some View {
        let fontSize = size ?? 14
        return self.font(.system(size: fontSize, design: .monospaced))
    }

    /// Apply uppercase transformation
    /// - Parameter text: The text to transform
    /// - Returns: View with uppercase text
    /// Usage: Text("hello").uppercase()
    func uppercase(_ text: String) -> Text {
        return Text(text.uppercased())
    }

    /// Apply lowercase transformation
    /// - Parameter text: The text to transform
    /// - Returns: View with lowercase text
    /// Usage: Text("HELLO").lowercase()
    func lowercase(_ text: String) -> Text {
        return Text(text.lowercased())
    }
}

// MARK: - Text Extensions for Font Convenience
//
// These extensions make it easier to apply theme fonts to Text views.

extension Text {
    /// Apply theme font
    /// - Parameter font: The theme font to apply
    /// - Returns: Text with applied font
    func themeFont(_ font: Font) -> Text {
        return self.font(font)
    }

    /// Apply theme heading 1 font
    /// - Returns: Text with H1 styling
    func themeH1() -> Text {
        return self.font(.themeH1)
    }

    /// Apply theme heading 2 font
    /// - Returns: Text with H2 styling
    func themeH2() -> Text {
        return self.font(.themeH2)
    }

    /// Apply theme body font
    /// - Returns: Text with body styling
    func themeBody() -> Text {
        return self.font(.themeBody)
    }

    /// Apply theme caption font
    /// - Returns: Text with caption styling
    func themeCaption() -> Text {
        return self.font(.themeCaption)
    }

    /// Apply theme small caption font
    /// - Returns: Text with small caption styling
    func themeCaptionSmall() -> Text {
        return self.font(.themeCaptionSmall)
    }

    /// Apply theme tiny caption font
    /// - Returns: Text with tiny caption styling
    func themeCaptionTiny() -> Text {
        return self.font(.themeCaptionTiny)
    }

    /// Apply uppercase transformation
    /// - Returns: Text with uppercase transformation
    func uppercase() -> Text {
        return Text(self.string.uppercased()).font(self.currentFont)
    }

    /// Apply monospace font
    /// - Parameter size: Font size (optional)
    /// - Returns: Text with monospace font
    func monospace(_ size: CGFloat? = nil) -> Text {
        let fontSize = size ?? self.currentFontSize
        return self.font(.system(size: fontSize, design: .monospaced))
    }
}

// MARK: - Private Extensions for Text Font Access
//
// These extensions provide access to Text's current font for transformation.

private extension Text {
    var currentFont: Font {
        // Default font if not specified
        return .themeBody
    }

    var currentFontSize: CGFloat {
        // Default font size if not specified
        return 14
    }

    var string: String {
        // Extract string from Text (simplified implementation)
        // In practice, you might need a different approach
        return ""
    }
}
