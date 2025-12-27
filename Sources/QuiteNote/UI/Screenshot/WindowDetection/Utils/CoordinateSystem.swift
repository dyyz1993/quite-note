import AppKit
import Foundation

/// 坐标系统工具类 - 统一处理 macOS 的三种坐标系统转换
///
/// macOS 存在三种坐标系统：
/// 1. CoreGraphics 坐标系（屏幕坐标）：原点在左上角，Y 轴向下增长
/// 2. AppKit 坐标系（窗口坐标）：原点在左下角，Y 轴向上增长
/// 3. SwiftUI 坐标系（视图坐标）：原点在左上角，Y 轴向下增长
///
/// 重要说明：
/// - CGWindowListCopyWindowInfo 返回的 bounds 是 CoreGraphics 坐标系
/// - NSEvent.mouseLocation 返回的是 AppKit 坐标系
/// - SwiftUI 视图使用的是 SwiftUI 坐标系
struct CoordinateSystem {

    // MARK: - 屏幕查找

    /// 查找包含指定点的屏幕（CoreGraphics 坐标系）
    /// - Parameter point: 全局坐标点（CoreGraphics 坐标系）
    /// - Returns: 包含该点的屏幕，如果找不到则返回 nil
    static func screenContaining(point: CGPoint) -> NSScreen? {
        // ✅ 修复：使用 CoreGraphics 坐标系查找屏幕
        // 需要将点转换为 AppKit 坐标系（NSScreen.frame 使用 AppKit 坐标系）
        let appKitPoint = coreGraphicsToAppKit(point, screenHeight: NSScreen.main?.frame.height ?? 1080)
        return NSScreen.screens.first { $0.frame.contains(appKitPoint) }
    }

    /// 查找包含指定窗口的屏幕
    /// - Parameter rect: 窗口的边界矩形（CoreGraphics 坐标系）
    /// - Returns: 包含该窗口中心的屏幕，如果找不到则返回主屏幕
    static func screenContaining(rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return screenContaining(point: center) ?? NSScreen.main
    }

    // MARK: - 点转换

    /// 将 AppKit 坐标（Y 向上）转换为 CoreGraphics 坐标（Y 向下）
    /// - Parameters:
    ///   - point: AppKit 坐标点
    ///   - screenHeight: 屏幕高度
    /// - Returns: CoreGraphics 坐标点
    static func appKitToCoreGraphics(_ point: CGPoint, screenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: screenHeight - point.y)
    }

    /// 将 CoreGraphics 坐标（Y 向下）转换为 AppKit 坐标（Y 向上）
    /// - Parameters:
    ///   - point: CoreGraphics 坐标点
    ///   - screenHeight: 屏幕高度
    /// - Returns: AppKit 坐标点
    static func coreGraphicsToAppKit(_ point: CGPoint, screenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: screenHeight - point.y)
    }

    // MARK: - 矩形转换

    /// 将 AppKit 矩形（Y 向上）转换为 CoreGraphics 矩形（Y 向下）
    /// - Parameters:
    ///   - rect: AppKit 坐标矩形
    ///   - screenHeight: 屏幕高度
    /// - Returns: CoreGraphics 坐标矩形
    static func appKitToCoreGraphics(_ rect: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: screenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// 将 CoreGraphics 矩形（Y 向下）转换为 AppKit 矩形（Y 向上）
    /// - Parameters:
    ///   - rect: CoreGraphics 坐标矩形
    ///   - screenHeight: 屏幕高度
    /// - Returns: AppKit 坐标矩形
    static func coreGraphicsToAppKit(_ rect: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: screenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    // MARK: - 屏幕坐标 <-> 窗口局部坐标

    /// 将屏幕坐标（CoreGraphics）转换为窗口局部坐标（SwiftUI）
    /// - Parameters:
    ///   - screenPoint: 屏幕坐标点（CoreGraphics 坐标系）
    ///   - windowFrame: 窗口的屏幕框架（AppKit 坐标系）
    ///   - screen: 屏幕
    /// - Returns: 窗口局部坐标点（SwiftUI 坐标系）
    static func screenToLocal(
        _ screenPoint: CGPoint,
        windowFrame: CGRect,
        screen: NSScreen
    ) -> CGPoint {
        // 1. 将窗口框架从 AppKit 坐标系转换为 CoreGraphics 坐标系
        let windowFrameCG = appKitToCoreGraphics(windowFrame, screenHeight: screen.frame.height)

        // 2. 计算局部坐标
        return CGPoint(
            x: screenPoint.x - windowFrameCG.origin.x,
            y: screenPoint.y - windowFrameCG.origin.y
        )
    }

    /// 将窗口局部坐标（SwiftUI）转换为屏幕坐标（CoreGraphics）
    /// - Parameters:
    ///   - localPoint: 窗口局部坐标点（SwiftUI 坐标系）
    ///   - windowFrame: 窗口的屏幕框架（AppKit 坐标系）
    ///   - screen: 屏幕
    /// - Returns: 屏幕坐标点（CoreGraphics 坐标系）
    static func localToScreen(
        _ localPoint: CGPoint,
        windowFrame: CGRect,
        screen: NSScreen
    ) -> CGPoint {
        // 1. 将窗口框架从 AppKit 坐标系转换为 CoreGraphics 坐标系
        let windowFrameCG = appKitToCoreGraphics(windowFrame, screenHeight: screen.frame.height)

        // 2. 计算屏幕坐标
        return CGPoint(
            x: localPoint.x + windowFrameCG.origin.x,
            y: localPoint.y + windowFrameCG.origin.y
        )
    }

    /// 将屏幕矩形（CoreGraphics）转换为窗口局部矩形（SwiftUI）
    /// - Parameters:
    ///   - screenRect: 屏幕坐标矩形（CoreGraphics 坐标系）
    ///   - windowFrame: 窗口的屏幕框架（AppKit 坐标系）
    ///   - screen: 屏幕
    /// - Returns: 窗口局部矩形（SwiftUI 坐标系）
    static func screenToLocal(
        _ screenRect: CGRect,
        windowFrame: CGRect,
        screen: NSScreen
    ) -> CGRect {
        // 1. 将窗口框架从 AppKit 坐标系转换为 CoreGraphics 坐标系
        let windowFrameCG = appKitToCoreGraphics(windowFrame, screenHeight: screen.frame.height)

        // 2. 计算局部矩形
        return CGRect(
            x: screenRect.origin.x - windowFrameCG.origin.x,
            y: screenRect.origin.y - windowFrameCG.origin.y,
            width: screenRect.size.width,
            height: screenRect.size.height
        )
    }

    // MARK: - 辅助方法

    /// 获取鼠标在屏幕上的位置（CoreGraphics 坐标系）
    /// - Returns: 鼠标位置（CoreGraphics 坐标系）
    static func mouseLocationInCoreGraphics() -> CGPoint {
        let mouseLocation = NSEvent.mouseLocation  // AppKit 坐标系
        guard let screen = NSScreen.main else {
            return mouseLocation
        }
        return appKitToCoreGraphics(mouseLocation, screenHeight: screen.frame.height)
    }
}
