import SwiftUI

// MARK: - Spacing System (Tailwind px scale)
//
// This file provides a complete mapping from Tailwind CSS spacing values
// to CGFloat values, based on the note.jsx React component.
//
// Usage:
//   .padding(ThemeSpacing.p4.rawValue)     // p-4
//   .frame(width: ThemeSpacing.w16.rawValue)  // w-16
//   .frame(height: ThemeSpacing.h12.rawValue) // h-12

enum ThemeSpacing: CGFloat {
    // Tailwind spacing scale (px to CGFloat)
    case px0   = 0     // 0
    case px1   = 4     // 1 (4px)
    case px2   = 8     // 2 (8px)
    case px3   = 12    // 3 (12px)
    case px4   = 16    // 4 (16px)
    case px5   = 20    // 5 (20px)
    case px6   = 24    // 6 (24px)
    case px8   = 32    // 8 (32px)
    case px10  = 40    // 10 (40px)
    case px12  = 48    // 12 (48px)
    case px16  = 64    // 16 (64px)
    case px20  = 80    // 20 (80px)
    case px24  = 96    // 24 (96px)
    case px32  = 128   // 32 (128px)

    // Computed values for convenience
    var rawValue: CGFloat {
        switch self {
        case .px0: return 0
        case .px1: return 4
        case .px2: return 8
        case .px3: return 12
        case .px4: return 16
        case .px5: return 20
        case .px6: return 24
        case .px8: return 32
        case .px10: return 40
        case .px12: return 48
        case .px16: return 64
        case .px20: return 80
        case .px24: return 96
        case .px32: return 128
        }
    }
}

// MARK: - Common Padding/Margin Values from note.jsx
//
// These are commonly used padding and margin values extracted from the React component.

extension ThemeSpacing {
    // Common padding/margin values from note.jsx
    static let p2  = ThemeSpacing.px8    // p-2
    static let p3  = ThemeSpacing.px12   // p-3
    static let p4  = ThemeSpacing.px16   // p-4
    static let p6  = ThemeSpacing.px24   // p-6
    static let p8  = ThemeSpacing.px32   // p-8
    static let p10 = ThemeSpacing.px10   // p-10 (使用 px10)
    static let p12 = ThemeSpacing.px12   // p-12
    static let p16 = ThemeSpacing.px16   // p-16

    // Width/Height (from note.jsx)
    static let w16 = ThemeSpacing.px16    // w-16 (sidebar width)
    static let h12 = ThemeSpacing.px12    // h-12 (header height)
    static let h8  = ThemeSpacing.px8     // h-8 (footer height)
    static let h1  = ThemeSpacing.px1     // h-1 (divider height)

    // Border width
    static let border1 = CGFloat(1)
    static let border2 = CGFloat(2)
}

// MARK: - View Extensions for Spacing
//
// These extensions provide convenient methods for applying spacing to views.

extension View {
    /// Apply padding with ThemeSpacing value
    /// - Parameter spacing: ThemeSpacing value
    /// - Returns: View with padding applied
    func padding(_ spacing: ThemeSpacing) -> some View {
        return self.padding(spacing.rawValue)
    }

    /// Apply padding with individual values
    /// - Parameters:
    ///   - top: Top padding
    ///   - leading: Leading padding
    ///   - bottom: Bottom padding
    ///   - trailing: Trailing padding
    /// - Returns: View with padding applied
    func padding(_ top: CGFloat, _ leading: CGFloat, _ bottom: CGFloat, _ trailing: CGFloat) -> some View {
        return self.padding(.top, top)
            .padding(.leading, leading)
            .padding(.bottom, bottom)
            .padding(.trailing, trailing)
    }

    /// Apply margin using offset (Note: SwiftUI doesn't have direct margin)
    /// - Parameters:
    ///   - top: Top margin
    ///   - leading: Leading margin
    ///   - bottom: Bottom margin
    ///   - trailing: Trailing margin
    /// - Returns: View with margin applied
    func margin(_ top: CGFloat, _ leading: CGFloat, _ bottom: CGFloat, _ trailing: CGFloat) -> some View {
        return self.offset(x: leading - trailing, y: top - bottom)
    }

    /// Apply frame with ThemeSpacing values
    /// - Parameters:
    ///   - width: Width (optional)
    ///   - height: Height (optional)
    /// - Returns: View with frame applied
    func frame(width: ThemeSpacing? = nil, height: ThemeSpacing? = nil) -> some View {
        return self.frame(
            width: width?.rawValue,
            height: height?.rawValue
        )
    }

