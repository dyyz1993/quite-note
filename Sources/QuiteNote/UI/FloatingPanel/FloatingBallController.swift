import Foundation
import AppKit
import SwiftUI

/// 浮球模式控制器 - 管理窗口和浮球之间的转换
final class FloatingBallController {
    private weak var panel: NSPanel?
    private let layoutManager: FloatingPanelLayoutManager
    private let animationManager: FloatingPanelAnimationManager
    private unowned let focusProvider: WindowFocusProvider

    @Published var mode: WindowMode = .expanded

    init(panel: NSPanel,
         layoutManager: FloatingPanelLayoutManager,
         animationManager: FloatingPanelAnimationManager,
         focusProvider: WindowFocusProvider) {
        self.panel = panel
        self.layoutManager = layoutManager
        self.animationManager = animationManager
        self.focusProvider = focusProvider
    }

    // MARK: - 模式切换

    /// 切换到浮球模式
    func minimizeToBall() {
        guard mode == .expanded, let panel = panel else { return }

        let currentFrame = panel.frame
        focusProvider.lastExpandedFrame = currentFrame

        // 保存位置
        layoutManager.saveCurrentPosition()

        // 计算目标位置
        let targetCenter = focusProvider.ballPosition != .zero ?
            focusProvider.ballPosition :
            layoutManager.calculateBallPosition(from: currentFrame)
        let targetFrame = layoutManager.calculateBallFrame(center: targetCenter)

        // 执行动画
        withAnimation(.easeInOut(duration: FloatingPanelConstants.minimizeDuration)) {
            self.mode = .floatingBall
        }

        animationManager.performMinimizeToBall(targetFrame: targetFrame) { [weak self] in
            // 更新球位置
            self?.focusProvider.ballPosition = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        }
    }

    /// 从浮球模式恢复
    func restoreFromBall(completion: (() -> Void)? = nil) {
        guard mode == .floatingBall, let panel = panel else { return }

        let ballFrame = panel.frame
        let ballCenter = CGPoint(x: ballFrame.midX, y: ballFrame.midY)

        // 记录球心位置
        focusProvider.ballPosition = ballCenter
        focusProvider.isRestoring = true

        // 计算目标帧
        let targetFrame = layoutManager.calculateRestoreFrame(from: ballCenter, lastFrame: focusProvider.lastExpandedFrame)

        // 保存位置
        if PreferencesManager.shared.rememberWindowPosition {
            focusProvider.lastExpandedFrame = targetFrame
            layoutManager.saveCurrentPosition()
        }

        // 执行动画
        withAnimation(.spring(response: FloatingPanelConstants.restoreDuration, dampingFraction: 0.8)) {
            self.mode = .expanded
        }

        animationManager.performRestoreFromBall(targetFrame: targetFrame) { [weak self] in
            self?.focusProvider.isRestoring = false
            completion?()
        }
    }

    /// 更新浮球位置
    func updateBallPosition(_ position: CGPoint) {
        guard let panel = panel, mode == .floatingBall else { return }

        let size = panel.frame.size
        let newFrame = NSRect(x: position.x - size.width/2, y: position.y - size.height/2, width: size.width, height: size.height)
        panel.setFrame(newFrame, display: true)

        focusProvider.ballPosition = position
    }

    /// 吸附浮球到边缘
    func snapToEdge(from position: CGPoint, completion: ((CGPoint) -> Void)? = nil) {
        let finalPos = layoutManager.snapBallToEdge(from: position)

        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            updateBallPosition(finalPos)
        }

        completion?(finalPos)
    }
}
