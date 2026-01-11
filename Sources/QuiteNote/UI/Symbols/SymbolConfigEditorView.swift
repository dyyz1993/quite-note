import SwiftUI

/// 符号配置编辑器界面
struct SymbolConfigEditorView: View {
    @Binding var config: SymbolConfig
    let isPresented: Binding<Bool>
    let onSave: (SymbolConfig) -> Void

    @State private var editedConfig: SymbolConfig
    @State private var yamlText: String
    @State private var selectedMenuIndex: Int = 0
    @State private var validationError: String?
    @State private var showPreview = false

    init(config: SymbolConfig, isPresented: Binding<Bool>, onSave: @escaping (SymbolConfig) -> Void) {
        self._config = Binding(
            get: { config },
            set: { _ in }
        )
        self.isPresented = isPresented
        self.onSave = onSave
        self._editedConfig = State(initialValue: config)
        self._yamlText = State(initialValue: config.toYaml())
    }

    var body: some View {
        VStack(spacing: 0) {
            // 头部
            headerView

            Divider()
                .background(Color.themeBorder)

            // 标签页
            HStack(spacing: 0) {
                tabButton(title: "基本信息", icon: "info.circle", isSelected: !showPreview) {
                    withAnimation { showPreview = false }
                }
                tabButton(title: "YAML 编辑", icon: "doc.text", isSelected: showPreview) {
                    withAnimation { showPreview = true }
                }
            }
            .padding(0)

            Divider()
                .background(Color.themeBorder)

            // 内容区
            ScrollView {
                VStack(spacing: 24) {
                    if showPreview {
                        yamlEditorView
                    } else {
                        basicInfoView
                        triggerConfigView
                        previewSection
                    }
                }
                .padding(24)
            }

            Divider()
                .background(Color.themeBorder)

            // 底部操作栏
            footerView
        }
        .background(Color.themeBackground)
        .frame(width: 600, height: 500)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Button(action: { isPresented.wrappedValue = false }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12))
                    .foregroundColor(Color.themeTextSecondary)
            }
            .buttonStyle(PlainButtonStyle())

            Text("编辑符号配置")
                .font(.themeH3)
                .foregroundColor(Color.themeTextPrimary)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Tab Button

    private func tabButton(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.themeCaption)
            }
            .foregroundColor(isSelected ? Color.themeBlue500 : Color.themeTextTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                Rectangle()
                    .fill(isSelected ? Color.themeBlue500.opacity(0.1) : Color.clear)
            )
            .overlay(
                Rectangle()
                    .fill(Color.themeBlue500)
                    .frame(height: 2),
                alignment: .bottom
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Basic Info View

    private var basicInfoView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "基本信息", icon: "info.circle")

            VStack(alignment: .leading, spacing: 12) {
                inputField(
                    title: "配置名称",
                    text: Binding(
                        get: { editedConfig.metadata.name },
                        set: { newValue in
                            var newMetadata = editedConfig.metadata
                            newMetadata = SymbolMetadata(
                                name: newValue,
                                icon: newMetadata.icon,
                                priority: newMetadata.priority,
                                enabled: newMetadata.enabled
                            )
                            editedConfig = SymbolConfig(
                                id: editedConfig.id,
                                metadata: newMetadata,
                                global: editedConfig.global,
                                menus: editedConfig.menus
                            )
                        }
                    ),
                    placeholder: "输入配置名称"
                )

                HStack(spacing: 16) {
                    inputField(
                        title: "图标 Emoji",
                        text: Binding(
                            get: { editedConfig.metadata.icon },
                            set: { newValue in
                                var newMetadata = editedConfig.metadata
                                newMetadata = SymbolMetadata(
                                    name: newMetadata.name,
                                    icon: newValue,
                                    priority: newMetadata.priority,
                                    enabled: newMetadata.enabled
                                )
                                editedConfig = SymbolConfig(
                                    id: editedConfig.id,
                                    metadata: newMetadata,
                                    global: editedConfig.global,
                                    menus: editedConfig.menus
                                )
                            }
                        ),
                        placeholder: "🔣"
                    )

                    inputField(
                        title: "优先级",
                        text: Binding(
                            get: { String(editedConfig.metadata.priority) },
                            set: { newValue in
                                var newMetadata = editedConfig.metadata
                                newMetadata = SymbolMetadata(
                                    name: newMetadata.name,
                                    icon: newMetadata.icon,
                                    priority: Int(newValue) ?? 1,
                                    enabled: newMetadata.enabled
                                )
                                editedConfig = SymbolConfig(
                                    id: editedConfig.id,
                                    metadata: newMetadata,
                                    global: editedConfig.global,
                                    menus: editedConfig.menus
                                )
                            }
                        ),
                        placeholder: "1"
                    )
                }

                toggleRow(
                    title: "启用状态",
                    isOn: Binding(
                        get: { editedConfig.metadata.enabled },
                        set: { newValue in
                            var newMetadata = editedConfig.metadata
                            newMetadata = SymbolMetadata(
                                name: newMetadata.name,
                                icon: newMetadata.icon,
                                priority: newMetadata.priority,
                                enabled: newValue
                            )
                            editedConfig = SymbolConfig(
                                id: editedConfig.id,
                                metadata: newMetadata,
                                global: editedConfig.global,
                                menus: editedConfig.menus
                            )
                        }
                    )
                )
            }
            .padding(16)
            .background(Color.themeHoverLight)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.themeBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Trigger Config View

    private var triggerConfigView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "触发配置", icon: "command")

            VStack(alignment: .leading, spacing: 12) {
                inputField(
                    title: "触发前缀",
                    text: Binding(
                        get: { editedConfig.global.triggerPrefix },
                        set: { newValue in
                            let newGlobal = SymbolGlobalConfig(
                                triggerPrefix: newValue,
                                autoHide: editedConfig.global.autoHide,
                                autoClean: editedConfig.global.autoClean,
                                panelPosition: editedConfig.global.panelPosition,
                                panelWidth: editedConfig.global.panelWidth
                            )
                            editedConfig = SymbolConfig(
                                id: editedConfig.id,
                                metadata: editedConfig.metadata,
                                global: newGlobal,
                                menus: editedConfig.menus
                            )
                        }
                    ),
                    placeholder: ":/"
                )

                toggleRow(
                    title: "插入后自动隐藏面板",
                    isOn: Binding(
                        get: { editedConfig.global.autoHide },
                        set: { newValue in
                            let newGlobal = SymbolGlobalConfig(
                                triggerPrefix: editedConfig.global.triggerPrefix,
                                autoHide: newValue,
                                autoClean: editedConfig.global.autoClean,
                                panelPosition: editedConfig.global.panelPosition,
                                panelWidth: editedConfig.global.panelWidth
                            )
                            editedConfig = SymbolConfig(
                                id: editedConfig.id,
                                metadata: editedConfig.metadata,
                                global: newGlobal,
                                menus: editedConfig.menus
                            )
                        }
                    )
                )

                toggleRow(
                    title: "插入后自动清除触发词",
                    detail: "如 /bug → 🐛",
                    isOn: Binding(
                        get: { editedConfig.global.autoClean },
                        set: { newValue in
                            let newGlobal = SymbolGlobalConfig(
                                triggerPrefix: editedConfig.global.triggerPrefix,
                                autoHide: editedConfig.global.autoHide,
                                autoClean: newValue,
                                panelPosition: editedConfig.global.panelPosition,
                                panelWidth: editedConfig.global.panelWidth
                            )
                            editedConfig = SymbolConfig(
                                id: editedConfig.id,
                                metadata: editedConfig.metadata,
                                global: newGlobal,
                                menus: editedConfig.menus
                            )
                        }
                    )
                )
            }
            .padding(16)
            .background(Color.themeHoverLight)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.themeBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "预览", icon: "eye")

            VStack(alignment: .leading, spacing: 12) {
                Picker("分类", selection: $selectedMenuIndex) {
                    ForEach(Array(editedConfig.menus.enumerated()), id: \.offset) { index, menu in
                        Text(menu.title).tag(index)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 200)

                if selectedMenuIndex < editedConfig.menus.count {
                    let menu = editedConfig.menus[selectedMenuIndex]
                    VStack(alignment: .leading, spacing: 8) {
                        Text(menu.title)
                            .font(.themeBody)
                            .foregroundColor(Color.themeTextPrimary)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ], spacing: 8) {
                            ForEach(menu.symbols) { symbol in
                                VStack(spacing: 4) {
                                    Text(symbol.content)
                                        .font(.system(size: 18))
                                    Text(symbol.desc)
                                        .font(.themeCaptionSmall)
                                        .foregroundColor(Color.themeTextTertiary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(8)
                                .background(Color.themeHoverMedium)
                                .cornerRadius(6)
                                .onTapGesture {
                                    // 点击预览效果
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.themeHoverLight)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.themeBorder, lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - YAML Editor View

    private var yamlEditorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YAML 配置")
                    .font(.themeH3)
                    .foregroundColor(Color.themeTextPrimary)

                Spacer()

                Button(action: { copyYamlToClipboard() }) {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.themeCaption)
                        .foregroundColor(Color.themeTextSecondary)
                }
                .buttonStyle(PlainButtonStyle())
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
                .frame(minHeight: 300)

            if let error = validationError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color.themeRed500)
                    Text(error)
                        .font(.themeCaption)
                        .foregroundColor(Color.themeRed500)
                    Spacer()
                }
                .padding(12)
                .background(Color.themeRed500.opacity(0.1))
                .cornerRadius(8)
            }

            HStack {
                Text("修改 YAML 后点击验证并保存生效")
                    .font(.themeCaptionSmall)
                    .foregroundColor(Color.themeTextTertiary)

                Spacer()

                Button(action: { validateAndUpdateFromYaml() }) {
                    Text("验证 YAML")
                        .font(.themeCaption)
                        .foregroundColor(Color.themeTextSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.themeHoverLight)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Text(config.metadata.name)
                .font(.themeCaption)
                .foregroundColor(Color.themeTextTertiary)

            Spacer()

            Button(action: { isPresented.wrappedValue = false }) {
                Text("取消")
                    .font(.themeBody)
                    .foregroundColor(Color.themeTextSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.themeHoverLight)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: { saveAndClose() }) {
                Text("保存")
                    .font(.themeBody)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.themeBlue600)
                    .cornerRadius(8)
                    .shadow(color: Color.themeShadowBlue, radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(20)
    }

    // MARK: - Helper Views

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(Color.themeTextSecondary)
            Text(title)
                .font(.themeBody)
                .foregroundColor(Color.themeTextPrimary)
        }
    }

    private func inputField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.themeCaption)
                .foregroundColor(Color.themeTextSecondary)

            TextField(placeholder, text: text)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.themeBody)
                .foregroundColor(Color.themeTextPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.themeGray800)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.themeBorder, lineWidth: 1)
                )
        }
    }

    private func toggleRow(title: String, detail: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.themeCaption)
                    .foregroundColor(Color.themeTextSecondary)

                if let detail = detail {
                    Text(detail)
                        .font(.themeCaptionSmall)
                        .foregroundColor(Color.themeTextTertiary)
                }
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(SwitchToggleStyle())
        }
    }

    // MARK: - Actions

    private func saveAndClose() {
        onSave(editedConfig)
        isPresented.wrappedValue = false
    }

    private func copyYamlToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(yamlText, forType: .string)
    }

    private func validateAndUpdateFromYaml() {
        do {
            let updated = try SymbolConfig.from(yaml: yamlText)
            editedConfig = updated
            validationError = nil
        } catch {
            validationError = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview {
    SymbolConfigEditorView(
        config: .defaultConfig,
        isPresented: .constant(true),
        onSave: { _ in }
    )
}
