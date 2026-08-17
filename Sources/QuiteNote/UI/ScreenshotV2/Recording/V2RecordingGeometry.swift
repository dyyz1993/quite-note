import Foundation
import CoreGraphics

/// 录屏几何纯函数集：截图选区 → ScreenCaptureKit / AVFoundation 参数换算
///
/// 坐标系约定（与截图会话一致）：
/// - 「局部坐标」= 选区所在屏幕的左上角原点、y 向下、单位 points（SwiftUI 视图坐标）
/// - SCStreamConfiguration.sourceRect 恰好也是每屏左上原点 points 坐标，可直接使用
/// - NSPanel 摆放需要 AppKit 全局坐标（左下原点），转换在本文件完成
///
/// 全部为无副作用纯函数，单测覆盖：Tests/QuiteNoteTests/RecordingGeometryTests.swift
enum V2RecordingGeometry {

    /// 选区钳制到所在屏幕内
    /// SCK 的 sourceRect 是每屏局部坐标系，跨屏部分会被系统静默裁掉——
    /// 与其让系统裁剪，不如显式钳制（返回 .zero 表示选区完全在屏外，调用方应放弃录制）
    static func clampedSourceRect(local: CGRect, screenPointSize: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: screenPointSize)
        let clamped = local.intersection(bounds)
        guard !clamped.isNull, clamped.width >= 2, clamped.height >= 2 else {
            return .zero
        }
        return clamped
    }

    /// 屏幕局部坐标（左上原点）→ AppKit 全局坐标（左下原点），用于 NSPanel 摆放
    static func appKitGlobalRect(local: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + local.minX,
            y: screenFrame.maxY - local.maxY,
            width: local.width,
            height: local.height
        )
    }

    /// 输出像素尺寸 = points × scale，且宽高必须为偶数
    /// H.264 的 4:2:0 色度采样要求偶数尺寸，奇数会导致编码器拒绝或花屏
    static func pixelSize(for pointSize: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: evenPixels(pointSize.width * scale),
               height: evenPixels(pointSize.height * scale))
    }

    private static func evenPixels(_ value: CGFloat) -> Int {
        let px = Int(value.rounded(.down))
        return max(2, px - px % 2)
    }

    /// 估算码率并钳制到 2M–20M：720p30 ≈ 6 Mbps、1080p30 ≈ 13 Mbps（QuickTime 默认量级）
    static func recommendedBitRate(pixelWidth: Int, pixelHeight: Int, fps: Int) -> Int {
        let raw = Double(pixelWidth * pixelHeight * fps) * 0.22
        return min(20_000_000, max(2_000_000, Int(raw)))
    }
}
