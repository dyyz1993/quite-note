import Foundation
import CoreGraphics

/// 窗口信息模型
struct WindowInfo: Identifiable, Equatable {
    let id: UUID = UUID()
    let windowNumber: Int
    let windowID: CGWindowID
    let bounds: CGRect
    let ownerName: String
    let windowName: String?
    let layer: Int
    let alpha: Double
    let isOnscreen: Bool

    /// 判断窗口是否可见（透明度足够高且在屏幕上）
    var isVisible: Bool {
        return isOnscreen && alpha > 0.1
    }

    /// 判断点是否在窗口边界内
    func contains(_ point: CGPoint) -> Bool {
        return bounds.contains(point)
    }

    /// 获取窗口显示标题
    var displayTitle: String {
        if let windowName = windowName, !windowName.isEmpty {
            return "\(ownerName) - \(windowName)"
        }
        return ownerName
    }

    /// 获取窗口尺寸描述
    var sizeDescription: String {
        return "\(Int(bounds.width)) × \(Int(bounds.height))"
    }

    /// 获取窗口位置描述
    var positionDescription: String {
        return "(\(Int(bounds.origin.x)), \(Int(bounds.origin.y)))"
    }
}

/// 窗口选择结果
struct SelectedArea {
    let rect: CGRect
    let mode: CaptureMode
    let windowInfo: WindowInfo?

    enum CaptureMode {
        case window       // 点击选中窗口
        case areaDrag     // 拖拽框选区域
        case fullscreen   // 全屏模式
    }
}

/// 窗口信息服务错误类型
enum WindowInfoError: Error, LocalizedError {
    case permissionDenied
    case noWindowsFound
    case screenCaptureAccessRequired

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "需要屏幕录制权限才能获取窗口信息"
        case .noWindowsFound:
            return "未找到任何可见窗口"
        case .screenCaptureAccessRequired:
            return "需要屏幕录制权限"
        }
    }
}
