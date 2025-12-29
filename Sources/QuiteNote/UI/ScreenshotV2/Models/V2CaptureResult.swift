import Foundation
import AppKit

/// V2 截图捕获结果
struct V2CaptureResult {
    /// 完整截图（不裁剪）
    let image: NSImage

    /// 截图来源的屏幕
    let screen: NSScreen

    /// 初始裁剪框（相对于完整截图的坐标）
    let initialCropRect: CGRect?

    /// 捕获模式
    let mode: V2CaptureMode

    /// 截图模式
    enum V2CaptureMode {
        case fullscreen    // 全屏截图
        case window       // 窗口截图
        case area         // 区域截图
    }
}
