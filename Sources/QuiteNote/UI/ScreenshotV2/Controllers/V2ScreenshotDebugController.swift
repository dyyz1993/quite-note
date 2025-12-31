import SwiftUI
import AppKit
import os.log

private let v2Logger = Logger(subsystem: "com.quitenote.app", category: "ScreenshotV2")

/// 调试窗口控制器
@MainActor
class V2ScreenshotDebugController {
    static var debugPanels: [NSPanel] = []
    static var longScreenshotControlPanel: V2LongScreenshotControlPanel?

    static func show() {
        // 先关闭旧的
        close()

        // ⚠️ 同时尝试关闭可能正在进行的正式截图流程
        V2CaptureController.shared.stopCapture()

        // ⚠️ 重置全局状态，确保每次进入调试模式都是干净的
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

            let snapshot = V2ScreenshotDebugController.captureScreen(screen)
            let view = V2ScreenshotDebugView(screen: screen, snapshot: snapshot, screenIndex: index, allWindows: allWindows)

            // ✅ 使用自定义面板类，允许 .borderless 样式下接收键盘输入
            let panel = V2TextInputPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],  // ✅ 简单样式，无偏移
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

            // 关键：确保面板在对应的屏幕上
            panel.setFrame(screen.frame, display: true)

            let hostingView = V2ScreenshotHostingView(rootView: view)
            hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentView = hostingView

            panel.makeKeyAndOrderFront(nil)
            debugPanels.append(panel)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() {
        for panel in debugPanels {
            panel.close()
        }
        debugPanels.removeAll()

        longScreenshotControlPanel?.close()
        longScreenshotControlPanel = nil

        // ⚠️ 关闭调试模式时也重置全局状态
        V2PrimaryScreenStateManager.shared.reset()
    }

    /// 显示/隐藏长图采集控制面板
    static func setLongScreenshotControlVisible(_ visible: Bool, selection: CGRect? = nil, screen: NSScreen? = nil) {
        if visible {
            if longScreenshotControlPanel == nil, let selection = selection, let screen = screen {
                longScreenshotControlPanel = V2LongScreenshotControlPanel(selection: selection, screen: screen) {
                    V2PrimaryScreenStateManager.shared.setCapturing(false)
                    setLongScreenshotControlVisible(false)
                }
            }
            longScreenshotControlPanel?.makeKeyAndOrderFront(nil)
        } else {
            longScreenshotControlPanel?.close()
            longScreenshotControlPanel = nil
        }

        // 同时根据状态设置所有主调试窗口是否忽略鼠标事件
        for panel in debugPanels {
            panel.ignoresMouseEvents = visible
        }
    }

    private static func captureScreen(_ screen: NSScreen) -> NSImage {
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
