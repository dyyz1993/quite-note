import AppKit
import Combine
import SwiftUI
import XCTest
@testable import QuiteNote

/// 便利贴编辑器回归（2026-11-24 审计用例转正）
///
/// 前身是走读审计时钉下的缺陷复现，缺陷修复后摘掉 XCTExpectFailure 成为正式回归用例；
/// `testControl…` 是不涉及缺陷的对照用例。转换器的系统性用例在 StickyNoteMarkdownTests，
/// 保存/持久化的在 StickyNoteSyncTests 与 StickyNotePersistenceTests。
///
/// 数据隔离：触达存储单例的用例先调 TestStorageIsolation.activate；全程不创建任何窗口。
@MainActor
final class StickyNoteAuditTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TestStorageIsolation.activate
    }

    // MARK: - 夹具

    private func makeCoordinator(
        commandPublisher: AnyPublisher<StickyNoteCommand, Never>? = nil
    ) -> StickyNoteEditor.Coordinator {
        StickyNoteEditor(
            text: .constant(""),
            isFocused: false,
            onFocusChange: { _ in },
            commandPublisher: commandPublisher
        ).makeCoordinator()
    }

    private func makeTextView(
        delegate: StickyNoteEditor.Coordinator? = nil,
        content: String
    ) -> StickyNoteTextView {
        let textView = StickyNoteTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        textView.delegate = delegate
        textView.textStorage?.setAttributedString(NSAttributedString(string: content))
        return textView
    }

    private func drainMainQueue(rounds: Int = 3) {
        for _ in 0..<rounds {
            let drained = expectation(description: "main queue drained")
            DispatchQueue.main.async { drained.fulfill() }
            wait(for: [drained], timeout: 2)
        }
    }

    private func hasBold(_ textView: NSTextView, at location: Int) -> Bool {
        textView.attributedString().attribute(NSAttributedString.Key("isBold"), at: location, effectiveRange: nil) != nil
    }

    private static let boldKey = NSAttributedString.Key("isBold")

    // MARK: - 工具栏命令

    func testControlToolbarCommandWorksWithoutSymbolDetectionSetup() {
        let commands = PassthroughSubject<StickyNoteCommand, Never>()
        let coordinator = makeCoordinator(commandPublisher: commands.eraseToAnyPublisher())
        let textView = makeTextView(delegate: coordinator, content: "hello world")
        coordinator.setupCommandSubscription(for: textView)
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        commands.send(.toggleBold)
        drainMainQueue()

        XCTAssertTrue(hasBold(textView, at: 0), "对照组：只注册命令订阅时「加粗」应生效")
    }

    /// 回归：makeNSView 的顺序是 setupCommandSubscription → setupSymbolDetectionDirectly，
    /// 修复前后者第一行 cancellables.removeAll() 会把刚存进去的命令订阅一起清掉
    /// （现在命令订阅单独放在 commandCancellables）
    func testToolbarCommandSurvivesSymbolDetectionSetup() {
        let commands = PassthroughSubject<StickyNoteCommand, Never>()
        let coordinator = makeCoordinator(commandPublisher: commands.eraseToAnyPublisher())
        let textView = makeTextView(delegate: coordinator, content: "hello world")
        coordinator.setupCommandSubscription(for: textView)
        coordinator.setupSymbolDetectionDirectly(for: textView)   // makeNSView 第 6 步
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        commands.send(.toggleBold)
        drainMainQueue()

        XCTAssertTrue(hasBold(textView, at: 0), "工具栏「加粗」应生效")
    }

    /// 回归：toggleAttribute 无选区分支里"字体转粗体"那段曾不判断 key，任何格式开关都会顺带改字重
    func testStrikethroughToggleWithoutSelectionLeavesFontWeightAlone() {
        let commands = PassthroughSubject<StickyNoteCommand, Never>()
        let coordinator = makeCoordinator(commandPublisher: commands.eraseToAnyPublisher())
        let textView = makeTextView(delegate: coordinator, content: "abc")
        coordinator.setupCommandSubscription(for: textView)
        textView.setSelectedRange(NSRange(location: 3, length: 0))   // 无选区：改的是 typingAttributes
        textView.typingAttributes = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white]
        let boldBefore = Self.isBoldFont(textView.typingAttributes[.font] as? NSFont)

        commands.send(.toggleStrikethrough)
        drainMainQueue()

        XCTAssertNotNil(textView.typingAttributes[.strikethroughStyle], "前置条件：删除线已打开")
        let boldAfter = Self.isBoldFont(textView.typingAttributes[.font] as? NSFont)
        XCTAssertFalse(boldBefore, "前置条件：切换前不是粗体")
        XCTAssertEqual(boldAfter, boldBefore, "切删除线不应改动字重")
    }

    private static func isBoldFont(_ font: NSFont?) -> Bool {
        font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
    }

    // MARK: - Markdown 往返

    /// 对照组：单行非待办格式往返稳定（这是现在能正常工作的部分）
    func testControlSingleLineFormatsRoundTrip() {
        let coordinator = makeCoordinator()
        let samples = [
            "**粗体**", "~~删除线~~", "<u>下划线</u>", "[c:60A5FA]彩色[/c]", "前缀 **粗体** 后缀",
            "- [ ] 待办", "- [x] 已办",
        ]
        for markdown in samples {
            let rendered = coordinator.markdownToAttributed(markdown)
            XCTAssertEqual(coordinator.attributedToMarkdown(rendered), markdown, "往返不恒等: \(markdown)")
        }
    }

    /// 回归：渲染曾把 "- [ ]"（5 字符）换成 "☐ "（图标+空格），转回时只把图标字符换成 "- [ ]"，
    /// 每渲染/转回一轮复选框后面就多一个空格
    func testTodoLineDoesNotGainSpacesOnRerender() {
        let coordinator = makeCoordinator()
        var markdown = "- [ ] 待办"
        var grew = false
        for _ in 0..<3 {                       // 模拟重开/切页三轮
            markdown = coordinator.attributedToMarkdown(coordinator.markdownToAttributed(markdown))
            grew = grew || markdown != "- [ ] 待办"
        }
        XCTAssertFalse(grew, "待办行多轮往返应保持恒等")
    }

    func testMultilineBoldRendersOnReopen() {
        let coordinator = makeCoordinator()
        let rendered = coordinator.markdownToAttributed("**第一行\n第二行**")
        let renderedBold = rendered.attribute(Self.boldKey, at: 0, effectiveRange: nil) != nil
        XCTAssertTrue(renderedBold && !rendered.string.contains("**"), "跨行加粗应被渲染，实际: \(rendered.string)")
    }

    func testMultilineColorRendersOnReopen() {
        let coordinator = makeCoordinator()
        let rendered = coordinator.markdownToAttributed("[c:60A5FA]第一行\n第二行[/c]")
        XCTAssertFalse(rendered.string.contains("[c:"), "颜色标记应被解析，实际: \(rendered.string)")
    }

    /// 回归：attributedToMarkdown 处理完颜色后 i = range.location - 1，曾跳过颜色范围内的加粗/删除线
    func testBoldInsideColorSurvivesRoundTrip() {
        let coordinator = makeCoordinator()
        let markdown = "[c:60A5FA]**加粗**[/c]"
        let roundTrip = coordinator.attributedToMarkdown(coordinator.markdownToAttributed(markdown))
        XCTAssertEqual(roundTrip, markdown)
    }

    /// 回归：外层加粗处理完 i 跳到范围之前，与它重叠的颜色曾被拆成两段独立标记
    func testColorInsideBoldSurvivesRoundTrip() {
        let coordinator = makeCoordinator()
        let markdown = "**a[c:60A5FA]bc[/c]d**"
        let roundTrip = coordinator.attributedToMarkdown(coordinator.markdownToAttributed(markdown))
        XCTAssertEqual(roundTrip, markdown)
    }

    /// 回归：颜色正则放行 3~8 位 hex，但 NSColor(hex:) 只认 6/8 位，重建时标记曾被静默删除
    func testShortHexColorMarkersAreNotSilentlyDropped() {
        let coordinator = makeCoordinator()
        let rendered = coordinator.markdownToAttributed("[c:123]重要[/c]")
        let colored = (rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) != NSColor.white
        XCTAssertTrue(colored, "应渲染出颜色（或至少保留用户写的标记）")
        XCTAssertEqual(rendered.string, "重要", "标记外的正文不应丢失，实际: \(rendered.string)")
    }

    // MARK: - 待办图标

    func testCheckedIconColorIsConsistentBetweenLiveTypingAndRerender() {
        let coordinator = makeCoordinator()
        // 路径 A：重建渲染（打开便利贴 / 切页）
        let rerendered = coordinator.markdownToAttributed("- [x] 任务")
        let rerenderedColor = rerendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        // 路径 B：实时输入（textDidChange → renderTodoIconsInPlace）
        let textView = makeTextView(delegate: coordinator, content: "- [x] 任务")
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        let liveColor = textView.attributedString().attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor

        XCTAssertNotNil(liveColor, "前置条件：实时路径已渲染出图标")
        XCTAssertNotNil(rerenderedColor, "前置条件：重建路径已渲染出图标")
        XCTAssertEqual(liveColor, rerenderedColor, "已勾选图标颜色应三处一致")
    }

    // MARK: - 项目名（失焦蒙层）

    func testProjectNameDropsClosingColorMarker() {
        let note = StickyNoteModel(pages: [StickyNotePage(content: "[c:60A5FA]购物清单[/c]\n牛奶")])
        XCTAssertNotNil(note.extractProjectInfo().color, "前置条件：首行颜色被识别")
        XCTAssertEqual(note.extractNoteTitle(), "购物清单", "对照：标题提取会同时剥掉开/闭标记")
        XCTAssertEqual(note.extractProjectInfo().name, "购物清单", "失焦蒙层的项目名不应露出 [/c]")
    }
}
