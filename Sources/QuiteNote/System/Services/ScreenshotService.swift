import Foundation
import AppKit
import OSLog

/// 截图服务，处理权限申请、截图执行及剪贴板保存
final class ScreenshotService {
    nonisolated(unsafe) static let shared = ScreenshotService()
    private let logger = Logger(subsystem: "com.quitenote.app.dev", category: "ScreenshotService")

    // 用于通知模式的临时存储
    private var pendingCompletion: ((NSImage?, CGRect?) -> Void)?

    // ⚠️ 全局强引用，确保 window detection controller 不会被释放
    nonisolated(unsafe) static var activeWindowDetectionController: WindowDetectionController?

    private init() {}
    
    /// 检查是否有辅助功能权限（用于全局快捷键监听）
    /// - Parameter prompt: 是否在未获得权限时弹出系统申请弹窗
    /// - Returns: 是否已获得权限
    func checkAccessibilityPermission(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        let granted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        logger.debug("检查辅助功能权限: \(granted)")
        return granted
    }

    /// 检查屏幕录制权限状态（不触发弹窗）
    /// - Returns: 是否已获得权限
    func checkScreenCapturePermission() -> Bool {
        if #available(macOS 10.15, *) {
            let granted = CGPreflightScreenCaptureAccess()
            logger.debug("检查屏幕录制权限: \(granted)")
            return granted
        }
        return true
    }
    
    /// 检查并请求屏幕录制权限
    /// - Returns: 是否已获得权限
    func checkAndRequestPermission() -> Bool {
        if #available(macOS 10.15, *) {
            let granted = CGRequestScreenCaptureAccess()
            logger.debug("请求屏幕录制权限结果: \(granted)")
            return granted
        }
        return true
    }
    
    /// 执行截图
    /// - Parameter completion: 截图完成后的回调，返回截图数据或 nil
    func capture(completion: @escaping (NSImage?) -> Void) {
        logger.info("准备执行截图...")
        
        // 1. 权限检查
        guard checkAndRequestPermission() else {
            logger.error("截图失败：未获得屏幕录制权限")
            completion(nil)
            return
        }
        
        // 2. 准备路径
        let tempDir = NSTemporaryDirectory()
        let fileName = "quite_note_screenshot_\(Int(Date().timeIntervalSince1970)).png"
        let tempPath = (tempDir as NSString).appendingPathComponent(fileName)
        
        // 3. 激活应用
        // 交互式截图需要应用处于活跃状态
        NSApp.activate(ignoringOtherApps: true)
        
        // 4. 执行命令
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        
        // 使用 -i (交互式) 和 -x (不播放声音，我们自己处理或者用系统的)
        // 注意：不使用 -c，因为直接存文件更可靠，我们可以事后读取并存入剪贴板
        process.arguments = ["-i", tempPath]
        
        logger.info("执行命令: /usr/sbin/screencapture -i \(tempPath)")
        
        process.terminationHandler = { process in
            let status = process.terminationStatus
            self.logger.info("screencapture 进程结束，退出码: \(status)")
            
            DispatchQueue.main.async {
                if status == 0 {
                    // 检查文件是否存在
                    if FileManager.default.fileExists(atPath: tempPath) {
                        if let image = NSImage(contentsOfFile: tempPath) {
                            self.logger.info("成功从文件读取截图: \(tempPath)")
                            
                            // 存入剪贴板
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.writeObjects([image])
                            self.logger.info("已同步存入剪贴板")
                            
                            // 删除临时文件
                            try? FileManager.default.removeItem(atPath: tempPath)
                            
                            completion(image)
                        } else {
                            self.logger.error("文件存在但无法解析为 NSImage")
                            completion(nil)
                        }
                    } else {
                        self.logger.error("截图进程返回成功，但文件不存在: \(tempPath)")
                        completion(nil)
                    }
                } else {
                    self.logger.warning("截图取消或失败，退出码: \(status)")
                    completion(nil)
                }
            }
        }
        
        do {
            try process.run()
        } catch {
            logger.error("启动 screencapture 失败: \(error.localizedDescription)")
            completion(nil)
        }
    }
    
    /// 将图片保存到系统剪贴板
    /// - Parameter image: 要保存的图片
    func saveToClipboard(image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        print("[DEBUG] 截图已保存到剪贴板")
    }

    /// 带窗口识别的截图流程（阶段0）
    /// - Parameter completion: 完成回调，返回 (图片, 初始裁剪区域)
    func captureWithWindowDetection(completion: @escaping (NSImage?, CGRect?) -> Void) {
        print("[DEBUG ScreenshotService] captureWithWindowDetection 被调用")
        logger.info("启动窗口识别截图流程...")

        // 1. 权限检查
        guard checkAndRequestPermission() else {
            print("[DEBUG ScreenshotService] 权限检查失败")
            logger.error("截图失败：未获得屏幕录制权限")
            completion(nil, nil)
            return
        }
        print("[DEBUG ScreenshotService] 权限检查通过")

        // 2. 在主线程创建窗口识别控制器
        if Thread.isMainThread {
            print("[DEBUG ScreenshotService] 在主线程，直接创建控制器")
            createAndShowController(completion: completion)
        } else {
            print("[DEBUG ScreenshotService] 不在主线程，切换到主线程")
            DispatchQueue.main.sync { [weak self] in
                self?.createAndShowController(completion: completion)
            }
        }
    }

    private func createAndShowController(completion: @escaping (NSImage?, CGRect?) -> Void) {
        print("[DEBUG ScreenshotService] createAndShowController 被调用")

        // 使用实例方法 + selector 模式避免闭包类型推断问题
        pendingCompletion = completion

        let notificationName = Notification.Name("qn.screenshot.windowSelection")
        print("[DEBUG ScreenshotService] 通知名: \(notificationName.rawValue)")

        // 使用 #selector 避免闭包
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowSelectionNotification(_:)),
            name: notificationName,
            object: nil
        )
        print("[DEBUG ScreenshotService] 已添加通知观察者")

        // 创建控制器并传入通知名
        print("[DEBUG ScreenshotService] 即将创建 WindowDetectionController")
        let controller = WindowDetectionController.createWithNotification(notificationName: notificationName)
        print("[DEBUG ScreenshotService] WindowDetectionController 已创建，准备 show")

        // ⚠️ 关键修复：使用全局静态变量保持强引用，防止 controller 被释放
        Self.activeWindowDetectionController = controller
        print("[DEBUG ScreenshotService] controller 已保存到全局引用")

        controller.show()
        print("[DEBUG ScreenshotService] controller.show() 已调用")
    }

    @objc private func handleWindowSelectionNotification(_ notification: Notification) {
        print("[DEBUG ScreenshotService] 收到窗口选择通知")

        // 移除观察者
        NotificationCenter.default.removeObserver(self, name: notification.name, object: nil)

        guard let completion = pendingCompletion else { return }
        pendingCompletion = nil

        if let image = notification.userInfo?["image"] as? NSImage,
           let rect = notification.userInfo?["rect"] as? CGRect {
            let cropRect = WindowInfoService.shared.screenToImageRect(
                rect,
                imageSize: image.size,
                screenSize: NSScreen.main?.frame.size ?? .zero
            )
            print("[DEBUG] 窗口选择完成，区域: \(cropRect)")
            completion(image, cropRect)
        } else if notification.userInfo?["cancelled"] as? Bool == true {
            print("[DEBUG] 窗口识别已取消")
            completion(nil, nil)
        }
    }
}
