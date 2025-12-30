import SwiftUI
import AppKit

/// NSViewRepresentable 用于创建和管理文本编辑面板
struct TextEditPanelRepresentable: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let color: Color
    let screen: NSScreen
    let position: CGPoint
    let onFinish: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.frame = .zero
        DispatchQueue.main.async {
            context.coordinator.createPanel(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // 面板已由 coordinator 管理
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, fontSize: fontSize, color: color, screen: screen, position: position, onFinish: onFinish)
    }

    class Coordinator: NSObject {
        @Binding var text: String
        let fontSize: CGFloat
        let color: Color
        let screen: NSScreen
        let position: CGPoint
        let onFinish: () -> Void
        var panel: NSPanel?

        init(text: Binding<String>, fontSize: CGFloat, color: Color, screen: NSScreen, position: CGPoint, onFinish: @escaping () -> Void) {
            self._text = text
            self.fontSize = fontSize
            self.color = color
            self.screen = screen
            self.position = position
            self.onFinish = onFinish
        }

        func createPanel(for ownerView: NSView) {
            guard let parentWindow = ownerView.window else {
                print("[TextEditPanelRepresentable] ERROR: No parent window")
                return
            }

            let panelWidth: CGFloat = 320
            let panelHeight: CGFloat = 50
            let screenFrame = screen.frame

            // 计算坐标
            let x = screenFrame.minX + position.x
            let y = screenFrame.maxY - position.y - panelHeight

            print("[TextEditPanelRepresentable] Creating panel at (\(x), \(y))")

            let panel = NSPanel(
                contentRect: NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            panel.level = .popUpMenu
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false

            // ✅ 关键：设置为父窗口的 child window
            parentWindow.addChildWindow(panel, ordered: .above)

            // 创建 TextField
            let textField = NSTextField(frame: NSRect(origin: .zero, size: NSSize(width: panelWidth, height: panelHeight)))
            textField.stringValue = text
            textField.font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            textField.textColor = NSColor(color)
            textField.isBordered = false
            textField.backgroundColor = .clear
            textField.focusRingType = .none

            // 创建容器视图来添加虚线边框
            let containerView = NSView(frame: NSRect(origin: .zero, size: NSSize(width: panelWidth, height: panelHeight)))
            containerView.addSubview(textField)

            // 添加虚线边框（使用 CAShapeLayer）
            containerView.wantsLayer = true
            let shapeLayer = CAShapeLayer()
            shapeLayer.frame = containerView.bounds
            shapeLayer.strokeColor = NSColor(color).cgColor
            shapeLayer.lineWidth = 1.5
            shapeLayer.lineDashPattern = [6, 4]  // 虚线模式
            shapeLayer.path = CGPath(roundedRect: containerView.bounds.insetBy(dx: 1, dy: 1), cornerWidth: 4, cornerHeight: 4, transform: nil)
            containerView.layer?.addSublayer(shapeLayer)

            panel.contentView = containerView

            // 绑定文本变化
            textField.delegate = self
            textField.target = self
            textField.action = #selector(textFieldDidChange(_:))

            self.panel = panel

            DispatchQueue.main.async {
                panel.orderFrontRegardless()
                parentWindow.makeKey()
                textField.becomeFirstResponder()
                print("[TextEditPanelRepresentable] Panel activated, textField focused: \(textField.currentEditor()?.selectedRange != nil)")
            }
        }

        @objc func textFieldDidChange(_ sender: NSTextField) {
            text = sender.stringValue
        }

        deinit {
            if let panel = panel {
                if let parent = panel.parent {
                    parent.removeChildWindow(panel)
                }
                panel.close()
            }
        }
    }
}

// MARK: - NSTextFieldDelegate
extension TextEditPanelRepresentable.Coordinator: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        text = textField.stringValue
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onFinish()
            return true
        }
        return false
    }
}
