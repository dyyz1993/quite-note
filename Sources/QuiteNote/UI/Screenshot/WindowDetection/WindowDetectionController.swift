import AppKit
import SwiftUI

/// 窗口识别控制器 - 阶段0的窗口控制器
@preconcurrency
class WindowDetectionController: NSPanel {
    // 回调（可选）
    private var onSelectionComplete: ((NSImage, CGRect) -> Void)?
    private var onCancel: (() -> Void)?

    // 通知模式
    private var notificationName: Notification.Name?

    // 状态
    private var hostingController: NSHostingController<WindowDetectionView>?

    // 私有初始化器
    private override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 创建窗口识别控制器的工厂方法（闭包模式 - 保留用于兼容性）
    static func create(
        onSelectionComplete: @escaping @Sendable (NSImage, CGRect) -> Void,
        onCancel: @escaping @Sendable () -> Void
    ) -> WindowDetectionController {
        let controller = WindowDetectionController(
            contentRect: NSScreen.main?.frame ?? .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        controller.onSelectionComplete = onSelectionComplete
        controller.onCancel = onCancel
        controller.setupPanel()
        return controller
    }

    /// 创建窗口识别控制器的工厂方法（通知模式 - 避免 Swift 6 类型推断问题）
    static func createWithNotification(notificationName: Notification.Name) -> WindowDetectionController {
        let controller = WindowDetectionController(
            contentRect: NSScreen.main?.frame ?? .zero,
            // ⚠️ 修复：移除 .nonactivatingPanel，让窗口能正常激活
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        controller.notificationName = notificationName
        controller.setupPanel()
        return controller
    }

    private func setupPanel() {
        // 面板配置
        level = .floating  // ⚠️ 修复：改为 floating 级别，避免 screenSaver 导致的事件异常
        backgroundColor = .clear
        isOpaque = false
        ignoresMouseEvents = false  // 必须接收鼠标事件
        isMovable = false
        hidesOnDeactivate = false  // 失去焦点时不隐藏
        collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]  // 全屏模式下也能显示

        // ✅ 修复：获取鼠标所在的屏幕，而不是主屏幕
        let targetScreen = NSScreen.screens.first { screen in
            screen.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main

        guard let screen = targetScreen else {
            print("[ERROR] WindowDetectionController: No screen found")
            return
        }
        let screenFrame = screen.frame

        print("[DEBUG WindowDetectionController] 使用屏幕: \(screen.localizedName ?? "Unknown"), frame: \(screenFrame)")

        // ⚠️ 关键修复 1：强制设置 contentView 的 frame
        // 这确保 contentView 在添加 contentViewController 之前就有正确的尺寸
        if let contentView = contentView {
            contentView.frame = screenFrame
            contentView.wantsLayer = true
            let transparentImage = NSImage(size: CGSize(width: 1, height: 1))
            transparentImage.lockFocus()
            NSColor.clear.set()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1, height: 1)).fill()
            transparentImage.unlockFocus()
            contentView.layer?.contents = transparentImage
        }

        // 创建 SwiftUI 视图
        let view = WindowDetectionView(
            onWindowSelected: { [weak self] window, rect in
                self?.handleWindowSelected(window, rect: rect)
            },
            onAreaSelected: { [weak self] rect in
                self?.handleAreaSelected(rect)
            },
            onFullscreen: { [weak self] in
                self?.handleFullscreen()
            },
            onCancel: { [weak self] in
                self?.handleCancel()
            }
        )

        hostingController = NSHostingController(rootView: view)

        // ⚠️ 关键修复 2：在设置 contentViewController 之前，强制设置 hostingController 视图的 frame
        // 参考：https://medium.com/@clyapp/resolving-nspanel-size-500x500-issues-in-macos-swift-app-71ba9ca8bc71
        hostingController?.view.frame = screenFrame

        contentViewController = hostingController

        // ⚠️ 关键修复 3：再次强制设置窗口 frame，确保没有被 SwiftUI 覆盖
        setFrame(screenFrame, display: false)

        print("[DEBUG WindowDetectionController] setupPanel 完成")
        print("[DEBUG] 期望窗口 frame: \(screenFrame)")
        print("[DEBUG] 实际窗口 frame: \(frame)")
    }

    // MARK: - 事件处理

    private func handleWindowSelected(_ window: WindowInfo, rect: CGRect) {
        // 截取选中的窗口
        guard let image = WindowInfoService.shared.captureWindow(window) else {
            print("[WindowDetection] Failed to capture window")
            return
        }

        close()
        notifySelectionComplete(image: image, rect: rect)
    }

