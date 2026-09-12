import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// ⌘V 归属通知：KeyboardShortcutManager 在反馈表单可见且焦点不在文本框时发出，
/// 表单收到后把剪贴板图片加为附件（绕开主菜单 keyEquivalent 吞键问题）
extension Notification.Name {
    static let feedbackPasteShortcut = Notification.Name("qn.feedbackPasteShortcut")
}

// MARK: - 表单模型（供视图与 footer 主按钮共享）

/// 反馈表单状态。由 SettingsOverlayView 以 @StateObject 持有并传入本 Tab，
/// footer 的「发送反馈」主按钮直接驱动提交（按钮位置/状态规范见 AGENTS.md）。
final class FeedbackFormModel: ObservableObject {
    @Published var kind: FeedbackKind = .bug
    @Published var text = ""
    @Published var contact = ""
    @Published var attachments: [FeedbackAttachment] = []
    @Published var sending = false
    @Published var successID: Int?
    @Published var failureMessage: String?
    @Published var attachmentNotice: String?
    /// 是否附带运行诊断日志（打点统计，与用户资料无关）；勾选状态持久化
    @Published var includeDiagnostics: Bool {
        didSet { UserDefaults.standard.set(includeDiagnostics, forKey: "feedbackIncludeDiagnostics") }
    }

    init() {
        self.includeDiagnostics = UserDefaults.standard.object(forKey: "feedbackIncludeDiagnostics") as? Bool ?? true
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// footer 主按钮可用条件：有正文且不在发送中（截图附件可选）
    var canSubmit: Bool {
        !trimmedText.isEmpty && !sending
    }

    func sendFeedback(entry: String) {
        let currentText = trimmedText
        guard !currentText.isEmpty, !sending else { return }
        sending = true
        successID = nil
        failureMessage = nil
        let currentKind = kind
        let currentContact = contact
        let currentAttachments = attachments
        let currentLogs = includeDiagnostics ? DiagnosticCenter.shared.recentLogs() : ""

        Task { @MainActor in
            do {
                let id = try await FeedbackService.shared.submit(
                    kind: currentKind,
                    text: currentText,
                    contact: currentContact,
                    attachments: currentAttachments,
                    entry: entry,
                    logs: currentLogs
                )
                DiagnosticCenter.info("Feedback", "反馈 #\(id) 已提交（\(currentKind.rawValue)，附件 \(currentAttachments.count) 张，来源 \(entry)\(currentLogs.isEmpty ? "" : "，含日志 \(currentLogs.utf8.count)B）")")
                successID = id
                text = ""
                contact = ""
                attachments = []
            } catch {
                let message = (error as? FeedbackError)?.message ?? "网络不可用或服务异常，请稍后重试"
                DiagnosticCenter.error("Feedback", "提交失败：\(message)")
                failureMessage = message
            }
            sending = false
        }
    }

    func openMailFallback() {
        let url = FeedbackService.mailtoURL(kind: kind, text: trimmedText, contact: contact)
        NSWorkspace.shared.open(url)
        DiagnosticCenter.info("Feedback", "已降级为邮件发送")
    }

    // MARK: 附件操作

    /// 把图片编码为附件（PNG 优先；超 5MB 降级 JPEG，仍超限则等比缩到 2200px 再编 JPEG）。
    /// 截图反馈的整屏 Retina 截图可能超限，粘贴的普通截图走 PNG 直通。
    static func makeAttachment(from image: NSImage, name: String) -> FeedbackAttachment? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        var data = rep.representation(using: .png, properties: [:])
        var mime = "image/png"
        if data == nil || data!.count > FeedbackService.maxAttachmentBytes {
            data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
            mime = "image/jpeg"
        }
        if let d = data, d.count > FeedbackService.maxAttachmentBytes {
            let maxSide: CGFloat = 2200
            let scale = min(1, maxSide / max(image.size.width, image.size.height, 1))
            let newSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let scaled = NSImage(size: newSize)
            scaled.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: newSize))
            scaled.unlockFocus()
            if let t2 = scaled.tiffRepresentation, let r2 = NSBitmapImageRep(data: t2),
               let j2 = r2.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                data = j2
                mime = "image/jpeg"
            }
        }
        guard let finalData = data, finalData.count <= FeedbackService.maxAttachmentBytes else { return nil }
        return FeedbackAttachment(name: name, mime: mime, data: finalData, preview: image)
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }

    func pasteFromClipboard() {
        DiagnosticCenter.info("Feedback", "粘贴截图触发（当前附件 \(attachments.count) 张，剪贴板类型 \(NSPasteboard.general.types?.map(\.rawValue) ?? [])）")
        guard attachments.count < FeedbackService.maxAttachments else {
            DiagnosticCenter.warning("Feedback", "粘贴被拦：附件已达上限")
            showNotice("最多 \(FeedbackService.maxAttachments) 张附件")
            return
        }
        guard let image = NSImage(pasteboard: .general) else {
            DiagnosticCenter.warning("Feedback", "粘贴被拦：NSImage(pasteboard:) 返回 nil")
            showNotice("剪贴板里没有图片（先复制一张截图再粘贴）")
            return
        }
        guard let attachment = Self.makeAttachment(from: image, name: "截图_\(Self.timestamp()).png") else {
            DiagnosticCenter.warning("Feedback", "粘贴被拦：图片编码失败或压缩后仍超过 5MB（image size \(image.size)）")
            showNotice("图片编码失败或超过 5MB")
            return
        }
        DiagnosticCenter.info("Feedback", "剪贴板图片读取成功 \(attachment.data.count) bytes，正在添加附件")
        addAttachment(attachment)
    }

    /// 直接添加已编码的附件（去重 + 限量拦截），自动附带/粘贴共用
    func addAttachment(_ attachment: FeedbackAttachment) {
        guard attachments.count < FeedbackService.maxAttachments else {
            DiagnosticCenter.warning("Feedback", "附件添加被拦：已达上限")
            showNotice("最多 \(FeedbackService.maxAttachments) 张附件")
            return
        }
        guard !attachments.contains(where: { $0.data == attachment.data }) else {
            DiagnosticCenter.warning("Feedback", "附件添加被拦：重复图片")
            showNotice("这张截图已经添加过了")
            return
        }
        attachments.append(attachment)
        DiagnosticCenter.info("Feedback", "附件已添加：\(attachment.name)（\(attachment.data.count) bytes），当前 \(attachments.count) 张")
    }

    private func showNotice(_ message: String) {
        attachmentNotice = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.attachmentNotice == message { self?.attachmentNotice = nil }
        }
    }
}

