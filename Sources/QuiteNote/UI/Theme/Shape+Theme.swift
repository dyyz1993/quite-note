import SwiftUI

// MARK: - Border Radius System (Tailwind rounded scale)
//
// This file provides a complete mapping from Tailwind CSS border radius values
// to CGFloat values, based on the note.jsx React component.
//
// Usage:
//   .cornerRadius(ThemeRadius.lg.rawValue)  // rounded-lg
//   .cornerRadius(ThemeRadius.full.rawValue) // rounded-full

enum ThemeRadius: CGFloat {
    // Tailwind border radius
    case none = 0       // rounded-none
    case sm   = 2       // rounded-sm
    case base = 4       // rounded
    case md   = 6       // rounded-md
    case lg   = 8       // rounded-lg
    case xl   = 12      // rounded-xl
    case xxl  = 16      // rounded-2xl
    case xxxl = 24      // rounded-3xl
    case full  = 9999   // rounded-full
}

// MARK: - Border System
//
// Border width and color definitions.

struct ThemeBorder {
    let width: CGFloat
    let color: Color

    static let thin = ThemeBorder(width: ThemeRadius.base.rawValue, color: .themeBorder)
    static let medium = ThemeBorder(width: ThemeRadius.md.rawValue, color: .themeBorder)
    static let thick = ThemeBorder(width: ThemeRadius.lg.rawValue, color: .themeBorder)
}

// MARK: - View Extensions for Shapes
//
// These extensions provide convenient methods for applying shapes and borders to views.

extension View {
    /// Apply corner radius with ThemeRadius value
    /// - Parameter radius: ThemeRadius value
    /// - Returns: View with corner radius applied
    func cornerRadius(_ radius: ThemeRadius) -> some View {
        return self.cornerRadius(radius.rawValue)
    }

    /// Apply border with ThemeBorder
    /// - Parameter border: ThemeBorder definition
    /// - Returns: View with border applied
    func border(_ border: ThemeBorder) -> some View {
        return self.overlay(
            RoundedRectangle(cornerRadius: ThemeRadius.base.rawValue)
                .stroke(border.color, lineWidth: border.width)
        )
    }

    /// Apply simple border with width and color
    /// - Parameters:
    ///   - width: Border width
    ///   - color: Border color (defaults to themeBorder)
    /// - Returns: View with border applied
    func border(width: CGFloat = ThemeRadius.base.rawValue, color: Color = .themeBorder) -> some View {
        return self.overlay(
            RoundedRectangle(cornerRadius: ThemeRadius.base.rawValue)
                .stroke(color, lineWidth: width)
        )
    }

    /// Apply shadow with theme-appropriate defaults
    /// - Parameters:
    ///   - color: Shadow color (defaults to black with 50% opacity)
    ///   - radius: Shadow blur radius
    ///   - x: Horizontal offset (defaults to 0)
    ///   - y: Vertical offset (defaults to 0)
    /// - Returns: View with shadow applied
    func themeShadow(color: Color = .black, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        return self.shadow(color: color.opacity(0.5), radius: radius, x: x, y: y)
    }

