import SwiftUI
import AppKit

/// V2 坐标空间管理 - 统一处理多屏幕截图中的坐标转换
///
/// 设计理念：
/// 1. 明确区分不同的坐标空间（屏幕全局、窗口、视图本地）
/// 2. 提供统一的转换接口，避免直接使用 .offset() 和 .position() 混合
/// 3. 分离"渲染"和"定位"职责，提高代码可维护性
///
enum V2CoordinateSpace {
    /// 屏幕全局坐标空间（原点在主屏幕左上角）
    case screen(NSScreen)
    /// 窗口坐标空间（原点在窗口左上角）
    case window
    /// 视图本地坐标空间（原点在视图左上角）
    case view

    // MARK: - 坐标转换

    /// 将一个点从当前坐标空间转换到目标坐标空间
    func convert(_ point: CGPoint, to targetSpace: V2CoordinateSpace) -> CGPoint? {
        // 暂时简化实现，后续可以扩展
        switch (self, targetSpace) {
        case (.screen(let sourceScreen), .screen(let targetScreen)):
            // 屏幕之间的转换
            if sourceScreen == targetScreen {
                return point
            }
            // 计算屏幕之间的偏移
            let offsetX = targetScreen.frame.origin.x - sourceScreen.frame.origin.x
            let offsetY = targetScreen.frame.origin.y - sourceScreen.frame.origin.y
            return CGPoint(x: point.x - offsetX, y: point.y - offsetY)

        case (.view, .screen(let screen)):
            // 视图本地 → 屏幕全局
            // 需要传入视图所在屏幕的偏移
            return CGPoint(
                x: point.x + screen.frame.origin.x,
                y: point.y + screen.frame.origin.y
            )

        case (.screen(let screen), .view):
            // 屏幕全局 → 视图本地
            return CGPoint(
                x: point.x - screen.frame.origin.x,
                y: point.y - screen.frame.origin.y
            )

        default:
            // 其他情况暂时返回 nil，等待实现
            return nil
        }
    }

    /// 将一个矩形从当前坐标空间转换到目标坐标空间
    func convert(_ rect: CGRect, to targetSpace: V2CoordinateSpace) -> CGRect? {
        guard let origin = convert(rect.origin, to: targetSpace) else {
            return nil
        }
        return CGRect(origin: origin, size: rect.size)
    }
}

// MARK: - 定位辅助

extension V2CoordinateSpace {
    /// 在指定坐标空间中定位视图
    ///
    /// 使用场景：
    /// - YellowWireframe 只负责渲染，不负责定位
    /// - 调用者使用此方法将线框定位到正确位置
    ///
    /// @param rect 线框在视图本地坐标系的尺寸和位置（相对于 (0, 0)）
    /// @returns 在当前坐标空间中的锚点位置
    func anchorPosition(for rect: CGRect) -> CGPoint {
        switch self {
        case .screen:
            // 屏幕空间：返回屏幕全局坐标
            return rect.origin
        case .window:
            // 窗口空间：返回窗口坐标
            return rect.origin
        case .view:
            // 视图空间：返回相对坐标
            return rect.origin
        }
    }

    /// 计算线框的中心点位置（用于 .position() 定位）
    func centerPosition(for rect: CGRect) -> CGPoint {
        return CGPoint(x: rect.midX, y: rect.midY)
    }
}

// MARK: - 线框定位协议

/// 可定位的线框协议
///
/// 所有需要定位的线框组件都应该遵循此协议
protocol V2PositionableWireframe {
    /// 线框的尺寸（不含位置信息）
    var size: CGSize { get }
}

// MARK: - 调试辅助

#if DEBUG
extension V2CoordinateSpace {
    /// 获取坐标空间的调试描述
    var debugDescription: String {
        switch self {
        case .screen(let screen):
            return "Screen(\(screen.localizedName))"
        case .window:
            return "Window"
        case .view:
            return "View"
        }
    }

    /// 打印坐标转换路径（用于调试）
    func debugConversion(_ point: CGPoint, to targetSpace: V2CoordinateSpace) -> String {
        let fromDesc = debugDescription
        let toDesc = targetSpace.debugDescription
        if let converted = convert(point, to: targetSpace) {
            return "[\(fromDesc) → \(toDesc)] \(point) → \(converted)"
        } else {
            return "[\(fromDesc) → \(toDesc)] FAILED: \(point)"
        }
    }
}
#endif
