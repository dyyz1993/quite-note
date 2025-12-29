import Foundation
import AppKit
import SwiftUI

/// V2 静态截图捕获阶段
enum V2CapturePhase {
    case idle           // 空闲
    case screenSelect   // 屏幕选择
    case windowHover    // 窗口悬停
    case areaSelect     // 区域选择
    case preview        // 预览
}

/// V2 静态截图捕获状态管理
@MainActor
class V2CaptureState: ObservableObject {
    /// 当前阶段
    @Published var phase: V2CapturePhase = .idle

    /// 所有屏幕的截图
    @Published var screenSnapshots: [NSScreen: NSImage] = [:]

    /// 选中的屏幕
    @Published var selectedScreen: NSScreen?

    /// 悬停的窗口
    @Published var hoveredWindow: WindowInfo?

    /// 最终的截图结果
    @Published var finalResult: V2CaptureResult?

    /// 调试日志
    private func log(_ message: String) {
        print("[V2CaptureState] \(message)")
    }
}
