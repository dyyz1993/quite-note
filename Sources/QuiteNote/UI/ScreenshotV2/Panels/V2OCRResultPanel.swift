import SwiftUI
import AppKit

/// OCR AI 整理模式（系统提示词内置，用户无需配置）
enum OCRPolishMode: String, CaseIterable {
    case tidy = "整理排版"
    case keyPoints = "提炼要点"
    case markdown = "转 Markdown"
    case translate = "翻译成中文"

    var systemPrompt: String {
        switch self {
        case .tidy:
            return """
            你是 OCR 文本整理助手。输入是从截图中识别出的原始文字，可能存在识别错误、断行混乱、标点不规范等问题。请：
            1. 修正明显的识别错别字（结合上下文判断，不确定的保持原样）
            2. 恢复正确的段落结构（OCR 的换行是视觉断行，不代表逻辑分段）
            3. 规范标点（中文语境用全角、英文语境用半角）
            4. 删除明显的版面噪音（页码、水印、界面按钮文字）
            5. 严格保真：不增删实质内容，不总结，不改写语气
            只输出整理后的文本，不要任何解释和前后缀。
            """
        case .keyPoints:
            return """
            你是 OCR 文本整理助手。请先修正输入文字中的识别错误并理顺语句，然后提炼为要点列表：
            - 每个要点一行，以 "• " 开头，信息完整、表述明确
            - 保留关键数字、日期、专有名词，不遗漏实质信息
            - 按原文逻辑顺序排列，不添加原文没有的推断
            只输出要点列表本身。
            """
        case .markdown:
            return """
            你是 OCR 文本结构化助手。请把输入的识别文字整理为 Markdown：
            1. 先修正识别错误、恢复段落
            2. 识别出的标题用 #/##，并列内容用列表，数据对比用表格，代码用代码块
            3. 删除页码、水印等版面噪音
            4. 不增删实质内容
            只输出 Markdown 本身，不要外层代码块包裹。
            """
        case .translate:
            return """
            你是 OCR 文本翻译助手。请先把输入文字当作 OCR 原文做纠错整理（保留原语言），再翻译成简体中文：
            1. 修正识别错误和断行
            2. 翻译自然流畅、术语准确；专有名词保留原文并在括号内注明
            3. 只输出整理后的中文文本，不要任何解释
            如果输入已是中文，则只做纠错整理。
            """
        }
    }
}

/// 支持 ESC 直接关闭、Enter 默认复制的识别窗口面板
final class V2OCRESCClosablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// ESC 直接关闭窗口（识别结果可编辑场景下，用户直觉是"看完了就关"）
    override func cancelOperation(_ sender: Any?) {
        V2OCRResultPanelController.shared.close()
    }

    /// Enter/小键盘 Enter 默认触发"复制全部"。
    /// 注意：文本框正在编辑时 Enter 被输入框消化为换行，不会走到这里——
    /// 即"看结果状态回车=复制，编辑状态回车=换行"，符合直觉
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            V2OCRResultPanelController.shared.copyAction?()
            return
        }
        super.keyDown(with: event)
    }
}

/// OCR 专属结果窗口：左边框选图片、右边识别结果
///
/// 交互定位：用户点 OCR 意味着目的是取文字而非截图——触发即退出截图会话，
/// 直接进入这个独立工作台（图片预览 + 可编辑结果 + 底部操作栏）
@MainActor
final class V2OCRResultPanelController {
    static let shared = V2OCRResultPanelController()
    private var panel: NSPanel?

    /// Enter 键触发的复制动作（由当前展示的视图注册，窗口关闭时清除）
    var copyAction: (() -> Void)?

    func show(image: NSImage) {
        if panel == nil {
            let p = V2OCRESCClosablePanel(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 480),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            p.title = "文字识别"
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

        let view = V2OCRResultView(image: image) {
            V2OCRResultPanelController.shared.close()
        }
        panel?.contentView = NSHostingView(rootView: view)
        panel?.center()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        DiagnosticCenter.info("OCR", "识别窗口已打开")
    }

    func close() {
        panel?.orderOut(nil)
    }
}

/// OCR 结果视图：左图右文 + 加载/空态 + 底部操作栏
struct V2OCRResultView: View {
    let image: NSImage
    var onClose: () -> Void

    @State private var recognizedText: String = ""
    @State private var isRecognizing = true
    @State private var failed = false
    @State private var copied = false
    @State private var savedFeedback: String?

    // AI 整理状态
    @State private var aiProcessing = false
    @State private var aiError: String?
    @State private var originalText: String = ""   // AI 整理前的识别原文（恢复用）
    @State private var canRestore = false

