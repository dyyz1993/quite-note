import SwiftUI
import AppKit

extension View {
    /// 监听 macOS 滚轮事件
    /// - Parameter action: 滚轮事件回调
    /// - Returns: 包装后的视图
    func onScrollWheel(action: @escaping (NSEvent) -> Void) -> some View {
        self.overlay(
            ScrollWheelReader(action: action)
                .allowsHitTesting(false) // 不拦截点击，只监听事件
        )
    }
}

/// 辅助视图：用于捕捉滚轮事件
private struct ScrollWheelReader: NSViewRepresentable {
    let action: (NSEvent) -> Void

    func makeNSView(context: Context) -> ScrollWheelView {
        let view = ScrollWheelView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: ScrollWheelView, context: Context) {
        nsView.action = action
    }
}

/// 实际的 NSView 子类，重写 scrollWheel
private class ScrollWheelView: NSView {
    var action: ((NSEvent) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        action?(event)
        // 继续传递事件，除非你想完全拦截
        super.scrollWheel(with: event)
    }
    
    // 必须能够接收事件
    override var acceptsFirstResponder: Bool { true }
}
