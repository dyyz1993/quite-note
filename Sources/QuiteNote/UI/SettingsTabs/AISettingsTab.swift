import SwiftUI

/// AI 设置主路径：连接方式 -> 模型 -> 真实试生成。行为与提示词保留在下方折叠区。
struct AISettingsTab: View {
    @ObservedObject var store: RecordStore
    @ObservedObject private var prefs = PreferencesManager.shared
    @Binding var isTestingConnection: Bool

    @State private var catalogState = MagpieCatalogUIState.idle
    @State private var modelSearch = ""
    @State private var validationMessage: String?
    @State private var validationResult: SummaryResult?
    @State private var validationElapsed: TimeInterval?
    @State private var showBehavior = false
    @State private var showAdvanced = false
    private let catalogService = MagpieCatalogService()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            aiToggleSection
            connectionSection
            if prefs.aiConnectionKind == .magpie {
                magpieModelSection
            } else {
                customAPISection
            }
            validationSection
            DisclosureGroup(isExpanded: $showBehavior) {
                aiBehaviorSection
            } label: {
                sectionTitle(icon: .activity, title: "提炼行为")
            }
            DisclosureGroup(isExpanded: $showAdvanced) {
                promptConfigSection
                magpieAdvancedSection
            } label: {
                sectionTitle(icon: .slidersHorizontal, title: "高级设置")
            }
            privacyNote
        }
        .onAppear { loadCatalogIfNeeded() }
    }

    // MARK: - Main

    private var aiToggleSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    LucideView(name: .sparkles, size: 16, color: .themeYellow500)
                    Text("AI 自动提炼")
                        .font(.themeH2)
                        .foregroundColor(.themeTextPrimary)
                }
                Text(currentStatusLine)
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
            }
            Spacer()
            CustomToggle(isOn: Binding(
                get: { store.enableAI },
                set: { store.enableAI = $0; store.savePreferences() }
            ))
        }
        .padding(20)
        .background(Color.themeGray800.opacity(0.4) as Color)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorderSubtle))
        .accessibilityElement(children: .combine)
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(icon: .link, title: "连接方式")
            HStack(spacing: 10) {
                connectionCard(
                    kind: .magpie,
                    title: "Magpie",
                    subtitle: "自动连接本机网关"
                )
                connectionCard(
                    kind: .customOpenAI,
                    title: "自定义 API",
                    subtitle: "OpenAI 兼容接口"
                )
            }
        }
        .padding(20)
        .background(Color.themeGray800.opacity(0.4) as Color)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorderSubtle))
    }

    private func connectionCard(kind: AIConnectionKind, title: String, subtitle: String) -> some View {
        let selected = prefs.aiConnectionKind == kind
        return Button {
            guard prefs.aiConnectionKind != kind else { return }
            prefs.setAIConnectionKind(kind)
            validationResult = nil
            validationMessage = nil
            validationElapsed = nil
            if kind == .magpie { loadCatalogIfNeeded(force: true) }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.themeBody)
                    .fontWeight(.semibold)
                    .foregroundColor(selected ? .themeTextPrimary : .themeTextSecondary)
                Text(subtitle)
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(selected ? Color.themeBlue500.opacity(0.14) : Color.themeInput)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.themeBlue500 : Color.themeBorder))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var magpieModelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle(icon: .bot, title: "模型")
                Spacer()
                statusBadge
            }

            switch catalogState {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在连接 Magpie...")
                }
            case .failed(let message):
                Text(message)
                    .font(.themeCaption)
                    .foregroundColor(.themeRed400)
                HStack {
                    Button("重试") { loadCatalogIfNeeded(force: true) }
                        .buttonStyle(.plain)
                    Button("打开 Magpie") { NSWorkspace.shared.open(URL(string: "https://usemagpie.ai")!) }
                        .buttonStyle(.plain)
                }
            case .loaded(let models):
                if let selected = prefs.magpieModelID, !models.contains(where: { $0.id == selected }) {
                    Text("上次选择的模型已不可用，请重新选择。")
                        .font(.themeCaption)
                        .foregroundColor(.themeYellow500)
                } else {
                    HStack {
                        Button {
                            loadCatalogIfNeeded(force: true)
                        } label: {
                            HStack(spacing: 4) {
                                LucideView(name: .refreshCw, size: 12, color: .themeBlue400)
                                Text("刷新")
                            }
                            .font(.themeCaptionSmall)
                            .foregroundColor(.themeBlue400)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
                TextField("搜索模型名称或 ID", text: $modelSearch)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.themeInput)
                    .cornerRadius(7)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.themeBorder))

                let visibleModels = models.filter { $0.matches(modelSearch) }
                if visibleModels.isEmpty {
                    Text("没有匹配的模型")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextTertiary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(visibleModels, content: modelRow)
                        }
                    }
                    .frame(minHeight: 132, maxHeight: 190)
                }
            case .idle:
                Text("尚未连接")
            }
        }
        .padding(20)
        .background(Color.themeGray800.opacity(0.4) as Color)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorderSubtle))
    }

    private func modelRow(_ model: MagpieModel) -> some View {
        let selected = prefs.magpieModelID == model.id
        return Button {
            prefs.setMagpieModelID(model.id)
            validationResult = nil
            validationMessage = nil
            validationElapsed = nil
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                    Text(model.id)
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if model.supportsImageInput {
                    Text("视觉")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themePurple500)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.themePurple500.opacity(0.1))
                        .cornerRadius(4)
                }
                if selected {
                    LucideView(name: .check, size: 14, color: .themeGreen500)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(selected ? Color.themeGreen500.opacity(0.1) : Color.themeInput.opacity(0.65))
            .cornerRadius(7)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var statusBadge: some View {
        let (text, color): (String, Color) = {
            if prefs.aiConnectionKind == .customOpenAI { return ("自定义 API", .themeTextSecondary) }
            if case .loaded = catalogState { return ("网关已连接", .themeGreen500) }
            if case .failed = catalogState { return ("连接失败", .themeRed400) }
            return ("未连接", .themeTextTertiary)
        }()
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
        .font(.themeCaptionSmall)
        .foregroundColor(color)
    }

    private var customAPISection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(icon: .bot, title: "模型")
            CustomTextField(label: "Base URL", placeholder: "https://api.openai.com/v1", text: Binding(
                get: { prefs.openAIBaseURL },
                set: { prefs.setOpenAIBaseURL($0) }
            ))
            CustomTextField(label: "Model", placeholder: "gpt-4o-mini", text: Binding(
                get: { prefs.openAIModel },
                set: { prefs.setOpenAIModel($0) }
            ))
            CustomTextField(label: "API Key", placeholder: "sk-...", text: Binding(
                get: { KeychainHelper.shared.read(service: "QuiteNote", account: "openai_api_key") ?? "" },
                set: { KeychainHelper.shared.write(service: "QuiteNote", account: "openai_api_key", value: $0) }
            ), isSecure: true)
        }
        .padding(20)
        .background(Color.themeGray800.opacity(0.4) as Color)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorderSubtle))
    }

    private var validationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle(icon: .zap, title: "试生成")
                Spacer()
                if let elapsed = validationElapsed {
                    Text(String(format: "约 %.1f 秒", elapsed))
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                }
            }

            Button(action: testModel) {
                HStack(spacing: 8) {
                    if isTestingConnection {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        LucideView(name: .zap, size: 14, color: .white)
                    }
                    Text(isTestingConnection ? "正在验证..." : "用固定安全样例试生成")
                }
            }
            .font(.themeBody)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(isTestingConnection ? Color.themeGray600 : Color.themeBlue600)
            .cornerRadius(8)
            .buttonStyle(.plain)
            .pointingHandCursor()
            .disabled(isTestingConnection)

            if let result = validationResult {
                VStack(alignment: .leading, spacing: 3) {
                    Text("标题：\(result.title)")
                    Text("总结：\(result.summary)")
                }
                .font(.themeCaption)
                .foregroundColor(.themeTextSecondary)
            } else if let validationMessage {
                Text(validationMessage)
                    .font(.themeCaption)
                    .foregroundColor(.themeRed400)
            }
        }
        .padding(20)
        .background(Color.themeGray800.opacity(0.4) as Color)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorderSubtle))
    }

    // MARK: - Advanced

    private var aiBehaviorSection: some View {
        VStack(spacing: 16) {
            NativeSliderRow(label: "总结触发长度", value: Binding(
                get: { Double(store.summaryTrigger) }, set: { store.summaryTrigger = Int($0); store.savePreferences() }
            ), range: 10...500)
            NativeSliderRow(label: "标题长度限制", value: Binding(
                get: { Double(store.titleLimit) }, set: { store.titleLimit = Int($0); store.savePreferences() }
            ), range: 10...40)
            NativeSliderRow(label: "总结长度限制", value: Binding(
                get: { Double(store.summaryLimit) }, set: { store.summaryLimit = Int($0); store.savePreferences() }
            ), range: 50...300)
        }
        .padding(.vertical, 10)
    }

    private var magpieAdvancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if prefs.aiConnectionKind == .magpie {
                CustomTextField(label: "Magpie Base URL", placeholder: "http://127.0.0.1:3425", text: Binding(
                    get: { prefs.magpieBaseURL },
                    set: {
                        prefs.setMagpieBaseURL($0)
                        loadCatalogIfNeeded(force: true)
                    }
                ))
            }
        }
        .padding(.top, 10)
    }

    private var promptConfigSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            systemPromptSection
            userPromptSection
        }
    }

    private var systemPromptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("System Prompt")
                    .font(.themeBody)
                    .fontWeight(.medium)
                    .foregroundColor(.themeTextSecondary)
                Button(action: { prefs.resetAISystemPrompt() }) {
                    LucideView(name: .rotateCcw, size: 12, color: .themeTextTertiary)
                }
                .buttonStyle(.plain)
                Spacer()
                VariableBadge(text: "{titleLimit}", color: .themeYellow500)
                VariableBadge(text: "{summaryLimit}", color: .themeGreen500)
            }
            TextEditor(text: Binding(
                get: { prefs.aiSystemPrompt },
                set: { prefs.setAISystemPrompt($0) }
            ))
            .font(.themeMono2)
            .lineSpacing(8)
            .foregroundColor(.themeGray200)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 120, maxHeight: 180)
            .padding(12)
            .background(Color.themeInput)
            .cornerRadius(8)
        }
    }

    private var userPromptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("User Prompt")
                    .font(.themeBody)
                    .fontWeight(.medium)
                    .foregroundColor(.themeTextSecondary)
                Button(action: { prefs.resetAIUserPrompt() }) {
                    LucideView(name: .rotateCcw, size: 12, color: .themeTextTertiary)
                }
                .buttonStyle(.plain)
                Spacer()
                VariableBadge(text: "{content}", color: .themeBlue500)
            }
            TextEditor(text: Binding(
                get: { prefs.aiUserPrompt },
                set: { prefs.setAIUserPrompt($0) }
            ))
            .font(.themeMono2)
            .lineSpacing(8)
            .foregroundColor(.themeGray200)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 80, maxHeight: 150)
            .padding(12)
            .background(Color.themeInput)
            .cornerRadius(8)
        }
    }

    private var privacyNote: some View {
        HStack(spacing: 6) {
            LucideView(name: .shield, size: 12, color: .themeTextTertiary)
            Text("Magpie 是本机连接入口；所选模型可能在云端处理笔记内容。")
        }
        .font(.themeCaptionSmall)
        .foregroundColor(.themeTextTertiary)
    }

    // MARK: - Helpers

    private func sectionTitle(icon: IconName, title: String) -> some View {
        HStack(spacing: 7) {
            LucideView(name: icon, size: 14, color: .themeBlue400)
            Text(title)
                .font(.themeBody)
                .fontWeight(.semibold)
                .foregroundColor(.themeTextPrimary)
        }
    }

    private var currentStatusLine: String {
        let connection = prefs.aiConnectionKind == .magpie ? "Magpie" : "自定义 API"
        let model = prefs.aiConnectionKind == .magpie ? (prefs.magpieModelID ?? "未选择模型") : prefs.openAIModel
        return "当前使用：\(connection) · \(model)"
    }

    private func loadCatalogIfNeeded(force: Bool = false) {
        guard prefs.aiConnectionKind == .magpie else { return }
        if case .loaded = catalogState, !force { return }
        catalogState = .loading
        catalogService.load(baseURL: prefs.magpieBaseURL) { result in
            DispatchQueue.main.async {
                switch result {
                case .success((_, let models)):
                    self.catalogState = .loaded(models)
                    self.validationMessage = nil
                case .failure(let error):
                    self.catalogState = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func testModel() {
        isTestingConnection = true
        validationMessage = nil
        validationResult = nil
        validationElapsed = nil
        let started = Date()
        (store.ai as? AIService)?.testModel { result in
            DispatchQueue.main.async {
                self.isTestingConnection = false
                self.validationElapsed = Date().timeIntervalSince(started)
                switch result {
                case .success(let summary):
                    self.validationResult = summary
                case .failure(let error):
                    self.validationMessage = error.localizedDescription
                }
            }
        }
    }
}
