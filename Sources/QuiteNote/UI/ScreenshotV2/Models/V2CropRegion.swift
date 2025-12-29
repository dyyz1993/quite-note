import Foundation
import CoreGraphics

/// V2 裁剪区域模型
struct V2CropRegion {
    /// 裁剪矩形
    var rect: CGRect

    /// 最小尺寸
    var minSize: CGSize = CGSize(width: 50, height: 50)

    /// 检查裁剪区域是否有效
    func isValid(for containerSize: CGSize) -> Bool {
        return rect.width >= minSize.width &&
               rect.height >= minSize.height &&
               rect.origin.x >= 0 &&
               rect.origin.y >= 0 &&
               rect.maxX <= containerSize.width &&
               rect.maxY <= containerSize.height
    }

    /// 限制裁剪区域在容器内
    func clamped(to containerSize: CGSize) -> V2CropRegion {
        var clamped = rect

        // 限制原点
        clamped.origin.x = max(0, clamped.origin.x)
        clamped.origin.y = max(0, clamped.origin.y)

        // 限制尺寸
        let maxWidth = containerSize.width - clamped.origin.x
        let maxHeight = containerSize.height - clamped.origin.y
        clamped.size.width = min(clamped.size.width, maxWidth)
        clamped.size.height = min(clamped.size.height, maxHeight)

        // 确保最小尺寸
        if clamped.size.width < minSize.width {
            clamped.size.width = minSize.width
        }
        if clamped.size.height < minSize.height {
            clamped.size.height = minSize.height
        }

        return V2CropRegion(rect: clamped, minSize: minSize)
    }

    /// 调整裁剪区域（用于拖拽手柄）
    func adjusting(by offset: CGSize, handle: V2CropHandle) -> V2CropRegion {
        var newRect = rect

        switch handle {
        case .topLeft:
            newRect.origin.x += offset.width
            newRect.origin.y += offset.height
            newRect.size.width -= offset.width
            newRect.size.height -= offset.height
        case .topRight:
            newRect.size.width += offset.width
            newRect.origin.y += offset.height
            newRect.size.height -= offset.height
        case .bottomLeft:
            newRect.origin.x += offset.width
            newRect.size.width -= offset.width
            newRect.size.height += offset.height
        case .bottomRight:
            newRect.size.width += offset.width
            newRect.size.height += offset.height
        case .top:
            newRect.origin.y += offset.height
            newRect.size.height -= offset.height
        case .bottom:
            newRect.size.height += offset.height
        case .left:
            newRect.origin.x += offset.width
            newRect.size.width -= offset.width
        case .right:
            newRect.size.width += offset.width
        case .center:
            newRect.origin.x += offset.width
            newRect.origin.y += offset.height
        }

        return V2CropRegion(rect: newRect, minSize: minSize)
    }
}

/// V2 裁剪手柄位置
enum V2CropHandle: CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case top
    case bottom
    case left
    case right
    case center
}
