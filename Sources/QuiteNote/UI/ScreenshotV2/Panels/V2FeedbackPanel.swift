import SwiftUI
import AppKit

// MARK: - ESC 关闭面板

final class V2FeedbackESCPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// ESC 直接关闭（截图现场随手反馈，看完/交完即走）
    override func cancelOperation(_ sender: Any?) {
        V2FeedbackPanelController.shared.close()
    }
}

// MARK: - 敏感信息引导（截图会话内）

/// 引导窗专属面板：ESC = 关闭引导窗（留在截图会话继续标注）
final class V2FeedbackGuidePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) {
        V2FeedbackPrivacyGuideController.shared.close()
    }
}

/// 引导小窗：点工具栏 🐞 时弹出，提醒用马赛克遮挡敏感信息；
/// 悬浮在截图遮罩之上（screenSaver+1），不退出会话——「返回打码」直接关窗继续标注。
@MainActor
final class V2FeedbackPrivacyGuideController {
    static let shared = V2FeedbackPrivacyGuideController()
    private var panel: NSPanel?

    func show(onContinue: @escaping () -> Void, onCancel: @escaping () -> Void, on screen: NSScreen? = nil) {
        if panel == nil {
            let p = V2FeedbackGuidePanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 230),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            p.title = "提交前小提醒"
            p.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1) // 盖住截图遮罩（遮罩=screenSaver）
            p.isFloatingPanel = true
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.appearance = NSAppearance(named: .darkAqua)
            p.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0)
            p.titlebarAppearsTransparent = true
            panel = p
        }
        panel?.contentView = NSHostingView(rootView: V2FeedbackPrivacyGuideView(
            onContinue: { [weak self] in
                self?.close()
                onContinue()
            },
            onCancel: { [weak self] in
                self?.close()
                onCancel()
            }
        ))
        if let p = panel {
            // 居中到截图所在屏（center() 在多屏下可能甩到别的屏）
            if let frame = screen?.visibleFrame {
                p.setFrameOrigin(NSPoint(
                    x: frame.midX - p.frame.width / 2,
                    y: frame.midY - p.frame.height / 2
                ))
            } else {
                p.center()
            }
            p.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel?.orderOut(nil)
    }
}

/// 引导内容：文案 + 不再提示勾选 + 双按钮（返回打码为视觉主选项）
struct V2FeedbackPrivacyGuideView: View {
    var onContinue: () -> Void
    var onCancel: () -> Void
    @State private var suppress = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("🔒")
                Text("截图将原样附加到反馈")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
            }
            Text("若截图包含敏感信息（密码、地址、聊天记录等），建议「返回打码」，用工具栏的马赛克工具遮挡后再提交。")
                .font(.themeBody)
                .foregroundColor(.themeTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("不再提示", isOn: $suppress)
                .font(.themeCaption)
                .foregroundColor(.themeTextTertiary)

            HStack(spacing: 10) {
                Button {
                    if suppress { UserDefaults.standard.set(true, forKey: "feedbackPrivacyGuideSuppressed") }
                    onCancel()
                } label: {
                    Text("🟪 返回打码")
                        .font(.themeBody)
                }
                .buttonStyle(.borderedProminent)
                .pointingHandCursor()

                Button {
                    if suppress { UserDefaults.standard.set(true, forKey: "feedbackPrivacyGuideSuppressed") }
                    onContinue()
                } label: {
                    Text("截图已脱敏，继续提交")
                        .font(.themeBody)
                }
                .buttonStyle(.bordered)
                .pointingHandCursor()
                Spacer()
            }
        }
        .padding(18)
        .frame(width: 380)
        .background(Color.themeBackground.opacity(0.97))
    }
}

// MARK: - 控制器

/// 截图会话专属反馈窗口：截图工具栏 🐞 触发，退出截图会话并把当前截图（含标注）自动带入。
/// 与 V2OCRResultPanel 同模式：独立悬浮窗口、深色主题、提交成功自动关闭。
@MainActor
final class V2FeedbackPanelController {
    static let shared = V2FeedbackPanelController()
    private var panel: NSPanel?

    /// - Parameter screen: 截图所在屏（传了就居中到该屏；nil 时退回 panel.center()）
    func show(image: NSImage, on screen: NSScreen? = nil) {
        if panel == nil {
            let p = V2FeedbackESCPanel(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            p.title = "用户反馈 · 截图"
            p.level = .floating
            p.isFloatingPanel = true
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            // UI 风格适配：与 App 深色主题一致（遵循 AGENTS.md UI 规范）
            p.appearance = NSAppearance(named: .darkAqua)
            p.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0)
            p.titlebarAppearsTransparent = true
            panel = p
        }

        let model = FeedbackFormModel()
        if let att = FeedbackFormModel.makeAttachment(from: image, name: "截图反馈_\(FeedbackFormModel.timestamp()).png") {
            model.attachments = [att]
        } else {
            DiagnosticCenter.warning("Feedback", "截图反馈：截图编码失败，反馈将以纯文本提交")
        }
        panel?.contentView = NSHostingView(rootView: V2FeedbackPanelView(model: model, onClose: { [weak self] in
            self?.close()
        }))
        // 居中到截图所在屏（panel.center() 可能甩到别的屏，多屏下遵循"反馈跟截图走"）
        if let panel = panel {
            if let frame = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(
                    x: frame.midX - panel.frame.width / 2,
                    y: frame.midY - panel.frame.height / 2
                ))
            } else {
                panel.center()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        DiagnosticCenter.info("Feedback", "截图反馈窗口已打开（截图 \(Int(image.size.width))x\(Int(image.size.height))）")
    }

