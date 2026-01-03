import SwiftUI

/// 文本编辑状态
struct TextEditState {
    let elementId: UUID
    var position: CGPoint
    var text: String
    var color: Color
    var fontSize: CGFloat
    var isEditing: Bool

    /// 计算文本边界框（用于定位输入框）
    func boundingRect(minWidth: CGFloat = 200, maxWidth: CGFloat = 600) -> CGRect {
        let lineHeight = fontSize * 1.3
        let lines = text.components(separatedBy: .newlines)

        // 计算每行宽度
        var maxLineWidth: CGFloat = minWidth
        for line in lines {
            let charWidth = fontSize * 0.6  // 粗略估计字符宽度
            let lineWidth = max(minWidth, CGFloat(line.count) * charWidth + 20)
            maxLineWidth = max(maxLineWidth, lineWidth)
        }

        // 限制最大宽度
        let width = min(maxLineWidth, maxWidth)
        let height = max(40, CGFloat(lines.count) * lineHeight)

        return CGRect(
            x: position.x,
            y: position.y,
            width: width,
            height: height
        )
    }

    /// 根据文本内容动态计算尺寸
    func calculatePreferredSize(fontSize: CGFloat) -> CGSize {
        let font = NSFont.systemFont(ofSize: fontSize)
        let lines = text.components(separatedBy: .newlines)

        var maxWidth: CGFloat = 200  // 最小宽度
        var totalHeight: CGFloat = 0

        for line in lines {
            let attrs = [NSAttributedString.Key.font: font]
            let size = (line as NSString).size(withAttributes: attrs)
            maxWidth = max(maxWidth, size.width + 20)  // 加padding
            totalHeight += fontSize * 1.3  // 行高
        }

        return CGSize(
            width: min(maxWidth, 600),  // 最大宽度限制
            height: max(totalHeight, 40)  // 最小高度
        )
    }
}
