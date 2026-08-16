import SwiftUI
import AppKit

/// OCR 结果面板控制器：在截图遮罩之上展示可编辑的识别文本
@MainActor
final class V2OCRResultPanelController {
    static let shared = V2OCRResultPanelController()
    private var panel: NSPanel?

    func show(text: String) {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            p.title = "文字识别结果"
            p.level = .screenSaver + 2  // 在截图遮罩之上
            p.isFloatingPanel = true
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            panel = p
        }

        let view = V2OCRResultView(text: text) {
            V2OCRResultPanelController.shared.close()
        }
        panel?.contentView = NSHostingView(rootView: view)
        panel?.center()
        panel?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        DiagnosticCenter.info("OCR", "结果面板已展示")
    }

    func close() {
        panel?.orderOut(nil)
    }
}

/// OCR 结果视图：可编辑文本 + 复制全部
struct V2OCRResultView: View {
    @State private var text: String
    @State private var copied = false
    var onClose: () -> Void

    init(text: String, onClose: @escaping () -> Void) {
        _text = State(initialValue: text)
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 16))
                    .foregroundColor(.themeBlue400)
                Text("文字识别结果")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
                Spacer()
                Text("\(text.count) 字符")
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
            }

            TextEditor(text: $text)
                .font(.system(size: 13))
                .foregroundColor(.themeTextPrimary)
                .scrollContentBackground(.hidden)
                .background(Color.themeInput)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeBorderSubtle))

            HStack(spacing: 12) {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Text(copied ? "已复制 ✅" : "复制全部")
                        .font(.themeBody)
                        .frame(minWidth: 90)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button {
                    onClose()
                } label: {
                    Text("关闭")
                        .font(.themeBody)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(width: 480, height: 380)
        .background(Color.themePanel)
    }
}