    /// Apply inset shadow (inner shadow effect)
    /// - Parameters:
    ///   - color: Shadow color
    ///   - radius: Shadow blur radius
    ///   - x: Horizontal offset (defaults to 0)
    ///   - y: Vertical offset (defaults to 0)
    /// - Returns: View with inset shadow applied
    func insetShadow(color: Color = .black, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        return self.overlay(
            RoundedRectangle(cornerRadius: ThemeRadius.base.rawValue)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            color.opacity(0.3),
                            color.opacity(0.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .mask(RoundedRectangle(cornerRadius: ThemeRadius.base.rawValue))
        )
    }

    /// Clip view to rounded rectangle shape
    /// - Parameter radius: Corner radius
    /// - Returns: View clipped to rounded rectangle
    func clipRounded(radius: ThemeRadius = .base) -> some View {
        return self.clipShape(RoundedRectangle(cornerRadius: radius.rawValue))
    }

    /// Clip view to circle shape
    /// - Returns: View clipped to circle
    func clipCircle() -> some View {
        return self.clipShape(Circle())
    }

    /// Apply theme-appropriate card styling
    /// - Parameters:
    ///   - cornerRadius: Corner radius (defaults to lg)
    ///   - shadow: Whether to add shadow (defaults to true)
    /// - Returns: View with card styling applied
    func cardStyle(cornerRadius: ThemeRadius = .lg, shadow: Bool = true) -> some View {
        return self
            .background(Color.themeCard)
            .cornerRadius(cornerRadius.rawValue)
            .border(width: ThemeRadius.base.rawValue, color: Color.themeBorder)
            .applyShadowIfNeeded(shadow: shadow, color: .black, radius: 20, x: 0, y: 10)
    }

    // Helper method to apply shadow conditionally
    private func applyShadowIfNeeded(shadow: Bool, color: Color = .black, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        if shadow {
            return AnyView(self.themeShadow(color: color, radius: radius, x: x, y: y))
        } else {
            return AnyView(self)
        }
    }

    /// Apply theme-appropriate button styling
    /// - Parameters:
    ///   - cornerRadius: Corner radius (defaults to md)
    ///   - background: Background color (defaults to white/10)
    ///   - shadow: Whether to add shadow (defaults to true)
    /// - Returns: View with button styling applied
    func buttonStyle(
        cornerRadius: ThemeRadius = .md,
        background: Color = .themeItem,
        shadow: Bool = true
    ) -> some View {
        return self
            .background(background)
            .cornerRadius(cornerRadius.rawValue)
            .border(width: ThemeRadius.base.rawValue, color: Color.themeBorder)
            .applyShadowIfNeeded(shadow: shadow, color: .black, radius: 8, x: 0, y: 2)
    }

    /// Apply theme-appropriate input field styling
    /// - Parameters:
    ///   - cornerRadius: Corner radius (defaults to base)
    ///   - background: Background color (defaults to black/40)
    /// - Returns: View with input styling applied
    func inputStyle(
        cornerRadius: ThemeRadius = .base,
        background: Color = .themeInput
    ) -> some View {
        return self
            .background(background)
            .cornerRadius(cornerRadius.rawValue)
            .border(width: ThemeRadius.base.rawValue, color: Color.themeBorder)
    }

    /// Apply theme-appropriate panel styling
    /// - Parameters:
    ///   - cornerRadius: Corner radius (defaults to xxl)
    ///   - shadow: Whether to add shadow (defaults to true)
    /// - Returns: View with panel styling applied
    func panelStyle(
        cornerRadius: ThemeRadius = .xxl,
        shadow: Bool = true
    ) -> some View {
        return self
            .background(Color.themeBackground)
            .cornerRadius(cornerRadius.rawValue)
            .border(width: ThemeRadius.base.rawValue, color: Color.themeBorder)
            .applyShadowIfNeeded(shadow: shadow, color: .black, radius: 20, x: 0, y: 10)
    }
}

// MARK: - Shape Extensions
//
// Additional shape utilities.

struct ThemeShapes {
    /// Create a rounded rectangle with theme corner radius
    /// - Parameters:
    ///   - cornerRadius: Corner radius (defaults to lg)
    /// - Returns: RoundedRectangle
    static func roundedRectangle(cornerRadius: ThemeRadius = .lg) -> RoundedRectangle {
        return RoundedRectangle(cornerRadius: cornerRadius.rawValue)
    }

    /// Create a capsule shape (pill)
    /// - Returns: Capsule
    static func capsule() -> Capsule {
        return Capsule()
    }

    /// Create a circle
    /// - Returns: Circle
    static func circle() -> Circle {
        return Circle()
    }
}

// MARK: - Border Utilities
//
// Additional utilities for working with borders.

struct Border {
    /// Create a top border
    /// - Parameters:
    ///   - width: Border width (defaults to 1)
    ///   - color: Border color (defaults to themeBorder)
    /// - Returns: View with top border
    static func top(width: CGFloat = ThemeRadius.base.rawValue, color: Color = .themeBorder) -> some View {
        return Rectangle()
            .fill(color)
            .frame(height: width)
    }

    /// Create a bottom border
    /// - Parameters:
    ///   - width: Border width (defaults to 1)
    ///   - color: Border color (defaults to themeBorder)
    /// - Returns: View with bottom border
    static func bottom(width: CGFloat = ThemeRadius.base.rawValue, color: Color = .themeBorder) -> some View {
        return Rectangle()
            .fill(color)
            .frame(height: width)
    }

    /// Create a left border
    /// - Parameters:
    ///   - width: Border width (defaults to 1)
    ///   - color: Border color (defaults to themeBorder)
    /// - Returns: View with left border
    static func left(width: CGFloat = ThemeRadius.base.rawValue, color: Color = .themeBorder) -> some View {
        return Rectangle()
            .fill(color)
            .frame(width: width)
    }

    /// Create a right border
    /// - Parameters:
    ///   - width: Border width (defaults to 1)
    ///   - color: Border color (defaults to themeBorder)
    /// - Returns: View with right border
    static func right(width: CGFloat = ThemeRadius.base.rawValue, color: Color = .themeBorder) -> some View {
        return Rectangle()
            .fill(color)
            .frame(width: width)
    }
}