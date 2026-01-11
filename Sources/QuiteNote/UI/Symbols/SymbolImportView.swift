import SwiftUI
import UniformTypeIdentifiers

/// 符号配置导入界面
struct SymbolImportView: View {
    @Binding var isPresented: Bool
    @StateObject private var configManager = SymbolConfigManager.shared

    @State private var selectedSource: ImportSource = .file
    @State private var yamlText: String = ""
    @State private var validationResult: ValidationResult?
    @State private var isProcessing = false

    enum ImportSource {
        case file
        case clipboard
        case url
    }

    struct ValidationResult {
        let isValid: Bool
        let config: SymbolConfig?
        let errors: [String]
        let warnings: [String]

        var stats: String? {
            guard let config = config else { return nil }
            let stats = config.stats
            return "✓ 包含 \(stats.menuCount) 个分类，共 \(stats.symbolCount) 个符号"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            headerView

            Divider()
                .background(Color.themeBorder)

            // 内容
            ScrollView {
                VStack(spacing: 24) {
                    // 选择来源
                    sourceSection

                    // YAML 内容
                    yamlContentSection

                    // 验证结果
                    if let result = validationResult {
                        validationResultSection(result)
                    }
                }
                .padding(24)
            }

            Divider()
                .background(Color.themeBorder)

            // 底部操作
            footerView
        }
        .background(Color.themeBackground)
        .frame(width: 500, height: 450)
        .onAppear {
            loadFromClipboard()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("导入符号配置")
                .font(.themeH3)
                .foregroundColor(Color.themeTextPrimary)

            Spacer()
        }
        .padding(24)
        .padding(.bottom, 16)
    }

    // MARK: - Source Section

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择来源")
                .font(.themeBody)
                .foregroundColor(Color.themeTextPrimary)

            HStack(spacing: 8) {
                sourceOption(title: "从文件导入", shortcut: "⌘F", source: .file)
                sourceOption(title: "从剪贴板导入", shortcut: "⌘V", source: .clipboard)
                sourceOption(title: "从 URL 导入", shortcut: "⌘U", source: .url)
            }
        }
    }

    private func sourceOption(title: String, shortcut: String, source: ImportSource) -> some View {
        Button(action: { selectedSource = source }) {
            VStack(spacing: 6) {
                HStack {
                    Text(title)
                        .font(.themeCaption)
                        .foregroundColor(selectedSource == source ? Color.themeBlue500 : Color.themeTextSecondary)
                    Spacer()
                    Text(shortcut)
                        .font(.themeCaptionSmall)
                        .foregroundColor(Color.themeTextTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedSource == source ? Color.themeBlue500.opacity(0.1) : Color.themeHoverLight)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selectedSource == source ? Color.themeBlue500 : Color.themeBorder, lineWidth: 1)
                )
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - YAML Content Section

    private var yamlContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YAML 内容")
                    .font(.themeBody)
                    .foregroundColor(Color.themeTextPrimary)

                Spacer()

                switch selectedSource {
                case .file:
                    Button(action: { importFromFile() }) {
                        Label("选择文件", systemImage: "doc")
                            .font(.themeCaption)
                            .foregroundColor(Color.themeTextSecondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                case .clipboard:
                    Button(action: { loadFromClipboard() }) {
                        Label("重新加载", systemImage: "arrow.counterclockwise")
                            .font(.themeCaption)
                            .foregroundColor(Color.themeTextSecondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                case .url:
                    EmptyView()
                }
            }

            TextEditor(text: $yamlText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color.themeTextSecondary)
                .padding(12)
                .background(Color.themeGray800)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
                .frame(minHeight: 150)

            // 快捷键提示
            if selectedSource == .url {
                HStack {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(Color.themeTextTertiary)
                    Text("输入 YAML 文件的 URL 地址")
                        .font(.themeCaptionSmall)
                        .foregroundColor(Color.themeTextTertiary)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Validation Result Section

    private func validationResultSection(_ result: ValidationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("验证结果")
                .font(.themeBody)
                .foregroundColor(Color.themeTextPrimary)

            VStack(alignment: .leading, spacing: 8) {
                if result.isValid {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color.themeGreen500)
                        Text("YAML 格式正确")
                            .font(.themeCaption)
                            .foregroundColor(Color.themeTextSecondary)
                    }

                    if let stats = result.stats {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundColor(Color.themeBlue500)
                            Text(stats)
                                .font(.themeCaption)
                                .foregroundColor(Color.themeTextSecondary)
                        }
                    }

                    if !result.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(result.warnings, id: \.self) { warning in
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color.themeYellow500)
                                    Text(warning)
                                        .font(.themeCaptionSmall)
                                        .foregroundColor(Color.themeTextTertiary)
                                }
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.errors, id: \.self) { error in
                            HStack(spacing: 8) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color.themeRed500)
                                Text(error)
                                    .font(.themeCaption)
                                    .foregroundColor(Color.themeRed500)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(result.isValid ? Color.themeGreen500.opacity(0.1) : Color.themeRed500.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(result.isValid ? Color.themeGreen500 : Color.themeRed500, lineWidth: 1)
            )
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button(action: { isPresented = false }) {
                Text("取消")
                    .font(.themeBody)
                    .foregroundColor(Color.themeTextSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.themeHoverLight)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            Button(action: { validateYaml() }) {
                Text("验证")
                    .font(.themeBody)
                    .foregroundColor(Color.themeTextSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.themeHoverLight)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(yamlText.isEmpty || isProcessing)

            Button(action: { importConfig() }) {
                Text("验证并导入")
                    .font(.themeBody)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.themeBlue600)
                    .cornerRadius(8)
                    .shadow(color: Color.themeShadowBlue, radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(validationResult?.isValid != true || isProcessing)
        }
        .padding(20)
    }

    // MARK: - Actions

    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.yaml, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                yamlText = content
            } catch {
                print("[SymbolImportView] 读取文件失败: \(error)")
            }
        }
    }

    private func loadFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let content = pasteboard.string(forType: .string) {
            yamlText = content
        }
    }

    private func validateYaml() {
        isProcessing = true
        defer { isProcessing = false }

        do {
            let config = try SymbolConfig.from(yaml: yamlText)

            // 检查冲突
            let conflicts = config.hasConflicts()
            var warnings: [String] = []

            if !conflicts.isEmpty {
                warnings.append("检测到 \(conflicts.count) 个触发词冲突")
            }

            // 检查同名配置
            let existingNames = configManager.configs.map { $0.metadata.name }
            if existingNames.contains(config.metadata.name) {
                warnings.append("配置名称 \(config.metadata.name) 已存在")
            }

            validationResult = ValidationResult(
                isValid: true,
                config: config,
                errors: [],
                warnings: warnings
            )
        } catch {
            validationResult = ValidationResult(
                isValid: false,
                config: nil,
                errors: [error.localizedDescription],
                warnings: []
            )
        }
    }

    private func importConfig() {
        guard let result = validationResult, result.isValid, let _ = result.config else {
            return
        }

        do {
            let _ = try configManager.importConfig(fromYAML: yamlText)

            // 检查是否有警告
            if !result.warnings.isEmpty {
                // 可以显示警告对话框
            }

            isPresented = false
        } catch {
            validationResult = ValidationResult(
                isValid: false,
                config: nil,
                errors: [error.localizedDescription],
                warnings: []
            )
        }
    }
}

// MARK: - Preview

#Preview {
    SymbolImportView(isPresented: .constant(true))
}

// MARK: - UTType Extension

extension UTType {
    static let yaml = UTType(filenameExtension: "yaml") ?? UTType.data
}
