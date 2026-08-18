import XCTest
@testable import QuiteNote

/// 符号配置管理器 TDD 测试
/// 钉死的缺陷：
/// 1. SymbolConfigError.custom 的 as! 强转必崩（导入重名配置 = 应用闪退）
/// 2. 配置目录为空且 bundle 无资源时 loadConfigs 无限递归（测试环境/CI 必现）
/// 3. 删除/编辑从 bundle 复制的配置（emoji.yaml 等小写文件名）时按名字找文件，必然失败或残留重复文件
/// 4. plist 兼容声明存在但从未生效（plist 文件被当 YAML 解析，每次启动报错）
/// 5. 存储目录硬编码，测试进程读生产数据、dev 变体与生产共享目录（数据隔离红线）
final class SymbolConfigManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TestStorageIsolation.activate
    }

    private func makeTempDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "symbol-config-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 把配置以指定文件名写入目录（模拟 bundle 复制出来的小写文件名，如 emoji.yaml）
    private func writeConfig(_ config: SymbolConfig, as filename: String, in dir: URL) {
        let url = dir.appendingPathComponent(filename)
        try! config.toYaml().write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - 错误构造不再崩溃

    func testDuplicateNameErrorCarriesReadableMessage() {
        // 修复前：SymbolConfigError.duplicateName 内部 as! 强转不相关类型，访问即 SIGTRAP
        let error = SymbolConfigError.duplicateName
        XCTAssertEqual(error.localizedDescription, "配置名称已存在")
    }

    func testCannotDeleteDefaultErrorCarriesReadableMessage() {
        let error = SymbolConfigError.cannotDeleteDefault
        XCTAssertEqual(error.localizedDescription, "无法删除默认配置")
    }

    // MARK: - 导入 / 删除

    func testImportDuplicateNameThrowsCleanErrorInsteadOfCrashing() {
        let dir = makeTempDirectory()
        let manager = SymbolConfigManager(symbolsDirectory: dir)
        writeConfig(SymbolConfig.defaultConfig, as: "default.yaml", in: dir)
        manager.loadConfigs()
        XCTAssertFalse(manager.configs.isEmpty)

        // 导入与现有配置同名的 YAML：应抛可读错误，而不是崩溃
        let yaml = SymbolConfig.defaultConfig.toYaml()
        XCTAssertThrowsError(try manager.importConfig(fromYAML: yaml)) { error in
            XCTAssertEqual((error as? SymbolConfigError)?.localizedDescription, "配置名称已存在")
        }
    }

    func testDeleteDefaultConfigThrowsCleanError() {
        let dir = makeTempDirectory()
        writeConfig(SymbolConfig.defaultConfig, as: "default.yaml", in: dir)
        let manager = SymbolConfigManager(symbolsDirectory: dir)
        manager.loadConfigs()

        let defaultConfig = manager.configs.first { $0.metadata.name == "默认符号库" }
        XCTAssertNotNil(defaultConfig)
        XCTAssertThrowsError(try manager.deleteConfig(defaultConfig!)) { error in
            XCTAssertEqual((error as? SymbolConfigError)?.localizedDescription, "无法删除默认配置")
        }
    }

    func testDeleteBundleNamedConfigRemovesOriginalFile() {
        // emoji.yaml 的 metadata.name 是「表情符号库」，删除时必须删掉磁盘上的 emoji.yaml
        // 修复前：按名字找「表情符号库.yaml」→ 文件不存在 → 抛错，配置永远删不掉
        let dir = makeTempDirectory()
        let emoji = SymbolConfig(
            metadata: SymbolMetadata(name: "表情符号库", icon: "😊", priority: 3, enabled: true),
            global: .default,
            menus: [SymbolMenu(title: "笑脸", sort: 1, icon: "😊", symbols: [
                SymbolItem(triggers: ["smile"], content: "😊", desc: "微笑"),
            ])]
        )
        writeConfig(emoji, as: "emoji.yaml", in: dir)

        let manager = SymbolConfigManager(symbolsDirectory: dir)
        manager.loadConfigs()
        let loaded = manager.configs.first { $0.metadata.name == "表情符号库" }
        XCTAssertNotNil(loaded, "应加载出表情符号库")

        XCTAssertNoThrow(try manager.deleteConfig(loaded!))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("emoji.yaml").path),
                       "应删除原始的 emoji.yaml")
        XCTAssertTrue(manager.configs.filter { $0.metadata.name == "表情符号库" }.isEmpty)
    }

    func testSaveLoadedConfigOverwritesSameFileWithoutDuplicates() {
        // 编辑内置配置（如表情符号库）后保存：必须覆写原文件
        // 修复前：按名字写「表情符号库.yaml」，旧的 emoji.yaml 仍在 → 重启后同一配置加载两份
        let dir = makeTempDirectory()
        writeConfig(SymbolConfig.englishConfig, as: "english.yaml", in: dir)

        let manager = SymbolConfigManager(symbolsDirectory: dir)
        manager.loadConfigs()
        guard let loaded = manager.configs.first(where: { $0.metadata.name == "English Symbols" }) else {
            return XCTFail("应加载出 English Symbols")
        }
        XCTAssertNoThrow(try manager.saveConfig(loaded))

        let files = try! FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".yaml") || $0.hasSuffix(".yml") }
        XCTAssertEqual(files.count, 1, "保存后不应产生重复配置文件，实际: \(files)")
        XCTAssertEqual(files.first, "english.yaml", "应覆写原文件而不是新建名字文件")
    }

    // MARK: - 空目录不递归

    func testLoadConfigsOnEmptyDirectoryTerminatesWithFallback() {
        // 修复前：目录空 + bundle 复制失败（测试进程 Bundle.main 无 Symbols 资源）
        // → loadConfigs 无限递归 → 栈溢出挂死
        let dir = makeTempDirectory()
        let manager = SymbolConfigManager(symbolsDirectory: dir)
        manager.loadConfigs()
        XCTAssertFalse(manager.configs.isEmpty, "空目录应回退到内置默认配置，保证功能可用")
        XCTAssertTrue(manager.configs.contains { $0.metadata.name == "默认符号库" })
    }

    // MARK: - plist 兼容

    func testLegacyPlistConfigLoads() {
        // 修复前：plist 文件走 Yams 解析必然失败（loadPlist 从未被调用）
        let dir = makeTempDirectory()
        let plistData = try! PropertyListSerialization.data(
            fromPropertyList: SymbolConfig.englishConfig.toDict(), format: .xml, options: 0)
        try! plistData.write(to: dir.appendingPathComponent("legacy.plist"))

        let manager = SymbolConfigManager(symbolsDirectory: dir)
        manager.loadConfigs()
        XCTAssertTrue(manager.configs.contains { $0.metadata.name == "English Symbols" },
                     "旧版 plist 配置应能加载，实际加载: \(manager.configs.map { $0.metadata.name })")
    }

    // MARK: - 存储隔离（数据隔离红线）

    func testDefaultSymbolsDirectoryHonorsTestRoot() {
        TestStorageIsolation.activate
        let dir = SymbolConfigManager.defaultSymbolsDirectory()
        XCTAssertTrue(dir.path.contains("qn-isolated-storage"),
                      "测试进程的符号目录必须落在 QN_TEST_STORAGE_ROOT 内，实际: \(dir.path)")
        XCTAssertFalse(dir.path.contains("/Application Support/"),
                       "测试进程的符号目录绝不能指向生产目录，实际: \(dir.path)")
    }

    func testDefaultSymbolsDirectorySeparatesDevVariant() {
        // dev 变体（com.quitenote.app.dev）必须与生产目录隔离
        let devDir = SymbolConfigManager.resolveSymbolsDirectory(
            bundleIdentifier: "com.quitenote.app.dev",
            executablePath: "/Applications/Quite Note Dev.app/Contents/MacOS/Quite Note")
        XCTAssertTrue(devDir.path.contains("QuiteNote-Debug"),
                      "dev 变体应使用独立目录，实际: \(devDir.path)")

        let prodDir = SymbolConfigManager.resolveSymbolsDirectory(
            bundleIdentifier: "com.quitenote.app",
            executablePath: "/Applications/Quite Note.app/Contents/MacOS/Quite Note")
        XCTAssertTrue(prodDir.path.contains("QuiteNote/Symbols"),
                      "生产目录保持既有路径（存量用户数据不迁移），实际: \(prodDir.path)")
    }

    // MARK: - YAML 往返

    func testYamlRoundTripPreservesConfig() throws {
        let original = SymbolConfig.defaultConfig
        let yaml = original.toYaml()
        let parsed = try SymbolConfig.from(yaml: yaml)
        XCTAssertEqual(parsed.metadata.name, original.metadata.name)
        XCTAssertEqual(parsed.metadata.priority, original.metadata.priority)
        XCTAssertEqual(parsed.menus.count, original.menus.count)
        XCTAssertEqual(parsed.menus.flatMap { $0.symbols.map { $0.content } },
                       original.menus.flatMap { $0.symbols.map { $0.content } })
    }

    func testYamlRoundTripHandlesQuotesInContent() throws {
        // toYaml 手拼字符串，内容含引号时必须正确转义，否则导出的配置无法再导入
        let config = SymbolConfig(
            metadata: SymbolMetadata(name: "引号库", icon: "🔣", priority: 5, enabled: true),
            global: .default,
            menus: [SymbolMenu(title: "测试", sort: 1, symbols: [
                SymbolItem(triggers: ["q"], content: "\"引用\"", desc: "含双引号的描述 \"quote\""),
                SymbolItem(triggers: ["b"], content: "反斜杠\\测试", desc: "含反斜杠"),
            ])]
        )
        let parsed = try SymbolConfig.from(yaml: config.toYaml())
        XCTAssertEqual(parsed.menus[0].symbols[0].content, "\"引用\"")
        XCTAssertEqual(parsed.menus[0].symbols[0].desc, "含双引号的描述 \"quote\"")
        XCTAssertEqual(parsed.menus[0].symbols[1].content, "反斜杠\\测试")
    }
}
