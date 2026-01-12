import SwiftUI

/// 符号设置标签页
struct SymbolSettingsTab: View {
    @StateObject private var configManager = SymbolConfigManager.shared
    @State private var validationError: String?
    @State private var validationSuccess: Bool = false
    @State private var newConfigURL: URL?
    @State private var fileWatcher: DispatchSourceFileSystemObject?
    @State private var configToDelete: SymbolConfig?
    @State private var showDeleteAlert: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题区域
            headerView

            Divider()
                .background(Color.themeBorder)

            // 内容区域
            ScrollView {
                VStack(spacing: 24) {
                    // 统计信息
                    statsSection

                    // 当前配置列表
                    if !configManager.configs.isEmpty {
                        configListSection
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
        .onAppear {
            validationError = nil
            validationSuccess = false
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("符号库设置")
                    .font(.themeH3)
                    .foregroundColor(Color.themeTextPrimary)

                Text("配置快速输入的符号和表情")
                    .font(.themeCaption)
                    .foregroundColor(Color.themeTextTertiary)
            }

            Spacer()

            // 创建新配置按钮
            Button(action: { createNewConfig() }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text("创建新配置")
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
            .help("创建新的符号库配置")

            // 重置按钮
            Button(action: { resetToDefault() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                    .foregroundColor(Color.themeTextSecondary)
                    .frame(width: 32, height: 32)
                    .background(Color.themeHoverLight)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.themeBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .help("重置为默认配置")
        }
        .padding(24)
        .padding(.bottom, 16)
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前状态")
                .font(.themeBody)
                .foregroundColor(Color.themeTextPrimary)

            HStack(spacing: 12) {
                // 符号库数量
                statCard(
                    icon: "folder.fill",
                    title: "\(configManager.configs.count) 个符号库",
                    subtitle: "已加载配置"
                )

                // 符号总数
                let totalSymbols = configManager.configs.reduce(0) { $0 + $1.stats.symbolCount }
                statCard(
                    icon: "square.grid.2x2.fill",
                    title: "\(totalSymbols) 个符号",
                    subtitle: "可用符号"
                )

                // 触发前缀
                let prefixes = configManager.configs.map { $0.global.triggerPrefix }.uniqued().sorted()
                statCard(
                    icon: "command.fill",
                    title: prefixes.joined(separator: " "),
                    subtitle: "触发前缀"
                )
            }

            // 验证结果
            if let error = validationError {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
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
            } else if validationSuccess {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color.themeGreen500)
                    Text("配置已保存，点击\"加载配置\"应用")
                        .font(.themeCaption)
                        .foregroundColor(Color.themeGreen500)
                    Spacer()

                    if let url = newConfigURL {
                        Button(action: { loadNewConfig() }) {
                            Text("加载配置")
                                .font(.themeCaption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.themeBlue600)
                                .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(12)
                .background(Color.themeGreen500.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    private func statCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Color.themeBlue500)
                Text(title)
                    .font(.themeBody)
                    .foregroundColor(Color.themeTextPrimary)
            }
            Text(subtitle)
                .font(.themeCaptionSmall)
                .foregroundColor(Color.themeTextTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.themeHoverLight)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.themeBorder, lineWidth: 1)
        )
    }

    // MARK: - Config List Section

    private var configListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("已加载的配置")
                .font(.themeBody)
                .foregroundColor(Color.themeTextPrimary)

            VStack(spacing: 8) {
                ForEach(configManager.configs) { config in
                    configRow(config)
                }
            }
        }
    }

    private func configRow(_ config: SymbolConfig) -> some View {
        HStack(spacing: 12) {
            // 图标
            Text(config.metadata.iconDisplay)
                .font(.system(size: 24))

            VStack(alignment: .leading, spacing: 6) {
                // 名称（移除触发前缀标签）
                Text(config.metadata.name)
                    .font(.themeBody)
                    .foregroundColor(Color.themeTextPrimary)
                    .fontWeight(.medium)

                // 统计信息
                Text("\(config.stats.menuCount) 个分类 · \(config.stats.symbolCount) 个符号")
                    .font(.themeCaptionSmall)
                    .foregroundColor(Color.themeTextTertiary)

                // 快捷符号展示（显示前8个符号）
                if !config.menus.isEmpty {
                    let quickSymbols = Array(config.menus
                        .sorted { $0.sort < $1.sort }
                        .flatMap { $0.symbols.prefix(2) }
                        .prefix(8))

                    if !quickSymbols.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(quickSymbols.prefix(8), id: \.id) { symbol in
                                Text(symbol.content)
                                    .font(.system(size: 13))
                                    .frame(width: 24, height: 24)
                                    .background(Color.themeHoverMedium)
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                // 编辑按钮
                Button(action: { editConfig(config) }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundColor(Color.themeTextSecondary)
                        .frame(width: 28, height: 28)
                        .background(Color.themeHoverMedium)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .help("编辑配置")

                // 删除按钮（默认配置不允许删除）
                if config.metadata.name != "默认符号库" && config.metadata.name != "English Symbols" {
                    Button(action: {
                        configToDelete = config
                        showDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(Color.themeRed500)
                            .frame(width: 28, height: 28)
                            .background(Color.themeRed500.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("删除配置")
                }
            }
        }
        .padding(12)
        .background(Color.themeHoverLight)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.themeBorder, lineWidth: 1)
        )
        .alert("删除配置", isPresented: $showDeleteAlert, presenting: configToDelete) { config in
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                deleteConfig(config)
            }
        } message: { config in
            Text("确定要删除「\(config.metadata.name)」吗？此操作无法撤销。")
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("使用触发前缀输入符号")
                    .font(.themeCaption)
                    .foregroundColor(Color.themeTextTertiary)

                let prefixes = configManager.configs.map { $0.global.triggerPrefix }.uniqued().sorted()
                if !prefixes.isEmpty {
                    Text("例如: \(prefixes.first ?? "")触发词")
                        .font(.themeCaptionSmall)
                        .foregroundColor(Color.themeTextTertiary)
                }
            }

            Spacer()
        }
        .padding(20)
    }

    // MARK: - Actions

    private func createNewConfig() {
        // 创建带注释的 YAML 模板
        let template = """
# 符号库配置模板
# 修改此文件后保存，然后点击"加载配置"按钮

metadata:
  name: "我的符号库"           # 配置名称
  icon: "⭐"                  # 图标 emoji
  priority: 10                # 优先级（数字越小越优先）
  enabled: true               # 是否启用

global:
  trigger_prefix: ":m"        # 触发前缀（例如 :m、:x 等）
  auto_hide: true             # 输入后是否自动隐藏面板
  auto_clean: true            # 是否自动清理触发前缀
  panel_position: "cursor_bottom"  # 面板位置
  panel_width: "auto"         # 面板宽度

symbol_menus:
  - title: "常用符号"          # 分类名称
    sort: 1                   # 排序（数字越小越靠前）
    icon: "⭐"                # 分类图标（可选）
    symbols:
      - trigger: ["ok", "好的"]     # 触发词（支持多个）
        content: "✅"                # 符号内容
        desc: "完成/通过"            # 描述
      - trigger: ["bug", "错误"]
        content: "🐛"
        desc: "BUG/错误"
      - trigger: ["fix", "修复"]
        content: "🔧"
        desc: "修复/改进"
      - trigger: ["test", "测试"]
        content: "🧪"
        desc: "测试"

  - title: "更多符号"
    sort: 2
    symbols:
      - trigger: ["star", "星星"]
        content: "⭐"
        desc: "星星"
      - trigger: ["heart", "爱心"]
        content: "❤️"
        desc: "爱心"
      - trigger: ["fire", "火焰"]
        content: "🔥"
        desc: "火焰"

# 提示：
# 1. trigger_prefix 不要与现有配置冲突（当前使用: :/ 和 :e）
# 2. 每个 symbol 可以有多个触发词
# 3. 保存后在设置页面点击"加载配置"即可
"""

        // 创建临时文件
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "my_symbols_\(Int(Date().timeIntervalSince1970)).yaml"
        let fileURL = tempDir.appendingPathComponent(fileName)

        // 写入模板
        do {
            try template.write(to: fileURL, atomically: true, encoding: .utf8)
            newConfigURL = fileURL

            // 在编辑器中打开
            let vscodeInstalled = openInVSCode(fileURL)
            if !vscodeInstalled {
                NSWorkspace.shared.open(fileURL)
            }

            // 监听文件变化
            startWatchingFile(fileURL)

            validationError = nil
            validationSuccess = true
        } catch {
            validationError = "创建配置文件失败: \(error.localizedDescription)"
            validationSuccess = false
        }
    }

    private func editConfig(_ config: SymbolConfig) {
        // 创建临时文件
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(config.metadata.name.replacingOccurrences(of: " ", with: "_"))_config.yaml"
        let fileURL = tempDir.appendingPathComponent(fileName)

        // 写入 YAML 内容
        do {
            let yamlContent = config.toYaml()
            try yamlContent.write(to: fileURL, atomically: true, encoding: .utf8)

            // 在编辑器中打开
            let vscodeInstalled = openInVSCode(fileURL)
            if !vscodeInstalled {
                NSWorkspace.shared.open(fileURL)
            }

            // 监听文件变化
            startWatchingFile(fileURL)
        } catch {
            print("[SymbolSettingsTab] 创建临时文件失败: \(error)")
        }
    }

    private func openInVSCode(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/code")
        if process.executableURL == nil {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/code")
        }

        process.arguments = [url.path]

        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private func startWatchingFile(_ url: URL) {
        if let watcher = fileWatcher {
            watcher.cancel()
            fileWatcher = nil
        }

        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor != -1 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.main
        )

        source.setEventHandler { [self] in
            reloadFromFile(url)
        }

        source.resume()
        fileWatcher = source
    }

    private func reloadFromFile(_ url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)

            // 如果是新配置模板
            if newConfigURL == url {
                validationError = nil
                validationSuccess = true
                return
            }

            // 尝试解析 YAML
            do {
                let config = try SymbolConfig.from(yaml: content)
                try configManager.saveConfig(config)
                validationError = nil
                validationSuccess = true

                // 3秒后清除提示
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    validationSuccess = false
                }
            } catch {
                validationError = "YAML 格式错误: \(error.localizedDescription)"
                validationSuccess = false
            }
        } catch {
            print("[SymbolSettingsTab] 读取文件失败: \(error)")
        }
    }