    private func handleAreaSelected(_ rect: CGRect) {
        // 截取选中的区域
        guard let image = WindowInfoService.shared.captureScreen(rect: rect) else {
            print("[WindowDetection] Failed to capture area")
            return
        }

        close()
        notifySelectionComplete(image: image, rect: rect)
    }

    private func handleFullscreen() {
        // 截取全屏
        guard let screen = NSScreen.main else {
            print("[WindowDetection] No screen found")
            return
        }

        let screenFrame = screen.frame
        guard let image = WindowInfoService.shared.captureScreen(rect: screenFrame) else {
            print("[WindowDetection] Failed to capture fullscreen")
            return
        }

        close()
        notifySelectionComplete(image: image, rect: screenFrame)
    }

    private func handleCancel() {
        close()
        notifyCancelled()
    }

    // MARK: - 结果通知

    private func notifySelectionComplete(image: NSImage, rect: CGRect) {
        if let notificationName = notificationName {
            NotificationCenter.default.post(
                name: notificationName,
                object: self,
                userInfo: ["image": image, "rect": rect]
            )
        } else {
            onSelectionComplete?(image, rect)
        }
    }

    private func notifyCancelled() {
        if let notificationName = notificationName {
            NotificationCenter.default.post(
                name: notificationName,
                object: self,
                userInfo: ["cancelled": true]
            )
        } else {
            onCancel?()
        }
    }

    // MARK: - 公开方法

    /// 显示窗口识别面板
    func show() {
        print("[DEBUG] ===== WindowDetectionController.show() START =====")

        // ✅ 修复：获取鼠标所在的屏幕
        let targetScreen = NSScreen.screens.first { screen in
            screen.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main

        // ⚠️ 关键修复 5：在显示前再次强制设置窗口 frame
        if let screen = targetScreen {
            let screenFrame = screen.frame
            setFrame(screenFrame, display: false)
            print("[DEBUG] 强制设置窗口 frame 为屏幕尺寸: \(screenFrame)")
            print("[DEBUG] 屏幕: \(screen.localizedName ?? "Unknown")")
        }

        print("[DEBUG] Window level: \(level.rawValue)")

        orderFrontRegardless()
        print("[DEBUG] orderFrontRegardless called")

        NSApp.activate(ignoringOtherApps: true)
        print("[DEBUG] NSApp.activate called")

        makeKeyAndOrderFront(nil)
        print("[DEBUG] makeKeyAndOrderFront called")

        // ⚠️ 关键修复：延迟确保窗口完全显示后成为 key window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.makeKey()

            // ✅ 修复：延迟后再次确认窗口 frame（使用当前窗口的屏幕）
            if let currentScreen = self.screen {
                let screenFrame = currentScreen.frame
                if self.frame != screenFrame {
                    print("[DEBUG] ⚠️ 检测到窗口 frame 被修改，重新设置为: \(screenFrame)")
                    self.setFrame(screenFrame, display: true)
                }
            }

            print("[DEBUG] 延迟设置完成，最终窗口 frame: \(self.frame), isVisible: \(self.isVisible)")
        }

        print("[DEBUG] ===== WindowDetectionController.show() END =====")
    }

    // MARK: - 窗口生命周期覆盖

    override var canBecomeKey: Bool {
        print("[DEBUG] canBecomeKey called, returning true")
        return true
    }

    override var acceptsFirstResponder: Bool {
        print("[DEBUG] acceptsFirstResponder called, returning true")
        return true
    }

    override func becomeKey() {
        super.becomeKey()
        print("[DEBUG WindowDetectionController] ✅ Became key window")

        // ✅ 设置全局光标
        DispatchQueue.main.async {
            CrosshairCursor.shared.set()
        }
    }

    override func resignKey() {
        super.resignKey()
        print("[DEBUG WindowDetectionController] ⚠️ Resigned key window")

        // ✅ 恢复默认光标
        DispatchQueue.main.async {
            CrosshairCursor.shared.reset()
        }
    }

    // ✅ 添加：重置光标矩形（确保光标在整个窗口区域有效）
    override func resetCursorRects() {
        // 为整个窗口设置光标
        if let contentView = contentView,
           let cursor = CrosshairCursor.shared.cursor {
            contentView.discardCursorRects()
            contentView.addCursorRect(contentView.bounds, cursor: cursor)
        } else {
            super.resetCursorRects()
        }
    }

    /// 关闭面板
    override func close() {
        super.close()
        hostingController = nil
    }
}
