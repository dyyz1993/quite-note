import SwiftUI
import AppKit

// MARK: - Symbol Config Editor Manager (NSPanel)

/// 符号配置编辑器管理器 - 使用 NSPanel 而不是 SwiftUI sheet
class SymbolConfigEditorManager {
    static let shared = SymbolConfigEditorManager()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<SymbolConfigEditorPanel>?
    private var fileWatcher: DispatchSourceFileSystemObject?

    private init() {}

    func showEditor(config: SymbolConfig, onSave: @escaping (SymbolConfig) -> Void) {
        // 关闭现有面板
        closeEditor()

        // 创建 SwiftUI 视图
        let editorPanel = SymbolConfigEditorPanel(
            config: config,
            onSave: onSave,
            onClose: { [weak self] in
                self?.closeEditor()
            }
        )

        // 创建 hosting view
        let hosting = NSHostingView(rootView: editorPanel)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        // 创建 panel
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 550),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        panel.title = "符号配置预览"
        panel.contentViewController = NSViewController()
        panel.contentViewController?.view.addSubview(hosting)

        // 设置约束
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: panel.contentViewController!.view.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: panel.contentViewController!.view.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: panel.contentViewController!.view.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: panel.contentViewController!.view.bottomAnchor)
        ])

        // 配置 panel
        panel.isFloatingPanel = false
        panel.level = .floating

        // 居中显示
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelSize = NSSize(width: 600, height: 550)
            panel.setFrame(
                NSRect(
                    x: screenFrame.midX - panelSize.width / 2,
                    y: screenFrame.midY - panelSize.height / 2,
                    width: panelSize.width,
                    height: panelSize.height
                ),
                display: true
            )
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = panel
        self.hostingView = hosting
    }

    func closeEditor() {
        // 停止文件监听
        if let watcher = fileWatcher {
            watcher.cancel()
            fileWatcher = nil
        }
        panel?.close()
        panel = nil
        hostingView = nil
    }

    func setFileWatcher(_ watcher: DispatchSourceFileSystemObject) {
        // 取消之前的监听
        if let oldWatcher = fileWatcher {
            oldWatcher.cancel()
        }
        fileWatcher = watcher
    }
}

// MARK: - Symbol Config Editor Panel (SwiftUI View for NSPanel)

/// 符号配置编辑器面板视图（用于 NSPanel）
struct SymbolConfigEditorPanel: View {
    @State private var editedConfig: SymbolConfig
    @State private var yamlText: String
    @State private var selectedMenuIndex: Int = 0
    @State private var validationError: String?
    @State private var externalEditorURL: URL?
    @State private var isWatchingFile = false

    let originalConfig: SymbolConfig
    let onSave: (SymbolConfig) -> Void
    let onClose: () -> Void

