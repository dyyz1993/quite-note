import SwiftUI
import AppKit
import OSLog

/// 修复版本 B：添加详细调试日志 + 临时放宽过滤条件
///
/// 使用方法：将此文件的内容复制到 V2WindowHighlightView.swift 的对应位置
///
/// ⚠️ 这个修复假设问题在于窗口过滤逻辑太严格或坐标转换错误
///
extension V2WindowHighlightView {

    /// ⚠️ 修复 B：增强版 windowsOnScreen 计算属性（带详细日志）
    ///
    /// 修改点：
    /// 1. 添加详细的坐标转换日志
    /// 2. 临时放宽窗口过滤条件
    /// 3. 记录每个窗口的过滤原因
    static func debugWindowsOnScreen(
        screen: NSScreen,
        allWindows: [WindowInfo],
        screenCaptureService: V2ScreenCaptureService
    ) -> [WindowInfo] {
        // 1. 获取屏幕边界
        guard let cgScreenBounds = screenCaptureService.getScreenBounds(screen) else {
            print("[V2WindowHighlightView] ⚠️ 无法获取屏幕边界")
            return []
        }

        print("[V2WindowHighlightView] ========== 窗口过滤调试 ==========")
        print("[V2WindowHighlightView] 屏幕: \(screen.localizedName)")
        print("[V2WindowHighlightView] 屏幕边界(CG): \(cgScreenBounds)")
        print("[V2WindowHighlightView] 总窗口数: \(allWindows.count)")

        // 2. 按屏幕过滤
        var windowsOnThisScreen: [WindowInfo] = []
        for window in allWindows {
            let windowCenter = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
            let contains = cgScreenBounds.contains(windowCenter)

            if contains {
                windowsOnThisScreen.append(window)
                print("  ✓ 窗口 '\(window.displayTitle)' 在屏幕内")
            } else {
                print("  ❌ 窗口 '\(window.displayTitle)' 不在屏幕内")
                print("     窗口中心(CG): \(windowCenter)")
                print("     窗口边界(CG): \(window.bounds)")
            }
        }

        print("[V2WindowHighlightView] 屏幕内窗口数: \(windowsOnThisScreen.count)")

        // 3. 应用过滤条件（临时放宽）
        var filtered: [WindowInfo] = []
        for window in windowsOnThisScreen {
            var pass = true
            var reason = ""

            // ⚠️ 放宽：只过滤极小的窗口（10x10 而不是 100x50）
            if window.bounds.width < 10 || window.bounds.height < 10 {
                pass = false
                reason = "尺寸太小 (\(Int(window.bounds.width))x\(Int(window.bounds.height)))"
            }

            // ⚠️ 放宽：不过滤系统窗口（保留所有窗口用于调试）
            // if systemOwners.contains(window.ownerName) {
            //     pass = false
            //     reason = "系统窗口 (\(window.ownerName))"
            // }

            if pass {
                filtered.append(window)
                print("  ✓ 通过过滤: '\(window.displayTitle)' (\(window.ownerName))")
            } else {
                print("  ❌ 过滤掉: '\(window.displayTitle)' - \(reason)")
            }
        }

        print("[V2WindowHighlightView] 过滤后窗口数: \(filtered.count)")
        print("[V2WindowHighlightView] =======================================")

        return filtered
    }
}

/// 在 V2WindowHighlightView.swift 中应用的修复说明
///
/// 步骤 1: 替换 windowsOnScreen 计算属性（第 46-99 行）
///
/// 原代码：
/// ```swift
/// private var windowsOnScreen: [WindowInfo] {
///     guard let cgScreenBounds = V2ScreenCaptureService.shared.getScreenBounds(screen) else {
///         return []
///     }
///
///     print("[V2WindowHighlightView] 屏幕: \(screen.localizedName), 总窗口数: \(allWindows.count)")
///
///     let windowsOnThisScreen = allWindows.filter { window in
///         let windowCenter = CGPoint(
///             x: window.bounds.midX,
///             y: window.bounds.midY
///         )
///         return cgScreenBounds.contains(windowCenter)
///     }
///
///     let filtered = windowsOnThisScreen.filter { window in
///         if window.bounds.width < 100 || window.bounds.height < 50 {
///             return false
///         }
///         // ... 其他过滤条件
///         return true
///     }
///
///     return filtered
/// }
/// ```
///
/// 替换为：
/// ```swift
/// private var windowsOnScreen: [WindowInfo] {
///     // ⚠️ 修复 B：使用增强版调试方法
///     debugWindowsOnScreen(
///         screen: screen,
///         allWindows: allWindows,
///         screenCaptureService: V2ScreenCaptureService.shared
///     )
/// }
/// ```
///
/// 步骤 2: 在 body 中添加更多调试日志（第 157 行附近）
///
/// 在 body 的开头添加：
/// ```swift
/// var body: some View {
///     // ⚠️ 修复 B：添加调试日志
///     let windowsOnScreen = self.windowsOnScreen
///     let localBoundsList = windowsOnScreen.compactMap { window in
///         V2CoordinateMapper.screenToLocal(rect: window.bounds, on: screen)
///     }
///
///     print("[V2WindowHighlightView] ========== 渲染调试 ==========")
///     print("[V2WindowHighlightView] windowsOnScreen.count: \(windowsOnScreen.count)")
///     print("[V2WindowHighlightView] localBoundsList.count: \(localBoundsList.count)")
///     print("[V2WindowHighlightView] localBoundsList.isEmpty: \(localBoundsList.isEmpty)")
///     print("[V2WindowHighlightView] isCurrentlyPrimary: \(isCurrentlyPrimary)")
///     print("[V2WindowHighlightView] =====================================")
///
///     // ... 原有的渲染逻辑
/// }
/// ```
///
/// 步骤 3: 重新编译并测试
/// ```bash
/// ./build-app.sh
/// ```
///
/// 步骤 4: 查看日志输出
///
/// 运行应用并按 `⌘⇧S`，然后在 Console.app 中查看：
/// - "窗口过滤调试" 部分：检查哪些窗口被过滤了
/// - "渲染调试" 部分：检查 localBoundsList 是否为空
///
/// 预期结果：
/// - 如果 "过滤后窗口数" 是 0，说明过滤条件太严格
/// - 如果 "屏幕内窗口数" 是 0，说明坐标转换有问题
/// - 如果 "总窗口数" 是 0，说明权限检查失败
///
/// 根据日志输出，可以进一步调整过滤条件或修复坐标转换逻辑
///
