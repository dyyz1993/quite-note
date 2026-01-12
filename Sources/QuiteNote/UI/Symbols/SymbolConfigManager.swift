import Foundation
import Combine
import os.log
import Yams

// MARK: - Symbol Configuration Manager

/// 符号配置管理器 - 单例
class SymbolConfigManager: ObservableObject {
    static let shared = SymbolConfigManager()

    // os_log logger
    private let logger = OSLog(subsystem: "com.quitenote.symbol", category: "ConfigManager")

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

            // 加载所有 YAML 文件（同时支持 .yaml 和 .yml）
            let yamlFiles = files.filter { $0.pathExtension == "yaml" || $0.pathExtension == "yml" }

            for file in yamlFiles {
                if let config = try? loadConfig(from: file) {
                    loadedConfigs.append(config)
                }
            }

            // 兼容旧的 plist 格式
            let plistFiles = files.filter { $0.pathExtension == "plist" }
            for file in plistFiles {
                if let config = try? loadConfig(from: file) {
                    loadedConfigs.append(config)
                }
            }
        } catch {
            print("[SymbolConfigManager] 无法读取配置目录: \(error)")
        }

        // 补充缺失的默认配置文件
        copyMissingDefaultConfigs()

        // 如果用户目录为空，重新加载
        if loadedConfigs.isEmpty {
            print("[SymbolConfigManager] 配置目录为空，从 bundle 复制默认配置")
            copyMissingDefaultConfigs()
            // 重新加载
            return loadConfigs()
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
        if let bundleURL = Bundle.main.url(forResource: "default", withExtension: "yaml", subdirectory: "Symbols") {
            print("[SymbolConfigManager] 从 bundle 加载配置: \(bundleURL.path)")
            return try? loadConfig(from: bundleURL)
        }

        print("[SymbolConfigManager] ⚠️ bundle 中未找到 default.yaml")
        return nil
    }

    /// 从文件加载配置
    func loadConfig(from url: URL) throws -> SymbolConfig {
        let data = try Data(contentsOf: url)

        // 使用 Yams 解析 YAML
        let yamlString = String(data: data, encoding: .utf8) ?? ""
        print("[SymbolConfigManager] Loading YAML from: \(url.path)")

        guard let yamlDict = try Yams.load(yaml: yamlString) as? [String: Any] else {
            print("[SymbolConfigManager] ❌ Failed to parse YAML with Yams")
            throw SymbolConfigError.invalidFormat
        }

        print("[SymbolConfigManager] ✅ YAML parsed successfully with Yams")
        print("[SymbolConfigManager] Keys: \(yamlDict.keys)")

        return try SymbolConfig.parse(from: yamlDict)
    }

    /// 从 plist 数据加载配置
    private func loadPlist(data: Data) throws -> SymbolConfig {
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw SymbolConfigError.invalidFormat
        }

        return try SymbolConfig.parse(from: plist)
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
    func importConfig(fromYAML yamlString: String) throws -> SymbolConfig {
        // 使用 Yams 库解析 YAML 字符串
        guard let yamlDict = try Yams.load(yaml: yamlString) as? [String: Any] else {
            throw SymbolConfigError.invalidFormat
        }

        let config = try SymbolConfig.parse(from: yamlDict)

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
        let enabled = configs.filter { $0.metadata.enabled }
        os_log("[SymbolConfigManager] enabledConfigs: %d 个配置", type: .info, enabled.count)
        for config in enabled {
            os_log("[SymbolConfigManager]   - %@: %d 个菜单", type: .info, config.metadata.name, config.menus.count)
            for menu in config.menus {
                os_log("[SymbolConfigManager]     - %@ (icon: %@): %d 个符号", type: .info, menu.title, menu.icon ?? "nil", menu.symbols.count)
            }
        }
        return enabled
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

    /// 从 bundle 复制缺失的默认配置文件到用户目录
    private func copyMissingDefaultConfigs() {
        // 需要复制的配置文件列表
        let configFiles = ["default", "english", "emoji"]

        for configName in configFiles {
            let destinationURL = symbolsDirectory.appendingPathComponent("\(configName).yaml")

            // 如果目标文件不存在，才从 bundle 复制
            if !fileManager.fileExists(atPath: destinationURL.path) {
                if let bundleURL = Bundle.main.url(forResource: configName, withExtension: "yaml", subdirectory: "Symbols") {
                    do {
                        try fileManager.copyItem(at: bundleURL, to: destinationURL)
                        print("[SymbolConfigManager] ✅ 复制 \(configName).yaml 到用户目录")
                    } catch {
                        print("[SymbolConfigManager] ❌ 复制 \(configName).yaml 失败: \(error)")
                    }
                } else {
                    print("[SymbolConfigManager] ⚠️ bundle 中未找到 \(configName).yaml")
                }
            }
        }
    }

    /// 保存默认配置到文件（同时保存中文和英文配置）
    private func saveDefaultConfig() {
        // 保存中文默认配置
        let defaultConfig = SymbolConfig.defaultConfig
        let plistURL = symbolsDirectory.appendingPathComponent("default.plist")

        // 使用 PropertyListSerialization 保存 plist
        if let plistData = try? PropertyListSerialization.data(fromPropertyList: defaultConfig.toDict(), format: .xml, options: 0) {
            try? plistData.write(to: plistURL)
        }

        // 保存英文配置
        let englishConfig = SymbolConfig.englishConfig
        let englishURL = symbolsDirectory.appendingPathComponent("english.plist")

        if let englishData = try? PropertyListSerialization.data(fromPropertyList: englishConfig.toDict(), format: .xml, options: 0) {
            try? englishData.write(to: englishURL)
        }

        print("[SymbolConfigManager] ✅ Saved default configs (Chinese + English)")
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
