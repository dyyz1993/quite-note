import Foundation
import AppKit

/// 图像拼接结果
struct StitchResult {
    /// 拼接后的长图
    let image: NSImage
    /// 使用的帧数
    let frameCount: Int
    /// 最终画布尺寸
    let canvasSize: NSSize
    /// 总滚动距离
    let totalScrollDistance: CGFloat

    /// 成功结果
    static func success(
        image: NSImage,
        frameCount: Int,
        canvasSize: NSSize,
        totalScrollDistance: CGFloat
    ) -> StitchResult {
        return StitchResult(
            image: image,
            frameCount: frameCount,
            canvasSize: canvasSize,
            totalScrollDistance: totalScrollDistance
        )
    }
}
