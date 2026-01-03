import AppKit

/// 支持文本输入的 NSPanel 子类
/// 关键：覆盖 canBecomeKey 和 canBecomeMain，使 .borderless 样式下仍能接收键盘输入
class V2TextInputPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