    func close() {
        panel?.orderOut(nil)
    }
}

// MARK: - 视图

/// 截图反馈表单：顶部截图预览条 + 反馈表单（复用 FeedbackFormModel，entry=screenshot）
struct V2FeedbackPanelView: View {
    @ObservedObject var model: FeedbackFormModel
    var onClose: () -> Void

    private let env = FeedbackEnvironment.collect()

    var body: some View {
        VStack(spacing: 16) {
            previewBanner
            kindSelector
            textField
            contactField
            diagnosticsToggle
            resultBanner
            Spacer(minLength: 0)
            actionRow
        }
        .padding(20)
        .background(Color.themeBackground.opacity(0.95))
        .onChange(of: model.successID) { id in
            // 提交成功短暂展示后自动关闭（回到桌面）
            if id != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    V2FeedbackPanelController.shared.close()
                }
            }
        }
    }

    // MARK: 截图预览条

    @ViewBuilder
    private var previewBanner: some View {
        HStack(spacing: 12) {
            if let att = model.attachments.first, let preview = att.preview {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 96, height: 60)
                    .cornerRadius(8)
                    .clipped()
                VStack(alignment: .leading, spacing: 3) {
                    Text("📸 已自动附带本次截图（含标注）")
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                    Text("\(att.name) · \(att.sizeDescription)")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextTertiary)
                }
                Spacer()
                Button {
                    model.attachments.removeAll()
                } label: {
                    Text("✕")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextTertiary)
                        .frame(width: 24, height: 24)
                        .background(Color.themeHoverLight)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("不想带截图？点此移除")
            } else {
                Text("截图已移除，将以纯文字反馈")
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
                Spacer()
            }
        }
        .padding(12)
        .background(Color.themeCard)
        .cornerRadius(10)

        Text("🔒 提交前请确认截图不含敏感信息（密码 / 地址 / 验证码等）；如需打码，点 ✕ 移除后重新截图，用马赛克工具处理再反馈")
            .font(.themeCaption)
            .foregroundColor(.themeTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 表单

    private var kindSelector: some View {
        HStack(spacing: 8) {
            ForEach(FeedbackKind.allCases) { k in
                Button {
                    model.kind = k
                } label: {
                    Text(k.label)
                        .font(.themeCaption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(model.kind == k ? Color.themeBlue600 : Color.themeInput)
                .cornerRadius(8)
                .foregroundColor(model.kind == k ? .white : .themeTextSecondary)
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            Spacer()
        }
    }

    private var textField: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.text)
                .font(.themeBody)
                .foregroundColor(.themeTextPrimary)
                .scrollContentBackground(.hidden)
                .background(Color.themeInput)
                .cornerRadius(8)
                .frame(minHeight: 110)
            if model.text.isEmpty {
                Text("遇到了什么问题？（bug / 需求 / 想法都可以，⌘V 可再贴图）")
                    .font(.themeBody)
                    .foregroundColor(.themeTextTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
    }

    private var contactField: some View {
        TextField("联系方式（选填），便于我们回复你", text: $model.contact)
            .font(.themeBody)
            .foregroundColor(.themeTextPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.themeInput)
            .cornerRadius(8)
    }

    private var diagnosticsToggle: some View {
        ToggleRow(
            title: "附带运行日志",
            subtitle: "仅打点统计（功能节点/尺寸/长度/哈希），不含任何消息与剪贴板内容",
            isOn: $model.includeDiagnostics
        )
    }

    // MARK: 结果与操作

    @ViewBuilder
    private var resultBanner: some View {
        if let id = model.successID {
            HStack(spacing: 8) {
                Text("✅")
                Text("已收到，感谢反馈！（编号 #\(id)）")
                    .font(.themeBody)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.themeGreen600.opacity(0.15))
            .cornerRadius(8)
            .foregroundColor(.themeGreen400)
        }
        if let failureMessage = model.failureMessage {
            Text("⚠️ \(failureMessage)")
                .font(.themeCaption)
                .foregroundColor(.themeRed300)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.themeRed600.opacity(0.12))
                .cornerRadius(8)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button("取消") { onClose() }
                .buttonStyle(.bordered)

            Button {
                model.sendFeedback(entry: "screenshot")
            } label: {
                HStack(spacing: 6) {
                    if model.sending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        LucideView(name: .upload, size: 14, color: .white)
                    }
                    Text(model.sending ? "发送中…" : "发送反馈")
                }
                .frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canSubmit)
            .pointingHandCursor()

            Spacer()

            Text("\(env.appVersion) · \(env.osVersion)")
                .font(.themeCaption)
                .foregroundColor(.themeTextTertiary)
        }
    }
}
