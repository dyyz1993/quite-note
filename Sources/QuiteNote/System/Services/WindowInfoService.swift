import Foundation
import CoreGraphics
import AppKit

// MARK: - Window Info Model

    /// 窗口信息
    struct WindowInfo: Identifiable {
        let id = UUID()
        let windowNumber: Int
        let windowID: CGWindowID
        let bounds: CGRect
        let ownerName: String
        let windowName: String?
        let layer: Int
        let alpha: Double
        let isOnscreen: Bool
    }

/// 窗口信息错误
enum WindowInfoError: Error {
    case screenCaptureAccessRequired
    case noWindowsFound
}

/// 窗口信息服务 - 获取和管理窗口信息
class WindowInfoService {
    static let shared = WindowInfoService()

    private init() {}

    // MARK: - 获取窗口列表

    /// 获取所有可见窗口信息
    /// - Returns: 窗口信息数组，按层级排序（高层级在前）
    func fetchAllWindows() -> Result<[WindowInfo], WindowInfoError> {
        // 检查屏幕录制权限
        guard CGPreflightScreenCaptureAccess() else {
            return .failure(.screenCaptureAccessRequired)
        }

        // 获取窗口列表
        guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: AnyObject]] else {
            return .failure(.noWindowsFound)
        }

        var windows: [WindowInfo] = []

        for windowInfo in windowList {
            // 解析窗口边界
            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: AnyObject],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let width = boundsDict["Width"] as? CGFloat,
                  let height = boundsDict["Height"] as? CGFloat,
                  width > 0 && height > 0 else {
                continue
            }

            let bounds = CGRect(x: x, y: y, width: width, height: height)

            // 解析窗口信息
            let windowNumber = windowInfo[kCGWindowNumber as String] as? Int ?? 0
            let ownerName = windowInfo[kCGWindowOwnerName as String] as? String ?? "Unknown"
            let windowName = windowInfo[kCGWindowName as String] as? String
            let layer = windowInfo[kCGWindowLayer as String] as? Int ?? 0
            
            // ⚠️ 过滤掉自己的窗口 (QuiteNote)
            // 这里的 ownerName 可能是 "QuiteNote" 或 "quite-note"
            if ownerName == "QuiteNote" || ownerName == "quite-note" {
                continue
            }
            
            let alpha = windowInfo[kCGWindowAlpha as String] as? Double ?? 1.0
            let isOnscreen = windowInfo[kCGWindowIsOnscreen as String] as? Bool ?? true

            // 过滤掉太小的窗口（可能是窗口部件）
            guard width >= 100 || height >= 100 else {
                continue
            }

            let window = WindowInfo(
                windowNumber: windowNumber,
                windowID: CGWindowID(windowNumber),
                bounds: bounds,
                ownerName: ownerName,
                windowName: windowName,
                layer: layer,
                alpha: alpha,
                isOnscreen: isOnscreen
            )

            windows.append(window)
        }

        // 按层级排序（高层级在前）
        windows.sort { $0.layer > $1.layer }

        return .success(windows)
    }
}
