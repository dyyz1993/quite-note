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

    /// 捕获单个屏幕的截图（同步版本，用于并发调用）
    /// - Parameter screen: 目标屏幕
    /// - Returns: 截图，失败返回 nil
    private func captureScreenSync(_ screen: NSScreen) -> NSImage? {
        // 使用 CGWindowListCreateImage 替代 CGDisplayCreateImage 以确保获取最高质量的截图
        // 特别是在 Retina 屏幕上，这样可以更可靠地获取 2x/3x 的像素数据
        let screenRect = screen.frame
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        
        // 转换坐标系：SwiftUI/AppKit (origin top-left, but screens are bottom-left) 
        // -> CoreGraphics (origin top-left)
        let cgRect = CGRect(
            x: screenRect.origin.x,
            y: mainScreenHeight - screenRect.origin.y - screenRect.height,
            width: screenRect.width,
            height: screenRect.height
        )

        guard let cgImage = CGWindowListCreateImage(
            cgRect,
            .optionAll,
            kCGNullWindowID,
            [.bestResolution, .nominalResolution]
        ) else {
            logger.error("CGWindowListCreateImage 失败 for screen \(screen.localizedName)")
            return nil
        }

        // 转换为 NSImage
        let image = NSImage(cgImage: cgImage, size: screen.frame.size)
        
        // ✨ 核心改进：显式预加载 CGImage 的像素数据。
        // 有时候 NSImage 内部是延迟加载的，或者在不同上下文中返回的分辨率不一致。
        // 通过 force-fetching 确保 NSImage 内部持有的就是原始高分像素。
        if let rep = image.representations.first as? NSBitmapImageRep {
            _ = rep.bitmapData // 强制加载像素
        }
        
        return image
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
}
