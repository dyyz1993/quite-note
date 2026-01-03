import Foundation
import AppKit

/// 长截图捕获配置
/// 简化版本：只保留基本参数，移除所有拼接相关配置
struct CaptureConfig {
    /// 滚动距离阈值（像素）
    let scrollThreshold: CGFloat
    /// 是否启用自动检测
    let autoDetectEnabled: Bool
    /// 最大捕获帧数（防止无限滚动）
    let maxFrames: Int
    /// 采集时的重叠百分比（用于计算滚动偏移）
    let captureOverlapPercentage: CGFloat

    static let `default` = CaptureConfig(
        scrollThreshold: 500,
        autoDetectEnabled: true,
        maxFrames: 50,
        captureOverlapPercentage: 0.30  // 30% 重叠
    )

    /// 保守配置（适用于快速滚动的内容）
    static let sensitive = CaptureConfig(
        scrollThreshold: 300,
        autoDetectEnabled: true,
        maxFrames: 50,
        captureOverlapPercentage: 0.35  // 35% 重叠
    )

    /// 宽松配置（适用于慢速滚动的内容）
    static let loose = CaptureConfig(
        scrollThreshold: 800,
        autoDetectEnabled: true,
        maxFrames: 50,
        captureOverlapPercentage: 0.25  // 25% 重叠
    )
}
