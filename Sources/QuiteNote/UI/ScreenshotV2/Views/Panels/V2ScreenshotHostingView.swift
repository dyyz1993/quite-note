import SwiftUI
import AppKit

/// 自定义 HostingView，用于在长图模式下实现选区内的事件穿透
class V2ScreenshotHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // 1. 先检查 SwiftUI 内部是否有组件需要拦截事件 (如按钮、工具栏)
        let hitView = super.hitTest(point)

        let stateManager = V2PrimaryScreenStateManager.shared
        if stateManager.isLongScreenshotMode {
            // 将 AppKit 坐标 (左下角) 转换为 SwiftUI 坐标 (左上角)
            let localSwiftUIPoint = CGPoint(x: point.x, y: self.bounds.height - point.y)

            var isInside = false
            if let selection = stateManager.selectedArea {
                isInside = selection.contains(localSwiftUIPoint)
            }

            let hitViewDesc = hitView != nil ? "\(type(of: hitView!))" : "nil"

            // 2. 判断是否应该穿透
            if isInside {
                // 如果命中的是 HostingView 本身，或者是一些背景类容器，则允许穿透
                var shouldPenetrate = false
                if hitView == nil || hitView == self {
                    shouldPenetrate = true
                } else if let hv = hitView {
                    let className = String(describing: type(of: hv))
                    // 核心修复：跳过 SwiftUI 内部的根视图和更新容器
                    if className.contains("RootView") || className.contains("ViewUpdater") {
                        shouldPenetrate = true
                    }
                }

                if shouldPenetrate {
                    // ⚠️ 终极方案：强制让窗口瞬间忽略事件，确保穿透到底层应用
                    // 这样可以解决系统级别的点击拦截问题，使得滚动和点击能直接作用于下方窗口
                    DispatchQueue.main.async {
                        self.window?.ignoresMouseEvents = true
                        // 延迟极短时间恢复，确保当前的鼠标按下/滚动事件已经穿透
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                            self.window?.ignoresMouseEvents = false
                        }
                    }

                    V2ScreenshotDebugView.onLog?("Penetrating to desktop @ \(Int(localSwiftUIPoint.x)),\(Int(localSwiftUIPoint.y))")
                    return nil // 穿透到桌面
                }
            }

            V2ScreenshotDebugView.onLog?("HitTest - Blocking - Hit: \(hitViewDesc), Inside: \(isInside)")
        }

        return hitView
    }
}
