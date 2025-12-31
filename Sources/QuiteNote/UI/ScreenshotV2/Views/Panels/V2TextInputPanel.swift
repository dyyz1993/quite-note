import AppKit

/// ✨ 自定义文本输入面板 - 允许 .borderless 窗口成为 key window
/// 覆盖 canBecomeKey 让窗口能够接收键盘输入，同时保持 .borderless 样式（无偏移）
class V2TextInputPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
