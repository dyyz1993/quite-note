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

// MARK: - View Extensions for Animations
//
// These extensions provide convenient methods for applying animations to views.

extension View {
    /// Apply theme animation
    /// - Parameters:
    ///   - duration: Animation duration (defaults to 300ms)
    ///   - curve: Animation curve (defaults to easeOut)
    /// - Returns: View with animation applied
    func animateIn(duration: ThemeDuration = ._300, curve: Animation = .easeOut) -> some View {
        return self.animation(curve, value: UUID())
    }

    /// Apply theme animation with explicit duration
    /// - Parameter duration: Animation duration
    /// - Returns: View with animation applied
    func animateInOut(duration: ThemeDuration = ._300) -> some View {
        return self.animation(Animation.easeInOut(duration: duration.rawValue), value: UUID())
    }

    /// Apply spring animation
    /// - Parameters:
    ///   - response: Response time
    ///   - dampingFraction: Damping fraction
    /// - Returns: View with spring animation applied
    func animateSpring(response: Double = 0.3, dampingFraction: Double = 0.7) -> some View {
        return self.animation(
            Animation.spring(response: response, dampingFraction: dampingFraction, blendDuration: 0.0),
            value: UUID()
        )
    }

    /// Apply custom bezier animation
    /// - Parameters:
    ///   - c1x: First control point x
    ///   - c1y: First control point y
    ///   - c2x: Second control point x
    ///   - c2y: Second control point y
    ///   - duration: Animation duration
    /// - Returns: View with custom bezier animation applied
    func animateBezier(c1x: Double, c1y: Double, c2x: Double, c2y: Double, duration: ThemeDuration = ._500) -> some View {
        return self.animation(
            Animation.timingCurve(c1x, c1y, c2x, c2y, duration: duration.rawValue),
            value: UUID()
        )
    }

    /// Apply pulse animation
    /// - Parameter duration: Animation duration (defaults to 1.5s)
    /// - Returns: View with pulse animation applied
    func animatePulse(duration: Double = 1.5) -> some View {
        return self.animation(
            Animation.easeInOut(duration: duration).repeatForever(autoreverses: true),
            value: UUID()
        )
    }

    /// Apply spin animation
    /// - Parameter duration: Animation duration (defaults to 1.0s)
    /// - Returns: View with spin animation applied
    func animateSpin(duration: Double = 1.0) -> some View {
        return self.animation(
            Animation.linear(duration: duration).repeatForever(autoreverses: false),
            value: UUID()
        )
    }

    /// Apply toast animation
    /// - Returns: View with toast animation applied
    func animateToast() -> some View {
        return self.animation(Animation.toast, value: UUID())
    }

    /// Apply fade animation
    /// - Returns: View with fade animation applied
    func animateFade() -> some View {
        return self.animation(Animation.fade, value: UUID())
    }

    /// Apply slide animation
    /// - Returns: View with slide animation applied
    func animateSlide() -> some View {
        return self.animation(Animation.slide, value: UUID())
    }

    /// Apply scale animation
    /// - Returns: View with scale animation applied
    func animateScale() -> some View {
        return self.animation(Animation.scale, value: UUID())
    }
}

// MARK: - Transition Extensions
//
// Convenience extensions for applying transitions.

extension View {
    /// Apply slide right transition
    /// - Returns: View with slide right transition
    func transitionSlideRight() -> some View {
        return self.transition(.slideRight)
    }

    /// Apply slide left transition
    /// - Returns: View with slide left transition
    func transitionSlideLeft() -> some View {
        return self.transition(.slideLeft)
    }

    /// Apply slide top transition
    /// - Returns: View with slide top transition
    func transitionSlideTop() -> some View {
        return self.transition(.slideTop)
    }

    /// Apply slide bottom transition
    /// - Returns: View with slide bottom transition
    func transitionSlideBottom() -> some View {
        return self.transition(.slideBottom)
    }

    /// Apply toast in transition
    /// - Returns: View with toast in transition
    func transitionToastIn() -> some View {
        return self.transition(.toastIn)
    }

    /// Apply toast out transition
    /// - Returns: View with toast out transition
    func transitionToastOut() -> some View {
        return self.transition(.toastOut)
    }

    /// Apply settings in transition
    /// - Returns: View with settings in transition
    func transitionSettingsIn() -> some View {
        return self.transition(.settingsIn)
    }

    /// Apply settings out transition
    /// - Returns: View with settings out transition
    func transitionSettingsOut() -> some View {
        return self.transition(.settingsOut)
    }

    /// Apply expand transition
    /// - Returns: View with expand transition
    func transitionExpand() -> some View {
        return self.transition(.expand)
    }

    /// Apply collapse transition
    /// - Returns: View with collapse transition
    func transitionCollapse() -> some View {
        return self.transition(.collapse)
    }
}

// MARK: - Animation Utilities
//
// Additional utilities for working with animations.

struct AnimationUtils {
    /// Create a delayed animation
    /// - Parameters:
    ///   - delay: Delay before animation starts
    ///   - animation: The animation to apply
    /// - Returns: Modified animation with delay
    static func delayed(delay: Double, animation: Animation) -> Animation {
        return animation.delay(delay)
    }

    /// Create a repeated animation
    /// - Parameters:
    ///   - count: Number of repetitions
    ///   - autoreverses: Whether to reverse after each repetition
    ///   - animation: The animation to repeat
    /// - Returns: Repeated animation
    static func repeated(count: Int, autoreverses: Bool = false, animation: Animation) -> Animation {
        return animation.repeatCount(count, autoreverses: autoreverses)
    }

    /// Create an infinite animation
    /// - Parameters:
    ///   - autoreverses: Whether to reverse after each repetition
    ///   - animation: The animation to repeat infinitely
    /// - Returns: Infinite animation
    static func infinite(autoreverses: Bool = false, animation: Animation) -> Animation {
        return animation.repeatForever(autoreverses: autoreverses)
    }

    /// Create a combined transition
    /// - Parameters:
    ///   - transition1: First transition
    ///   - transition2: Second transition
    /// - Returns: Combined transition
    static func combined(transition1: AnyTransition, transition2: AnyTransition) -> AnyTransition {
        return transition1.combined(with: transition2)
    }
}

// MARK: - Animation Presets
//
// Common animation presets for specific use cases.

struct AnimationPresets {
    /// Toast animation preset
    static let toast: Animation = .toast

    /// Button press animation preset
    static let buttonPress: Animation = .spring(response: 0.2, dampingFraction: 0.8)

    /// Card hover animation preset
    static let cardHover: Animation = .easeOut(duration: ThemeDuration._200.rawValue)

    /// Settings panel animation preset
    static let settingsPanel: Animation = .customBezier

    /// Record card expand animation preset
    static let recordCardExpand: Animation = .spring(response: 0.3, dampingFraction: 0.7)

    /// Loading spinner animation preset
    static let loadingSpinner: Animation = .spin

    /// Success pulse animation preset
    static let successPulse: Animation = .pulse

    /// Error shake animation preset
    static func errorShake() -> Animation {
        return Animation.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.3)
    }
}