    /// Apply frame with size
    /// - Parameter size: CGSize
    /// - Returns: View with frame applied
    func frame(size: CGSize) -> some View {
        return self.frame(width: size.width, height: size.height)
    }

    /// Apply square frame
    /// - Parameter size: Side length
    /// - Returns: View with square frame applied
    func frame(square size: CGFloat) -> some View {
        return self.frame(width: size, height: size)
    }

    /// Apply minimum width
    /// - Parameter width: Minimum width
    /// - Returns: View with minimum width applied
    func minWidth(_ width: ThemeSpacing) -> some View {
        return self.frame(minWidth: width.rawValue)
    }

    /// Apply minimum height
    /// - Parameter height: Minimum height
    /// - Returns: View with minimum height applied
    func minHeight(_ height: ThemeSpacing) -> some View {
        return self.frame(minHeight: height.rawValue)
    }

    /// Apply maximum width
    /// - Parameter width: Maximum width
    /// - Returns: View with maximum width applied
    func maxWidth(_ width: ThemeSpacing) -> some View {
        return self.frame(maxWidth: width.rawValue)
    }

    /// Apply maximum height
    /// - Parameter height: Maximum height
    /// - Returns: View with maximum height applied
    func maxHeight(_ height: ThemeSpacing) -> some View {
        return self.frame(maxHeight: height.rawValue)
    }

    /// Apply fixed spacing between views
    /// - Parameter spacing: ThemeSpacing value
    /// - Returns: View with spacing applied
    func spacing(_ spacing: ThemeSpacing) -> some View {
        return self.padding(.all, spacing.rawValue)
    }

    /// Apply vertical spacing
    /// - Parameter spacing: ThemeSpacing value
    /// - Returns: View with vertical spacing applied
    func verticalSpacing(_ spacing: ThemeSpacing) -> some View {
        return self.padding(.vertical, spacing.rawValue)
    }

    /// Apply horizontal spacing
    /// - Parameter spacing: ThemeSpacing value
    /// - Returns: View with horizontal spacing applied
    func horizontalSpacing(_ spacing: ThemeSpacing) -> some View {
        return self.padding(.horizontal, spacing.rawValue)
    }
}

// MARK: - VStack Extensions for Spacing
//
// Convenience extensions for VStack spacing.

extension VStack {
    /// Create VStack with ThemeSpacing spacing
    /// - Parameters:
    ///   - spacing: ThemeSpacing value
    ///   - content: View content
    init(spacing: ThemeSpacing, @ViewBuilder content: () -> Content) {
        self.init(spacing: spacing.rawValue, content: content)
    }
}

// MARK: - HStack Extensions for Spacing
//
// Convenience extensions for HStack spacing.

extension HStack {
    /// Create HStack with ThemeSpacing spacing
    /// - Parameters:
    ///   - spacing: ThemeSpacing value
    ///   - content: View content
    init(spacing: ThemeSpacing, @ViewBuilder content: () -> Content) {
        self.init(spacing: spacing.rawValue, content: content)
    }
}

// MARK: - ZStack Extensions for Spacing
//
// Convenience extensions for ZStack spacing.

extension ZStack {
    /// Create ZStack with ThemeSpacing spacing
    /// - Parameters:
    ///   - spacing: ThemeSpacing value
    ///   - content: View content
    init(spacing: ThemeSpacing, @ViewBuilder content: () -> Content) {
        self.init(content: content)
    }
}

// MARK: - Spacing Utilities
//
// Additional utilities for working with spacing.

struct Spacing {
    /// Create a spacer with fixed height
    /// - Parameter height: ThemeSpacing value
    /// - Returns: Spacer with fixed height
    static func vertical(_ height: ThemeSpacing) -> some View {
        return Spacer().frame(height: height.rawValue)
    }

    /// Create a spacer with fixed width
    /// - Parameter width: ThemeSpacing value
    /// - Returns: Spacer with fixed width
    static func horizontal(_ width: ThemeSpacing) -> some View {
        return Spacer().frame(width: width.rawValue)
    }

    /// Create a fixed-size spacer
    /// - Parameter size: ThemeSpacing value for both width and height
    /// - Returns: Spacer with fixed size
    static func fixed(_ size: ThemeSpacing) -> some View {
        return Spacer().frame(width: size.rawValue, height: size.rawValue)
    }
}