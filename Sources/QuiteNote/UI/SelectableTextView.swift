import SwiftUI
import AppKit

/// 一个基于 NSTextView 的 SwiftUI 包装器，支持高效渲染长文本并允许选择和复制
struct SelectableTextView: NSViewRepresentable {
    let text: String
    var fontSize: CGFloat = 12
    var isMonospaced: Bool = true
    var textColor: NSColor = .textColor
    var inset: CGSize = CGSize(width: 12, height: 12)
    var showScrollbar: Bool = true
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = showScrollbar
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: inset.width, height: inset.height)
        
        // 优化性能
        textView.usesFontPanel = false
        textView.isRichText = false
        
        // 设置字体 - 优先使用更适合 ASCII 艺术的 Menlo 字体
        if isMonospaced {
            if let menloFont = NSFont(name: "Menlo", size: fontSize) {
                textView.font = menloFont
                // 确保字符间距为 0，防止一些双线字符因为微小的间距导致对齐失败
                textView.defaultParagraphStyle = .default
            } else {
                textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            }
        } else {
            textView.font = NSFont.systemFont(ofSize: fontSize)
        }
        
        textView.textColor = textColor
        textView.string = text // 初始赋值
        
        scrollView.documentView = textView
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        nsView.hasVerticalScroller = showScrollbar
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        if textView.string != text {
            textView.string = text
        }
        
        // 更新样式
        if isMonospaced {
            if let menloFont = NSFont(name: "Menlo", size: fontSize) {
                textView.font = menloFont
            } else {
                textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            }
        } else {
            textView.font = NSFont.systemFont(ofSize: fontSize)
        }
        textView.textColor = textColor
    }
}
