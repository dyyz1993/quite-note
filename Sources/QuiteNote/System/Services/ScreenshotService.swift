import Foundation
import AppKit
import AVFoundation
import CoreMedia
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
        
        // 进程内 CoreGraphics 截图，避免 App Sandbox 中启动
        // /usr/sbin/screencapture。交互式选区统一走 startScreenshot() 的 V2 流程。
        guard let screen = NSScreen.main,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let cgImage = CGDisplayCreateImage(displayID) else {
            logger.error("进程内截图失败：无法获取主屏幕图像")
            completion(nil)
            return
        }

        let image = NSImage(cgImage: cgImage, size: screen.frame.size)
        saveToClipboard(image: image)
        completion(image)
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

    // MARK: - 录屏收尾提示（M1：文件 + 剪贴板路径 + 轻提示；预览/闪记入档在后续里程碑）

    /// 录屏保存成功：复制路径到剪贴板（跟随截图的开关）+ 轻提示 + 日志
    func announceRecordingSaved(path: String) {
        DiagnosticCenter.info("Save", "录屏已导出: \(path)")
        if PreferencesManager.shared.screenshotCopyPathAfterSave {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(path, forType: .string)
            print("[DEBUG ScreenshotService] 已复制录屏路径到剪贴板: \(path)")
        }
        recordStore?.postLightHint("录屏已保存 ✅ 路径已复制")
    }

    /// 录屏取消（用户主动丢弃）
    func announceRecordingCancelled() {
        recordStore?.postLightHint("已取消录制，未产生文件")
    }

    /// 录屏失败提示（启动/写盘错误）
    func announceRecordingError(_ message: String) {
        DiagnosticCenter.error("Recording", message)
        recordStore?.postLightHint(message)
    }

    /// 把录屏存入闪记：首帧缩略图进附件库 + 路径引用记录（不拷贝视频本体，不占数据库体积）
    /// - Parameters:
    ///   - fileURL: 导出的 mp4（已在用户目录）
    ///   - duration: 成片时长（秒），用于展示文案
    func saveRecordingToFlashNotes(fileURL: URL, duration: Double) {
        let path = fileURL.path
        // 稳定哈希：同一文件重复保存走去重（更新时间戳），导出修剪后文件大小变化 → 视为新记录
        let sizeBytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        let hash = "recording_\(path.hashValue)_\(sizeBytes)"

        Task.detached(priority: .userInitiated) { [weak self] in
            // 首帧图（宽松容差取关键帧，单帧很快）→ 附件库 → 虚拟路径 + 缓存缩略图
            var virtualPath: String?
            let asset = AVURLAsset(url: fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.maximumSize = CGSize(width: 1280, height: 720)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
            if let frame = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                let image = NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
                do {
                    let localURL = try FileCoordinator.shared.storeImage(
                        image, type: .file,
                        originalName: fileURL.deletingPathExtension().lastPathComponent + ".png")
                    virtualPath = FileCoordinator.shared.convertToVirtualPath(from: localURL)
                    ThumbnailGenerator.shared.getThumbnailURLAsync(for: localURL) { _ in }
                } catch {
                    print("[DEBUG ScreenshotService] 录屏首帧保存失败: \(error.localizedDescription)")
                }
            }

            let seconds = Int(max(0, duration))
            let durationText = seconds >= 3600
                ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
                : String(format: "%d:%02d", seconds / 60, seconds % 60)

            await MainActor.run { [weak self] in
                self?.recordStore?.addRecord(
                    content: "录屏 \(durationText)：\(path)",
                    hash: hash,
                    sourceApp: "Screen Recording",
                    sourceUrl: virtualPath,
                    type: .video,
                    skipAI: true
                )
                self?.recordStore?.postLightHint("录屏已存入闪记 ✅")
                DiagnosticCenter.info("Save", "录屏已存入闪记: \(fileURL.lastPathComponent)")
            }
        }
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
                ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        } else {
            let bookmarkStore = SecurityScopedBookmarkStore.shared
            if let scopedURL = bookmarkStore.resolve(forKey: "screenshotSaveDirectoryBookmark") {
                dirURL = scopedURL
            } else if bookmarkStore.hasBookmark(forKey: "screenshotSaveDirectoryBookmark") {
                logger.error("截图导出失败：保存目录授权已失效，请重新选择目录")
                return nil
            } else {
                dirURL = URL(fileURLWithPath: (dirPref as NSString).expandingTildeInPath, isDirectory: true)
            }
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
