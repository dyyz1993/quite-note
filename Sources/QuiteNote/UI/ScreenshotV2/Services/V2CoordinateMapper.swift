import Foundation
import AppKit
import CoreGraphics
import OSLog

/// V2 坐标映射服务 - 负责不同坐标系之间的转换
/// ✅ 统一使用 NSScreen.frame (AppKit 坐标系: 左下角原点)
@MainActor
struct V2CoordinateMapper {
    private static let logger = Logger(subsystem: "com.quitenote.app.dev", category: "V2CoordinateMapper")

    /// ✅ AppKit 全局坐标转换为屏幕局部坐标
    /// - Parameters:
    ///   - rect: 全局矩形（AppKit坐标系，左下角原点）
    ///   - screen: 目标屏幕
    /// - Returns: 屏幕局部矩形
    nonisolated static func appKitGlobalToLocal(rect: CGRect, on screen: NSScreen) -> CGRect {
        let screenFrame = screen.frame
        return CGRect(
            x: rect.origin.x - screenFrame.origin.x,
            y: rect.origin.y - screenFrame.origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    /// ✅ 全局坐标（AppKit 坐标系）转换为屏幕局部坐标
    /// - Parameters:
    ///   - point: 全局坐标（AppKit 坐标系，左下角原点）
    ///   - screen: 目标屏幕
    /// - Returns: 屏幕局部坐标，转换失败返回 nil
    static func screenToLocal(point: CGPoint, on screen: NSScreen) -> CGPoint? {
        let screenFrame = screen.frame

        // 验证点是否在屏幕范围内（仅警告，不阻止转换）
        if !screenFrame.contains(point) {
            print("[V2CoordinateMapper] 点不在屏幕范围内，坐标转换可能不准确: point=\(point), screen=\(screen.localizedName)")
        }

        return CGPoint(
            x: point.x - screenFrame.origin.x,
            y: point.y - screenFrame.origin.y
        )
    }

    /// 屏幕局部坐标转换为 CoreGraphics 全局坐标
    /// - Parameters:
    ///   - point: 局部坐标
    ///   - screen: 所在屏幕
    /// - Returns: 全局坐标
    static func localToScreen(point: CGPoint, on screen: NSScreen) -> CGPoint? {
        guard let screenBounds = V2ScreenCaptureService.shared.getScreenBounds(screen) else {
            return nil
        }

        return CGPoint(
            x: point.x + screenBounds.origin.x,
            y: point.y + screenBounds.origin.y
        )
    }

    /// CoreGraphics 全局 CGRect 转换为屏幕局部坐标
    /// - Parameters:
    ///   - rect: 全局矩形
    ///   - screen: 目标屏幕
    /// - Returns: 局部矩形，转换失败返回 nil
    static func screenToLocal(rect: CGRect, on screen: NSScreen) -> CGRect? {
        guard let screenBounds = V2ScreenCaptureService.shared.getScreenBounds(screen) else {
            logger.error("无法获取屏幕边界，矩形坐标转换失败: \(screen.localizedName)")
            return nil
        }

        // ⚠️ 不验证矩形是否完全在屏幕内，因为窗口可能跨屏幕
        // 只检查矩形是否有有效尺寸
        guard rect.width > 0 && rect.height > 0 else {
            print("[V2CoordinateMapper] 矩形尺寸无效: \(rect)")
            return nil
        }

        return CGRect(
            x: rect.origin.x - screenBounds.origin.x,
            y: rect.origin.y - screenBounds.origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    /// 屏幕局部 CGRect 转换为 CoreGraphics 全局坐标
    /// - Parameters:
    ///   - rect: 局部矩形
    ///   - screen: 所在屏幕
    /// - Returns: 全局矩形
    static func localToScreen(rect: CGRect, on screen: NSScreen) -> CGRect? {
        guard let screenBounds = V2ScreenCaptureService.shared.getScreenBounds(screen) else {
            return nil
        }

        return CGRect(
            x: rect.origin.x + screenBounds.origin.x,
            y: rect.origin.y + screenBounds.origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    /// AppKit 坐标（鼠标位置）转换为 CoreGraphics 全局坐标
    /// - Parameter appKitPoint: AppKit 坐标（左下角原点）
    /// - Returns: CoreGraphics 坐标（左上角原点）
    static func appKitToCoreGraphics(_ appKitPoint: CGPoint) -> CGPoint {
        // 找到包含这个点的屏幕
        for screen in NSScreen.screens {
            let screenFrame = screen.frame
            // AppKit: 左下角原点
            if screenFrame.contains(appKitPoint) {
                // 转换为该屏幕的 CoreGraphics 坐标
                return CGPoint(
                    x: appKitPoint.x,
                    y: screenFrame.maxY - appKitPoint.y + screenFrame.minY
                )
            }
        }

        // 降级：使用主屏幕
        let mainScreenHeight = NSScreen.main?.frame.height ?? 0
        return CGPoint(
            x: appKitPoint.x,
            y: mainScreenHeight - appKitPoint.y
        )
    }

    /// CoreGraphics 全局坐标转换为 AppKit 坐标
    /// - Parameter cgPoint: CoreGraphics 坐标（左上角原点）
    /// - Returns: AppKit 坐标（左下角原点）
    static func coreGraphicsToAppKit(_ cgPoint: CGPoint) -> CGPoint {
        // 找到包含这个点的屏幕
        for screen in NSScreen.screens {
            if let screenBounds = V2ScreenCaptureService.shared.getScreenBounds(screen) {
                if screenBounds.contains(cgPoint) {
                    // 转换为该屏幕的 AppKit 坐标
                    return CGPoint(
                        x: cgPoint.x,
                        y: screenBounds.maxY - cgPoint.y + screenBounds.minY
                    )
                }
            }
        }

        // 降级：使用主屏幕
        let mainScreenHeight = NSScreen.main?.frame.height ?? 0
        return CGPoint(
            x: cgPoint.x,
            y: mainScreenHeight - cgPoint.y
        )
    }

    /// 检查点是否在屏幕内
    /// - Parameters:
    ///   - point: 点（全局坐标）
    ///   - screen: 目标屏幕
    /// - Returns: 是否在屏幕内
    static func isPointInScreen(_ point: CGPoint, on screen: NSScreen) -> Bool {
        guard let screenBounds = V2ScreenCaptureService.shared.getScreenBounds(screen) else {
            return false
        }
        return screenBounds.contains(point)
    }

    /// 查找包含点的屏幕
    /// - Parameter point: 点（全局坐标）
    /// - Returns: 屏幕，未找到返回 nil
    static func findScreenContaining(point: CGPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            if isPointInScreen(point, on: screen) {
                return screen
            }
        }
        return nil
    }

    /// 打印坐标转换信息（调试用）
    static func debugPrintCoordinates() {
        print("[V2CoordinateMapper] ========== 坐标调试信息 ==========")
        print("鼠标位置 (AppKit): \(NSEvent.mouseLocation)")
        let cgPoint = appKitToCoreGraphics(NSEvent.mouseLocation)
        print("鼠标位置 (CoreGraphics): \(cgPoint)")

        for screen in NSScreen.screens {
            if let bounds = V2ScreenCaptureService.shared.getScreenBounds(screen) {
                print("\n屏幕: \(screen.localizedName)")
                print("  NSScreen.frame (AppKit): \(screen.frame)")
                print("  CGDisplayBounds (CoreGraphics): \(bounds)")
                print("  包含鼠标: \(bounds.contains(cgPoint))")
            }
        }
        print("==========================================")
    }
}
