import Foundation
import AppKit

/// 窗口位置管理器 - 负责窗口位置计算、多屏幕支持、位置记忆
final class FloatingPanelLayoutManager {
    private weak var panel: NSPanel?
    private let preferences: PreferencesManager

    init(panel: NSPanel, preferences: PreferencesManager = .shared) {
        self.panel = panel
        self.preferences = preferences
    }

    // MARK: - 居中显示

    /// 计算屏幕中心位置
    func calculateCenterPosition(on screen: NSScreen? = nil) -> NSRect {
        let screen = screen ?? NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame

        let centerX = screenFrame.midX - (FloatingPanelConstants.defaultWidth / 2)
        let centerY = screenFrame.midY - (FloatingPanelConstants.defaultHeight / 2)

        return NSRect(
            x: centerX,
            y: centerY,
            width: FloatingPanelConstants.defaultWidth,
            height: FloatingPanelConstants.defaultHeight
        )
    }

    /// 将窗口移动到屏幕中心
    func centerOnScreen() {
        guard let panel = panel else { return }
        let newFrame = calculateCenterPosition()
        panel.setFrame(newFrame, display: true)
    }

    // MARK: - 位置保存与恢复

    /// 保存当前窗口位置
    func saveCurrentPosition(screenId: String? = nil) {
        guard let panel = panel,
              preferences.rememberWindowPosition else { return }

        let screen = panel.screen
        let frameToSave = panel.frame

        preferences.setWindowPosition(frameToSave)

        if let screen = screen,
           let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let id = screenId ?? screenNumber.stringValue
            preferences.setWindowScreenId(id)
        }
    }

    /// 恢复保存的窗口位置
    func restoreSavedPosition() -> Bool {
        guard let panel = panel,
              preferences.rememberWindowPosition else { return false }

        guard let savedFrame = preferences.getWindowPosition() else {
            centerOnScreen()
            return false
        }

        // 获取目标屏幕
        var targetScreen: NSScreen?
        if let screenId = preferences.getWindowScreenId() {
            targetScreen = preferences.getScreenById(screenId)
        }

        if targetScreen == nil {
            targetScreen = NSScreen.main
        }

        // 确保窗口在屏幕范围内
        guard let screen = targetScreen else {
            centerOnScreen()
            return false
        }

        let adjustedFrame = adjustFrameToScreen(savedFrame, screen: screen)
        panel.setFrame(adjustedFrame, display: true)

        return true
    }

    /// 调整窗口位置以确保其在屏幕范围内
    func adjustFrameToScreen(_ frame: NSRect, screen: NSScreen) -> NSRect {
        var adjusted = frame
        let screenFrame = screen.visibleFrame
        let minPadding = FloatingPanelConstants.screenMinPadding

        if adjusted.maxX < screenFrame.minX + minPadding {
            adjusted.origin.x = screenFrame.minX + minPadding
        }
        if adjusted.minX > screenFrame.maxX - minPadding {
            adjusted.origin.x = screenFrame.maxX - adjusted.width - minPadding
        }
        if adjusted.maxY < screenFrame.minY + minPadding {
            adjusted.origin.y = screenFrame.minY + minPadding
        }
        if adjusted.minY > screenFrame.maxY - minPadding {
            adjusted.origin.y = screenFrame.maxY - adjusted.height - minPadding
        }

        return adjusted
    }

    // MARK: - 浮球位置计算

    /// 计算浮球位置（基于窗口中心）
    func calculateBallPosition(from windowFrame: NSRect) -> CGPoint {
        return CGPoint(x: windowFrame.midX, y: windowFrame.midY)
    }

    /// 计算浮球窗口帧（从中心点）
    func calculateBallFrame(center: CGPoint) -> NSRect {
        let size = FloatingPanelConstants.ballSize
        return NSRect(
            x: center.x - size / 2,
            y: center.y - size / 2,
            width: size,
            height: size
        )
    }

    /// 计算从浮球恢复到窗口的帧
    func calculateRestoreFrame(from ballCenter: CGPoint, lastFrame: NSRect?) -> NSRect {
        var targetWidth = FloatingPanelConstants.defaultWidth
        var targetHeight = FloatingPanelConstants.defaultHeight

        if preferences.rememberWindowPosition, let saved = lastFrame {
            targetWidth = max(FloatingPanelConstants.defaultWidth, saved.width)
            targetHeight = max(FloatingPanelConstants.defaultHeight, saved.height)
        }

        var targetX = ballCenter.x - (targetWidth / 2)
        var targetY = ballCenter.y - (targetHeight / 2)

        // 边界适配
        let screen = panel?.screen ?? NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        let padding = FloatingPanelConstants.screenPadding

        if targetX < screenFrame.minX + padding { targetX = screenFrame.minX + padding }
        else if targetX + targetWidth > screenFrame.maxX - padding { targetX = screenFrame.maxX - targetWidth - padding }

        if targetY < screenFrame.minY + padding { targetY = screenFrame.minY + padding }
        else if targetY + targetHeight > screenFrame.maxY - padding { targetY = screenFrame.maxY - targetHeight - padding }

        return NSRect(x: targetX, y: targetY, width: targetWidth, height: targetHeight)
    }

    /// 吸附浮球到屏幕边缘
    func snapBallToEdge(from position: CGPoint) -> CGPoint {
        let screens = NSScreen.screens
        let targetScreen = screens.first { NSMouseInRect(position, $0.frame, false) } ?? NSScreen.main ?? screens.first!

        let screenFrame = targetScreen.visibleFrame
        let padding = FloatingPanelConstants.screenPadding
        let ballRadius = FloatingPanelConstants.ballRadius / 2

        var finalPos = position

        if finalPos.x < screenFrame.minX + padding + ballRadius {
            finalPos.x = screenFrame.minX + padding + ballRadius
        } else if finalPos.x > screenFrame.maxX - padding - ballRadius {
            finalPos.x = screenFrame.maxX - padding - ballRadius
        }

        if finalPos.y < screenFrame.minY + padding + ballRadius {
            finalPos.y = screenFrame.minY + padding + ballRadius
        } else if finalPos.y > screenFrame.maxY - padding - ballRadius {
            finalPos.y = screenFrame.maxY - padding - ballRadius
        }

        return finalPos
    }
}