    private func loadNewConfig() {
        guard let url = newConfigURL else { return }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let config = try SymbolConfig.from(yaml: content)

            // 检查触发前缀是否冲突
            let existingPrefixes = configManager.configs.map { $0.global.triggerPrefix }
            if existingPrefixes.contains(config.global.triggerPrefix) {
                validationError = "触发前缀 \(config.global.triggerPrefix) 已存在，请使用不同的前缀"
                validationSuccess = false
                return
            }

            // 保存新配置
            try configManager.saveConfig(config)

            validationError = nil
            validationSuccess = true
            newConfigURL = nil

            // 3秒后清除提示
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                validationSuccess = false
            }
        } catch {
            validationError = "加载配置失败: \(error.localizedDescription)"
            validationSuccess = false
        }
    }

    private func resetToDefault() {
        configManager.resetToDefault()
        validationError = nil
        validationSuccess = false
        newConfigURL = nil
    }

    private func deleteConfig(_ config: SymbolConfig) {
        do {
            try configManager.deleteConfig(config)
            validationError = nil
            validationSuccess = false
        } catch {
            validationError = "删除配置失败: \(error.localizedDescription)"
        }
    }

    private func closeSettings() {
        NotificationCenter.default.post(name: .closeSettings, object: nil)
    }
}

// MARK: - Array Extension

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let closeSettings = Notification.Name("closeSettings")
}
