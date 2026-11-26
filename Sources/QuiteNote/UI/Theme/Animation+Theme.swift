import SwiftUI

// MARK: - Animation Duration (ms to seconds)
//
// This file provides a complete mapping from Tailwind CSS animation durations
// to SwiftUI Animation values, based on the note.jsx React component.
//
// Usage:
//   .animation(.easeOut(duration: ThemeDuration.`300`.rawValue), value: someValue)
//   .animation(.customBezier, value: someValue)
//   .transition(.slideRight)

enum ThemeDuration: Double {
    case _100 = 0.1      // 100ms
    case _200 = 0.2      // 200ms
    case _300 = 0.3      // 300ms
    case _500 = 0.5      // 500ms
    case _1000 = 1.0     // 1000ms
}

// MARK: - Easing Functions
//
// Common easing functions used in the React component.

extension Animation {
    static let easeIn = Animation.easeIn(duration: ThemeDuration._300.rawValue)
    static let easeOut = Animation.easeOut(duration: ThemeDuration._300.rawValue)
    static let easeInOut = Animation.easeInOut(duration: ThemeDuration._300.rawValue)

    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.0)

    // Custom cubic-bezier from note.jsx (悬浮窗展开)
    static let customBezier = Animation.timingCurve(0.34, 1.56, 0.64, 1.0, duration: ThemeDuration._500.rawValue)

    // Pulse animation (animate-pulse)
    static let pulse = Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)

    // Spin animation (animate-spin)
    static let spin = Animation.linear(duration: 1.0).repeatForever(autoreverses: false)

    // Toast animation
    static let toast = Animation.easeInOut(duration: ThemeDuration._300.rawValue)

    // Fade animation
    static let fade = Animation.easeInOut(duration: ThemeDuration._200.rawValue)

    // Slide animation
    static let slide = Animation.easeInOut(duration: ThemeDuration._300.rawValue)

    // Scale animation
    static let scale = Animation.spring(response: 0.2, dampingFraction: 0.8, blendDuration: 0.0)
}

// MARK: - Transition Presets
//
// Common transitions used in the React component.

extension AnyTransition {
    static let slideRight = AnyTransition.move(edge: .trailing).combined(with: .opacity)
    static let slideLeft = AnyTransition.move(edge: .leading).combined(with: .opacity)
    static let slideTop = AnyTransition.move(edge: .top).combined(with: .opacity)
    static let slideBottom = AnyTransition.move(edge: .bottom).combined(with: .opacity)

    // Toast transitions
    static let toastIn = AnyTransition.move(edge: .top).combined(with: .opacity)
    static let toastOut = AnyTransition.move(edge: .top).combined(with: .opacity)

    // Settings panel transitions
    static let settingsIn = AnyTransition.move(edge: .trailing).combined(with: .opacity)
    static let settingsOut = AnyTransition.move(edge: .trailing).combined(with: .opacity)

    // Card expand transitions
    static let expand = AnyTransition.scale.combined(with: .opacity)
    static let collapse = AnyTransition.scale.combined(with: .opacity)
}

