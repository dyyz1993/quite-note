import Foundation
import Combine

// MARK: - Symbol Configuration Manager

/// 符号配置管理器 - 单例
class SymbolConfigManager: ObservableObject {
    static let shared = SymbolConfigManager()

    // MARK: - Published Properties

    @Published var configs: [SymbolConfig] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let fileManager = FileManager.default
    private var cancellables = Set<AnyCancellable>()

    private var symbolsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let quiteNoteDir = appSupport.appendingPathComponent("QuiteNote", isDirectory: true)
        let symbolsDir = quiteNoteDir.appendingPathComponent("Symbols", isDirectory: true)

        // 确保目录存在
        try? fileManager.createDirectory(at: symbolsDir, withIntermediateDirectories: true)

        return symbolsDir
    }

    // MARK: - Initialization

    private init() {
        print("[SymbolConfigManager] 初始化配置管理器...")
        loadConfigs()
        print("[SymbolConfigManager] 初始化完成，加载了 \(configs.count) 个配置")
    }

    // MARK: - Public Methods

    /// 加载所有配置
    func loadConfigs() {
        isLoading = true
        defer { isLoading = false }

        var loadedConfigs: [SymbolConfig] = []

        do {
            let files = try fileManager.contentsOfDirectory(
                at: symbolsDirectory,
                includingPropertiesForKeys: nil
            )

            let yamlFiles = files.filter { $0.pathExtension == "yaml" || $0.pathExtension == "yml" }

            for file in yamlFiles {
                if let config = try? loadConfig(from: file) {
                    loadedConfigs.append(config)
                }
            }
        } catch {
            print("[SymbolConfigManager] 无法读取配置目录: \(error)")
        }

        // 如果没有任何配置，从 bundle 加载默认配置
        if loadedConfigs.isEmpty {
            print("[SymbolConfigManager] 配置目录为空，从 bundle 加载默认配置")
            if let bundleConfig = loadDefaultConfigFromBundle() {
                loadedConfigs = [bundleConfig]
                saveDefaultConfig()
            } else {
                print("[SymbolConfigManager] ⚠️ 无法从 bundle 加载配置，使用硬编码默认配置")
                loadedConfigs = [SymbolConfig.defaultConfig]
                saveDefaultConfig()
            }
        }

        // 按优先级排序
        loadedConfigs.sort { $0.metadata.priority < $1.metadata.priority }

        self.configs = loadedConfigs
        self.errorMessage = nil

        print("[SymbolConfigManager] ✅ 加载完成: \(loadedConfigs.count) 个配置")
        for config in loadedConfigs {
            print("[SymbolConfigManager]   - \(config.metadata.name): \(config.menus.count) 个分类, \(config.menus.map { $0.symbols.count }.reduce(0, +)) 个符号")
        }
    }

    /// 从 bundle 加载默认配置
    private func loadDefaultConfigFromBundle() -> SymbolConfig? {
        guard let bundleURL = Bundle.main.url(forResource: "default", withExtension: "yaml", subdirectory: "Symbols") else {
            print("[SymbolConfigManager] ⚠️ bundle 中未找到 default.yaml")
            return nil
        }

        print("[SymbolConfigManager] 从 bundle 加载配置: \(bundleURL.path)")
        return try? loadConfig(from: bundleURL)
    }

    /// 从文件加载配置
    func loadConfig(from url: URL) throws -> SymbolConfig {
        let data = try Data(contentsOf: url)

        // 简单的 YAML 解析（使用正则表达式）
        let yamlString = String(data: data, encoding: .utf8) ?? ""
        return try parseYAML(yamlString)
    }

    /// 保存配置
    func saveConfig(_ config: SymbolConfig) throws {
        let filename = "\(sanitizeFilename(config.metadata.name)).yaml"
        let fileURL = symbolsDirectory.appendingPathComponent(filename)

        let yamlString = config.toYaml()
        try yamlString.write(to: fileURL, atomically: true, encoding: .utf8)

        // 更新内存中的配置
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
        } else {
            configs.append(config)
        }

        // 重新排序
        configs.sort { $0.metadata.priority < $1.metadata.priority }
    }

    /// 删除配置
    func deleteConfig(_ config: SymbolConfig) throws {
        let filename = "\(sanitizeFilename(config.metadata.name)).yaml"
        let fileURL = symbolsDirectory.appendingPathComponent(filename)

        // 如果是默认配置，不允许删除
        if config.metadata.name == "默认符号库" {
            throw SymbolConfigError.cannotDeleteDefault
        }

        try fileManager.removeItem(at: fileURL)

        // 从内存中移除
        configs.removeAll { $0.id == config.id }
    }

    /// 导入配置
    func importConfig(fromYAML yaml: String) throws -> SymbolConfig {
        let config = try parseYAML(yaml)

        // 检查是否有同名配置
        let existingNames = configs.map { $0.metadata.name }
        if existingNames.contains(config.metadata.name) {
            throw SymbolConfigError.duplicateName
        }

        try saveConfig(config)
        return config
    }

    /// 导出配置为 YAML
    func exportConfig(_ config: SymbolConfig) -> String {
        return config.toYaml()
    }

    /// 重置为默认配置
    func resetToDefault() {
        // 删除所有配置文件
        try? fileManager.removeItem(at: symbolsDirectory)

        // 重新创建目录
        try? fileManager.createDirectory(at: symbolsDirectory, withIntermediateDirectories: true)

        // 保存默认配置
        saveDefaultConfig()

        // 重新加载
        loadConfigs()
    }

    /// 搜索所有配置中的符号
    func searchSymbols(query: String) -> [SymbolItem] {
        guard !query.isEmpty else { return [] }

        var results: Set<SymbolItem> = []

        for config in configs where config.metadata.enabled {
            let matches = config.search(query: query)
            results.formUnion(matches)
        }

        return Array(results)
    }

    /// 获取所有启用的配置
    var enabledConfigs: [SymbolConfig] {
        configs.filter { $0.metadata.enabled }
    }

    /// 获取合并后的触发词映射
    var combinedTriggerMap: [String: SymbolItem] {
        var map: [String: SymbolItem] = [:]

        for config in enabledConfigs {
            for (trigger, symbol) in config.triggerMap {
                // 后加载的配置覆盖前面的
                map[trigger] = symbol
            }
        }

        return map
    }

    // MARK: - Private Methods

    /// 保存默认配置到文件
    private func saveDefaultConfig() {
        let defaultConfig = SymbolConfig.defaultConfig
        let fileURL = symbolsDirectory.appendingPathComponent("default.yaml")

        let yamlString = defaultConfig.toYaml()
        try? yamlString.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// 解析 YAML 字符串
    private func parseYAML(_ yaml: String) throws -> SymbolConfig {
        let lines = yaml.components(separatedBy: .newlines)

        var metadataDict: [String: Any] = [:]
        var globalDict: [String: Any] = [:]
        var menusArray: [[String: Any]] = []
        var currentMenu: [String: Any] = [:]
        var currentSymbols: [[String: Any]] = []
        var inSymbolsSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 跳过注释和空行
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // 解析 metadata
            if trimmed.hasPrefix("metadata:") {
                continue
            } else if trimmed.hasPrefix("global:") {
                continue
            } else if trimmed.hasPrefix("symbol_menus:") {
                continue
            }

            // 解析 metadata 字段
            if trimmed.contains("name:") {
                metadataDict["name"] = extractValue(from: trimmed)
            } else if trimmed.contains("icon:") {
                metadataDict["icon"] = extractValue(from: trimmed)
            } else if trimmed.contains("priority:") {
                metadataDict["priority"] = Int(extractValue(from: trimmed)) ?? 1
            } else if trimmed.contains("enabled:") {
                metadataDict["enabled"] = Bool(extractValue(from: trimmed)) ?? true
            }
            // 解析 global 字段
            else if trimmed.contains("trigger_prefix:") {
                globalDict["trigger_prefix"] = extractValue(from: trimmed)
            } else if trimmed.contains("auto_hide:") {
                globalDict["auto_hide"] = Bool(extractValue(from: trimmed)) ?? true
            } else if trimmed.contains("auto_clean:") {
                globalDict["auto_clean"] = Bool(extractValue(from: trimmed)) ?? true
            } else if trimmed.contains("panel_position:") {
                globalDict["panel_position"] = extractValue(from: trimmed)
            } else if trimmed.contains("panel_width:") {
                globalDict["panel_width"] = extractValue(from: trimmed)
            }
            // 解析菜单
            else if trimmed.hasPrefix("- title:") {
                // 开始新的菜单
                if !currentMenu.isEmpty && !currentSymbols.isEmpty {
                    currentMenu["symbols"] = currentSymbols
                    menusArray.append(currentMenu)
                    currentSymbols = []
                }
                currentMenu = ["title": extractValue(from: trimmed)]
                inSymbolsSection = false
            } else if trimmed.contains("sort:") {
                currentMenu["sort"] = Int(extractValue(from: trimmed)) ?? 0
            } else if trimmed.contains("icon:") && !trimmed.contains("symbol_") {
                currentMenu["icon"] = extractValue(from: trimmed)
            } else if trimmed.hasPrefix("symbols:") {
                inSymbolsSection = true
            } else if trimmed.hasPrefix("- trigger:") && inSymbolsSection {
                // 开始新的符号
                let triggerString = extractValue(from: trimmed)
                let triggers = parseArrayValue(triggerString)

                currentSymbols.append([
                    "trigger": triggers,
                    "content": "",
                    "desc": ""
                ])
            } else if trimmed.contains("content:") && inSymbolsSection && !currentSymbols.isEmpty {
                currentSymbols[currentSymbols.count - 1]["content"] = extractValue(from: trimmed)
            } else if trimmed.contains("desc:") && inSymbolsSection && !currentSymbols.isEmpty {
                currentSymbols[currentSymbols.count - 1]["desc"] = extractValue(from: trimmed)
            }
        }

        // 添加最后一个菜单
        if !currentMenu.isEmpty && !currentSymbols.isEmpty {
            currentMenu["symbols"] = currentSymbols
            menusArray.append(currentMenu)
        }

        // 构建配置
        let metadata = SymbolMetadata(
            name: (metadataDict["name"] as? String) ?? "未命名配置",
            icon: (metadataDict["icon"] as? String) ?? "🔣",
            priority: (metadataDict["priority"] as? Int) ?? 1,
            enabled: (metadataDict["enabled"] as? Bool) ?? true
        )

        let global = SymbolGlobalConfig(
            triggerPrefix: (globalDict["trigger_prefix"] as? String) ?? ":/",
            autoHide: (globalDict["auto_hide"] as? Bool) ?? true,
            autoClean: (globalDict["auto_clean"] as? Bool) ?? true,
            panelPosition: (globalDict["panel_position"] as? String) ?? "cursor_bottom",
            panelWidth: (globalDict["panel_width"] as? String) ?? "auto"
        )

        let menus = try menusArray.map { menuDict -> SymbolMenu in
            guard let title = menuDict["title"] as? String else {
                throw SymbolConfigError.invalidMenuFormat
            }

            let sort = (menuDict["sort"] as? Int) ?? 0
            let icon = menuDict["icon"] as? String

            guard let symbolsArray = menuDict["symbols"] as? [[String: Any]] else {
                throw SymbolConfigError.invalidMenuFormat
            }

            let symbols = symbolsArray.compactMap { symbolDict -> SymbolItem? in
                guard let triggers = symbolDict["trigger"] as? [String],
                      let content = symbolDict["content"] as? String,
                      let desc = symbolDict["desc"] as? String else {
                    return nil
                }
                return SymbolItem(triggers: triggers, content: content, desc: desc)
            }

            return SymbolMenu(title: title, sort: sort, icon: icon, symbols: symbols)
        }

        return SymbolConfig(metadata: metadata, global: global, menus: menus)
    }

    /// 从行中提取值
    private func extractValue(from line: String) -> String {
        let components = line.split(separator: ":", maxSplits: 1)
        guard components.count == 2 else { return "" }

        var value = components[1].trimmingCharacters(in: .whitespaces)

        // 移除引号
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        } else if value.hasPrefix("'") && value.hasSuffix("'") {
            value = String(value.dropFirst().dropLast())
        }

        return value
    }

    /// 解析数组值 [a, b, c]
    private func parseArrayValue(_ value: String) -> [String] {
        var cleaned = value
        cleaned.removeFirst()
        cleaned.removeLast()

        let elements = cleaned.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { element in
                // 移除引号
                if element.hasPrefix("\"") && element.hasSuffix("\"") {
                    return String(element.dropFirst().dropLast())
                } else if element.hasPrefix("'") && element.hasSuffix("'") {
                    return String(element.dropFirst().dropLast())
                }
                return element
            }

        return elements
    }

    /// 清理文件名
    private func sanitizeFilename(_ name: String) -> String {
        var sanitized = name

        // 移除不安全的字符
        let invalidChars = CharacterSet(charactersIn: ":/\\?*|\"<>")
        sanitized = sanitized.components(separatedBy: invalidChars).joined(separator: "_")

        // 限制长度
        if sanitized.count > 100 {
            sanitized = String(sanitized.prefix(100))
        }

        return sanitized.isEmpty ? "unnamed" : sanitized
    }
}

// MARK: - Errors

extension SymbolConfigError {
    static var cannotDeleteDefault: SymbolConfigError {
        .custom("无法删除默认配置")
    }

    static var duplicateName: SymbolConfigError {
        .custom("配置名称已存在")
    }

    static var custom: (String) -> SymbolConfigError = { message in
        enum CustomError: LocalizedError {
            case custom(String)
            var errorDescription: String? {
                switch self {
                case .custom(let msg): return msg
                }
            }
        }
        return CustomError.custom(message) as! SymbolConfigError
    }
}
