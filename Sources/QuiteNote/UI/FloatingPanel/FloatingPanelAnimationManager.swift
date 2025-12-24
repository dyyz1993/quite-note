import Foundation
import AppKit

/// 窗口动画管理器 - 负责窗口动画效果
final class FloatingPanelAnimationManager {
    private weak var panel: NSPanel?
    private var isEnabled: Bool = true

    init(panel: NSPanel, animationsEnabled: Bool = true) {
        self.panel = panel
        self.isEnabled = animationsEnabled
    }

    /// 更新动画开关状态
    func setAnimationsEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    // MARK: - 显示/隐藏动画

    /// 执行淡入动画
    func performFadeIn(completion: (() -> Void)? = nil) {
        guard let panel = panel else { return }

        panel.alphaValue = 1

        if isEnabled {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = FloatingPanelConstants.fadeInDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            } completionHandler: {
                completion?()
            }
        } else {
            completion?()
        }
    }

    /// 执行淡出动画
    func performFadeOut(completion: (() -> Void)? = nil) {
        guard let panel = panel else { return }

        if isEnabled {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = FloatingPanelConstants.fadeOutDuration
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.6, 1.0)
                panel.animator().alphaValue = 0
            } completionHandler: { [weak panel] in
                panel?.orderOut(nil)
                panel?.alphaValue = 1
                NSApp.setActivationPolicy(.accessory)
                completion?()
            }
        } else {
            panel.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
            completion?()
        }
    }

    // MARK: - 浮球动画

    /// 执行最小化到浮球的动画
    func performMinimizeToBall(targetFrame: NSRect, completion: (() -> Void)? = nil) {
        guard let panel = panel else { return }

        let duration = FloatingPanelConstants.minimizeDuration

        // 先切换背景和阴影，避免动画过程中出现黑边
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = false

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: {
            completion?()
        }
    }

    /// 执行从浮球恢复的动画
    func performRestoreFromBall(targetFrame: NSRect, completion: (() -> Void)? = nil) {
        guard let panel = panel else { return }

        let duration = FloatingPanelConstants.restoreDuration

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak panel] in
            // 动画结束后恢复背景
            panel?.backgroundColor = NSColor.clear.withAlphaComponent(0.9)
            panel?.hasShadow = true
            completion?()
        }
    }
}
