import SwiftUI

/// AI 闪烁图标 (用户提供的 SVG 设计)
struct AISparkleIcon: View {
    var size: CGFloat = 30
    var color: Color = .white

    var body: some View {
        Canvas { context, size in
            let w = size.width

            // 比例系数
            let scale = w / 24.0

            var path = Path()

            // M12 3v1
            path.move(to: CGPoint(x: 12 * scale, y: 3 * scale))
            path.addLine(to: CGPoint(x: 12 * scale, y: 4 * scale))

            // m0 16v1
            path.move(to: CGPoint(x: 12 * scale, y: 20 * scale))
            path.addLine(to: CGPoint(x: 12 * scale, y: 21 * scale))

            // m9-9h-1
            path.move(to: CGPoint(x: 21 * scale, y: 12 * scale))
            path.addLine(to: CGPoint(x: 20 * scale, y: 12 * scale))

            // M4 12H3
            path.move(to: CGPoint(x: 4 * scale, y: 12 * scale))
            path.addLine(to: CGPoint(x: 3 * scale, y: 12 * scale))

            // m15.364-6.364l-.707.707
            path.move(to: CGPoint(x: 18.364 * scale, y: 5.636 * scale))
            path.addLine(to: CGPoint(x: 17.657 * scale, y: 6.343 * scale))

            // M6.343 17.657l-.707.707
            path.move(to: CGPoint(x: 6.343 * scale, y: 17.657 * scale))
            path.addLine(to: CGPoint(x: 5.636 * scale, y: 18.364 * scale))

            // m0-12.728l.707.707
            path.move(to: CGPoint(x: 5.636 * scale, y: 5.636 * scale))
            path.addLine(to: CGPoint(x: 6.343 * scale, y: 6.343 * scale))

            // m11.314 11.314l.707.707
            path.move(to: CGPoint(x: 17.657 * scale, y: 17.657 * scale))
            path.addLine(to: CGPoint(x: 18.364 * scale, y: 18.364 * scale))

            // M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z (中心圆)
            let circleRect = CGRect(x: 8 * scale, y: 8 * scale, width: 8 * scale, height: 8 * scale)
            path.addEllipse(in: circleRect)

            context.stroke(path, with: .color(color), lineWidth: 2 * scale)
        }
        .frame(width: size, height: size)
    }
}
