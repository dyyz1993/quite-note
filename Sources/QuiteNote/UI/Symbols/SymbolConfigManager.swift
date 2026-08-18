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
    private let storageDirectory: URL
    /// config id → 源文件名。内置配置从 bundle 复制时文件名（如 emoji.yaml）与配置名不一致，
    /// 保存/删除必须回写原文件，否则会产生重复文件或删除失败
    private var sourceFileNames: [UUID: String] = [:]

    var symbolsDirectory: URL { storageDirectory }

    // MARK: - Initialization

    /// - Parameter symbolsDirectory: 符号配置目录；默认按测试隔离 / dev 变体规则解析（见 defaultSymbolsDirectory）
    init(symbolsDirectory: URL? = nil) {
        self.storageDirectory = symbolsDirectory ?? Self.defaultSymbolsDirectory()
        try? fileManager.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
        loadConfigs()
    }

    /// 符号配置目录解析（与 CoreDataStack 的隔离策略保持一致）
    ///
    /// 优先级：
    /// 1. QN_TEST_STORAGE_ROOT（测试进程整体重定向，绝不读写生产数据）
    /// 2. dev/debug 变体（Bundle ID 含 dev/debug 或 .build 路径）→ QuiteNote-Debug/Symbols
    /// 3. 生产 → QuiteNote/Symbols（保持既有路径，存量用户数据不迁移）
    static func defaultSymbolsDirectory(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.quitenote.app",
        executablePath: String = Bundle.main.executableURL?.path ?? ""
    ) -> URL {
        if let testRoot = ProcessInfo.processInfo.environment["QN_TEST_STORAGE_ROOT"] {
            return URL(fileURLWithPath: testRoot, isDirectory: true)
                .appendingPathComponent("Symbols", isDirectory: true)
        }
        return resolveSymbolsDirectory(bundleIdentifier: bundleIdentifier, executablePath: executablePath)
    }

    /// dev/debug 与生产目录解析（纯函数，可单测）
    static func resolveSymbolsDirectory(bundleIdentifier: String, executablePath: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let isDebug = bundleIdentifier.contains("debug") || bundleIdentifier.contains("dev") || executablePath.contains(".build")
        let dirName = isDebug ? "QuiteNote-Debug" : "QuiteNote"
        return appSupport.appendingPathComponent(dirName, isDirectory: true)
            .appendingPathComponent("Symbols", isDirectory: true)
    }

    // MARK: - Public Methods

    /// 加载所有配置
    func loadConfigs() {
        isLoading = true
        defer { isLoading = false }

        var loadedConfigs = loadFromDirectory()

        if loadedConfigs.isEmpty {
            // 首次运行：从 bundle 复制默认配置后重读一次（只重试一次，绝不递归调用自身）
            copyMissingDefaultConfigs()
            loadedConfigs = loadFromDirectory()
        }

        if loadedConfigs.isEmpty {
            // bundle 中也没有资源（测试环境等）：回退到内置默认配置，保证功能可用且不挂死
            os_log("[SymbolConfigManager] 配置目录与 bundle 均为空，回退内置默认配置", type: .info)
            loadedConfigs = [SymbolConfig.defaultConfig, SymbolConfig.englishConfig]
        }

        loadedConfigs.sort { $0.metadata.priority < $1.metadata.priority }
        configs = loadedConfigs
        errorMessage = nil
    }

    /// 从目录读取配置（按文件名稳定排序，保证跨启动的加载顺序一致）
    private func loadFromDirectory() -> [SymbolConfig] {
        sourceFileNames.removeAll()
        var loadedConfigs: [SymbolConfig] = []

        let files = (try? fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let config: SymbolConfig
            do {
                switch file.pathExtension.lowercased() {
                case "yaml", "yml":
                    config = try loadConfig(from: file)
                case "plist":
                    let data = try Data(contentsOf: file)
                    config = try loadPlist(data: data)
                default:
                    continue
                }
                loadedConfigs.append(config)
                sourceFileNames[config.id] = file.lastPathComponent
            } catch {
                print("[SymbolConfigManager] ❌ 加载配置失败: \(file.lastPathComponent) - \(error)")
            }
        }
        return loadedConfigs
    }

    /// 从文件加载配置
    func loadConfig(from url: URL) throws -> SymbolConfig {
        let data = try Data(contentsOf: url)
        let yamlString = String(data: data, encoding: .utf8) ?? ""

        guard let yamlDict = try Yams.load(yaml: yamlString) as? [String: Any] else {
            throw SymbolConfigError.invalidFormat
        }

        return try SymbolConfig.parse(from: yamlDict)
    }

    /// 从 plist 数据加载配置（旧版格式兼容）
    private func loadPlist(data: Data) throws -> SymbolConfig {
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw SymbolConfigError.invalidFormat
        }
        return try SymbolConfig.parse(from: plist)
    }

    /// 保存配置（优先覆写该配置的源文件，避免按配置名找文件导致残留/重复）
    func saveConfig(_ config: SymbolConfig) throws {
        let filename = sourceFileNames[config.id] ?? "\(sanitizeFilename(config.metadata.name)).yaml"
        let fileURL = storageDirectory.appendingPathComponent(filename)

        try config.toYaml().write(to: fileURL, atomically: true, encoding: .utf8)
        sourceFileNames[config.id] = filename

        // 更新内存中的配置
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
        } else {
            configs.append(config)
        }

        // 重新排序
        configs.sort { $0.metadata.priority < $1.metadata.priority }
    }

    /// 删除配置（默认配置不允许删除）
    func deleteConfig(_ config: SymbolConfig) throws {
        if config.metadata.name == "默认符号库" {
            throw SymbolConfigError.cannotDeleteDefault
        }

        let filename = sourceFileNames[config.id] ?? "\(sanitizeFilename(config.metadata.name)).yaml"
        let fileURL = storageDirectory.appendingPathComponent(filename)

        try fileManager.removeItem(at: fileURL)
        sourceFileNames[config.id] = nil

        // 从内存中移除
        configs.removeAll { $0.id == config.id }
    }

    /// 导入配置
    func importConfig(fromYAML yamlString: String) throws -> SymbolConfig {
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
        // 删除所有配置文件后重建目录
        try? fileManager.removeItem(at: storageDirectory)
        try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)

        // 以 YAML 写回内置默认配置（与正常保存格式一致；plist 仅作旧文件读取兼容）
        try? SymbolConfig.defaultConfig.toYaml()
            .write(to: storageDirectory.appendingPathComponent("default.yaml"), atomically: true, encoding: .utf8)
        try? SymbolConfig.englishConfig.toYaml()
            .write(to: storageDirectory.appendingPathComponent("english.yaml"), atomically: true, encoding: .utf8)

        // emoji.yaml 等仅存在于 bundle 的配置
        copyMissingDefaultConfigs()

        // 重新加载
        loadConfigs()
    }

    /// 搜索所有配置中的符号
    func searchSymbols(query: String) -> [SymbolItem] {
        guard !query.isEmpty else { return [] }

        var results: Set<SymbolItem> = []
        for config in configs where config.metadata.enabled {
            results.formUnion(config.search(query: query))
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
                map[trigger] = symbol
            }
        }
        return map
    }

    // MARK: - Private Methods

    /// 从 bundle 复制缺失的默认配置文件到用户目录
    private func copyMissingDefaultConfigs() {
        let configFiles = ["default", "english", "emoji"]

        for configName in configFiles {
            let destinationURL = storageDirectory.appendingPathComponent("\(configName).yaml")

            if fileManager.fileExists(atPath: destinationURL.path) { continue }
            guard let bundleURL = bundleURL(forResource: configName) else {
                print("[SymbolConfigManager] ⚠️ bundle 中未找到 \(configName).yaml")
                continue
            }
            do {
                try fileManager.copyItem(at: bundleURL, to: destinationURL)
            } catch {
                print("[SymbolConfigManager] ❌ 复制 \(configName).yaml 失败: \(error)")
            }
        }
    }

    /// bundle 资源查找：优先 Symbols 子目录（build-app.sh 打包形态），回退 bundle 根（SPM 处理后的形态）
    private func bundleURL(forResource name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "yaml", subdirectory: "Symbols")
            ?? Bundle.main.url(forResource: name, withExtension: "yaml")
            ?? Bundle(for: SymbolConfigManager.self).url(forResource: name, withExtension: "yaml", subdirectory: "Symbols")
    }

    /// 清理文件名
    private func sanitizeFilename(_ name: String) -> String {
        var sanitized = name

        let invalidChars = CharacterSet(charactersIn: ":/\\?*|\"<>")
        sanitized = sanitized.components(separatedBy: invalidChars).joined(separator: "_")

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
}
