import AppKit
import Combine
import SwiftUI
import XCTest
@testable import QuiteNote

/// 便利贴 Markdown 转换器（`StickyNoteMarkdown`）与编辑器修复的回归测试。
///
/// - 数据隔离：`TestStorageIsolation.activate`，不触达生产数据
/// - 不创建窗口：文本视图 / 滚动视图都不进窗口；撤销栈用子类注入的 UndoManager
/// - 不碰系统剪贴板：粘贴用独立命名的 pasteboard
@MainActor
final class StickyNoteMarkdownTests: XCTestCase {

    private typealias Markdown = StickyNoteMarkdown
    private var temporaryDirectories: [URL] = []

    override func setUp() {
        super.setUp()
        TestStorageIsolation.activate
    }

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
        super.tearDown()
    }

    // MARK: - 夹具

    /// 逐字符的语义属性签名（加粗/删除线/下划线/颜色/图标状态），用来比较两次渲染是否等价
    private func semanticSignature(_ attributed: NSAttributedString) -> [String] {
        let string = attributed.string as NSString
        var result: [String] = []
        for location in 0..<string.length {
            let attrs = attributed.attributes(at: location, effectiveRange: nil)
            var mark = ""
            if attrs[Markdown.boldKey] != nil { mark += "B" }
            if attrs[Markdown.strikethroughKey] != nil { mark += "S" }
            if attrs[Markdown.underlineKey] != nil { mark += "U" }
            if let hex = attrs[Markdown.colorKey] as? String { mark += "C(\(hex))" }
            if let checked = attrs[Markdown.todoIconKey] as? Bool { mark += checked ? "[x]" : "[ ]" }
            result.append("\(string.substring(with: NSRange(location: location, length: 1))):\(mark)")
        }
        return result
    }

    /// 规范写法：往返恒等 + 幂等 + 两轮渲染的属性逐字符一致
    private func assertRoundTrip(_ markdown: String, file: StaticString = #filePath, line: UInt = #line) {
        let rendered = Markdown.render(markdown)
        let once = Markdown.serialize(rendered)
        XCTAssertEqual(once, markdown, "往返不恒等", file: file, line: line)
        let twice = Markdown.serialize(Markdown.render(once))
        XCTAssertEqual(twice, once, "第二轮序列化结果变了", file: file, line: line)
        XCTAssertEqual(semanticSignature(Markdown.render(twice)), semanticSignature(rendered), "两轮渲染的属性不一致", file: file, line: line)
    }

    /// 非规范写法：第一轮归一化成 `expected`，显示效果不变，之后稳定
    private func assertNormalized(_ input: String, to expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let once = Markdown.serialize(Markdown.render(input))
        XCTAssertEqual(once, expected, file: file, line: line)
        XCTAssertEqual(Markdown.serialize(Markdown.render(once)), once, "归一化后应保持稳定", file: file, line: line)
        XCTAssertEqual(semanticSignature(Markdown.render(once)), semanticSignature(Markdown.render(input)), "归一化不应改变显示效果", file: file, line: line)
    }

    /// 只比较文本的归一化（待办的分隔空格被字距取代，显示效果本来就要变）：第一轮变成 `expected`，之后稳定
    private func assertNormalizedText(_ input: String, to expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let once = Markdown.serialize(Markdown.render(input))
        XCTAssertEqual(once, expected, file: file, line: line)
        XCTAssertEqual(Markdown.serialize(Markdown.render(once)), once, "归一化后应保持稳定", file: file, line: line)
    }

    /// 给一段文字加上工具栏会产生的那种属性（语义属性 + 对应的显示属性）
    private func applying(_ text: String, bold: NSRange? = nil, strikethrough: NSRange? = nil, underline: NSRange? = nil, color: (hex: String, range: NSRange)? = nil) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: Markdown.baseAttributes)
        if let range = bold {
            result.addAttribute(Markdown.boldKey, value: true, range: range)
            result.addAttribute(.font, value: Markdown.boldFont, range: range)
        }
        if let range = strikethrough {
            result.addAttribute(Markdown.strikethroughKey, value: true, range: range)
            result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        if let range = underline {
            result.addAttribute(Markdown.underlineKey, value: true, range: range)
            result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        if let (hex, range) = color {
            result.addAttribute(Markdown.colorKey, value: hex, range: range)
            if let nsColor = NSColor(hex: hex) {
                result.addAttribute(.foregroundColor, value: nsColor, range: range)
            }
        }
        return result
    }

    /// 编辑器的模型端：Binding 直接读写一个字符串
    private final class EditorModel {
        var text: String
        init(_ text: String) { self.text = text }
        var binding: Binding<String> {
            Binding(get: { self.text }, set: { self.text = $0 })
        }
    }

    /// 编辑器夹具：模型 + 协调器 + 不进窗口的文本视图（自带撤销栈）
    private final class EditorRig {
        final class Counter: @unchecked Sendable { var value = 0 }

        let model: EditorModel
        let commands: PassthroughSubject<StickyNoteCommand, Never>
        let coordinator: StickyNoteEditor.Coordinator
        let textView: StickyNoteTextView
        private let changeCount: Counter
        private var observers: [NSObjectProtocol] = []

        var changeNotifications: Int { changeCount.value }
        var storage: NSTextStorage { textView.textStorage! }
        var attributed: NSAttributedString { textView.attributedString() }

        init(modelText: String) {
            let model = EditorModel(modelText)
            let commands = PassthroughSubject<StickyNoteCommand, Never>()
            self.model = model
            self.commands = commands
            coordinator = StickyNoteEditor(
                text: model.binding,
                isFocused: false,
                onFocusChange: { _ in },
                commandPublisher: commands.eraseToAnyPublisher()
            ).makeCoordinator()
            textView = UndoableTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
            changeCount = Counter()

            textView.delegate = coordinator
            textView.allowsUndo = true
            textView.typingAttributes = Markdown.baseAttributes
            textView.textStorage?.setAttributedString(Markdown.render(modelText))
            coordinator.setupCommandSubscription(for: textView)
            let counter = changeCount
            observers.append(NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: textView, queue: nil) { _ in
                counter.value += 1
            })
        }

        deinit {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
        }
    }

    /// 无窗口时 NSTextView 取不到 window.undoManager；注入一个，用来验证「操作进了撤销栈」
    private final class UndoableTextView: StickyNoteTextView {
        private let privateUndoManager = UndoManager()
        override var undoManager: UndoManager? { privateUndoManager }
    }

    private func makeCoordinator(model: EditorModel, commands: PassthroughSubject<StickyNoteCommand, Never>? = nil) -> StickyNoteEditor.Coordinator {
        StickyNoteEditor(
            text: model.binding,
            isFocused: false,
            onFocusChange: { _ in },
            commandPublisher: commands?.eraseToAnyPublisher()
        ).makeCoordinator()
    }

    private func makeRig(_ markdown: String) -> EditorRig {
        EditorRig(modelText: markdown)
    }

    /// 走真实的组装路径（滚动视图 + 文本视图 + 符号检测订阅），同样不进窗口
    private func makeEditor(text: String) -> (model: EditorModel, coordinator: StickyNoteEditor.Coordinator, scrollView: NSScrollView) {
        let model = EditorModel(text)
        let coordinator = makeCoordinator(model: model)
        let scrollView = StickyNoteEditor.makeScrollView(text: text, coordinator: coordinator)
        scrollView.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        let textView = scrollView.documentView as! StickyNoteTextView
        textView.sizeToFit()
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        return (model, coordinator, scrollView)
    }

    private func drainMainQueue(rounds: Int = 3) {
        for _ in 0..<rounds {
            let drained = expectation(description: "main queue drained")
            DispatchQueue.main.async { drained.fulfill() }
            wait(for: [drained], timeout: 2)
        }
    }

    /// 发一条工具栏命令并等它送达（命令订阅走 RunLoop.main），同时核对模型与文本视图一致
    private func send(_ command: StickyNoteCommand, to rig: EditorRig, file: StaticString = #filePath, line: UInt = #line) {
        rig.commands.send(command)
        drainMainQueue()
        XCTAssertEqual(rig.model.text, rig.coordinator.lastSerializedMarkdown, "模型文本应与缓存的上次序列化结果一致", file: file, line: line)
        XCTAssertEqual(rig.model.text, Markdown.serialize(rig.attributed), "模型文本应等于文本视图当前内容的序列化结果", file: file, line: line)
    }

    private func undo(_ textView: NSTextView, file: StaticString = #filePath, line: UInt = #line) {
        guard let undoManager = textView.undoManager else {
            XCTFail("文本视图没有撤销栈", file: file, line: line)
            return
        }
        XCTAssertTrue(undoManager.canUndo, "操作没有进撤销栈", file: file, line: line)
        undoManager.undo()
        drainMainQueue()
    }

    private func hasAttribute(_ key: NSAttributedString.Key, in attributed: NSAttributedString, at location: Int) -> Bool {
        attributed.attribute(key, at: location, effectiveRange: nil) != nil
    }

    private func makeTemporaryDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "qn-markdown-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    /// 符号库：前缀 `:/`，一个符号 smile → 😊
    private func makeDetector(autoClean: Bool) -> (detector: SymbolTriggerDetector, smile: SymbolItem) {
        let manager = SymbolConfigManager(symbolsDirectory: makeTemporaryDirectory())
        let smile = SymbolItem(triggers: ["smile", "微笑"], content: "😊", desc: "微笑")
        manager.configs = [
            SymbolConfig(
                metadata: SymbolMetadata(name: "表情符号库", icon: "😊", priority: 3, enabled: true),
                global: SymbolGlobalConfig(triggerPrefix: ":/", autoHide: true, autoClean: autoClean, panelPosition: "cursor_bottom", panelWidth: "auto"),
                menus: [SymbolMenu(title: "笑脸", sort: 1, icon: "😊", symbols: [smile])]
            )
        ]
        return (SymbolTriggerDetector(configManager: manager), smile)
    }

    /// 50KB 出头的混合格式长文（多段落、待办、emoji）
    private func makeLargeMarkdown() -> String {
        var lines: [String] = []
        var total = 0
        var index = 0
        while total < 55 * 1024 {
            var line = "第 \(index) 行：普通文字 **加粗** ~~删除线~~ [c:60A5FA]彩色[/c] <u>下划线</u> 😀 收尾"
            if index % 4 == 0 { line += "\n- [ ] 待办事项" }
            if index % 9 == 0 { line += "\n" }
            lines.append(line)
            total += line.utf8.count
            index += 1
        }
        return lines.joined(separator: "\n")
    }

    private func elapsedMilliseconds(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    // MARK: - 往返恒等

    func testSingleLineFormatsRoundTrip() {
        for sample in ["**粗体**", "~~删除线~~", "<u>下划线</u>", "[c:60A5FA]彩色[/c]", "前缀 **粗体** 后缀",
                       "普通文字没有标记", "单个 * ~ < > [ 不成对", "2*3*4 和 a~b"] {
            assertRoundTrip(sample)
        }
    }

    func testNestedFormatsRoundTrip() {
        for sample in ["[c:60A5FA]**加粗**[/c]", "**a[c:60A5FA]bc[/c]d**", "[c:60A5FA]<u>~~**四层**~~</u>[/c]",
                       "前缀 [c:60A5FA]中间 ~~删~~ 后缀[/c] 尾巴", "[c:60A5FA]前[/c]<u>中</u>**后**",
                       "[c:60A5FA]一[/c][c:F87171]二[/c]", "[c:60A5FA]一[/c][c:60a5fa]二[/c]"] {
            assertRoundTrip(sample)
        }
    }

    func testTodoLinesRoundTrip() {
        for sample in ["- [ ] 待办", "- [x] 已办", "- [ ] 待办\n- [x] 已办\n- [ ] 再一条",
                       "行中间也有 - [ ] 待办", "- [ ]", "- [x]\n下一行", "- [ ]  两个空格开头", "- [ ] \t空格制表符", "\t- [x] 缩进"] {
            assertRoundTrip(sample)
        }
    }

    func testTodoWithInlineFormatsRoundTrip() {
        for sample in ["- [ ] **加粗待办**", "- [x] ~~已划掉~~", "[c:60A5FA]- [ ] 彩色待办[/c]", "**- [ ] 粗体待办**",
                       "- [ ] [c:F87171]红色[/c] 普通", "- [ ] 第一行\n**第二行加粗**\n- [x] 第三行"] {
            assertRoundTrip(sample)
        }
    }

    func testEmojiRoundTrip() {
        for sample in ["😀 **粗体** 🎉", "- [ ] 😀 表情", "[c:F87171]🎉[/c]", "😀**🎉**😁", "[c:4ADE80]👍[/c]👍",
                       "👨‍👩‍👧 家庭 - [x] 完成 **🚀**"] {
            assertRoundTrip(sample)
        }
    }

    func testMultilineFormatsRoundTrip() {
        for sample in ["**第一行\n第二行**", "[c:60A5FA]第一行\n第二行[/c]", "<u>a\nb</u>~~c\nd~~",
                       "第一行 **加粗\n继续** 第三行", "[c:60A5FA]跨行\n- [ ] 待办\n文字[/c]"] {
            assertRoundTrip(sample)
        }
    }

    func testHexCaseIsPreserved() {
        assertRoundTrip("[c:60a5fa]小写[/c]")
        assertRoundTrip("[c:60A5FA]大写[/c]")
        assertRoundTrip("[c:AbCdEf]混排[/c]")
        assertRoundTrip("[c:60a5fa]小写[/c][c:60A5FA]大写[/c]")
    }

    func testShortHexRoundTripsWithoutBeingRewritten() {
        assertRoundTrip("[c:123]三位[/c]")
        assertRoundTrip("[c:1234]四位[/c]")
        assertRoundTrip("[c:12345678]八位[/c]")
    }

    func testEmptyInput() {
        XCTAssertEqual(Markdown.render("").string, "")
        XCTAssertEqual(Markdown.serialize(NSAttributedString(string: "")), "")
        XCTAssertEqual(Markdown.plainText(""), "")
    }

    // MARK: - 交叉重叠 / 同一落点的嵌套顺序

    func testCrossingFormatsSerializeToEquivalentNesting() {
        // 加粗 abc，彩色 bcd：工具栏分两次选中不同范围就会出现这种交叉
        let original = applying("abcdef", bold: NSRange(location: 0, length: 3), color: (hex: "60A5FA", range: NSRange(location: 1, length: 3)))
        let once = Markdown.serialize(original)
        XCTAssertEqual(once, "**a[c:60A5FA]bc[/c]**[c:60A5FA]d[/c]ef")
        XCTAssertEqual(Markdown.serialize(Markdown.render(once)), once, "第二轮应稳定")
        XCTAssertEqual(semanticSignature(Markdown.render(once)), semanticSignature(original), "重渲染后每一段的格式应与原来一致")
    }

    func testOuterClosingBeforeInnerReopensInner() {
        // 删除线 abcd，下划线 bcde：外层先结束，内层要闭合后重开
        let original = applying("abcde", strikethrough: NSRange(location: 0, length: 4), underline: NSRange(location: 1, length: 4))
        let once = Markdown.serialize(original)
        XCTAssertEqual(once, "~~a<u>bcd</u>~~<u>e</u>")
        XCTAssertEqual(Markdown.serialize(Markdown.render(once)), once)
        XCTAssertEqual(semanticSignature(Markdown.render(once)), semanticSignature(original))
    }

    func testSameStartUsesFixedNestingOrder() {
        // 四种格式都从 0 开始、依次先结束：固定按 颜色 > 下划线 > 删除线 > 加粗
        let forward = applying("abcd", bold: NSRange(location: 0, length: 1), strikethrough: NSRange(location: 0, length: 2),
                               underline: NSRange(location: 0, length: 3), color: (hex: "60A5FA", range: NSRange(location: 0, length: 4)))
        XCTAssertEqual(Markdown.serialize(forward), "[c:60A5FA]<u>~~**a**b~~c</u>d[/c]")

        // 结束顺序反过来，同一落点的开始顺序仍然是这个
        let backward = applying("abcd", bold: NSRange(location: 0, length: 4), strikethrough: NSRange(location: 0, length: 3),
                                underline: NSRange(location: 0, length: 2), color: (hex: "60A5FA", range: NSRange(location: 0, length: 1)))
        let once = Markdown.serialize(backward)
        XCTAssertTrue(once.hasPrefix("[c:60A5FA]<u>~~**a"), "同一落点应按固定顺序开标记，实际: \(once)")
        XCTAssertEqual(Markdown.serialize(Markdown.render(once)), once)
        XCTAssertEqual(semanticSignature(Markdown.render(once)), semanticSignature(backward))
    }

    func testReopenedAndNewFormatsAtSamePositionUseFixedOrder() {
        // 下划线 ab，加粗 abcd，颜色从 c 开始：加粗在 c 处被重开，颜色也在此处新开
        let original = applying("abcd", bold: NSRange(location: 0, length: 4), underline: NSRange(location: 0, length: 2),
                                color: (hex: "F87171", range: NSRange(location: 2, length: 2)))
        let once = Markdown.serialize(original)
        XCTAssertEqual(once, "<u>**ab**</u>[c:F87171]**cd**[/c]")
        XCTAssertEqual(Markdown.serialize(Markdown.render(once)), once)
        XCTAssertEqual(semanticSignature(Markdown.render(once)), semanticSignature(original))
    }

    // MARK: - 归一化（非规范写法只改一次）

    /// 显示效果不变的归一化
    func testNonCanonicalFormattingIsNormalizedOnce() {
        assertNormalized("[c:#60A5FA]带井号[/c]", to: "[c:60A5FA]带井号[/c]")
        assertNormalized("**[c:60A5FA]加粗写在外面[/c]**", to: "[c:60A5FA]**加粗写在外面**[/c]")
        assertNormalized("**a****b**", to: "**ab**")
        assertNormalized("**~~粗删~~**", to: "~~**粗删**~~")
        assertNormalized("<u>**[c:4ADE80]由内到外[/c]**</u>", to: "[c:4ADE80]<u>**由内到外**</u>[/c]")
    }

    /// 待办的归一化：标记后的分隔空格/制表符换成字距，图标一律写成「标记 + 一个空格」
    func testNonCanonicalTodoIsNormalizedOnce() {
        assertNormalizedText("- [ ]文字", to: "- [ ] 文字")
        assertNormalizedText("- [ ]\t制表符", to: "- [ ] 制表符")
        assertNormalizedText("☐ 裸图标", to: "- [ ]  裸图标")
        assertNormalizedText("☐裸图标", to: "- [ ] 裸图标")
        assertNormalizedText("已办☑", to: "已办- [x]")
        assertNormalizedText("- [ ] ", to: "- [ ]")
        assertNormalizedText("- [x]\t", to: "- [x]")
    }

    // MARK: - 空行边界 / 未闭合

    func testInlineFormatsDoNotCrossBlankLines() {
        for sample in ["**a\n\nb**", "~~a\n \nb~~", "[c:60A5FA]a\n\t\nb[/c]", "<u>a\n\n\nb</u>", "[c:60A5FA]a\r\n\r\nb[/c]"] {
            let rendered = Markdown.render(sample)
            XCTAssertEqual(rendered.string, sample, "跨空行的标记应按字面保留")
            XCTAssertEqual(semanticSignature(rendered), semanticSignature(NSAttributedString(string: sample)), "跨空行不应叠加任何格式")
            assertRoundTrip(sample)
        }
    }

    func testFormatsWorkAgainAfterBlankLine() {
        let rendered = Markdown.render("段落一 **加粗**\n\n段落二 [c:60A5FA]颜色[/c]\n\n- [ ] 待办")
        XCTAssertEqual(rendered.string, "段落一 加粗\n\n段落二 颜色\n\n☐待办")
        XCTAssertEqual(semanticSignature(rendered).filter { $0.contains("B") }.count, 2)
        XCTAssertEqual(semanticSignature(rendered).filter { $0.contains("C(") }.count, 2)
    }

    func testUnclosedMarkersStayLiteral() {
        for sample in ["**没闭合", "~~没闭合", "<u>没闭合", "[c:60A5FA]没闭合", "落单的[/c]", "a ** b",
                       "**没闭合 [c:60A5FA]也没闭合"] {
            XCTAssertEqual(Markdown.render(sample).string, sample, "未闭合的标记应按字面保留")
            assertRoundTrip(sample)
        }
    }

    func testLoneClosingMarkerAfterAPairedOneStaysLiteral() {
        for (sample, visible) in [("前 **加粗** 后 **没闭合", "前 加粗 后 **没闭合"), ("<u>a</u> </u>", "a </u>")] {
            let rendered = Markdown.render(sample)
            XCTAssertEqual(rendered.string, visible)
            XCTAssertEqual(Markdown.serialize(rendered), sample, "成对的渲染、落单的字面保留，往返仍恒等")
        }
    }

    /// 内容为空的标记（一串星号当分隔线是常见写法）不能被当成空格式吃掉
    func testEmptySpansKeepTheirMarkers() {
        for sample in ["****", "********", "~~~~", "<u></u>", "[c:123][/c]", "分隔线****下一行"] {
            XCTAssertEqual(Markdown.render(sample).string, sample, sample)
            assertRoundTrip(sample)
        }
    }

    // MARK: - 渲染属性

    func testBoldRendersBoldFontAndFlag() {
        let rendered = Markdown.render("a**粗**b")
        XCTAssertEqual(rendered.string, "a粗b")
        let boldFont = rendered.attribute(.font, at: 1, effectiveRange: nil) as? NSFont
        XCTAssertEqual(boldFont, Markdown.boldFont)
        XCTAssertEqual(boldFont?.fontDescriptor.symbolicTraits.contains(.bold), true)
        XCTAssertEqual(rendered.attribute(Markdown.boldKey, at: 1, effectiveRange: nil) as? Bool, true)
        XCTAssertFalse(hasAttribute(Markdown.boldKey, in: rendered, at: 0))
        XCTAssertEqual(rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, Markdown.baseFont)
    }

    func testStrikethroughAndUnderlineRenderStyles() {
        let rendered = Markdown.render("~~删~~|<u>下</u>")
        XCTAssertEqual(rendered.string, "删|下")
        XCTAssertEqual(rendered.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(rendered.attribute(Markdown.strikethroughKey, at: 0, effectiveRange: nil) as? Bool, true)
        XCTAssertEqual(rendered.attribute(.underlineStyle, at: 2, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(rendered.attribute(Markdown.underlineKey, at: 2, effectiveRange: nil) as? Bool, true)
        XCTAssertNil(rendered.attribute(.strikethroughStyle, at: 2, effectiveRange: nil))
        XCTAssertNil(rendered.attribute(.underlineStyle, at: 0, effectiveRange: nil))
    }

    func testColorRendersForegroundColorAndHex() {
        let rendered = Markdown.render("a[c:60A5FA]彩[/c]b")
        XCTAssertEqual(rendered.attribute(Markdown.colorKey, at: 1, effectiveRange: nil) as? String, "60A5FA")
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor, NSColor(hex: "60A5FA"))
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, Markdown.textColor)
    }

    func testBaseStyleIsAppliedEverywhere() {
        let rendered = Markdown.render("第一行 **粗**\n第二行 - [ ] 待办 [c:F87171]红[/c]")
        var runCount = 0
        var sawIcon = false
        rendered.enumerateAttributes(in: NSRange(location: 0, length: rendered.length), options: []) { attrs, _, _ in
            runCount += 1
            let font = attrs[.font] as? NSFont
            let isIcon = (attrs[Markdown.todoIconKey] as? Bool) != nil
            sawIcon = sawIcon || isIcon
            XCTAssertEqual(font?.pointSize, isIcon ? Markdown.iconFontSize : Markdown.baseFontSize)
            XCTAssertNotNil(attrs[.foregroundColor])
            let paragraph = attrs[.paragraphStyle] as? NSParagraphStyle
            XCTAssertEqual(paragraph?.lineSpacing, 4)
            XCTAssertEqual(paragraph?.minimumLineHeight, 18)
            XCTAssertEqual(paragraph?.maximumLineHeight, 18)
        }
        XCTAssertGreaterThan(runCount, 0)
        XCTAssertTrue(sawIcon)
    }

    func testTodoIconAttributes() {
        let rendered = Markdown.render("- [ ] 未办\n- [x] 已办")
        XCTAssertEqual(rendered.string, "☐未办\n☑已办")
        XCTAssertEqual(rendered.attribute(Markdown.todoIconKey, at: 0, effectiveRange: nil) as? Bool, false)
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, NSColor.themeGray400)
        XCTAssertEqual(rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, Markdown.iconFont)
        XCTAssertEqual(rendered.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat, Markdown.todoIconGap)

        let checkedLocation = ("☐未办\n" as NSString).length
        XCTAssertEqual(rendered.attribute(Markdown.todoIconKey, at: checkedLocation, effectiveRange: nil) as? Bool, true)
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: checkedLocation, effectiveRange: nil) as? NSColor, NSColor.themeGreen400)
        XCTAssertEqual(rendered.attribute(.font, at: checkedLocation, effectiveRange: nil) as? NSFont, Markdown.iconFont)

        // 图标后面的正文回到基础样式，不带图标专用属性
        XCTAssertNil(rendered.attribute(Markdown.todoIconKey, at: 1, effectiveRange: nil))
        XCTAssertNil(rendered.attribute(.kern, at: 1, effectiveRange: nil))
        XCTAssertEqual(rendered.attribute(.font, at: 1, effectiveRange: nil) as? NSFont, Markdown.baseFont)
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor, Markdown.textColor)
    }

    func testIconGapMatchesASpace() {
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: Markdown.baseFont]).width
        XCTAssertEqual(Markdown.todoIconGap, spaceWidth, accuracy: 0.01)
    }

    func testIconInheritsEnclosingSemanticAttributes() {
        let colored = Markdown.render("[c:60A5FA]- [ ] x[/c]")
        XCTAssertEqual(colored.string, "☐x")
        XCTAssertEqual(colored.attribute(Markdown.colorKey, at: 0, effectiveRange: nil) as? String, "60A5FA")
        XCTAssertEqual(colored.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, NSColor(hex: "60A5FA"))

        let bold = Markdown.render("**- [ ] x**")
        XCTAssertEqual(bold.attribute(Markdown.boldKey, at: 0, effectiveRange: nil) as? Bool, true)
        XCTAssertEqual(bold.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, Markdown.boldIconFont)
    }

    // MARK: - hex

    func testInvalidHexMarkersKeepUserText() {
        for sample in ["[c:12345]重要[/c]", "[c:12]重要[/c]", "[c:1234567]重要[/c]", "[c:123456789]重要[/c]",
                       "[c:xyz]重要[/c]", "[c:]重要[/c]", "[c:60A5FG]重要[/c]", "[c:１２３]全角数字[/c]"] {
            XCTAssertEqual(Markdown.render(sample).string, sample, "位数不合法的标记不能删掉用户文字")
            assertRoundTrip(sample)
        }
    }

    func testShortHexExpandsToColor() {
        let rgb = Markdown.color(fromHex: "123")?.usingColorSpace(.sRGB)
        XCTAssertEqual(rgb?.redComponent ?? -1, 0x11 / 255.0, accuracy: 0.002)
        XCTAssertEqual(rgb?.greenComponent ?? -1, 0x22 / 255.0, accuracy: 0.002)
        XCTAssertEqual(rgb?.blueComponent ?? -1, 0x33 / 255.0, accuracy: 0.002)

        let translucent = Markdown.color(fromHex: "1234")?.usingColorSpace(.sRGB)
        XCTAssertEqual(translucent?.alphaComponent ?? -1, 0x44 / 255.0, accuracy: 0.002)
        XCTAssertEqual(Markdown.color(fromHex: "#F87171"), NSColor(hex: "F87171"))

        for invalid in ["12345", "1234567", "xyz", "123456789", "１２３", "", "#"] {
            XCTAssertNil(Markdown.color(fromHex: invalid), invalid)
        }
    }

    // MARK: - plainText / 项目名

    func testPlainTextStripsMarkers() {
        XCTAssertEqual(Markdown.plainText("**粗体**"), "粗体")
        XCTAssertEqual(Markdown.plainText("[c:60A5FA]购物清单[/c]"), "购物清单")
        XCTAssertEqual(Markdown.plainText("~~删~~<u>下</u>"), "删下")
        XCTAssertEqual(Markdown.plainText("- [ ] 待办\n- [x] 已办"), "☐ 待办\n☑ 已办")
        XCTAssertEqual(Markdown.plainText("- [ ]  两个空格"), "☐  两个空格")
        XCTAssertEqual(Markdown.plainText("已办☑"), "已办☑")
        XCTAssertEqual(Markdown.plainText("[c:60A5FA]**粗**[/c]\n<u>下</u>"), "粗\n下")
        XCTAssertEqual(Markdown.plainText("**跨行\n加粗**"), "跨行\n加粗")
    }

    func testPlainTextKeepsUnclosedMarkers() {
        let sample = "**没闭合 [c:12345]原样[/c]"
        XCTAssertEqual(Markdown.plainText(sample), sample)
    }

    func testProjectNameFromFirstLine() {
        func name(_ content: String) -> String { StickyNoteModel(pages: [StickyNotePage(content: content)]).extractProjectInfo().name }
        func color(_ content: String) -> Color? { StickyNoteModel(pages: [StickyNotePage(content: content)]).extractProjectInfo().color }

        XCTAssertEqual(name("- [ ] 购物清单"), "购物清单")
        XCTAssertEqual(name("[c:60A5FA]- [ ] 彩色待办[/c]"), "彩色待办")
        XCTAssertEqual(name("**加粗**标题"), "加粗标题")
        XCTAssertEqual(name("[c:12345]位数不对[/c]"), "位数不对", "位数不合法的标记也不该露在蒙层上")
        XCTAssertEqual(name("[c:60A5FA]没闭合"), "没闭合")
        XCTAssertEqual(name("[c:60A5FA]购物清单[/c]\n牛奶"), "购物清单")
        XCTAssertEqual(name(""), "")
        XCTAssertEqual(name("一二三四五六七八九十一二三"), "一二三四五六七八九十", "项目名最多 10 个字符")

        XCTAssertNotNil(color("[c:60A5FA]购物清单[/c]"))
        XCTAssertNotNil(color("[c:60A5FA]没闭合"), "沿用旧行为：没闭合的颜色标记也决定边框颜色")
        XCTAssertNotNil(color("[c:123]三位缩写[/c]"))
        XCTAssertNil(color("[c:12345]位数不对[/c]"))
        XCTAssertNil(color("普通文字"))
    }

    // MARK: - 缺陷 1：工具栏命令订阅

    func testCommandSubscriptionSurvivesRepeatedSymbolDetectionSetup() {
        let rig = makeRig("hello world")
        rig.textView.setSelectedRange(NSRange(location: 0, length: 5))
        rig.coordinator.setupSymbolDetectionDirectly(for: rig.textView)
        rig.coordinator.setupSymbolDetectionDirectly(for: rig.textView)

        send(.toggleBold, to: rig)
        XCTAssertTrue(hasAttribute(Markdown.boldKey, in: rig.attributed, at: 0), "加粗命令应生效")
        XCTAssertTrue(hasAttribute(Markdown.boldKey, in: rig.attributed, at: 4))
        XCTAssertFalse(hasAttribute(Markdown.boldKey, in: rig.attributed, at: 5))
        XCTAssertEqual(rig.model.text, "**hello** world")

        // 再发一次是取消加粗；订阅若被重复注册，两次切换会互相抵消
        send(.toggleBold, to: rig)
        XCTAssertFalse(hasAttribute(Markdown.boldKey, in: rig.attributed, at: 0), "同一命令只应被处理一次")
        XCTAssertEqual(rig.model.text, "hello world")
    }

    func testStrikethroughAndColorCommandsDoNotTouchFontWeight() {
        let rig = makeRig("abc")
        rig.textView.setSelectedRange(NSRange(location: 3, length: 0))

        send(.toggleStrikethrough, to: rig)
        XCTAssertEqual(rig.textView.typingAttributes[.font] as? NSFont, Markdown.baseFont)
        send(.applyColor(hex: "60A5FA"), to: rig)
        XCTAssertEqual(rig.textView.typingAttributes[.font] as? NSFont, Markdown.baseFont, "上色不应连带加粗")
        XCTAssertEqual(rig.textView.typingAttributes[Markdown.colorKey] as? String, "60A5FA")

        // 接着打出来的字带颜色和删除线，但没有加粗
        rig.textView.insertText("字", replacementRange: NSRange(location: 3, length: 0))
        XCTAssertEqual(rig.model.text, "abc[c:60A5FA]~~字~~[/c]")
    }

    // MARK: - 缺陷 6：图标点击切换

    func testClickToggleUsesSameIconColorsAsRender() {
        let rig = makeRig("- [ ] 任务")
        XCTAssertEqual(rig.attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, NSColor.themeGray400)

        XCTAssertTrue(rig.textView.toggleTodoIcon(at: 0))
        XCTAssertEqual(rig.attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, NSColor.themeGreen400)
        XCTAssertEqual(rig.attributed.attribute(Markdown.todoIconKey, at: 0, effectiveRange: nil) as? Bool, true)
        XCTAssertEqual(rig.model.text, "- [x] 任务")
        XCTAssertEqual(rig.attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                       Markdown.render("- [x] 任务").attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)

        XCTAssertTrue(rig.textView.toggleTodoIcon(at: 0))
        XCTAssertEqual(rig.model.text, "- [ ] 任务")
        XCTAssertEqual(rig.attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                       Markdown.render("- [ ] 任务").attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)

        XCTAssertFalse(rig.textView.toggleTodoIcon(at: 1), "非图标位置不应切换")
    }

    // MARK: - 缺陷 8：待办 / 列表按钮只增删行首前缀

    func testTodoToggleKeepsInlineFormattingAndCursor() {
        let rig = makeRig("普通[c:60A5FA]彩色[/c]**加粗文字**")
        rig.textView.setSelectedRange(NSRange(location: 6, length: 0))   // 光标在加粗文字中间

        send(.toggleTodo, to: rig)
        XCTAssertEqual(rig.textView.string, "☐普通彩色加粗文字")
        XCTAssertTrue(hasAttribute(Markdown.colorKey, in: rig.attributed, at: 3))
        XCTAssertTrue(hasAttribute(Markdown.boldKey, in: rig.attributed, at: 5))
        XCTAssertEqual(rig.textView.selectedRange(), NSRange(location: 7, length: 0), "光标应停在原来的正文位置")
        XCTAssertEqual(rig.model.text, "- [ ] 普通[c:60A5FA]彩色[/c]**加粗文字**")

        send(.toggleTodo, to: rig)
        XCTAssertEqual(rig.model.text, "- [x] 普通[c:60A5FA]彩色[/c]**加粗文字**")
        XCTAssertEqual(rig.textView.selectedRange(), NSRange(location: 7, length: 0))

        send(.toggleTodo, to: rig)
        XCTAssertEqual(rig.model.text, "普通[c:60A5FA]彩色[/c]**加粗文字**", "取消待办后应回到原样")
        XCTAssertEqual(rig.textView.selectedRange(), NSRange(location: 6, length: 0))
    }

    func testTodoIconInheritsLineColor() {
        let rig = makeRig("[c:F87171]红色事项[/c]")
        send(.toggleTodo, to: rig)
        XCTAssertEqual(rig.model.text, "[c:F87171]- [ ] 红色事项[/c]")
        XCTAssertEqual(rig.attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, NSColor(hex: "F87171"))
    }

    func testRemovingTodoAlsoRemovesTheTypedSpace() {
        // 实时敲出来的形态：图标后面是一个真实的空格
        let typed = makeRig("- [x] 已办事项")
        typed.storage.replaceCharacters(in: NSRange(location: 1, length: 0), with: NSAttributedString(string: " ", attributes: Markdown.baseAttributes))
        XCTAssertEqual(typed.textView.string, "☑ 已办事项")
        send(.toggleTodo, to: typed)
        XCTAssertEqual(typed.textView.string, "已办事项")
        XCTAssertEqual(typed.model.text, "已办事项")

        // 重开后的形态：图标后面没有空格字符
        let rendered = makeRig("- [x] 已办事项")
        send(.toggleTodo, to: rendered)
        XCTAssertEqual(rendered.textView.string, "已办事项")
        XCTAssertEqual(rendered.model.text, "已办事项")
    }

    func testListToggleKeepsInlineFormattingAndCursor() {
        let rig = makeRig("[c:FACC15]黄色[/c] 正文")
        rig.textView.setSelectedRange(NSRange(location: 3, length: 0))

        send(.toggleBulletList, to: rig)
        XCTAssertEqual(rig.textView.string, "- 黄色 正文")
        XCTAssertTrue(hasAttribute(Markdown.colorKey, in: rig.attributed, at: 2))
        XCTAssertEqual(rig.textView.selectedRange(), NSRange(location: 5, length: 0))
        XCTAssertEqual(rig.model.text, "[c:FACC15]- 黄色[/c] 正文")

        send(.toggleBulletList, to: rig)
        XCTAssertEqual(rig.model.text, "[c:FACC15]黄色[/c] 正文")
        XCTAssertEqual(rig.textView.selectedRange(), NSRange(location: 3, length: 0))
    }

    func testNumberedListContinuesNumberingAndTogglesOff() {
        let rig = makeRig("1. 一\n2. 二\n三")
        rig.textView.setSelectedRange(NSRange(location: 11, length: 0))

        send(.toggleNumberList, to: rig)
        XCTAssertEqual(rig.textView.string, "1. 一\n2. 二\n3. 三")
        XCTAssertEqual(rig.textView.selectedRange(), NSRange(location: 14, length: 0))

        send(.toggleNumberList, to: rig)
        XCTAssertEqual(rig.textView.string, "1. 一\n2. 二\n三")
        XCTAssertEqual(rig.textView.selectedRange(), NSRange(location: 11, length: 0))
    }

    func testTodoAndListPrefixesReplaceEachOther() {
        let bullet = makeRig("- 事项")
        send(.toggleTodo, to: bullet)
        XCTAssertEqual(bullet.textView.string, "☐事项")
        XCTAssertEqual(bullet.model.text, "- [ ] 事项")

        let numbered = makeRig("1. 事项")
        send(.toggleTodo, to: numbered)
        XCTAssertEqual(numbered.textView.string, "☐事项")

        let todo = makeRig("- [x] 事项")
        send(.toggleBulletList, to: todo)
        XCTAssertEqual(todo.textView.string, "- 事项")
        XCTAssertEqual(todo.model.text, "- 事项")
    }

    func testLinePrefixToggleKeepsIndentAndSelection() {
        let indented = makeRig("  缩进行")
        indented.textView.setSelectedRange(NSRange(location: 0, length: 0))
        send(.toggleTodo, to: indented)
        XCTAssertEqual(indented.textView.string, "  ☐缩进行")
        XCTAssertEqual(indented.textView.selectedRange(), NSRange(location: 0, length: 0), "光标在行首缩进里时应原地不动")

        let selected = makeRig("ab\ncd")
        selected.textView.setSelectedRange(NSRange(location: 3, length: 1))   // 选中第二行的 c
        send(.toggleTodo, to: selected)
        XCTAssertEqual(selected.textView.string, "ab\n☐cd")
        XCTAssertEqual(selected.textView.selectedRange(), NSRange(location: 4, length: 1), "选中的正文应保持选中")

        let untouched = makeRig("- [ ] 第一行\n**第二行**")
        untouched.textView.setSelectedRange(NSRange(location: 8, length: 0))
        send(.toggleTodo, to: untouched)
        XCTAssertEqual(untouched.textView.string, "☐第一行\n☐第二行")
        XCTAssertTrue(hasAttribute(Markdown.boldKey, in: untouched.attributed, at: 6), "其它行的格式不受影响")
    }

    func testLinePrefixToggleIsUndoable() {
        let rig = makeRig("正文**加粗**")
        rig.textView.setSelectedRange(NSRange(location: 2, length: 0))
        send(.toggleTodo, to: rig)
        XCTAssertEqual(rig.model.text, "- [ ] 正文**加粗**")

        undo(rig.textView)
        XCTAssertEqual(rig.textView.string, "正文加粗")
        XCTAssertEqual(rig.model.text, "正文**加粗**", "撤销后模型应跟着回退")
    }

    // MARK: - 回车：列表续传 / 取消（实机验证时发现：空的列表项上按回车不取消）

    /// 模拟在文本视图里按下回车（走 NSTextView 的命令分发 → 代理的 doCommandBy）
    private func pressReturn(_ rig: EditorRig, caret: Int? = nil, file: StaticString = #filePath, line: UInt = #line) {
        if let caret { rig.textView.setSelectedRange(NSRange(location: caret, length: 0)) }
        rig.textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        drainMainQueue()
        XCTAssertEqual(rig.model.text, Markdown.serialize(rig.attributed), file: file, line: line)
    }

    func testEnterContinuesTodoBulletAndNumberedItems() {
        let todo = makeRig("☐买牛奶")
        pressReturn(todo, caret: 4)
        XCTAssertEqual(todo.textView.string, "☐买牛奶\n☐", "待办行回车：下一行续一个未勾选的待办")

        let bullet = makeRig("- 项目")
        pressReturn(bullet, caret: 4)
        XCTAssertEqual(bullet.textView.string, "- 项目\n- ")

        let numbered = makeRig("1. 第一")
        pressReturn(numbered, caret: 5)
        XCTAssertEqual(numbered.textView.string, "1. 第一\n2. ", "有序列表序号递增")

        let indented = makeRig("  - 项目")
        pressReturn(indented, caret: 6)
        XCTAssertEqual(indented.textView.string, "  - 项目\n  - ", "缩进跟着带到下一行")

        let plain = makeRig("普通文字")
        pressReturn(plain, caret: 2)
        XCTAssertEqual(plain.textView.string, "普通\n文字", "普通行回车就是普通换行")
    }

    /// 旧实现拿"去掉首尾空白后的行文本"判断：`"- "` 被裁成 `"-"`，空列表项永远匹配不上，
    /// 回车只会多出一个换行、留下一行悬空的「- 」
    func testEnterOnEmptyBulletCancelsTheList() {
        let last = makeRig("- 项目\n- ")
        pressReturn(last, caret: 7)
        XCTAssertEqual(last.textView.string, "- 项目\n", "空的列表项上回车：去掉「- 」，只留一个空行")
        XCTAssertEqual(last.textView.selectedRange(), NSRange(location: 5, length: 0), "光标停在空行上")
        XCTAssertEqual(last.model.text, "- 项目\n")

        let middle = makeRig("上一行\n- \n下一行")
        pressReturn(middle, caret: 5)
        XCTAssertEqual(middle.textView.string, "上一行\n\n下一行")
        XCTAssertEqual(middle.textView.selectedRange(), NSRange(location: 4, length: 0))
    }

    func testEnterOnEmptyNumberedItemCancelsTheList() {
        let rig = makeRig("1. 第一\n2. ")
        pressReturn(rig, caret: 8)
        XCTAssertEqual(rig.textView.string, "1. 第一\n")
        XCTAssertEqual(rig.textView.selectedRange(), NSRange(location: 6, length: 0))
    }

    func testEnterOnEmptyTodoCancelsWithoutLeavingAnExtraBlankLine() {
        let rig = makeRig("☐买牛奶\n☐")
        pressReturn(rig, caret: 5)
        XCTAssertEqual(rig.textView.string, "☐买牛奶\n", "只有一个待办图标时回车：去掉图标，不再多出一个空行")
        XCTAssertEqual(rig.textView.selectedRange(), NSRange(location: 5, length: 0))
        XCTAssertEqual(rig.model.text, "- [ ] 买牛奶\n")
    }

    // MARK: - 缺陷 9：粘贴

    func testPasteReplacesSelectionRendersMarkdownAndNotifies() {
        let rig = makeRig("前 后")
        rig.textView.setSelectedRange(NSRange(location: 1, length: 1))
        let changesBefore = rig.changeNotifications

        rig.coordinator.pastePlainText("**粗体** ~~删~~", into: rig.textView)

        XCTAssertEqual(rig.textView.string, "前粗体 删后")
        XCTAssertTrue(hasAttribute(Markdown.boldKey, in: rig.attributed, at: 1))
        XCTAssertTrue(hasAttribute(Markdown.strikethroughKey, in: rig.attributed, at: 4))
        XCTAssertEqual(rig.textView.selectedRange(), NSRange(location: 5, length: 0), "光标应落在粘贴内容之后")
        XCTAssertEqual(rig.model.text, "前**粗体** ~~删~~后")
        XCTAssertGreaterThan(rig.changeNotifications, changesBefore, "粘贴应广播 NSText.didChangeNotification（符号检测靠它）")
    }

    func testPasteIsUndoable() {
        let rig = makeRig("前 后")
        rig.textView.setSelectedRange(NSRange(location: 1, length: 1))
        rig.coordinator.pastePlainText("- [ ] 待办", into: rig.textView)
        XCTAssertEqual(rig.textView.string, "前☐待办后")

        undo(rig.textView)
        XCTAssertEqual(rig.textView.string, "前 后")
        XCTAssertEqual(rig.model.text, "前 后", "撤销后模型应跟着回退")
    }

    func testPasteFromPasteboardRendersMarkdown() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("qn-sticky-note-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("- [ ] 待办 **粗**", forType: .string)

        let rig = makeRig("末尾")
        rig.textView.setSelectedRange(NSRange(location: 2, length: 0))
        rig.textView.pasteSource = pasteboard
        rig.textView.paste(nil)

        XCTAssertEqual(rig.textView.string, "末尾☐待办 粗")
        XCTAssertTrue(hasAttribute(Markdown.boldKey, in: rig.attributed, at: 6))
        XCTAssertEqual(rig.model.text, "末尾- [ ] 待办 **粗**")
    }

    // MARK: - 缺陷 10：符号插入

    func testTriggerSymbolReplacesOnlyTheTriggerRange() {
        let rig = makeRig("**加粗** :/smi")
        let (detector, smile) = makeDetector(autoClean: true)
        XCTAssertEqual(rig.textView.string, "加粗 :/smi")
        rig.textView.setSelectedRange(NSRange(location: 8, length: 0))
        let changesBefore = rig.changeNotifications

        rig.coordinator.insertSymbolFromTrigger(smile, detectedBy: detector, into: rig.textView)

        XCTAssertEqual(rig.textView.string, "加粗 😊")
        XCTAssertTrue(hasAttribute(Markdown.boldKey, in: rig.attributed, at: 0), "符号前面的格式应保留")
        XCTAssertEqual(rig.textView.selectedRange(), NSRange(location: 5, length: 0), "光标应落在符号之后")
        XCTAssertEqual(rig.model.text, "**加粗** 😊")
        XCTAssertGreaterThan(rig.changeNotifications, changesBefore, "应广播 NSText.didChangeNotification")

        undo(rig.textView)
        XCTAssertEqual(rig.textView.string, "加粗 :/smi")
        XCTAssertEqual(rig.model.text, "**加粗** :/smi", "撤销后模型应跟着回退")
    }

    func testTriggerSymbolKeepsPrefixWhenAutoCleanIsOff() {
        let rig = makeRig(":/smi")
        let (detector, smile) = makeDetector(autoClean: false)
        rig.textView.setSelectedRange(NSRange(location: 5, length: 0))

        rig.coordinator.insertSymbolFromTrigger(smile, detectedBy: detector, into: rig.textView)

        XCTAssertEqual(rig.textView.string, ":/😊")
        XCTAssertEqual(rig.textView.selectedRange(), NSRange(location: 4, length: 0))
    }

    func testTriggerSymbolWithoutTriggerDoesNothing() {
        let rig = makeRig("没有触发词")
        let (detector, smile) = makeDetector(autoClean: true)
        rig.textView.setSelectedRange(NSRange(location: 6, length: 0))

        rig.coordinator.insertSymbolFromTrigger(smile, detectedBy: detector, into: rig.textView)

        XCTAssertEqual(rig.textView.string, "没有触发词")
        XCTAssertEqual(rig.changeNotifications, 0)
    }

    func testBrowserSymbolReplacesSelection() {
        let rig = makeRig("a[c:60A5FA]bc[/c]d")   // 渲染后是 abcd，b、c 带颜色
        rig.textView.setSelectedRange(NSRange(location: 1, length: 1))   // 选中 b
        // 用户用鼠标选中文字时 AppKit 会把输入属性更新成选区首字符的属性，这里手动模拟
        rig.textView.typingAttributes = rig.storage.attributes(at: 1, effectiveRange: nil)

        XCTAssertTrue(rig.coordinator.insertSymbolAtCursor("🎉", into: rig.textView))
        XCTAssertEqual(rig.textView.string, "a🎉cd")
        XCTAssertTrue(hasAttribute(Markdown.colorKey, in: rig.attributed, at: 1))
        XCTAssertEqual(rig.textView.selectedRange(), NSRange(location: 3, length: 0), "a(0) 🎉(1,2) 之后")
        XCTAssertEqual(rig.model.text, "a[c:60A5FA]🎉c[/c]d")

        undo(rig.textView)
        XCTAssertEqual(rig.textView.string, "abcd")
        XCTAssertEqual(rig.model.text, "a[c:60A5FA]bc[/c]d")
    }

    func testBrowserSymbolWithoutContentDoesNothing() {
        let rig = makeRig("文字")
        XCTAssertFalse(rig.coordinator.insertSymbolAtCursor("", into: rig.textView))
        XCTAssertEqual(rig.changeNotifications, 0)
    }

    func testInsertionPlanAgreesWithInsertSymbol() throws {
        let (detector, smile) = makeDetector(autoClean: true)
        let text = "加粗 😀 :/smi 尾巴"
        let cursor = (text as NSString).length - (" 尾巴" as NSString).length
        let plan = try XCTUnwrap(detector.insertionPlan(in: text, cursorPosition: cursor, symbolContent: smile.content))
        XCTAssertEqual(plan.replacementRange, NSRange(location: 6, length: 5), "应只覆盖触发前缀和触发词")
        XCTAssertEqual(plan.cursorAfterInsertion, 8)

        let legacy = try XCTUnwrap(detector.insertSymbol(smile, into: text, cursorPosition: cursor))
        XCTAssertEqual(legacy.newText, "加粗 😀 😊 尾巴")
        XCTAssertEqual(legacy.newCursorPos, plan.cursorAfterInsertion)
    }

    // MARK: - 缺陷 11：重建保持选区长度和滚动位置

    func testExternalRebuildKeepsSelectionLength() {
        let (_, coordinator, scrollView) = makeEditor(text: "abcdefghij")
        let textView = scrollView.documentView as! StickyNoteTextView
        textView.setSelectedRange(NSRange(location: 3, length: 4))

        coordinator.syncExternalText("abcdefghij**粗体**", in: scrollView)

        XCTAssertEqual(textView.string, "abcdefghij粗体")
        XCTAssertTrue(hasAttribute(Markdown.boldKey, in: textView.attributedString(), at: 10))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 4), "重建不应把选区长度清零")

        coordinator.syncExternalText("ab", in: scrollView)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0), "文本变短时选区应钳制到新长度内")
    }

    func testExternalRebuildKeepsScrollPosition() {
        let longText = (0..<300).map { "第 \($0) 行" }.joined(separator: "\n")
        let (_, coordinator, scrollView) = makeEditor(text: longText)
        let textView = scrollView.documentView as! StickyNoteTextView
        let clipView = scrollView.contentView

        XCTAssertGreaterThan(textView.frame.height, 800, "前置条件：长文本应已撑高文本视图")
        clipView.scroll(to: NSPoint(x: 0, y: 600))
        XCTAssertEqual(clipView.bounds.origin.y, 600, "前置条件：无窗口环境下滚动位置可设置")

        coordinator.syncExternalText(longText + "\n新增一行", in: scrollView)
        XCTAssertEqual(clipView.bounds.origin.y, 600, "重建后应保持滚动位置")

        // 内容大幅变短：钳到可滚动范围内
        coordinator.syncExternalText("短内容", in: scrollView)
        XCTAssertEqual(clipView.bounds.origin.y, 0)
    }

    // MARK: - 缺陷 12：手打标记不实时渲染，但不能因此被重建

    func testHandTypedMarkersStayLiteralUntilReopen() {
        let (model, coordinator, scrollView) = makeEditor(text: "文字")
        let textView = scrollView.documentView as! StickyNoteTextView
        XCTAssertEqual(coordinator.lastSerializedMarkdown, "文字")

        // 手打 **粗体**：视图里是字面星号，模型里也是字面星号
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.insertText("**粗体**", replacementRange: NSRange(location: 2, length: 0))
        XCTAssertEqual(textView.string, "文字**粗体**")
        XCTAssertFalse(hasAttribute(Markdown.boldKey, in: textView.attributedString(), at: 2), "手打标记不做实时渲染")
        XCTAssertEqual(model.text, "文字**粗体**")

        // body 重算带来的同步不能动它，选区也要留住
        textView.setSelectedRange(NSRange(location: 4, length: 2))
        coordinator.syncExternalText(model.text, in: scrollView)
        XCTAssertEqual(textView.string, "文字**粗体**")
        XCTAssertFalse(hasAttribute(Markdown.boldKey, in: textView.attributedString(), at: 2))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 4, length: 2))

        // 外部内容真的变了（重开 / 切页）才重建并渲染
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        coordinator.syncExternalText("前缀" + model.text, in: scrollView)
        XCTAssertEqual(textView.string, "前缀文字粗体")
        XCTAssertTrue(hasAttribute(Markdown.boldKey, in: textView.attributedString(), at: 4))
        XCTAssertEqual(coordinator.lastSerializedMarkdown, "前缀文字**粗体**")
    }

    func testLiveTypedTodoConsumesItsSeparatorSpace() {
        let (model, coordinator, scrollView) = makeEditor(text: "前缀")
        let textView = scrollView.documentView as! StickyNoteTextView
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        // 整段插入 "- [ ] "（回车续传就是这么插的）：标记连同其后一个空格换成图标，光标紧跟图标
        textView.insertText("- [ ] ", replacementRange: NSRange(location: 2, length: 0))
        XCTAssertEqual(textView.string, "前缀☐")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0))
        XCTAssertEqual(model.text, "前缀- [ ]")

        // 图标后面再敲进去的空格是正文：序列化成「标记 + 分隔空格 + 正文」
        textView.insertText(" 后缀", replacementRange: NSRange(location: 3, length: 0))
        XCTAssertEqual(textView.string, "前缀☐ 后缀")
        XCTAssertEqual(model.text, "前缀- [ ]  后缀")

        // 模型没变 → 不重建，实时形态保持原样
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        coordinator.syncExternalText(model.text, in: scrollView)
        XCTAssertEqual(textView.string, "前缀☐ 后缀")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 6, length: 0))
    }

    func testSeparatorSpaceTypedAfterFreshTodoIconIsAbsorbed() {
        let rig = makeRig("前缀")
        let textView = rig.textView
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.insertText("- [x]", replacementRange: NSRange(location: 2, length: 0))
        XCTAssertEqual(textView.string, "前缀☑")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0))
        let changes = rig.changeNotifications

        // 紧跟图标敲的分隔空格：吸收（间距已由字距表示），文本、光标、模型都不动
        textView.insertText(" ", replacementRange: NSRange(location: 3, length: 0))
        XCTAssertEqual(textView.string, "前缀☑")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0))
        XCTAssertEqual(rig.changeNotifications, changes, "被吸收的空格不应产生文本变化")
        XCTAssertEqual(rig.model.text, "前缀- [x]")

        // 再敲一个空格是用户真想要的：保留
        textView.insertText(" ", replacementRange: NSRange(location: 3, length: 0))
        XCTAssertEqual(textView.string, "前缀☑ ")
    }

    func testSeparatorSpaceIsOnlyAbsorbedRightAfterAFreshIcon() {
        // 工具栏刚放上的图标同理（光标在行首，插入后紧跟图标）
        let toolbar = makeRig("事项")
        toolbar.textView.setSelectedRange(NSRange(location: 0, length: 0))
        send(.toggleTodo, to: toolbar)
        XCTAssertEqual(toolbar.textView.selectedRange(), NSRange(location: 1, length: 0))
        toolbar.textView.insertText(" ", replacementRange: NSRange(location: 1, length: 0))
        XCTAssertEqual(toolbar.textView.string, "☐事项")

        // 重开后已有的图标后面：空格是用户真想要的，保留
        let reopened = makeRig("- [ ] 事项")
        reopened.textView.setSelectedRange(NSRange(location: 1, length: 0))
        reopened.textView.insertText(" ", replacementRange: NSRange(location: 1, length: 0))
        XCTAssertEqual(reopened.textView.string, "☐ 事项")

        // 图标后面先打了字再打空格：保留
        let typed = makeRig("- [ ]")
        typed.textView.setSelectedRange(NSRange(location: 1, length: 0))
        typed.textView.insertText("字", replacementRange: NSRange(location: 1, length: 0))
        typed.textView.insertText(" ", replacementRange: NSRange(location: 2, length: 0))
        XCTAssertEqual(typed.textView.string, "☐字 ")
    }

    func testUnchangedExternalTextDoesNotResetTypingAttributes() {
        // 重建会把输入属性重置成基础样式；内容没变时不能走到那一步
        let (model, coordinator, scrollView) = makeEditor(text: "文字")
        let textView = scrollView.documentView as! StickyNoteTextView
        var bold = StickyNoteMarkdown.baseAttributes
        bold[Markdown.boldKey] = true
        bold[.font] = Markdown.boldFont
        textView.typingAttributes = bold

        coordinator.syncExternalText(model.text, in: scrollView)
        XCTAssertEqual(textView.typingAttributes[.font] as? NSFont, Markdown.boldFont, "内容未变时不应重建")

        coordinator.syncExternalText("别的文字", in: scrollView)
        XCTAssertEqual(textView.string, "别的文字")
        XCTAssertEqual(textView.typingAttributes[.font] as? NSFont, Markdown.baseFont, "重建后输入属性回到基础样式")
    }

    func testStaleCacheFallsBackToFreshSerialization() {
        let (model, coordinator, scrollView) = makeEditor(text: "**粗体**")
        let textView = scrollView.documentView as! StickyNoteTextView

        // 绕过 textDidChange 直接改内容（撤销这类路径），缓存就过期了
        textView.textStorage?.setAttributedString(Markdown.render("**新内容**"))
        XCTAssertEqual(coordinator.lastSerializedMarkdown, "**粗体**")
        var bold = StickyNoteMarkdown.baseAttributes
        bold[Markdown.boldKey] = true
        bold[.font] = Markdown.boldFont
        textView.typingAttributes = bold

        // 外部文本和视图的真实内容一致：只刷新缓存，不重建
        coordinator.syncExternalText("**新内容**", in: scrollView)
        XCTAssertEqual(coordinator.lastSerializedMarkdown, "**新内容**")
        XCTAssertEqual(textView.typingAttributes[.font] as? NSFont, Markdown.boldFont, "内容一致时不应重建")

        // 外部文本和视图的真实内容不一致：重建
        textView.textStorage?.setAttributedString(Markdown.render("**旧内容**"))
        coordinator.syncExternalText("**另一个内容**", in: scrollView)
        XCTAssertEqual(textView.string, "另一个内容")
        XCTAssertEqual(coordinator.lastSerializedMarkdown, "**另一个内容**")
    }

    func testUndoAndRedoKeepModelInSync() {
        let rig = makeRig("文字")
        let textView = rig.textView
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.insertText("新", replacementRange: NSRange(location: 2, length: 0))
        XCTAssertEqual(rig.model.text, "文字新")

        undo(textView)
        XCTAssertEqual(textView.string, "文字")
        XCTAssertEqual(rig.model.text, "文字", "撤销后模型应跟着回退")
        XCTAssertEqual(rig.coordinator.lastSerializedMarkdown, "文字")

        guard let undoManager = textView.undoManager else { return XCTFail("文本视图没有撤销栈") }
        XCTAssertTrue(undoManager.canRedo)
        undoManager.redo()
        drainMainQueue()
        XCTAssertEqual(textView.string, "文字新")
        XCTAssertEqual(rig.model.text, "文字新", "重做后模型应跟上")
    }

    // MARK: - 实时路径（每次按键只处理光标所在段落）

    func testLiveTypingRendersCheckedTodoMarker() {
        let rig = makeRig("前缀")
        let textView = rig.textView
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.insertText("- [x] 后缀", replacementRange: NSRange(location: 2, length: 0))

        XCTAssertEqual(textView.string, "前缀☑后缀")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 5, length: 0), "光标停在敲完的位置（文本末尾）")
        XCTAssertEqual(rig.attributed.attribute(Markdown.todoIconKey, at: 2, effectiveRange: nil) as? Bool, true)
        XCTAssertEqual(rig.attributed.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor, NSColor.themeGreen400)
        XCTAssertEqual(rig.model.text, "前缀- [x] 后缀")
    }

    func testLivePathLeavesOtherParagraphsAlone() {
        let rig = makeRig("第一段\n第二段")
        let textView = rig.textView
        // 第一段里塞一个「带着 isTodoIcon 却不是图标」的字符（模拟残留）
        rig.storage.addAttribute(Markdown.todoIconKey, value: false, range: NSRange(location: 0, length: 1))

        textView.setSelectedRange(NSRange(location: 4, length: 0))   // 第二段开头
        textView.insertText("字", replacementRange: NSRange(location: 4, length: 0))

        XCTAssertEqual(rig.attributed.attribute(Markdown.todoIconKey, at: 0, effectiveRange: nil) as? Bool, false,
                       "别的段落不应被每个按键扫描/改写")
        XCTAssertEqual(rig.model.text, "第一段\n字第二段", "带 isTodoIcon 的普通字符不能被序列化吃掉")
    }

    func testOrphanTodoIconAttributeDoesNotDestroyText() {
        let attributed = NSAttributedString(string: "a☐b", attributes: Markdown.baseAttributes)
        let orphaned = NSMutableAttributedString(attributedString: attributed)
        orphaned.addAttribute(Markdown.todoIconKey, value: true, range: NSRange(location: 2, length: 1))   // b 带着图标的属性
        XCTAssertEqual(Markdown.serialize(orphaned), "a- [ ] b", "isTodoIcon 只认图标字符本身")
    }

    func testIconStyleLeakingIntoNextTextIsCleanedUp() {
        let rig = makeRig("- [ ] 文字")
        let textView = rig.textView
        // 模拟「点进图标后面直接打字」：正文字号变成图标的 14pt、颜色变成图标灰，但没有语义属性
        rig.storage.addAttribute(.font, value: Markdown.iconFont, range: NSRange(location: 1, length: 2))
        rig.storage.addAttributes([.foregroundColor: Markdown.todoUncheckedColor, .kern: Markdown.todoIconGap], range: NSRange(location: 1, length: 2))

        textView.setSelectedRange(NSRange(location: 3, length: 0))
        textView.insertText("x", replacementRange: NSRange(location: 3, length: 0))

        let rendered = rig.attributed
        XCTAssertEqual(rendered.attribute(.font, at: 1, effectiveRange: nil) as? NSFont, Markdown.baseFont)
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor, Markdown.textColor)
        XCTAssertNil(rendered.attribute(.kern, at: 1, effectiveRange: nil))
        XCTAssertEqual(rendered.attribute(.font, at: 3, effectiveRange: nil) as? NSFont, Markdown.baseFont, "紧跟着图标打出来的字也不应继承图标字号")
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? NSColor, Markdown.textColor)
        XCTAssertEqual(rig.model.text, "- [ ] 文字x")
    }

    func testLivePathFixesCursorWhenMarkerIsCompletedInsideIt() {
        let rig = makeRig("- [  ] x")
        let textView = rig.textView
        XCTAssertEqual(textView.string, "- [  ] x")
        // 删掉标记里多出来的那个空格，标记补全，光标落在标记内部
        textView.setSelectedRange(NSRange(location: 4, length: 1))
        textView.insertText("", replacementRange: NSRange(location: 4, length: 1))
        XCTAssertEqual(textView.string, "☐x")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 1, length: 0))
        XCTAssertEqual(rig.model.text, "- [ ] x")
    }

    // MARK: - 性能基线（阈值放宽到慢机器也不会误报）

    func testSerializeFiftyKilobytesWithinBudget() {
        let markdown = makeLargeMarkdown()
        XCTAssertGreaterThanOrEqual(markdown.utf8.count, 50 * 1024, "前置条件：文本至少 50KB")
        let attributed = Markdown.render(markdown)
        XCTAssertEqual(Markdown.serialize(attributed), markdown, "大文本同样往返恒等")

        let start = DispatchTime.now()
        _ = Markdown.serialize(attributed)
        let elapsed = elapsedMilliseconds(since: start)
        XCTAssertLessThan(elapsed, 200, "50KB 单次序列化耗时 \(elapsed)ms")
    }

    func testRenderFiftyKilobytesWithinBudget() {
        let markdown = makeLargeMarkdown()
        let start = DispatchTime.now()
        let rendered = Markdown.render(markdown)
        let elapsed = elapsedMilliseconds(since: start)
        XCTAssertLessThan(elapsed, 200, "50KB 单次渲染耗时 \(elapsed)ms")
        XCTAssertEqual(Markdown.serialize(rendered), markdown)
    }

    func testUnchangedExternalTextIsNotReconverted() {
        let markdown = makeLargeMarkdown()
        let (_, coordinator, scrollView) = makeEditor(text: markdown)

        let start = DispatchTime.now()
        for _ in 0..<500 {
            coordinator.syncExternalText(markdown, in: scrollView)
        }
        let elapsed = elapsedMilliseconds(since: start)
        XCTAssertLessThan(elapsed, 200, "500 次内容未变的同步应只做字符串比较，实际 \(elapsed)ms")
    }

    func testKeystrokeOnFiftyKilobytesWithinBudget() {
        let markdown = makeLargeMarkdown()
        let (model, _, scrollView) = makeEditor(text: markdown)
        let textView = scrollView.documentView as! StickyNoteTextView
        let end = (textView.string as NSString).length

        let start = DispatchTime.now()
        textView.setSelectedRange(NSRange(location: end, length: 0))
        textView.insertText("x", replacementRange: NSRange(location: end, length: 0))
        let elapsed = elapsedMilliseconds(since: start)

        XCTAssertEqual(model.text, markdown + "x", "前置条件：按键已写进模型")
        XCTAssertLessThan(elapsed, 200, "50KB 文档上的一次按键耗时 \(elapsed)ms")
    }
}
