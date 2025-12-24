import Foundation
import AppKit

/// FloatingPanel 相关常量定义
enum FloatingPanelConstants {
    /// 窗口默认尺寸
    static let defaultWidth: CGFloat = 520
    static let defaultHeight: CGFloat = 640

    /// 浮球窗口尺寸
    static let ballSize: CGFloat = 80
    static let ballRadius: CGFloat = 56

    /// 动画时长
    static let fadeInDuration: TimeInterval = 0.3
    static let fadeOutDuration: TimeInterval = 0.5
    static let minimizeDuration: TimeInterval = 0.35
    static let restoreDuration: TimeInterval = 0.4

    /// 延迟时间
    static let hoverFocusDelay: TimeInterval = 0.6
    static let revertDelay: TimeInterval = 0.3
    static let launchReinforceDelay: TimeInterval = 0.2

    /// 边界值
    static let screenPadding: CGFloat = 16
    static let screenMinPadding: CGFloat = 100

    /// 交互防抖时间
    static let interactionDebounceDelay: TimeInterval = 0.5
}
