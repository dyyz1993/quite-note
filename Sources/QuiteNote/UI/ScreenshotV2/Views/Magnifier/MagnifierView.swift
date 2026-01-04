import SwiftUI

/// 放大镜预览组件 (正方形 + 十字准星版)
struct MagnifierView: View {
    let snapshot: NSImage
    let location: CGPoint
    let screen: NSScreen
    let color: Color // 添加自定义颜色支持

    private let magnifierSize: CGFloat = 120
    private let zoomScale: CGFloat = 3.0

    // 获取当前像素点的颜色
    private var pixelColor: Color {
        let scale = screen.backingScaleFactor
        let x = Int(location.x * scale)
        let y = Int((screen.frame.height - location.y) * scale)

        guard let cgImage = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let pixelData = cgImage.dataProvider?.data,
              let data = CFDataGetBytePtr(pixelData) else {
            return .clear
        }

        let bytesPerPixel = 4
        let bytesPerRow = cgImage.bytesPerRow
        let pixelInfo = y * bytesPerRow + x * bytesPerPixel

        // 确保不越界
        if pixelInfo + 3 >= CFDataGetLength(pixelData) {
            return .clear
        }

        let r = CGFloat(data[pixelInfo]) / 255.0
        let g = CGFloat(data[pixelInfo+1]) / 255.0
        let b = CGFloat(data[pixelInfo+2]) / 255.0
        let a = CGFloat(data[pixelInfo+3]) / 255.0

        return Color(red: r, green: g, blue: b, opacity: a)
    }

    // 获取颜色的 HEX 字符串
    private var hexString: String {
        let nsColor = NSColor(pixelColor)
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var body: some View {
        VStack(spacing: 4) {
            // 放大镜正方形区域
            ZStack {
                // 背景图片裁剪放大
                Rectangle()
                    .fill(Color.black)
                    .frame(width: magnifierSize, height: magnifierSize)

                Image(nsImage: snapshot)
                    .resizable()
                    .frame(width: screen.frame.width * zoomScale, height: screen.frame.height * zoomScale)
                    .offset(
                        x: (screen.frame.width / 2 - location.x) * zoomScale,
                        y: (screen.frame.height / 2 - location.y) * zoomScale
                    )

                // 中心十字准星 (极细线)
                Group {
                    // 纵向线
                    Rectangle()
                        .fill(color.opacity(0.8)) // 使用自定义颜色
                        .frame(width: 0.5, height: magnifierSize)
                        .shadow(color: .black.opacity(0.5), radius: 0.5)

                    // 横向线
                    Rectangle()
                        .fill(color.opacity(0.8)) // 使用自定义颜色
                        .frame(width: magnifierSize, height: 0.5)
                        .shadow(color: .black.opacity(0.5), radius: 0.5)
                }

                // 外框边框
                Rectangle()
                    .stroke(color, lineWidth: 1) // 使用自定义颜色
                    .frame(width: magnifierSize, height: magnifierSize)
                    .shadow(radius: 4)
            }
            .frame(width: magnifierSize, height: magnifierSize)
            .clipped() // ⚠️ 必须裁剪，防止巨型图片溢出

            // 信息面板
            VStack(spacing: 2) {
                Text(hexString)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                HStack(spacing: 4) {
                    Circle() // 将正方形改为小圆点
                        .fill(color) // 使用工具的主题颜色
                        .frame(width: 6, height: 6)
                    
                    Rectangle()
                        .fill(pixelColor)
                        .frame(width: 8, height: 8)
                        .overlay(Rectangle().stroke(Color.white.opacity(0.5), lineWidth: 0.5))

                    Text("(\(Int(location.x)), \(Int(location.y)))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.7))
            .cornerRadius(4)
        }
        .allowsHitTesting(false) // ⚠️ 放大镜不应拦截鼠标事件，确保底层交互层能正常工作
    }
}
