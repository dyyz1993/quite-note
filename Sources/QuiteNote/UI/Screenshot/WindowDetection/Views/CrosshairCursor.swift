import AppKit
import SwiftUI

/// 瞄准镜光标视图（用于 SwiftUI 预览）
struct CrosshairCursorView: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                // 十字准星 - 水平线
                Path { path in
                    path.move(to: CGPoint(x: 0, y: center.y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: center.y))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2))

                // 十字准星 - 垂直线
                Path { path in
                    path.move(to: CGPoint(x: center.x, y: 0))
                    path.addLine(to: CGPoint(x: center.x, y: geometry.size.height))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2))

                // 外圈
                Circle()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2))
                    .frame(width: size * 0.7, height: size * 0.7)
                    .position(center)

                // 内圈
                Circle()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1))
                    .frame(width: size * 0.3, height: size * 0.3)
                    .position(center)

                // 中心点
                Circle()
                    .fill(Color.white)
                    .frame(width: 4, height: 4)
                    .position(center)
            }
        }
        .background(Color.clear)
    }
}

/// 瞄准镜光标管理器
class CrosshairCursor {
    static let shared = CrosshairCursor()

    // ✅ 公开光标对象，让外部可以访问
    var cursor: NSCursor?

    private init() {
        cursor = createCursor()
    }

    /// 创建瞄准镜光标
    func createCursor() -> NSCursor {
        let cursorSize = NSSize(width: 40, height: 40)
        let image = NSImage(size: cursorSize)
        image.lockFocus()

        let centerX = cursorSize.width / 2
        let centerY = cursorSize.height / 2

        // 绘制阴影（白色描边效果）
        NSColor.white.setStroke()

        // 十字准星 - 水平线（带阴影）
        let horizontalShadowPath = NSBezierPath()
        horizontalShadowPath.move(to: NSPoint(x: 0, y: centerY + 1))
        horizontalShadowPath.line(to: NSPoint(x: cursorSize.width, y: centerY + 1))
        horizontalShadowPath.lineWidth = 3
        horizontalShadowPath.stroke()

        // 十字准星 - 垂直线（带阴影）
        let verticalShadowPath = NSBezierPath()
        verticalShadowPath.move(to: NSPoint(x: centerX + 1, y: 0))
        verticalShadowPath.line(to: NSPoint(x: centerX + 1, y: cursorSize.height))
        verticalShadowPath.lineWidth = 3
        verticalShadowPath.stroke()

        // 外圈（带阴影）
        let outerCircleShadow = NSBezierPath(ovalIn: NSRect(
            x: (cursorSize.width - cursorSize.width * 0.7) / 2 + 1,
            y: (cursorSize.height - cursorSize.height * 0.7) / 2 + 1,
            width: cursorSize.width * 0.7,
            height: cursorSize.height * 0.7
        ))
        outerCircleShadow.lineWidth = 3
        outerCircleShadow.stroke()

        // 绘制主图形（黑色）
        NSColor.black.setStroke()

        // 十字准星 - 水平线
        let horizontalPath = NSBezierPath()
        horizontalPath.move(to: NSPoint(x: 0, y: centerY))
        horizontalPath.line(to: NSPoint(x: cursorSize.width, y: centerY))
        horizontalPath.lineWidth = 1.5
        horizontalPath.stroke()

        // 十字准星 - 垂直线
        let verticalPath = NSBezierPath()
        verticalPath.move(to: NSPoint(x: centerX, y: 0))
        verticalPath.line(to: NSPoint(x: centerX, y: cursorSize.height))
        verticalPath.lineWidth = 1.5
        verticalPath.stroke()

        // 外圈
        let outerCircle = NSBezierPath(ovalIn: NSRect(
            x: (cursorSize.width - cursorSize.width * 0.7) / 2,
            y: (cursorSize.height - cursorSize.height * 0.7) / 2,
            width: cursorSize.width * 0.7,
            height: cursorSize.height * 0.7
        ))
        outerCircle.lineWidth = 2
        outerCircle.stroke()

        // 内圈
        let innerCircle = NSBezierPath(ovalIn: NSRect(
            x: (cursorSize.width - cursorSize.width * 0.3) / 2,
            y: (cursorSize.height - cursorSize.height * 0.3) / 2,
            width: cursorSize.width * 0.3,
            height: cursorSize.height * 0.3
        ))
        innerCircle.lineWidth = 1
        innerCircle.stroke()

        // 中心点
        let centerDot = NSBezierPath(ovalIn: NSRect(
            x: centerX - 2,
            y: centerY - 2,
            width: 4,
            height: 4
        ))
        NSColor.black.setFill()
        centerDot.fill()

        image.unlockFocus()

        return NSCursor(image: image, hotSpot: NSPoint(x: centerX, y: centerY))
    }

    /// 设置瞄准镜光标
    func set() {
        cursor?.set()
    }

    /// 重置为默认光标
    func reset() {
        NSCursor.arrow.set()
    }
}

// MARK: - SwiftUI Preview

#Preview {
    CrosshairCursorView()
        .frame(width: 40, height: 40)
        .background(Color.gray.opacity(0.3))
}
