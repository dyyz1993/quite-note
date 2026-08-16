import Foundation
import AppKit
import OSLog

/// 截图服务，处理权限申请、截图执行及剪贴板保存
final class ScreenshotService {
    nonisolated(unsafe) static let shared = ScreenshotService()
    private let logger = Logger(subsystem: "com.quitenote.app.dev", category: "ScreenshotService")

    // 用于通知模式的临时存储
    private var pendingCompletion: ((NSImage?, CGRect?, NSScreen?) -> Void)?

    // 截图计数器
    private var screenshotCount = 0

    // 弱引用 RecordStore，用于保存截图记录
    private weak var recordStore: RecordStore?

    // ⚠️ 关键：用于在截图开始前隐藏主窗口，截图结束后恢复
    var onWillStartScreenshot: (() -> Void)?
    var onDidFinishScreenshot: (() -> Void)?

    private init() {}

    /// 设置 RecordStore（需要在应用启动时调用）
    func attachRecordStore(_ store: RecordStore) {
        self.recordStore = store
    }
    
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
            let hasPreflight = CGPreflightScreenCaptureAccess()
            print("[DEBUG ScreenshotService] 权限检查 - CGPreflightScreenCaptureAccess: \(hasPreflight)")

            if !hasPreflight {
                let granted = CGRequestScreenCaptureAccess()
                print("[DEBUG ScreenshotService] 权限请求 - CGRequestScreenCaptureAccess: \(granted)")

                if !granted {
                    print("[DEBUG ScreenshotService] ❌ 屏幕录制权限被拒绝，请到系统设置中手动开启")
                    return false
                }
            }

            print("[DEBUG ScreenshotService] ✅ 屏幕录制权限已获取")
            return true
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
    // MARK: - 统一截图入口

    /// 统一的截图入口 - 处理完整的截图流程
    /// 这是唯一应该被调用的公开截图方法
    func startScreenshot() {
        print("[DEBUG ScreenshotService] ========== 启动统一截图流程（V2 静态模式） ==========")

        // ⚠️ 修复：调用设置好回调的 V2 截图方法
        Task { @MainActor in
            startV2Screenshot()
        }
    }

    /// 启动 V2 静态截图流程
    @MainActor
    func startV2Screenshot() {
        print("[DEBUG ScreenshotService] 启动 V2 截图流程")

        // 无屏幕录制权限时：显示权限引导悬浮窗（可拖拽图标到系统设置列表），
        // 不再进入"灰屏降级"模式——那只会截到灰色画面，体验更差。
        // 注意：这里只用 preflight 检查，不调 CGRequestScreenCaptureAccess 的系统弹窗，
        // 避免系统弹窗和自定义引导窗同时出现互相抢戏
        guard checkScreenCapturePermission() else {
            print("[WARN ScreenshotService] ⚠️ 没有屏幕录制权限，显示权限引导窗口")
            DiagnosticCenter.warning("Screenshot", "触发截图但无屏幕录制权限，已弹出权限引导窗")
            PermissionGuideController.shared.show()
            return
        }

        // ⚠️ 传递隐藏/显示主窗口的回调
        onWillStartScreenshot?()

        // 直接调用 V2ScreenshotController
        // 截图完成后会通过 NotificationCenter 发送 "SaveScreenshot" 通知
        V2ScreenshotController.show()
    }

    /// 保存截图到闪记
    func saveScreenshotToFlashNotes(image: NSImage) {
        saveScreenshotRecord(image: image)
    }

    /// 保存截图（推荐入口）：导出 PNG 文件到默认目录 + 复制绝对路径到剪贴板 + 存入闪记
    func saveScreenshotWithFile(image: NSImage) {
        let exportedPath = exportImageFile(image)
        if let path = exportedPath {
            DiagnosticCenter.info("Save", "截图已导出: \(path)")
        } else {
            DiagnosticCenter.error("Save", "截图导出文件失败（闪记记录不受影响）")
        }

        // 保存成功后把绝对路径复制到剪贴板，方便直接粘贴引用
        if let path = exportedPath, PreferencesManager.shared.screenshotCopyPathAfterSave {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(path, forType: .string)
            print("[DEBUG ScreenshotService] 已复制文件路径到剪贴板: \(path)")
        }

        saveScreenshotRecord(image: image, exportedPath: exportedPath)
    }

    /// 导出 PNG 到用户设置的默认保存目录（未设置时使用桌面）
    /// - Returns: 导出文件的绝对路径，失败返回 nil
    func exportImageFile(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            print("[DEBUG ScreenshotService] 导出失败：无法生成 PNG 数据")
            return nil
        }

        // 解析保存目录：未设置时默认「下载」文件夹（不弄乱桌面；设置里可改任意目录）
        let dirPref = PreferencesManager.shared.screenshotSaveDirectory
        let dirURL: URL
        if dirPref.isEmpty {
            dirURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        } else {
            dirURL = URL(fileURLWithPath: (dirPref as NSString).expandingTildeInPath, isDirectory: true)
        }

        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

            // 文件名：应用前缀 + 紧凑时间戳（无空格无中文，排序/命令行引用友好）
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let baseName = "QuiteNote_\(formatter.string(from: Date()))"

            var fileURL = dirURL.appendingPathComponent("\(baseName).png")
            var counter = 2
            while FileManager.default.fileExists(atPath: fileURL.path) {
                fileURL = dirURL.appendingPathComponent("\(baseName)-\(counter).png")
                counter += 1
            }

            try pngData.write(to: fileURL)
            print("[DEBUG ScreenshotService] 截图已导出: \(fileURL.path)")
            return fileURL.path
        } catch {
            print("[DEBUG ScreenshotService] 导出截图失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// 保存截图到记录中
    private func saveScreenshotRecord(image: NSImage, exportedPath: String? = nil) {
        self.screenshotCount += 1
        let timestamp = Int(Date().timeIntervalSince1970)
        let hash = "screenshot_\(timestamp)_\(self.screenshotCount)"

        // 有导出文件时，提示和记录都带上路径信息
        let message: String
        if let path = exportedPath {
            message = "截图已保存 ✅ 路径已复制"
            print("[DEBUG ScreenshotService] 导出路径: \(path)")
        } else {
            message = "截图 \(self.screenshotCount)"
        }

        var sourceUrl: String? = nil
        
        // 使用 FileCoordinator 保存截图
        do {
            let localURL = try FileCoordinator.shared.storeImage(image, type: .screenshot, originalName: "screenshot.png")
            sourceUrl = FileCoordinator.shared.convertToVirtualPath(from: localURL)
            
            // 预生成缩略图
            ThumbnailGenerator.shared.getThumbnailURLAsync(for: localURL) { _ in }
            
            print("[DEBUG ScreenshotService] 截图已通过 FileCoordinator 保存: \(sourceUrl ?? "nil")")
        } catch {
            print("[DEBUG ScreenshotService] 保存截图失败: \(error.localizedDescription)")
        }

        // 1. 发送轻提示
        self.recordStore?.postLightHint(message)

        // 2. 创建真正的记录（带上导出路径，方便日后检索定位文件）
        let recordContent: String
        if let path = exportedPath {
            recordContent = "截图 \(self.screenshotCount)：\(path)"
        } else {
            recordContent = message
        }
        self.recordStore?.addRecord(
            content: recordContent,
            hash: hash,
            sourceApp: "Screen Capture",
            sourceUrl: sourceUrl,
            type: .screenshot,
            skipAI: true
        )

        print("[DEBUG ScreenshotService] \(message) 已保存并创建记录")
    }
}
