import AppKit

/// 便利贴窗口几何：纯函数，便于单测
enum StickyNoteGeometry {
    static let defaultSize = NSSize(width: 300, height: 200)
    static let minimumSize = NSSize(width: 150, height: 100)
    /// 窗口与屏幕可见区边缘的间距
    static let screenMargin: CGFloat = 10
    /// 连续新建时逐张错开的偏移，免得后一张正好盖住前一张
    static let cascadeOffset = NSPoint(x: 28, y: -28)

    struct Screen: Equatable {
        let frame: NSRect
        let visibleFrame: NSRect
    }

    static func currentScreens() -> [Screen] {
        NSScreen.screens.map { Screen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }

    /// 新建便利贴的位置：以鼠标所在屏为基准，中心跟随鼠标；如果正好压在已有便利贴上，
    /// 沿对角线逐张错开
    static func newNoteFrame(
        mouseLocation: NSPoint,
        screens: [Screen],
        existingFrames: [NSRect] = []
    ) -> NSRect {
        let screen = screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? screens.first
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: defaultSize)
        var frame = clamp(
            NSRect(x: mouseLocation.x - defaultSize.width / 2, y: mouseLocation.y - defaultSize.height / 2,
                   width: defaultSize.width, height: defaultSize.height),
            to: visible
        )
        for _ in 0..<12 where existingFrames.contains(frame) {
            frame.origin.x += cascadeOffset.x
            frame.origin.y += cascadeOffset.y
            frame = clamp(frame, to: visible)
        }
        return frame
    }

    /// 恢复保存的窗口位置时用：显示器拔掉或分辨率变化后，保存的位置可能整块落在屏外，
    /// 而便利贴没有任何"找回"入口。窗口中心还在某块屏的可见区内就留在那块屏，
    /// 否则挪到 fallback（主屏可见区）居中
    static func restoredFrame(_ frame: NSRect, screens: [Screen], fallback: NSRect) -> NSRect {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        if let screen = screens.first(where: { NSPointInRect(center, $0.visibleFrame) }) {
            return clamp(frame, to: screen.visibleFrame)
        }
        let origin = NSPoint(x: fallback.midX - frame.width / 2, y: fallback.midY - frame.height / 2)
        return clamp(NSRect(origin: origin, size: frame.size), to: fallback)
    }

    /// 把窗口完整地放进可见区：尺寸超出的先缩到可见区大小（不低于最小尺寸），位置钳到边缘内
    static func clamp(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect {
        let width = max(min(frame.width, visibleFrame.width), min(minimumSize.width, visibleFrame.width))
        let height = max(min(frame.height, visibleFrame.height), min(minimumSize.height, visibleFrame.height))
        return NSRect(
            x: place(frame.minX, size: width, visibleMin: visibleFrame.minX, visibleMax: visibleFrame.maxX),
            y: place(frame.minY, size: height, visibleMin: visibleFrame.minY, visibleMax: visibleFrame.maxY),
            width: width,
            height: height
        )
    }

    private static func place(_ frameMin: CGFloat, size: CGFloat, visibleMin: CGFloat, visibleMax: CGFloat) -> CGFloat {
        // 窗口已经和可见区一样大：贴着可见区原点放
        if size >= visibleMax - visibleMin { return visibleMin }
        let lower = visibleMin + screenMargin
        let upper = visibleMax - screenMargin - size
        if lower <= upper {
            return min(max(frameMin, lower), upper)
        }
        // 可见区扣掉边距后放不下：不留边距，贴边放
        return min(max(frameMin, visibleMin), visibleMax - size)
    }
}
