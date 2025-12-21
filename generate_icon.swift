import AppKit

let size = NSSize(width: 36, height: 36)
let image = NSImage(size: size)

image.lockFocus()
let context = NSGraphicsContext.current?.cgContext

// 背景透明
NSColor.clear.set()
NSRect(origin: .zero, size: size).fill()

// 设置绘图样式
let blackColor = NSColor.black
blackColor.setStroke()
blackColor.setFill()

let center = CGPoint(x: size.width / 2, y: size.height / 2)

// 1. 绘制剪贴板轮廓 (向左上偏移)
let clipboardW: CGFloat = 12
let clipboardH: CGFloat = 15
let clipboardOffset = CGPoint(x: -4, y: 2) // 向左上偏移
let clipboardRect = NSRect(x: center.x - clipboardW/2 + clipboardOffset.x, 
                          y: center.y - clipboardH/2 + clipboardOffset.y, 
                          width: clipboardW, height: clipboardH)
let clipboardPath = NSBezierPath(roundedRect: clipboardRect, xRadius: 2, yRadius: 2)
clipboardPath.lineWidth = 1.5
blackColor.setStroke()
clipboardPath.stroke()

// 剪贴板顶部的夹子
let clipW: CGFloat = 6
let clipH: CGFloat = 3
let clipRect = NSRect(x: clipboardRect.midX - clipW/2, y: clipboardRect.maxY - 1, width: clipW, height: clipH)
let clipPath = NSBezierPath(roundedRect: clipRect, xRadius: 1, yRadius: 1)
blackColor.setFill()
clipPath.fill()

// 2. 绘制放大的四角星 (向右下偏移，产生明显的错位感)
let starLongRadius: CGFloat = 14
let starShortRadius: CGFloat = 4.5
let starOffset = CGPoint(x: 4, y: -3) // 向右下偏移

let starPath = NSBezierPath()
for i in 0..<8 {
    let radius = (i % 2 == 0) ? starLongRadius : starShortRadius
    let angle = CGFloat(i) * .pi / 4
    let pt = CGPoint(
        x: center.x + cos(angle) * radius + starOffset.x,
        y: center.y + sin(angle) * radius + starOffset.y
    )
    if i == 0 {
        starPath.move(to: pt)
    } else {
        starPath.line(to: pt)
    }
}
starPath.close()

// 为了让错位更清晰，给星星加一个白色的细边框（在模板模式下这会产生物理上的空隙）
NSGraphicsContext.saveGraphicsState()
context?.setBlendMode(.destinationOut)
starPath.lineWidth = 2.5
starPath.stroke() // 先用挖空模式画一个粗边框，产生间隙
NSGraphicsContext.restoreGraphicsState()

// 填充星星
blackColor.setFill()
starPath.fill()

// 3. 星星中心的圆点 (挖空)
let innerDotRadius: CGFloat = 1.8
let innerDotRect = NSRect(x: center.x + starOffset.x - innerDotRadius, 
                         y: center.y + starOffset.y - innerDotRadius, 
                         width: innerDotRadius * 2, height: innerDotRadius * 2)
NSGraphicsContext.saveGraphicsState()
context?.setBlendMode(.destinationOut)
let innerDotPath = NSBezierPath(ovalIn: innerDotRect)
NSColor.black.set()
innerDotPath.fill()
NSGraphicsContext.restoreGraphicsState()

image.unlockFocus()

// 设置为模板图像
image.isTemplate = true

if let tiffData = image.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: tiffData),
   let pngData = bitmap.representation(using: .png, properties: [:]) {
    try? pngData.write(to: URL(fileURLWithPath: "StatusBarIcon.png"))
    print("Successfully generated StatusBarIcon.png with offset layout")
}
