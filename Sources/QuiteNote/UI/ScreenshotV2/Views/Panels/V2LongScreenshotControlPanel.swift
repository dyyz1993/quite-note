import SwiftUI
import AppKit

/// 长图采集过程中的停止按钮面板
class V2LongScreenshotControlPanel: NSPanel {
    init(selection: CGRect, screen: NSScreen, onFinish: @escaping () -> Void) {
        // 侧边栏布局：窄而长
        let panelWidth: CGFloat = 180
        let panelHeight: CGFloat = 460

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver + 2
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.ignoresMouseEvents = false

        let contentView = NSHostingView(rootView:
            V2CaptureStopToolbarView(onFinish: onFinish)
        )
        self.contentView = contentView

        // 计算位置：优先放在选区右侧，间距 16px
        let spacing: CGFloat = 16

        // 1. 尝试右侧
        var x = screen.frame.minX + selection.maxX + spacing

        // 如果右侧放不下，则尝试左侧
        if x + panelWidth > screen.frame.maxX - 20 {
            x = screen.frame.minX + selection.minX - panelWidth - spacing
        }

        // 2. 垂直居中于选区
        let selectionCenterY = screen.frame.minY + (screen.frame.height - selection.midY)
        var y = selectionCenterY - (panelHeight / 2)

        // 边界保护：确保不超出屏幕顶部或底部
        y = max(screen.frame.minY + 20, min(y, screen.frame.maxX - panelHeight - 20))

        self.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
