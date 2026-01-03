import SwiftUI
import AppKit

/// 自定义 HostingView，用于在长图模式下实现选区内的事件穿透
class V2ScreenshotHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // 1. 先检查 SwiftUI 内部是否有组件需要拦截事件 (如按钮、工具栏)
        let hitView = super.hitTest(point)

        let stateManager = V2PrimaryScreenStateManager.shared
        // ✅ 只在长截图采集模式下穿透，其他模式正常处理
        guard stateManager.isLongScreenshotMode, stateManager.isCapturing else {
            return hitView
        }

        // 将 AppKit 坐标 (左下角) 转换为 SwiftUI 坐标 (左上角)
        let localSwiftUIPoint = CGPoint(x: point.x, y: self.bounds.height - point.y)

        var isInsideSelection = false
        if let globalSelection = stateManager.selectedArea, let window = self.window {
            // 获取窗口所在的屏幕
            if let screen = NSScreen.screens.first(where: { $0.frame == window.frame }) {
                let screenFrame = screen.frame

                // 将全局 selection 转换为本地坐标
                let localSelection = CGRect(
                    x: max(0, globalSelection.minX - screenFrame.minX),
                    y: max(0, globalSelection.minY - screenFrame.minY),
                    width: min(globalSelection.width, screenFrame.width - max(0, globalSelection.minX - screenFrame.minX)),
                    height: min(globalSelection.height, screenFrame.height - max(0, globalSelection.minY - screenFrame.minY))
                )

                isInsideSelection = localSelection.contains(localSwiftUIPoint)
            }
        }

        // 2. 判断是否应该穿透
        if isInsideSelection {
            // 如果命中的是 HostingView 本身，或者是一些背景类容器，则允许穿透
            var shouldPenetrate = false
            if hitView == nil || hitView == self {
                shouldPenetrate = true
            } else if let hv = hitView {
                let className = String(describing: type(of: hv))
                // ✅ 排除工具栏和按钮类组件
                if className.contains("RootView") ||
                   className.contains("ViewUpdater") ||
                   className.contains("NSButton") ||
                   className.contains("Toolbar") {
                    // 检查是否是工具栏相关组件
                    if !className.contains("Control") {
                        shouldPenetrate = true
                    }
                }
            }

            if shouldPenetrate {
                // ✅ 修复：使用极短延迟（1ms）确保当前滚动事件立即穿透，同时快速恢复窗口响应
                self.window?.ignoresMouseEvents = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
                    self.window?.ignoresMouseEvents = false
                }

                V2ScreenshotView.onLog?("Penetrating to desktop @ \(Int(localSwiftUIPoint.x)),\(Int(localSwiftUIPoint.y))")
                return nil // 穿透到桌面
            }
        }

        let hitViewDesc = hitView != nil ? "\(type(of: hitView!))" : "nil"
        V2ScreenshotView.onLog?("HitTest - Blocking - Hit: \(hitViewDesc), Inside: \(isInsideSelection)")

        return hitView
    }
}