    init(config: SymbolConfig, onSave: @escaping (SymbolConfig) -> Void, onClose: @escaping () -> Void) {
        self.originalConfig = config
        // Since metadata has let constants, we create a new config with editable fields
        let editableMetadata = SymbolMetadata(
            name: config.metadata.name,
            icon: config.metadata.icon,
            priority: config.metadata.priority,
            enabled: config.metadata.enabled
        )
        let editableConfig = SymbolConfig(
            id: config.id,
            metadata: editableMetadata,
            global: config.global,
            menus: config.menus
        )
        self._editedConfig = State(initialValue: editableConfig)
        self._yamlText = State(initialValue: config.toYaml())
        self.onSave = onSave
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            // 头部
            headerView

            Divider()
                .background(Color.themeBorder)

            // 内容区
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 配置信息卡片
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeader(title: "配置信息", icon: "info.circle")

                        infoRow(title: "名称", value: editedConfig.metadata.name)
                        infoRow(title: "图标", value: editedConfig.metadata.icon)
                        infoRow(title: "优先级", value: "\(editedConfig.metadata.priority)")
                        infoRow(title: "触发前缀", value: editedConfig.global.triggerPrefix)
                        infoRow(title: "符号数", value: "\(editedConfig.menus.reduce(0) { $0 + $1.symbols.count })")
                        infoRow(title: "分类数", value: "\(editedConfig.menus.count)")
                    }
                    .padding(16)
                    .background(Color.themeHoverLight)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.themeBorder, lineWidth: 1)
                    )

                    // 符号预览
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeader(title: "符号预览", icon: "square.grid.2x2")

                        Picker("分类", selection: $selectedMenuIndex) {
                            ForEach(Array(editedConfig.menus.enumerated()), id: \.offset) { index, menu in
                                Text(menu.title).tag(index)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 200)

                        if selectedMenuIndex < editedConfig.menus.count {
                            let menu = editedConfig.menus[selectedMenuIndex]
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(menu.title)
                                        .font(.themeBody)
                                        .foregroundColor(Color.themeTextPrimary)
                                    if let icon = menu.icon {
                                        Text(icon)
                                            .font(.system(size: 14))
                                    }
                                }

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
                                        .padding(10)
                                        .background(Color.themeHoverMedium)
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(16)
                            .background(Color.themeGray800)
                            .cornerRadius(10)
                        }
                    }

                    // 验证结果
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

                    // 外部编辑器提示
                    if let url = externalEditorURL {
                        HStack(spacing: 8) {
                            Image(systemName: "text.doc")
                                .font(.system(size: 12))
                                .foregroundColor(Color.themeBlue500)
                            Text("正在编辑: \(url.lastPathComponent)")
                                .font(.themeCaption)
                                .foregroundColor(Color.themeTextSecondary)
                            if isWatchingFile {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(Color.themeGreen500)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.themeBlue500.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }

            Divider()
                .background(Color.themeBorder)

            // 底部操作栏
            footerView
        }
        .background(Color.themeBackground)
        .frame(width: 600, height: 550)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("符号配置预览")
                .font(.themeH3)
                .foregroundColor(Color.themeTextPrimary)

            Spacer()

            Button(action: { onClose() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color.themeTextSecondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
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

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.themeCaption)
                .foregroundColor(Color.themeTextSecondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.themeBody)
                .foregroundColor(Color.themeTextPrimary)
            Spacer()
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Text(originalConfig.metadata.name)
                .font(.themeCaption)
                .foregroundColor(Color.themeTextTertiary)

            Spacer()

            // 在外部编辑器中打开按钮
            Button(action: { openInExternalEditor() }) {
                HStack(spacing: 6) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 13))
                    Text("打开编辑器")
                        .font(.themeBody)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.themeGreen600)
                .cornerRadius(8)
                .shadow(color: Color.themeShadowGreen, radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
            .help("在系统默认文本编辑器中打开 YAML 配置")
            .disabled(externalEditorURL != nil)

            // 重新加载按钮
            if externalEditorURL != nil {
                Button(action: { reloadFromExternalEditor() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                        Text("重新加载")
                            .font(.themeBody)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.themeBlue600)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .help("重新加载 YAML 文件内容")
            }

            Button(action: { onClose() }) {
                Text("关闭")
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

    // MARK: - Actions

    private func openInExternalEditor() {
        // 创建临时文件
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(originalConfig.metadata.name.replacingOccurrences(of: " ", with: "_"))_config.yaml"
        let fileURL = tempDir.appendingPathComponent(fileName)

        // 写入 YAML 内容
        do {
            try yamlText.write(to: fileURL, atomically: true, encoding: .utf8)
            externalEditorURL = fileURL

            // 在系统默认编辑器中打开
            NSWorkspace.shared.open(fileURL)

            // 启动文件监听
            startWatchingFile(fileURL)
        } catch {
            print("[SymbolConfigEditorPanel] 创建临时文件失败: \(error)")
        }
    }

    private func startWatchingFile(_ url: URL) {
        // 使用 DispatchSource 监听文件变化
        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor != -1 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.main
        )

        // 捕获 self 值用于回调
        let capturedURL = url
        source.setEventHandler { [capturedURL] in
            // 通知文件已变化
            NotificationCenter.default.post(
                name: NSNotification.Name("YamlFileDidChange"),
                object: capturedURL
            )
        }

        source.resume()
        SymbolConfigEditorManager.shared.setFileWatcher(source)
        isWatchingFile = true

        // 监听文件变化通知
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("YamlFileDidChange"),
            object: url,
            queue: .main
        ) { [self] _ in
            self.reloadFromExternalEditor()
        }
    }

    private func reloadFromExternalEditor() {
        guard let url = externalEditorURL else { return }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            yamlText = content

            // 验证并更新配置
            do {
                let updated = try SymbolConfig.from(yaml: content)
                editedConfig = updated
                validationError = nil
            } catch {
                validationError = error.localizedDescription
            }
        } catch {
            print("[SymbolConfigEditorPanel] 读取文件失败: \(error)")
        }
    }

    private func saveAndClose() {
        onSave(editedConfig)
        onClose()
    }
}
