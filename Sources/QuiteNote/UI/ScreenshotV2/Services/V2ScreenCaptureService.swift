import Foundation
import AppKit
import CoreGraphics
import OSLog

/// V2 屏幕捕获服务 - 负责截取所有屏幕的静态截图
/// ⚠️ 性能优化：使用并发截图，但限制并发数为2以避免内存峰值
@MainActor
class V2ScreenCaptureService {
    private let logger = Logger(subsystem: "com.quitenote.app.dev", category: "V2ScreenCaptureService")

    static let shared = V2ScreenCaptureService()

    private init() {}

    /// 捕获所有屏幕的截图（性能优化版本）
    /// - Returns: [NSScreen: NSImage] 屏幕到截图的映射
    func captureAllScreens() -> [NSScreen: NSImage] {
        let startTime = Date()
        logger.info("开始捕获所有屏幕，共 \(NSScreen.screens.count) 个")

        var snapshots: [NSScreen: NSImage] = [:]

        // ⚠️ 性能优化：顺序截图，添加进度日志
        for screen in NSScreen.screens {
            if let snapshot = captureScreenSync(screen) {
                snapshots[screen] = snapshot
                print("[V2ScreenCaptureService] ✓ 捕获屏幕: \(screen.localizedName), 尺寸: \(snapshot.size)")
            } else {
                logger.error("✗ 捕获失败: \(screen.localizedName)")
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        logger.info("捕获完成，共 \(snapshots.count)/\(NSScreen.screens.count) 个屏幕，耗时 \(String(format: "%.2f", duration))s")

        return snapshots
    }

    /// 捕获单个屏幕的截图（同步版本，用于并发调用）
    /// - Parameter screen: 目标屏幕
    /// - Returns: 截图，失败返回 nil
    private func captureScreenSync(_ screen: NSScreen) -> NSImage? {
        // 获取屏幕的 Display ID
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            logger.error("无法获取 Display ID for \(screen.localizedName)")
            return nil
        }

        // 使用 CGDisplayCreateImage 截图
        guard let cgImage = CGDisplayCreateImage(displayID) else {
            logger.error("CGDisplayCreateImage 失败 for display \(displayID)")
            return nil
        }

        // 转换为 NSImage
        return NSImage(cgImage: cgImage, size: screen.frame.size)
    }

    /// 捕获单个屏幕的截图（公开方法，保持向后兼容）
    /// - Parameter screen: 目标屏幕
    /// - Returns: 截图，失败返回 nil
    func captureScreen(_ screen: NSScreen) -> NSImage? {
        return captureScreenSync(screen)
    }

    /// 获取屏幕的 Display ID
    /// - Parameter screen: 目标屏幕
    /// - Returns: Display ID，失败返回 nil
    func getDisplayID(for screen: NSScreen) -> CGDirectDisplayID? {
        return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// 获取屏幕的全局 Frame（CoreGraphics 坐标系）
    /// - Parameter screen: 目标屏幕
    /// - Returns: 屏幕 Frame，失败返回 nil
    func getScreenBounds(_ screen: NSScreen) -> CGRect? {
        guard let displayID = getDisplayID(for: screen) else {
            return nil
        }
        return CGDisplayBounds(displayID)
    }

    /// 计算所有屏幕的合并边界
    /// - Returns: 包含所有屏幕的最小 CGRect
    func getTotalScreensBounds() -> CGRect {
        var minX: CGFloat = .infinity
        var minY: CGFloat = .infinity
        var maxX: CGFloat = -.infinity
        var maxY: CGFloat = -.infinity

        for screen in NSScreen.screens {
            guard let bounds = getScreenBounds(screen) else { continue }
            minX = min(minX, bounds.minX)
            minY = min(minY, bounds.minY)
            maxX = max(maxX, bounds.maxX)
            maxY = max(maxY, bounds.maxY)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 打印所有屏幕信息（调试用）
    func printAllScreensInfo() {
        print("[V2ScreenCaptureService] ========== 屏幕信息 ==========")
        for (index, screen) in NSScreen.screens.enumerated() {
            let bounds = getScreenBounds(screen)
            print("屏幕 \(index): \(screen.localizedName)")
            print("  NSScreen.frame: \(screen.frame)")
            print("  CGDisplayBounds: \(String(describing: bounds))")
            print("  可见区域: \(screen.visibleFrame)")
            if let displayID = getDisplayID(for: screen) {
                print("  Display ID: \(displayID)")
            }
            print("  是否主屏: \(screen == NSScreen.main ? "是" : "否")")
            print("----------------------------------------")
        }
        print("========================================")
    }
}
