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

    /// 窗口是否可见
    var isVisible: Bool {
        return alpha > 0.01 && isOnscreen
    }

    /// 窗口是否包含指定点
    func contains(_ point: CGPoint) -> Bool {
        return bounds.contains(point)
    }

    /// 显示标题（用于调试）
    var displayTitle: String {
        if let windowName = windowName, !windowName.isEmpty {
            return "\(ownerName) - \(windowName)"
        }
        return ownerName
    }
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

    // MARK: - 窗口命中检测

    /// 查找指定位置下的窗口
    /// - Parameters:
    ///   - point: 屏幕坐标点
    ///   - windows: 窗口列表（可选，为空时自动获取）
    /// - Returns: 命中的窗口信息，如果没有命中则返回 nil
    func findWindow(at point: CGPoint, in windows: [WindowInfo]? = nil) -> WindowInfo? {
        print("[DEBUG WindowInfoService] findWindow 被调用，point: \(point)")
        let windowList: [WindowInfo]

        if let windows = windows {
            windowList = windows
            print("[DEBUG WindowInfoService] 使用传入的窗口列表，数量: \(windows.count)")
        } else {
            // 自动获取窗口列表
            switch fetchAllWindows() {
            case .success(let list):
                windowList = list
                print("[DEBUG WindowInfoService] 自动获取窗口列表，数量: \(list.count)")
            case .failure(let error):
                print("[DEBUG WindowInfoService] 获取窗口列表失败: \(error)")
                return nil
            }
        }

        // 查找命中点且可见的窗口
        // 由于已按层级排序，第一个命中的就是最高层级的窗口
        let found = windowList.first { window in
            let contains = window.isVisible && window.contains(point)
            if contains {
                print("[DEBUG WindowInfoService] 命中窗口: \(window.displayTitle), bounds: \(window.bounds)")
            }
            return contains
        }

        print("[DEBUG WindowInfoService] 最终结果: \(found?.displayTitle ?? "nil")")
        return found
    }

    // MARK: - 屏幕截图

    /// 截取屏幕指定区域
    /// - Parameters:
    ///   - rect: 要截取的区域（屏幕坐标）
    ///   - screen: 目标屏幕（nil 表示主屏幕）
    /// - Returns: 截图图片
    func captureScreen(rect: CGRect, screen: NSScreen? = nil) -> NSImage? {
        let targetScreen = screen ?? NSScreen.main
        guard let targetScreen = targetScreen else {
            return nil
        }

        // 获取屏幕的 displayID
        let displayID = targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID

        // 创建截图
        guard let cgImage = CGDisplayCreateImage(displayID, rect: rect) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: rect.size)
    }

    /// 截取指定窗口
    /// - Parameter window: 窗口信息
    /// - Returns: 截图图片
    func captureWindow(_ window: WindowInfo) -> NSImage? {
        print("[DEBUG WindowInfoService] captureWindow 被调用")
        print("[DEBUG WindowInfoService] 窗口 bounds（屏幕坐标）: \(window.bounds)")
        print("[DEBUG WindowInfoService] 窗口尺寸: \(window.bounds.width) x \(window.bounds.height)")

        let image = captureScreen(rect: window.bounds)

        if let image = image {
            print("[DEBUG WindowInfoService] 截图成功，图片尺寸: \(image.size)")
        } else {
            print("[DEBUG WindowInfoService] ⚠️ 截图失败")
        }

        return image
    }

    /// 截取整个屏幕
    /// - Parameter screen: 目标屏幕（nil 表示主屏幕）
    /// - Returns: 截图图片
    func captureFullScreen(screen: NSScreen? = nil) -> NSImage? {
        let targetScreen = screen ?? NSScreen.main
        guard let targetScreen = targetScreen else {
            return nil
        }

        return captureScreen(rect: targetScreen.frame, screen: targetScreen)
    }

    // MARK: - 坐标转换

    /// 将屏幕坐标转换为图片坐标
    /// - Parameters:
    ///   - screenRect: 屏幕坐标矩形
    ///   - imageSize: 图片尺寸
    ///   - screenSize: 屏幕尺寸
    /// - Returns: 图片坐标矩形
    func screenToImageRect(_ screenRect: CGRect, imageSize: CGSize, screenSize: CGSize) -> CGRect {
        let scaleX = imageSize.width / screenSize.width
        let scaleY = imageSize.height / screenSize.height

        return CGRect(
            x: screenRect.origin.x * scaleX,
            y: screenRect.origin.y * scaleY,
            width: screenRect.size.width * scaleX,
            height: screenRect.size.height * scaleY
        )
    }

    /// 获取主屏幕尺寸
    var mainScreenSize: CGSize {
        return NSScreen.main?.frame.size ?? .zero
    }

    /// 获取主屏幕框架
    var mainScreenFrame: CGRect {
        return NSScreen.main?.frame ?? .zero
    }
}
