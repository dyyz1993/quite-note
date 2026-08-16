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
    private static var localMonitor: Any?
    /// 失焦自动拉回监听器（cleanup 时必须移除，否则闭包持有旧面板数组，截图结束后失焦会把已关闭的"幽灵"面板拉回前台）
    private static var resignActiveObserver: NSObjectProtocol?

    /// ✨ 新增：互斥锁，确保同一时间只有一个截图流程在运行
    private static var isShowing = false

    /// ✨ 当前截图会话的唯一ID
    internal static var currentSessionID: UUID?

    static func show() {
        // ✨ 互斥锁逻辑：如果已经在显示中，则直接返回，防止重复触发
        guard !isShowing else {
            v2Logger.info("Controller - Already showing, ignoring duplicate show() request")
            return
        }

        // 先检查是否已经有 panel，如果有也说明在显示中
        if !debugPanels.isEmpty {
            v2Logger.info("Controller - Panels not empty, ignoring show() request")
            return
        }

        isShowing = true

        // ✨ 生成新的会话ID
        let sessionID = UUID()
        currentSessionID = sessionID
        v2Logger.info("Controller - Starting new screenshot session: \(sessionID)")
        DiagnosticCenter.info("Screenshot", "截图会话开始 \(sessionID.uuidString.prefix(8))，屏幕数 \(NSScreen.screens.count)")

        // 清理可能残留的状态
        cleanup()

        // ✨ 设置全局键盘监听
        setupKeyboardMonitor()

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
            let view = V2ScreenshotView(screen: screen, snapshot: snapshot, screenIndex: index, allWindows: allWindows, sessionID: sessionID)

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

    /// ✨ 内部清理逻辑，不重置 isShowing 锁
    private static func cleanup() {
        // 移除监听
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        // 移除失焦监听器（关键：不移除会在截图结束后触发"幽灵面板"重新弹出）
        if let observer = resignActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            resignActiveObserver = nil
        }

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

    static func close() {
        DiagnosticCenter.info("Screenshot", "截图会话结束（元素 \(V2PrimaryScreenStateManager.shared.elements.count) 个）")
        // 先执行清理
        cleanup()
        // 最后重置状态锁
        isShowing = false
        // ✨ 清除会话ID
        currentSessionID = nil
    }

    private static func setupKeyboardMonitor() {
        // 先重置状态
        V2PrimaryScreenStateManager.shared.reset()

        // ✨ 使用 Local Monitor（不需要辅助功能权限）
        // 同时配合 Panel 的 resignsKey 处理，确保失去焦点后重新激活
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 只有在显示截图界面时才拦截
            guard !debugPanels.isEmpty else { return event }

            // 处理 ESC (53)
            if event.keyCode == 53 {
                handleGlobalExitCommand()
                return nil  // 阻止事件传递
            }

            // 处理 Command+C/S
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command {
                if event.charactersIgnoringModifiers == "s" {
                    NotificationCenter.default.post(name: NSNotification.Name("SaveScreenshot"), object: nil)
                    return nil  // 阻止事件传递
                } else if event.charactersIgnoringModifiers == "c" {
                    NotificationCenter.default.post(name: NSNotification.Name("CopyScreenshot"), object: nil)
                    return nil  // 阻止事件传递
                }
            }

            return event
        }

        // ✨ 新增：监听应用失去焦点事件，自动重新激活 Panel
        // ⚠️ 修复：用实时的 debugPanels 判断（不能用闭包捕获的旧数组），
        // 并在 cleanup 时移除监听，否则截图结束后的任何一次失焦都会把已关闭的面板重新拉出来
        resignActiveObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            guard !debugPanels.isEmpty else { return }
            // 延迟一点重新激活，确保系统完成焦点切换
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard !debugPanels.isEmpty else { return }
                // 重新激活所有 Panel
                for panel in debugPanels {
                    panel.orderFrontRegardless()
                    panel.becomeKey()
                }
            }
        }
    }
    
    private static func handleGlobalExitCommand() {
        let manager = V2PrimaryScreenStateManager.shared
        
        // 1. 如果有标注内容，为了防止误操作，需要双击 ESC 退出
        if !manager.elements.isEmpty {
            if let lastEscTime = manager.lastEscKeyPressTime,
               Date().timeIntervalSince(lastEscTime) < 2.0 {
                close()
            } else {
                let now = Date()
                manager.lastEscKeyPressTime = now
                manager.postToast("再按一次退出 (已保留标注内容)", type: "info")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if manager.lastEscKeyPressTime == now {
                        manager.lastEscKeyPressTime = nil
                    }
                }
            }
            return
        }
        
        // 2. 阶段返回逻辑：如果有选区，先清除选区
        if manager.selectedArea != nil {
            manager.updateSelection(nil, on: nil)
            manager.updateHover(nil, label: nil, on: nil)
            // 重置工具和模式
            manager.updateTool(.cursor)
            manager.selectedElementId = nil
            manager.isLongScreenshotMode = false
            return
        }
        
        // 3. 初始状态或仅选择了工具但未画图，直接退出
        close()
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

    /// 支持文本输入的 NSPanel 子类
    /// 关键：覆盖 canBecomeKey 和 canBecomeMain，使 .borderless 样式下仍能接收键盘输入
    class V2TextInputPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
        
        // 允许第一响应者
        override var acceptsFirstResponder: Bool { true }
        
        // 覆盖 cancelOperation (处理 ESC)
        override func cancelOperation(_ sender: Any?) {
            V2ScreenshotController.handleGlobalExitCommand()
        }
    }
}
