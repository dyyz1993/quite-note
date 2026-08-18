import XCTest
@testable import QuiteNote

/// 符号触发检测 TDD 测试
/// 钉死的缺陷：
/// 1. emoji 库的 ":e" 前缀完全失效（检测器只认第一个配置的前缀 ":/"）
/// 2. 输入 URL（https:/）误触发符号面板（前缀无词边界约束）
/// 3. 检测与替换范围计算不一致（一个限 50 字符窗口，一个全文搜索）
/// 4. 跨配置同内容符号在建议列表中重复出现
/// 5. autoClean=false 时用错前缀长度
final class SymbolTriggerDetectionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TestStorageIsolation.activate
    }

    private func makeTempDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "symbol-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 表情符号库测试配置（触发前缀 :e，模拟 emoji.yaml）
    private func makeEmojiConfig(autoClean: Bool = true) -> SymbolConfig {
        SymbolConfig(
            metadata: SymbolMetadata(name: "表情符号库", icon: "😊", priority: 3, enabled: true),
            global: SymbolGlobalConfig(
                triggerPrefix: ":e", autoHide: true, autoClean: autoClean,
                panelPosition: "cursor_bottom", panelWidth: "auto"
            ),
            menus: [
                SymbolMenu(title: "笑脸", sort: 1, icon: "😊", symbols: [
                    SymbolItem(triggers: ["smile", "微笑"], content: "😊", desc: "微笑"),
                    SymbolItem(triggers: ["cry", "哭"], content: "😢", desc: "哭"),
                ]),
                SymbolMenu(title: "手势", sort: 2, icon: "👍", symbols: [
                    SymbolItem(triggers: ["ok", "好的"], content: "👍", desc: "好的"),
                ]),
            ]
        )
    }

    private func makeDetector(configs: [SymbolConfig]) -> SymbolTriggerDetector {
        let manager = SymbolConfigManager(symbolsDirectory: makeTempDirectory())
        manager.configs = configs
        return SymbolTriggerDetector(configManager: manager)
    }

    // MARK: - 前缀定位（词边界 + 多前缀 + 就近匹配）

    func testLocateTrigger_FindsNearestPrefixAmongMultiple() {
        let text = "a :/x b :ey" as NSString
        let ctx = SymbolTriggerDetector.locateTrigger(nsText: text, cursor: 11, prefixes: [":/", ":e"])
        XCTAssertNotNil(ctx)
        XCTAssertEqual(ctx?.prefix, ":e")
        XCTAssertEqual(ctx?.range, NSRange(location: 8, length: 2))
    }

    func testLocateTrigger_URLSchemeIsRejectedByWordBoundary() {
        // "https:/" 里的 ":/" 前一个字符是字母 s，属于 URL scheme，不应触发
        let text = "https:/" as NSString
        let ctx = SymbolTriggerDetector.locateTrigger(nsText: text, cursor: 7, prefixes: [":/"])
        XCTAssertNil(ctx, "输入 URL 时不应触发符号联想")
    }

    func testLocateTrigger_SkipsRejectedOccurrenceToEarlierValidOne() {
        // 窗口内有两个 ":/"：一个合法（前面是空格），一个在 URL 里（前面是字母）
        // 应回退到更早的合法那个，而不是整个前缀作废
        let text = "see :/hi and https:/" as NSString
        let ctx = SymbolTriggerDetector.locateTrigger(nsText: text, cursor: 20, prefixes: [":/"])
        XCTAssertNotNil(ctx)
        XCTAssertEqual(ctx?.range, NSRange(location: 4, length: 2))
    }

    func testLocateTrigger_CJKCharacterBeforePrefixStillTriggers() {
        // 中文后直接接 ":/" 是合法输入（中文不属于 ASCII 字母数字）
        let text = "你好:/ok" as NSString
        let ctx = SymbolTriggerDetector.locateTrigger(nsText: text, cursor: 6, prefixes: [":/"])
        XCTAssertNotNil(ctx)
        XCTAssertEqual(ctx?.prefix, ":/")
    }

    func testLocateTrigger_DigitBeforePrefixIsRejected() {
        // 数字也是词内字符（例如 "12:/" 不应触发）
        let text = "12:/" as NSString
        let ctx = SymbolTriggerDetector.locateTrigger(nsText: text, cursor: 4, prefixes: [":/"])
        XCTAssertNil(ctx)
    }

    func testLocateTrigger_LongerPrefixWinsAtSameLocation() {
        // ":e" 与 ":ex" 同时命中时取更长的（更精确的）
        let text = ":ex" as NSString
        let ctx = SymbolTriggerDetector.locateTrigger(nsText: text, cursor: 3, prefixes: [":e", ":ex"])
        XCTAssertEqual(ctx?.prefix, ":ex")
    }

    func testLocateTrigger_EmptyPrefixesReturnsNil() {
        let ctx = SymbolTriggerDetector.locateTrigger(nsText: ":/x" as NSString, cursor: 3, prefixes: [])
        XCTAssertNil(ctx)
    }

    // MARK: - 端到端检测（detectTrigger）

    func testDetect_EmojiPrefixProducesSuggestions() {
        // emoji 库触发前缀 ":e" 必须可用——修复前检测器只认 ":/"，":e" 永远检不到
        let detector = makeDetector(configs: [SymbolConfig.defaultConfig, makeEmojiConfig()])
        detector.detectTrigger(in: "hi :esmile", cursorPosition: 10)
        XCTAssertNotNil(detector.detectedTrigger, "':e' 前缀应触发检测")
        XCTAssertEqual(detector.detectedTrigger, "smile")
        let contents = detector.suggestions.map(\.content)
        XCTAssertTrue(contents.contains("😊"), "应包含表情库的微笑符号，实际: \(contents)")
    }

    func testDetect_EmojiPrefixChineseTrigger() {
        let detector = makeDetector(configs: [SymbolConfig.defaultConfig, makeEmojiConfig()])
        detector.detectTrigger(in: ":e微笑", cursorPosition: 4) // ":e微笑" = 4 个 UTF-16 单位
        XCTAssertEqual(detector.detectedTrigger, "微笑")
        XCTAssertTrue(detector.suggestions.map(\.content).contains("😊"))
    }

    func testDetect_URLOpeningDoesNotTriggerPanel() {
        // 修复前：输入 "https:/" 会立刻弹出全部符号面板，按 Enter 还会吃掉 URL 前缀
        let detector = makeDetector(configs: [SymbolConfig.defaultConfig])
        detector.detectTrigger(in: "https:/", cursorPosition: 7)
        XCTAssertNil(detector.detectedTrigger, "输入 URL 前缀不应触发符号联想")
        XCTAssertTrue(detector.suggestions.isEmpty)
    }

    func testDetect_EmptyTriggerListsSymbolsOfMatchingConfigOnly() {
        // 输入裸前缀 ":e" 应列出表情库的符号，而不是所有配置的大杂烩
        let detector = makeDetector(configs: [SymbolConfig.defaultConfig, makeEmojiConfig()])
        detector.detectTrigger(in: ":e", cursorPosition: 2)
        XCTAssertNotNil(detector.detectedTrigger)
        XCTAssertEqual(detector.detectedTrigger, "")
        let contents = Set(detector.suggestions.map(\.content))
        XCTAssertFalse(contents.isEmpty)
        XCTAssertTrue(contents.isSubset(of: ["😊", "😢", "👍"]),
                      "空触发词只应展示 ':e' 所属配置的符号，实际: \(contents)")
    }

    func testDetect_DefaultPrefixStillWorks() {
        let detector = makeDetector(configs: [SymbolConfig.defaultConfig, makeEmojiConfig()])
        detector.detectTrigger(in: "todo :/bug", cursorPosition: 10)
        XCTAssertEqual(detector.detectedTrigger, "bug")
        XCTAssertEqual(detector.suggestions.first?.content, "🐛")
    }

    // MARK: - 检测与替换范围一致性

    func testReplacementRangeMatchesDetectionPosition() {
        // 修复前 detect 限 50 字符窗口、getReplacementRange 全文搜索，早先输入的 ":/" 会替换错位置
        let detector = makeDetector(configs: [SymbolConfig.defaultConfig])
        detector.detectTrigger(in: "x :/ok", cursorPosition: 6)
        let detectedPosition = detector.triggerPosition
        XCTAssertEqual(detectedPosition, NSRange(location: 2, length: 4))
        let replacement = detector.getReplacementRange(in: "x :/ok", cursorPosition: 6)
        XCTAssertEqual(replacement, detectedPosition,
                       "替换范围必须与检测到的触发位置一致，否则会替换掉错误文本")
    }

    // MARK: - 建议列表去重与排序

    func testDetect_SameContentAcrossConfigsIsDeduplicated() {
        // defaultConfig 与 englishConfig 都有 bug→🐛，修复前建议列表出现两条 🐛
        let detector = makeDetector(configs: [SymbolConfig.defaultConfig, SymbolConfig.englishConfig])
        detector.detectTrigger(in: ":/bug", cursorPosition: 5)
        XCTAssertFalse(detector.suggestions.isEmpty)
        let contents = detector.suggestions.map(\.content)
        XCTAssertEqual(contents.filter { $0 == "🐛" }.count, 1,
                       "跨配置同内容符号应去重，实际: \(contents)")
    }

    func testDetect_ExactMatchRanksFirst() {
        let detector = makeDetector(configs: [SymbolConfig.defaultConfig])
        detector.detectTrigger(in: ":/bug", cursorPosition: 5)
        XCTAssertEqual(detector.suggestions.first?.content, "🐛", "精确匹配应排第一")
    }

    // MARK: - 插入与光标（UTF-16 坐标系）

    func testInsertSymbol_ReplacesTriggerAndPrefix_PutsCursorAfterSymbol() {
        let detector = makeDetector(configs: [SymbolConfig.defaultConfig])
        // 前文有 emoji（UTF-16 占 2 位），验证光标按 NSString 坐标计算
        let text = "🎉:/bug" // 🎉(0-1) :(2) /(3) b(4) u(5) g(6)，光标 7
        detector.detectTrigger(in: text, cursorPosition: 7)
        XCTAssertEqual(detector.suggestions.first?.content, "🐛", "\"bug\" 应精确匹配到 🐛")
        guard let bug = detector.suggestions.first else {
            return XCTFail("应有建议")
        }
        let result = detector.insertSymbol(bug.symbol, into: text, cursorPosition: 7)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.newText, "🎉🐛")
        XCTAssertEqual(result?.newCursorPos, 4, "新光标 = 2(🎉) + 2(🐛) 的 UTF-16 长度")
    }

    func testInsertSymbol_AutoCleanDisabledKeepsMatchedPrefix() {
        // autoClean=false 时只替换触发词、保留前缀；多前缀下必须用实际匹配到的 ":e" 而非写死 ":/"
        let detector = makeDetector(configs: [makeEmojiConfig(autoClean: false)])
        let text = ":esmile"
        detector.detectTrigger(in: text, cursorPosition: 7)
        guard let smile = detector.suggestions.first(where: { $0.content == "😊" }) else {
            return XCTFail("应匹配到微笑，实际: \(detector.suggestions.map(\.content))")
        }
        let result = detector.insertSymbol(smile.symbol, into: text, cursorPosition: 7)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.newText, ":e😊", "应保留 ':e' 前缀只替换触发词")
        XCTAssertEqual(result?.newCursorPos, 4, "光标 = 2(:e) + 2(😊) 的 UTF-16 长度")
    }
}