// MARK: - Tab 视图

/// 设置 → 反馈：类型 + 描述 + 截图附件（⌘V / 拖拽）+ 联系方式。
/// 主操作「发送反馈」在 footer（SettingsOverlayView footerView），不在内容区；
/// 断网降级邮件按钮在失败提示块内。
struct FeedbackSettingsTab: View {
    @ObservedObject var model: FeedbackFormModel
    @State private var dropTargeted = false

    /// 反馈表单是否可见（供 KeyboardShortcutManager 判断 ⌘V 归属：
    /// 可见时放行给表单粘贴截图附件，不再触发"全局粘贴"收走剪贴板）
    static var isFeedbackFormVisible = false

    private let env = FeedbackEnvironment.collect()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            contentSection
            attachmentSection
            envSection
            resultSection
        }
        .onAppear { FeedbackSettingsTab.isFeedbackFormVisible = true }
        .onDisappear { FeedbackSettingsTab.isFeedbackFormVisible = false }
        .onReceive(NotificationCenter.default.publisher(for: .feedbackPasteShortcut)) { _ in
            model.pasteFromClipboard()
        }
        .onDrop(of: [UTType.image], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - 反馈内容

    private var contentSection: some View {
        section(title: "反馈内容", icon: .bug) {
            VStack(alignment: .leading, spacing: 12) {
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

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $model.text)
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                        .scrollContentBackground(.hidden)
                        .background(Color.themeInput)
                        .cornerRadius(8)
                        .frame(minHeight: 96)
                    if model.text.isEmpty {
                        Text("遇到了什么问题？或有什么想法？（⌘V 可粘贴截图）")
                            .font(.themeBody)
                            .foregroundColor(.themeTextTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }

                HStack {
                    Text("提交后开发者会立即收到推送通知")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextTertiary)
                    Spacer()
                    Text("\(model.text.count)/\(FeedbackService.maxTextLength)")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextTertiary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("联系方式（选填）")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextSecondary)
                    TextField("邮箱 / 微信号，便于我们回复你", text: $model.contact)
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.themeInput)
                        .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - 截图附件

    private var attachmentSection: some View {
        section(title: "截图附件（可选）", icon: .camera) {
            VStack(alignment: .leading, spacing: 10) {
                if model.attachments.isEmpty {
                    HStack(spacing: 12) {
                        LucideView(name: .camera, size: 20, color: dropTargeted ? .themeBlue400 : .themeTextTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("把截图拖到这里，或直接 ⌘V 粘贴")
                                .font(.themeBody)
                                .foregroundColor(.themeTextSecondary)
                            Text("最多 \(FeedbackService.maxAttachments) 张，单张 ≤ 5MB；含敏感信息请先打码再添加")
                                .font(.themeCaption)
                                .foregroundColor(.themeTextTertiary)
                        }
                        Spacer()
                        Button("⌘V 粘贴截图") { model.pasteFromClipboard() }
                            .buttonStyle(.bordered)
                    }
                    .padding(16)
                    .background(dropTargeted ? Color.themeBlue600.opacity(0.12) : Color.themeInput)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                dropTargeted ? Color.themeBlue500 : Color.themeBorder,
                                style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                            )
                    )
                } else {
                    ForEach(model.attachments) { att in
                        HStack(spacing: 10) {
                            if let preview = att.preview {
                                Image(nsImage: preview)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 56, height: 38)
                                    .cornerRadius(6)
                                    .clipped()
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(att.name)
                                    .font(.themeCaption)
                                    .foregroundColor(.themeTextPrimary)
                                    .lineLimit(1)
                                Text(att.sizeDescription)
                                    .font(.themeCaption)
                                    .foregroundColor(.themeTextTertiary)
                            }
                            Spacer()
                            Button {
                                model.attachments.removeAll { $0.id == att.id }
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
                        }
                        .padding(8)
                        .background(Color.themeInput)
                        .cornerRadius(8)
                    }
                    if model.attachments.count < FeedbackService.maxAttachments {
                        Button {
                            model.pasteFromClipboard()
                        } label: {
                            Label("继续添加（⌘V）", systemImage: "plus")
                                .font(.themeCaption)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let notice = model.attachmentNotice {
                    Text(notice)
                        .font(.themeCaption)
                        .foregroundColor(.themeYellow400)
                }
            }
        }
    }

    // MARK: - 自动附带

    private var envSection: some View {
        section(title: "自动附带", icon: .cpu) {
            VStack(alignment: .leading, spacing: 8) {
                envRow("App 版本", "\(env.appVersion) · \(env.channelLabel)")
                envRow("系统", env.osVersion)
                envRow("语言", env.locale)
                ToggleRow(
                    title: "附带运行日志",
                    subtitle: "仅打点统计（功能节点/截图尺寸/文本长度/哈希），不含任何消息与剪贴板内容",
                    isOn: $model.includeDiagnostics
                )
                Text("仅用于排查问题，不含任何剪贴板与记录内容")
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
            }
        }
    }

    private func envRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.themeCaption)
                .foregroundColor(.themeTextSecondary)
            Spacer()
            Text(value)
                .font(.themeCaption)
                .foregroundColor(.themeTextPrimary)
        }
    }

    // MARK: - 提交结果（主按钮在 footer；失败时这里给重试/邮件降级）

    @ViewBuilder
    private var resultSection: some View {
        if let successID = model.successID {
            HStack(spacing: 8) {
                Text("✅")
                Text("已收到，感谢反馈！（编号 #\(successID)）")
                    .font(.themeBody)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.themeGreen600.opacity(0.15))
            .cornerRadius(8)
            .foregroundColor(.themeGreen400)
        }

        if let failureMessage = model.failureMessage {
            VStack(alignment: .leading, spacing: 10) {
                Text("⚠️ \(failureMessage)")
                    .font(.themeCaption)
                    .foregroundColor(.themeRed300)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("重试") { model.sendFeedback(entry: "prefs") }
                        .buttonStyle(.bordered)
                    Button("改用邮件发送") { model.openMailFallback() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            .background(Color.themeRed600.opacity(0.12))
            .cornerRadius(8)
        }
    }

    // MARK: - 拖拽

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                DispatchQueue.main.async {
                    let isJPEG = data.starts(with: [0xFF, 0xD8, 0xFF])
                    let mime = isJPEG ? "image/jpeg" : "image/png"
                    let ext = isJPEG ? "jpg" : "png"
                    guard let image = NSImage(data: data),
                          let att = FeedbackFormModel.makeAttachment(from: image, name: "拖入图片_\(FeedbackFormModel.timestamp()).\(ext)") else { return }
                    self.model.addAttachment(att)
                }
            }
            accepted = true
        }
        return accepted
    }

    // MARK: - 容器

    private func section<Content: View>(title: String, icon: IconName, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                LucideView(name: icon, size: 16, color: .themeBlue400)
                Text(title)
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
            }
            content()
        }
        .padding(16)
        .background(Color.themeCard)
        .cornerRadius(12)
    }
}