    var body: some View {
        VStack(spacing: 0) {
            // 主体：左（截图预览） | 右（识别结果）
            HStack(spacing: 0) {
                // 左侧：框选图片预览
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
                    .background(Color.themeInput)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.themeBorderSubtle)
                            .padding(6)
                    )

                Divider().background(Color.themeBorderSubtle)

                // 右侧：识别结果（加载态 / 空态 / 结果态）
                ZStack {
                    if isRecognizing {
                        VStack(spacing: 14) {
                            ProgressView()
                                .controlSize(.large)
                            Text("正在识别…")
                                .font(.themeBody)
                                .foregroundColor(.themeTextSecondary)
                            Text("本地 Vision 引擎，无需联网")
                                .font(.themeCaption)
                                .foregroundColor(.themeTextTertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if failed || recognizedText.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "text.magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundColor(.themeTextTertiary)
                            Text("未识别到文字")
                                .font(.themeBody)
                                .foregroundColor(.themeTextSecondary)
                            Button(action: recognize) {
                                Label("重新识别", systemImage: "arrow.clockwise")
                                    .font(.themeCaption)
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 0) {
                            TextEditor(text: $recognizedText)
                                .font(.system(size: 13))
                                .foregroundColor(.themeTextPrimary)
                                .scrollContentBackground(.hidden)
                                .padding(10)
                            HStack {
                                Spacer()
                                Text("\(recognizedText.count) 字符")
                                    .font(.themeCaption)
                                    .foregroundColor(.themeTextTertiary)
                                    .padding(.trailing, 12)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider().background(Color.themeBorderSubtle)

            // 底部操作栏
            HStack(spacing: 10) {
                if let savedFeedback {
                    Text(savedFeedback)
                        .font(.themeCaption)
                        .foregroundColor(.themeStatusSuccess)
                        .lineLimit(1)
                }
                if let aiError {
                    Text(aiError)
                        .font(.themeCaption)
                        .foregroundColor(.themeStatusError)
                        .lineLimit(1)
                }

                Spacer()

                if aiProcessing {
                    ProgressView()
                        .controlSize(.small)
                }

                if canRestore {
                    Button(action: restoreOriginal) {
                        Label("恢复原文", systemImage: "arrow.uturn.backward")
                            .font(.themeCaption)
                    }
                    .buttonStyle(.bordered)
                    .help("撤销 AI 整理，恢复识别原文")
                }

                // AI 整理：四模式（提示词内置）
                Menu {
                    ForEach(OCRPolishMode.allCases, id: \.self) { mode in
                        Button(mode.rawValue) { aiPolish(mode) }
                    }
                } label: {
                    Label(aiProcessing ? "AI 处理中…" : "AI 整理", systemImage: "wand.and.stars")
                        .font(.themeBody)
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .fixedSize()
                .disabled(isRecognizing || recognizedText.isEmpty || aiProcessing)
                .help("用大模型整理识别文本（需在 设置 → AI 配置密钥）")

                Button(action: copyAll) {
                    Text(copied ? "已复制 ✅" : "复制全部 ⏎")
                        .font(.themeBody)
                        .frame(minWidth: 84)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRecognizing || recognizedText.isEmpty)

                Button(action: saveImage) {
                    Label("保存图片", systemImage: "arrow.down.doc")
                        .font(.themeBody)
                }
                .buttonStyle(.bordered)

                Button(action: recognize) {
                    Label("重新识别", systemImage: "arrow.clockwise")
                        .font(.themeBody)
                }
                .buttonStyle(.bordered)
                .disabled(isRecognizing)

                Button(action: onClose) {
                    Text("关闭")
                        .font(.themeBody)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 780, height: 480)
        .background(Color.themePanel)
        .onAppear {
            // 注册 Enter 复制动作（编辑文本时 Enter 是换行，不会触发这里）
            V2OCRResultPanelController.shared.copyAction = { copyAll() }
            DiagnosticCenter.info("OCR", "开始识别，图片 \(Int(image.size.width))x\(Int(image.size.height))")
            recognize()
        }
        .onDisappear {
            V2OCRResultPanelController.shared.copyAction = nil
        }
    }

    private func recognize() {
        isRecognizing = true
        failed = false
        recognizedText = ""
        copied = false
        savedFeedback = nil

        V2OCRService.shared.recognizeText(in: image) { text in
            isRecognizing = false
            if let text, !text.isEmpty {
                recognizedText = text
                DiagnosticCenter.info("OCR", "识别完成，\(text.count) 字符")
            } else {
                failed = true
                DiagnosticCenter.warning("OCR", "未识别到文字")
            }
        }
    }

    private func copyAll() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(recognizedText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    // MARK: - AI 整理

    private func aiPolish(_ mode: OCRPolishMode) {
        let text = recognizedText
        guard !text.isEmpty else { return }

        let service = AIService()
        guard service.hasAPIKey() else {
            aiError = "未配置 AI 密钥：设置 → AI 中填写后即可使用"
            return
        }

        aiProcessing = true
        aiError = nil
        DiagnosticCenter.info("OCR", "AI 整理（\(mode.rawValue)）开始，\(text.count) 字符")

        service.rewrite(
            system: mode.systemPrompt,
            user: "【原文开始】\n\(text)\n【原文结束】"
        ) { result in
            aiProcessing = false
            switch result {
            case .success(let polished):
                if originalText.isEmpty { originalText = text }  // 只记录第一次，保留最原始识别结果
                recognizedText = polished
                canRestore = true
                DiagnosticCenter.info("OCR", "AI 整理完成，结果 \(polished.count) 字符")
            case .failure(let error):
                aiError = error.localizedDescription
                DiagnosticCenter.error("OCR", "AI 整理失败: \(error.localizedDescription)")
            }
        }
    }

    private func restoreOriginal() {
        guard !originalText.isEmpty else { return }
        recognizedText = originalText
        originalText = ""
        canRestore = false
        DiagnosticCenter.info("OCR", "已恢复识别原文")
    }

    private func saveImage() {
        if let path = ScreenshotService.shared.exportImageFile(image) {
            if PreferencesManager.shared.screenshotCopyPathAfterSave {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(path, forType: .string)
            }
            savedFeedback = "已保存 ✅ \( ((path as NSString).lastPathComponent) )"
            DiagnosticCenter.info("OCR", "图片已保存: \(path)")
        } else {
            savedFeedback = "保存失败"
        }
    }
}
