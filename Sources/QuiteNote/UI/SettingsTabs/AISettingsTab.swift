import SwiftUI

/// AI 设置标签页视图
struct AISettingsTab: View {
    @ObservedObject var store: RecordStore
    @ObservedObject private var prefs = PreferencesManager.shared
    @Binding var isTestingConnection: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            aiToggleSection
            if store.enableAI {
                aiBehaviorSection
                providerSection
                apiConfigSection
                promptConfigSection
            }
        }
    }

    // MARK: - AI Toggle Section

    private var aiToggleSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    LucideView(name: .sparkles, size: 16, color: .themeYellow500)
                    Text("AI 自动提炼")
                        .font(.themeH2)
                        .foregroundColor(.themeTextPrimary)
                }
                Text("开启后自动为新记录生成标题和总结。")
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
    }

    // MARK: - AI Behavior Section

    private var aiBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                LucideView(name: .activity, size: 16, color: .themeBlue400)
                Text("提炼行为约束")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
            }
            .padding(.bottom, 4)

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
        }
        .padding(20)
        .background(Color.themeGray800.opacity(0.4) as Color)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorderSubtle))
    }

    // MARK: - Provider Section

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LucideLabel(icon: .link, text: "模型服务商与连接", size: 14, color: .themeTextSecondary)
                .font(.themeBody)
                .fontWeight(.medium)

            HStack(spacing: 8) {
                ProviderButton(title: "OpenAI GPT", isSelected: true) { }
                Spacer()
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - API Config Section

    private var apiConfigSection: some View {
        VStack(spacing: 16) {
            CustomTextField(label: "API Key", placeholder: "sk-...", text: Binding(
                get: { KeychainHelper.shared.read(service: "QuiteNote", account: "openai_api_key") ?? "" },
                set: { KeychainHelper.shared.write(service: "QuiteNote", account: "openai_api_key", value: $0) }
            ), isSecure: true)

            CustomTextField(label: "Base URL", placeholder: "https://api.openai.com/v1", text: Binding(
                get: { (store.ai as? AIService)?.openAIBaseURL ?? "https://api.openai.com/v1" },
                set: { store.configureOpenAI(apiKey: KeychainHelper.shared.read(service: "QuiteNote", account: "openai_api_key") ?? "", baseURL: $0, model: (store.ai as? AIService)?.openAIModel ?? "gpt-4o-mini") }
            ))

            CustomTextField(label: "Model", placeholder: "gpt-4o-mini", text: Binding(
                get: { (store.ai as? AIService)?.openAIModel ?? "gpt-4o-mini" },
                set: { store.configureOpenAI(apiKey: KeychainHelper.shared.read(service: "QuiteNote", account: "openai_api_key") ?? "", baseURL: (store.ai as? AIService)?.openAIBaseURL ?? "https://api.openai.com/v1", model: $0) }
            ))

            // API测试按钮
            Button(action: {
                testAPIConnection()
            }) {
                HStack(spacing: 8) {
                    if isTestingConnection {
                        ProgressView()
                            .scaleEffect(0.7)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        LucideView(name: .zap, size: 14, color: .white)
                    }
                    Text(isTestingConnection ? "正在验证连接..." : "验证连接有效性")
                }
                .font(.themeBody)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color.themeBlue600)
                .cornerRadius(8)
                .shadow(color: Color.themeShadowBlue, radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .disabled(isTestingConnection)
        }
        .padding(20)
        .background(Color.themeGray800.opacity(0.4) as Color)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorderSubtle))
    }

    // MARK: - Prompt Config Section

    private var promptConfigSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                LucideView(name: .slidersHorizontal, size: 16, color: .themeBlue400)
                Text("提炼提示词 (Prompt) 配置")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
            }
            .padding(.bottom, 4)

            systemPromptSection
            userPromptSection
        }
    }

    private var systemPromptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Text("系统提示词 (System Prompt)")
                        .font(.themeBody)
                        .fontWeight(.medium)
                        .foregroundColor(.themeTextSecondary)

                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            PreferencesManager.shared.resetAISystemPrompt()
                        }
                    }) {
                        LucideView(name: .rotateCcw, size: 12, color: .themeTextTertiary)
                            .padding(4)
                            .background(Color.themeHoverLight)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .help("重置为默认值")
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("可用变量:").font(.themeCaptionSmall).foregroundColor(.themeTextTertiary)
                    VariableBadge(text: "{titleLimit}", color: .themeYellow500)
                    VariableBadge(text: "{summaryLimit}", color: .themeGreen500)
                }
                .fixedSize(horizontal: true, vertical: false)
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
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.themeBorder, lineWidth: 1)
                    .opacity(0.5)
            )
        }
    }

    private var userPromptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Text("用户提示词 (User Prompt)")
                        .font(.themeBody)
                        .fontWeight(.medium)
                        .foregroundColor(.themeTextSecondary)

                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            PreferencesManager.shared.resetAIUserPrompt()
                        }
                    }) {
                        LucideView(name: .rotateCcw, size: 12, color: .themeTextTertiary)
                            .padding(4)
                            .background(Color.themeHoverLight)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .help("重置为默认值")
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("可用变量:").font(.themeCaptionSmall).foregroundColor(.themeTextTertiary)
                    VariableBadge(text: "{content}", color: .themeBlue500)
                }
                .fixedSize(horizontal: true, vertical: false)
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
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.themeBorder, lineWidth: 1)
                    .opacity(0.5)
            )
        }
    }

    // MARK: - Methods

    private func testAPIConnection() {
        isTestingConnection = true
        (store.ai as? AIService)?.testConnection { result in
            DispatchQueue.main.async {
                self.isTestingConnection = false
                switch result {
                case .success:
                    self.store.postToast("连接成功！API 配置有效。", type: "success")
                case .failure(let error):
                    self.store.postToast("连接失败: \(error.localizedDescription)", type: "error")
                }
            }
        }
    }
}
