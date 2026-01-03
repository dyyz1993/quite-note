import SwiftUI
import AppKit
import os.log

private let v2Logger = Logger(subsystem: "com.quitenote.app", category: "ScreenshotV2")

/// 截图窗口控制器
@MainActor
class V2ScreenshotController {
    static var debugPanels: [NSPanel] = []
    /// ✨ 新增：屏幕到 panel 的映射，用于快速查找对应屏幕的 panel
    static var screenPanelMap: [NSScreen: NSPanel] = [:]
    static var longScreenshotControlPanel: LongScreenshotControlPanel?
    static var longScreenshotPreviewPanel: LongScreenshotPreviewPanel?

    static func show() {
        // 先关闭旧的
        close()

        // ⚠️ 重置全局状态，确保每次进入截图模式都是干净的
        V2PrimaryScreenStateManager.shared.reset()

        v2Logger.info("Controller - Starting multi-screen debug window with REAL windows...")

        // 获取真实窗口列表
        let windowResult = WindowInfoService.shared.fetchAllWindows()
        let allWindows: [WindowInfo]

        switch windowResult {
        case .success(let windows):
            // 过滤掉不需要的窗口：
            // 1. 当前应用自身的窗口
            // 2. 桌面/墙纸 (Wallpaper/Desktop) - 这些通常覆盖全屏且由 Finder 或 WindowServer 拥有
            // 3. 菜单栏/Dock 栏等系统 UI
            allWindows = windows.filter { window in
                let name = window.ownerName
                let isSelf = name == "Quite Note" || name == "QuiteNote"
                let isSystemBackground = name == "Window Server" || name == "Dock" || (name == "Finder" && window.windowName == nil)

                // 只有不是自身且不是系统背景的窗口才显示交互矩形
                return !isSelf && !isSystemBackground
            }
            v2Logger.info("Fetched \(allWindows.count) real windows (filtered system backgrounds)")
        case .failure(let error):
            v2Logger.error("Failed to fetch real windows: \(error.localizedDescription)")
            allWindows = []
        }

        for (index, screen) in NSScreen.screens.enumerated() {
            v2Logger.info("Creating debug window for Screen \(index): \(screen.frame.debugDescription, privacy: .public)")

            let snapshot = V2ScreenshotController.captureScreen(screen)
            let view = V2ScreenshotView(screen: screen, snapshot: snapshot, screenIndex: index, allWindows: allWindows)

            // ✅ 使用支持文本输入的 V2TextInputPanel
            let panel = V2TextInputPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            panel.level = .screenSaver  // ✨ 最高级别，确保在所有窗口（包括浮球）之上
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.acceptsMouseMovedEvents = true
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false  // ✨ 防止失去焦点时自动隐藏

            // 关键：确保面板在对应的屏幕上
            panel.setFrame(screen.frame, display: true)

            let hostingView = V2ScreenshotHostingView(rootView: view)
            hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentView = hostingView

            panel.orderFront(nil)
            debugPanels.append(panel)
            V2ScreenshotController.screenPanelMap[screen] = panel
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() {
        for panel in debugPanels {
            panel.close()
        }
        debugPanels.removeAll()
        screenPanelMap.removeAll()

        // 关闭长截图面板
        longScreenshotControlPanel?.close()
        longScreenshotControlPanel = nil
        longScreenshotPreviewPanel?.close()
        longScreenshotPreviewPanel = nil

        // ⚠️ 关闭调试模式时也重置全局状态
        V2PrimaryScreenStateManager.shared.reset()
    }

    /// 显示/隐藏长图采集预览面板
    static func setLongScreenshotControlVisible(_ visible: Bool, selection: CGRect? = nil, screen: NSScreen? = nil) {
        if visible {
            // 只显示预览面板，控制按钮在工具栏上
            if longScreenshotPreviewPanel == nil, let selection = selection, let screen = screen {
                longScreenshotPreviewPanel = LongScreenshotPreviewPanel(selection: selection, screen: screen)
            }
            longScreenshotPreviewPanel?.orderFrontRegardless()
        } else {
            // 隐藏并清理面板
            longScreenshotControlPanel?.close()
            longScreenshotControlPanel = nil
            longScreenshotPreviewPanel?.close()
            longScreenshotPreviewPanel = nil
        }
    }

    static func captureScreen(_ screen: NSScreen) -> NSImage {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let cgImage = CGDisplayCreateImage(displayID) else {
            let img = NSImage(size: screen.frame.size)
            img.lockFocus()
            NSColor(calibratedWhite: 0.2, alpha: 1.0).set()
            NSRect(origin: .zero, size: screen.frame.size).fill()
            img.unlockFocus()
            return img
        }

        // ⚠️ 修复 Retina 模糊问题：确保图片尺寸与像素一致
        let image = NSImage(cgImage: cgImage, size: screen.frame.size) // 逻辑尺寸

        // 显式设置像素尺寸，避免缩放模糊
        image.size = screen.frame.size
        return image
    }
}
