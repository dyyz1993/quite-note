import SwiftUI
import AppKit
import Combine

/// 贴纸编辑器支持的命令
enum StickyNoteCommand {
    case toggleBold
    case toggleStrikethrough
    case applyColor(hex: String)
    case resetFormat
    case toggleTodo
    case toggleBulletList
    case toggleNumberList
}

/// 一个增强型的文本编辑器，支持 Markdown 复选框的交互式显示和编辑
///
/// 模型里存 Markdown 文本：显示时由 `StickyNoteMarkdown.render` 渲染成富文本，每次内容变化后
/// `StickyNoteMarkdown.serialize` 转回 Markdown 写回模型。手打的行内标记不做实时渲染（半截标记会抖动），
/// 靠「往返恒等」保证 updateNSView 不会因为转回的结果和模型不一致而重建。
struct StickyNoteEditor: NSViewRepresentable {
    @Binding var text: String
    /// 兼容参数，当前不生效：正文固定按 `StickyNoteMarkdown.baseFontSize` 渲染。
    /// 让它真正生效会把存量便利贴的正文从 12pt 改成调用方传入的字号，而固定行高是按 12pt 调的，
    /// 没有经过界面验证之前不动。
    var fontSize: CGFloat = 12
    var isFocused: Bool // 从外部控制焦点
    var onFocusChange: (Bool) -> Void
    var commandPublisher: AnyPublisher<StickyNoteCommand, Never>? = nil // 接收外部命令

    func makeNSView(context: Context) -> NSScrollView {
        Self.makeScrollView(text: text, coordinator: context.coordinator)
    }

    /// 组装「滚动视图 + 文本视图」。不依赖窗口，单元测试可以直接调用。
    static func makeScrollView(text: String, coordinator: Coordinator) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .clear

        let textView = StickyNoteTextView()
        textView.delegate = coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true // 必须为 true 以支持图标
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.autoresizingMask = [.width]

        // 强制绘制背景但设为透明，移除 Layer 干扰
        textView.drawsBackground = true
        textView.backgroundColor = .clear
        textView.insertionPointColor = .white
        textView.font = StickyNoteMarkdown.baseFont
        textView.textColor = StickyNoteMarkdown.textColor

        // 固定内边距，确保内容不随焦点位移
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true

        // 禁用干扰功能
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        // 内容。先放内容再设输入属性：整体替换内容可能把输入属性重置成系统默认
        textView.textStorage?.setAttributedString(StickyNoteMarkdown.render(text))
        coordinator.lastSerializedMarkdown = text
        textView.typingAttributes = StickyNoteMarkdown.baseAttributes

        // 命令订阅 → 符号检测（后者会清空并重建自己的订阅，不动命令订阅）
        coordinator.setupCommandSubscription(for: textView)
        coordinator.setupSymbolDetectionDirectly(for: textView)

        // 强制布局刷新
        if let textContainer = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: textContainer)
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? StickyNoteTextView else { return }
        context.coordinator.parent = self

        // 只有当外部 text 真正变化、且不是由内部触发时才同步
        context.coordinator.syncExternalText(text, in: nsView)

        // 焦点同步
        if isFocused && NSEvent.pressedMouseButtons == 0 && textView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                guard NSEvent.pressedMouseButtons == 0 else { return }
                // 只把 first responder 交给编辑器，不额外滚动：用户把长笔记上滚到中间阅读时，
                // 悬停触发聚焦不该把视图拽到底部（滚动位置和选区都保持原样）
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: StickyNoteEditor
        var isUpdatingFromTextView = false
        var cancellables = Set<AnyCancellable>()  // Internal access for SymbolIntegration extension（符号检测的订阅）
        /// 工具栏命令的订阅单独放：`cancellables` 归符号检测用，`setupSymbolDetectionDirectly` 会把它整体清空
        var commandCancellables = Set<AnyCancellable>()
        /// 最近一次把文本视图内容序列化成的 Markdown。updateNSView 先拿它和外部 text 比较，
        /// 相同就直接返回——拖窗口、悬停引起的 body 重算不再触发整文转换。
        var lastSerializedMarkdown: String?
        var textView: NSTextView?  // Internal access for SymbolIntegration extension
        /// 文本视图当前的撤销栈（换了实例就重新订阅撤销/重做通知）
        private var observedUndoManager: UndoManager?
        private var undoCancellables = Set<AnyCancellable>()
        /// 刚在光标前生成了一个待办图标：用户接着在这个位置敲的单个空格/制表符是标记语法里的分隔符，
        /// 吸收掉（间距已经用字距表示）。任何一次编辑只匹配一次。
        private var pendingSeparatorLocation: Int?

        // Duplicate prevention: track last processed symbol with timestamp
        private var lastProcessedSymbol: (symbol: String, timestamp: Date)?

        init(_ parent: StickyNoteEditor) {
            self.parent = parent
            super.init()
        }

        deinit {
            cancellables.removeAll()
            commandCancellables.removeAll()
            undoCancellables.removeAll()
        }

        func setupCommandSubscription(for textView: NSTextView) {
            self.textView = textView
            commandCancellables.removeAll()
            parent.commandPublisher?
                .receive(on: RunLoop.main)
                .sink { [weak self] command in
                    self?.handleCommand(command)
                }
                .store(in: &commandCancellables)
        }

        // Direct symbol detection setup (moved from extension)
        func setupSymbolDetectionDirectly(for textView: NSTextView) {
            // 清空旧的符号检测订阅，防止重复订阅。命令订阅在 commandCancellables 里，不受影响。
            cancellables.removeAll()

            // SymbolIntegration 的 setupSymbolDetection 负责：存储 textView、订阅文本变化做触发检测、
            // 监听窗口失焦/结束编辑时隐藏联想面板。
            // 此处不再重复订阅 NSText.didChangeNotification——修复前每个按键会跑两遍检测、两遍面板更新
            self.setupSymbolDetection(for: textView)

            if SymbolConfigManager.shared.configs.isEmpty {
                DiagnosticCenter.warning("StickyNote", "符号配置为空，联想面板不会有建议")
            }

            // Monitor InsertSymbolFromBrowser notification (from SymbolBrowserPanelManager)
            NotificationCenter.default.publisher(for: NSNotification.Name("InsertSymbolFromBrowser"))
                .sink { [weak self, weak textView] notification in
                    guard let self = self, let textView = textView else { return }
                    // 只处理发给本窗口的通知
                    guard let symbolContent = notification.userInfo?["symbol"] as? String,
                          let targetUUIDString = notification.userInfo?["windowUUID"] as? String,
                          let currentUUIDString = (textView.window as? StickyNoteWindow)?.uuid.uuidString,
                          currentUUIDString == targetUUIDString else { return }
                    self.insertSymbolIntoTextView(symbolContent, into: textView)
                }
                .store(in: &cancellables)
        }

        // MARK: - 与外部同步

        /// 把外部 Markdown 同步进文本视图。先和「上一次序列化结果」比较，相同就直接返回。
        func syncExternalText(_ text: String, in scrollView: NSScrollView) {
            guard !isUpdatingFromTextView,
                  let textView = scrollView.documentView as? StickyNoteTextView,
                  let storage = textView.textStorage else { return }
            if lastSerializedMarkdown == text { return }

            // 缓存不可信时（视图内容被绕过 textDidChange 改过）以实时序列化为准，再决定要不要重建
            let current = StickyNoteMarkdown.serialize(storage)
            lastSerializedMarkdown = current
            if current == text { return }

            rebuild(textView, storage: storage, in: scrollView, with: text)
        }

        /// 用外部 Markdown 整段重建富文本，保持选区长度和滚动位置。
        private func rebuild(_ textView: StickyNoteTextView, storage: NSTextStorage, in scrollView: NSScrollView, with text: String) {
            let selection = textView.selectedRange()
            let visibleOrigin = scrollView.contentView.bounds.origin

            storage.setAttributedString(StickyNoteMarkdown.render(text))
            lastSerializedMarkdown = text

            // 保持选区：位置和长度都钳制到新文本长度内
            let newLength = storage.length
            let location = min(selection.location, newLength)
            let length = min(selection.length, newLength - location)
            textView.setSelectedRange(NSRange(location: location, length: length))
            textView.typingAttributes = StickyNoteMarkdown.baseAttributes

            // 尽量保持滚动位置：内容变短时钳到可滚动范围内
            if let textContainer = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: textContainer)
            }
            textView.sizeToFit()
            let clipView = scrollView.contentView
            let maxScroll = max(0, textView.frame.height - clipView.bounds.height)
            let target = NSPoint(x: visibleOrigin.x, y: min(visibleOrigin.y, maxScroll))
            if clipView.bounds.origin != target {
                clipView.scroll(to: target)
                scrollView.reflectScrolledClipView(clipView)
            }

            DiagnosticCenter.info("StickyNote", "内容已从外部重建：\(text.count) 字符")
        }

        // MARK: - 命令处理

        private func handleCommand(_ command: StickyNoteCommand) {
            guard textView != nil else { return }

            switch command {
            case .toggleBold:
                toggleAttribute(key: StickyNoteMarkdown.boldKey)
            case .toggleStrikethrough:
                toggleAttribute(key: StickyNoteMarkdown.strikethroughKey)
            case .applyColor(let hex):
                applyColorAttribute(hex: hex)
            case .resetFormat:
                resetFormatting()
            case .toggleTodo:
                toggleTodoAtCurrentLine()
            case .toggleBulletList:
                toggleList(prefix: "- ")
            case .toggleNumberList:
                toggleList(prefix: "1. ")
            }
        }

        private func toggleAttribute(key: NSAttributedString.Key) {
            guard let textView = self.textView, let storage = textView.textStorage else { return }
            let range = textView.selectedRange()

            textView.breakUndoCoalescing()
            storage.beginEditing()

            if range.length > 0 {
                // 1. 检查选中区域是否已经全部拥有该属性
                var allHave = true
                storage.enumerateAttribute(key, in: range, options: []) { value, _, _ in
                    if value == nil { allHave = false }
                }

                let isAdding = !allHave
                if isAdding {
                    storage.addAttribute(key, value: true, range: range)
                } else {
                    storage.removeAttribute(key, range: range)
                }
                if key == StickyNoteMarkdown.strikethroughKey {
                    if isAdding {
                        storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    } else {
                        storage.removeAttribute(.strikethroughStyle, range: range)
                    }
                }
                // 字体（加粗）和图标样式按语义属性重新推导：选区里的待办图标不会被改成正文字体
                StickyNoteMarkdown.normalize(storage, range: range)
            } else {
                // 2. 无选中时更新 typingAttributes
                var attrs = textView.typingAttributes
                let isAdding = attrs[key] == nil
                if isAdding {
                    attrs[key] = true
                } else {
                    attrs.removeValue(forKey: key)
                }

                // 只有「加粗」开关动字重（此前任何格式开关都会连带改字重）
                if key == StickyNoteMarkdown.boldKey {
                    attrs[.font] = isAdding ? StickyNoteMarkdown.boldFont : StickyNoteMarkdown.baseFont
                }
                if key == StickyNoteMarkdown.strikethroughKey {
                    if isAdding {
                        attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                    } else {
                        attrs.removeValue(forKey: .strikethroughStyle)
                    }
                }

                textView.typingAttributes = attrs
            }

            storage.endEditing()
            textView.didChangeText()
        }

        private func applyColorAttribute(hex: String) {
            guard let textView = self.textView, let storage = textView.textStorage else { return }

            // 确保 hex 格式正确 (移除 #)
            let sanitizedHex = hex.replacingOccurrences(of: "#", with: "")
            guard let color = StickyNoteMarkdown.color(fromHex: sanitizedHex) else { return }

            let range = textView.selectedRange()
            let key = StickyNoteMarkdown.colorKey

            textView.breakUndoCoalescing()
            storage.beginEditing()

            if range.length > 0 {
                storage.addAttribute(key, value: sanitizedHex, range: range)
                StickyNoteMarkdown.normalize(storage, range: range)
            } else {
                var attrs = textView.typingAttributes
                attrs[key] = sanitizedHex
                attrs[.foregroundColor] = color
                textView.typingAttributes = attrs
            }

            storage.endEditing()
            textView.didChangeText()
        }

        private func resetFormatting() {
            guard let textView = self.textView, let storage = textView.textStorage else { return }
            let range = textView.selectedRange()

            textView.breakUndoCoalescing()
            storage.beginEditing()

            if range.length > 0 {
                // 只重置颜色：去掉语义属性后重新推导显示颜色（正文回白色，图标回标准图标色）
                storage.removeAttribute(StickyNoteMarkdown.colorKey, range: range)
                StickyNoteMarkdown.normalize(storage, range: range)
            }

            // 无论是否有选中，都重置 typingAttributes，确保后续输入为白色
            var attrs = textView.typingAttributes
            attrs.removeValue(forKey: StickyNoteMarkdown.colorKey)
            attrs[.foregroundColor] = StickyNoteMarkdown.textColor
            textView.typingAttributes = attrs

            storage.endEditing()
            textView.didChangeText()
        }

        // MARK: - 行首前缀（待办 / 列表）

        /// 行首前缀的种类
        private enum LinePrefix {
            case none
            case todo(checked: Bool)
            case bullet
            case number(Int)
        }

        /// 光标所在行的前缀信息（全部 UTF-16 坐标）
        private struct LineInfo {
            let range: NSRange        // 整行（含行尾换行）
            let prefixStart: Int      // 缩进之后
            let prefixLength: Int     // 现有前缀长度，0 表示没有
            let prefix: LinePrefix
        }

        private func toggleTodoAtCurrentLine() {
            guard let textView = self.textView, let storage = textView.textStorage,
                  let line = currentLineInfo(in: textView) else { return }
            let prefixRange = NSRange(location: line.prefixStart, length: line.prefixLength)

            switch line.prefix {
            case .none, .bullet, .number:
                // 加待办：图标继承正文首字符的语义属性（正文是彩色的，图标也是彩色，和手打 `- [ ] ` 的效果一致）
                let inherited = inheritedAttributes(for: line, in: textView)
                replaceLinePrefix(in: textView, replacementRange: prefixRange,
                                  with: StickyNoteMarkdown.todoIcon(checked: false, inheriting: inherited))
                markFreshIconSeparator(at: line.prefixStart, in: textView)
            case .todo(false):
                let inherited = storage.attributes(at: line.prefixStart, effectiveRange: nil)
                replaceLinePrefix(in: textView, replacementRange: prefixRange,
                                  with: StickyNoteMarkdown.todoIcon(checked: true, inheriting: inherited))
                markFreshIconSeparator(at: line.prefixStart, in: textView)
            case .todo(true):
                // 取消待办：连同图标后的一个空格/制表符一起去掉
                var length = line.prefixLength
                let after = line.prefixStart + length
                if after < storage.length {
                    let next = (storage.string as NSString).character(at: after)
                    if next == 0x20 || next == 0x09 { length += 1 }
                }
                replaceLinePrefix(in: textView, replacementRange: NSRange(location: line.prefixStart, length: length), with: nil)
            }
        }

        private func toggleList(prefix: String) {
            guard let textView = self.textView, let line = currentLineInfo(in: textView) else { return }
            let prefixRange = NSRange(location: line.prefixStart, length: line.prefixLength)

            switch (prefix, line.prefix) {
            case ("- ", .bullet), ("1. ", .number):
                // 已是同种列表：取消
                replaceLinePrefix(in: textView, replacementRange: prefixRange, with: nil)
                return
            default:
                break
            }

            var newPrefix = prefix
            if prefix != "- " {
                // 有序列表：接着上一行的序号
                let previous = findPreviousListNumber(in: textView, before: line.range)
                newPrefix = "\(previous + 1). "
            }
            let inherited = inheritedAttributes(for: line, in: textView)
            let insertion = NSAttributedString(string: newPrefix, attributes: StickyNoteMarkdown.linePrefixAttributes(inheriting: inherited))
            replaceLinePrefix(in: textView, replacementRange: prefixRange, with: insertion)
        }

        /// 只替换行首前缀这一段（可撤销插入）。行内格式不动，光标保持在「相对正文」原来的位置。
        private func replaceLinePrefix(in textView: NSTextView, replacementRange: NSRange, with insertion: NSAttributedString?) {
            let selection = textView.selectedRange()
            textView.breakUndoCoalescing()
            if let insertion {
                textView.insertText(insertion, replacementRange: replacementRange)
            } else {
                textView.insertText("", replacementRange: replacementRange)
            }

            // insertText 会把光标放到插入内容末尾；这里改回原来的相对位置
            let newLength = insertion?.length ?? 0
            let delta = newLength - replacementRange.length
            func mapped(_ position: Int) -> Int {
                if position < replacementRange.location { return position }                                   // 在被替换的前缀之前：不动
                if position < NSMaxRange(replacementRange) { return replacementRange.location + newLength }     // 落在被替换的前缀内部：落到新前缀之后
                return position + delta
            }
            let location = mapped(selection.location)
            let end = mapped(NSMaxRange(selection))
            textView.setSelectedRange(NSRange(location: location, length: max(0, end - location)))
        }

        /// 刚放好的待办图标：光标如果紧跟在它后面，下一个敲出来的分隔空格/制表符要吸收掉
        private func markFreshIconSeparator(at iconLocation: Int, in textView: NSTextView) {
            let afterIcon = NSRange(location: iconLocation + 1, length: 0)
            pendingSeparatorLocation = textView.selectedRange() == afterIcon ? afterIcon.location : nil
        }

        /// 新加的行首前缀继承哪里的语义属性：正文首字符的（没有正文时用当前输入属性）
        private func inheritedAttributes(for line: LineInfo, in textView: NSTextView) -> [NSAttributedString.Key: Any] {
            if let storage = textView.textStorage {
                let location = line.prefixStart + line.prefixLength
                if location < storage.length {
                    let unit = (storage.string as NSString).character(at: location)
                    if unit != 0x0A && unit != 0x0D && unit != 0x2028 && unit != 0x2029 {
                        return storage.attributes(at: location, effectiveRange: nil)
                    }
                }
            }
            return textView.typingAttributes
        }

        /// 光标所在行的范围与行首前缀
        private func currentLineInfo(in textView: NSTextView) -> LineInfo? {
            guard let storage = textView.textStorage else { return nil }
            let ns = storage.string as NSString
            let selection = textView.selectedRange()
            let lineRange = ns.lineRange(for: NSRange(location: min(selection.location, ns.length), length: 0))
            let chars = Array(ns.substring(with: lineRange).utf16)
            var indent = 0
            while indent < chars.count, chars[indent] == 0x20 || chars[indent] == 0x09 { indent += 1 }
            let detected = Self.detectPrefix(chars, from: indent)
            return LineInfo(range: lineRange, prefixStart: lineRange.location + indent, prefixLength: detected.length, prefix: detected.prefix)
        }

        /// 从 `start` 起识别行首前缀：待办图标 / `- [ ]` / `- [x]` / `- ` / `N. `
        private static func detectPrefix(_ chars: [unichar], from start: Int) -> (prefix: LinePrefix, length: Int) {
            func unit(_ offset: Int) -> unichar? {
                let index = start + offset
                return index < chars.count ? chars[index] : nil
            }
            let unchecked = StickyNoteMarkdown.uncheckedIconUnit
            let checked = StickyNoteMarkdown.checkedIconUnit

            if let first = unit(0) {
                if first == unchecked { return (.todo(checked: false), 1) }
                if first == checked { return (.todo(checked: true), 1) }
                if first == 0x2D, unit(1) == 0x20 {                                         // "-"
                    if unit(2) == 0x5B, unit(4) == 0x5D, unit(3) == 0x20 || unit(3) == 0x78 {   // "[ ]" / "[x]"
                        return (.todo(checked: unit(3) == 0x78), 5)
                    }
                    return (.bullet, 2)
                }
                if first >= 0x30 && first <= 0x39 {                                          // 数字
                    var digits = 1
                    while let next = unit(digits), next >= 0x30, next <= 0x39 { digits += 1 }
                    if unit(digits) == 0x2E, unit(digits + 1) == 0x20 {                       // ". "
                        let text = String(decoding: chars[start..<start + digits], as: UTF16.self)
                        return (.number(Int(text) ?? 0), digits + 2)
                    }
                }
            }
            return (.none, 0)
        }

        /// 上一行如果是有序列表项，返回它的序号；否则 0
        private func findPreviousListNumber(in textView: NSTextView, before lineRange: NSRange) -> Int {
            guard lineRange.location > 0, let storage = textView.textStorage else { return 0 }
            let ns = storage.string as NSString
            let previousRange = ns.lineRange(for: NSRange(location: lineRange.location - 1, length: 0))
            let chars = Array(ns.substring(with: previousRange).utf16)
            var indent = 0
            while indent < chars.count, chars[indent] == 0x20 || chars[indent] == 0x09 { indent += 1 }
            if case .number(let value) = Self.detectPrefix(chars, from: indent).prefix {
                return value
            }
            return 0
        }

        // MARK: - 符号插入

        /// 插入符号到文本视图（来自符号浏览器面板）
        func insertSymbolIntoTextView(_ symbolContent: String, into textView: NSTextView) {
            // 防止在短时间内重复插入相同符号
            let now = Date()
            if let last = lastProcessedSymbol,
               last.symbol == symbolContent,
               now.timeIntervalSince(last.timestamp) < 0.5 {
                return
            }
            lastProcessedSymbol = (symbolContent, now)

            let length = (symbolContent as NSString).length
            if insertSymbolAtCursor(symbolContent, into: textView) {
                DiagnosticCenter.info("StickyNote", "浏览器插入符号：\(length) 单元")
            }
        }

        /// 符号浏览器插入：替换当前选区（可撤销）。返回是否真的插入了。
        @discardableResult
        func insertSymbolAtCursor(_ symbolContent: String, into textView: NSTextView) -> Bool {
            guard !symbolContent.isEmpty else { return false }
            replaceText(symbolContent, in: textView.selectedRange(), of: textView)
            return true
        }

        /// 联想面板确认符号：只替换「触发前缀 + 触发词」这一段（可撤销），不再整段重建
        func insertSymbolFromTrigger(_ symbol: SymbolItem, detectedBy detector: SymbolTriggerDetector, into textView: NSTextView) {
            guard let plan = detector.insertionPlan(in: textView.string, cursorPosition: textView.selectedRange().location, symbolContent: symbol.content) else {
                return
            }
            replaceText(symbol.content, in: plan.replacementRange, of: textView)
            DiagnosticCenter.info("StickyNote", "联想插入符号：替换 \(plan.replacementRange.length) 单元 → \((symbol.content as NSString).length) 单元")
        }

        /// 统一的可撤销插入：走 insertText 才会进撤销栈、过 shouldChangeText、广播 NSText.didChangeNotification（符号检测靠它）
        private func replaceText(_ text: String, in range: NSRange, of textView: NSTextView) {
            textView.breakUndoCoalescing()
            textView.insertText(text, replacementRange: range)
        }

        // MARK: - 粘贴

        /// 粘贴的核心逻辑（可测，不碰剪贴板）：纯文本按 Markdown 渲染后，以可撤销插入替换当前选区
        func pastePlainText(_ plainText: String, into textView: NSTextView) {
            StickyNoteTextView.insertPastedText(plainText, into: textView, rendering: markdownToAttributed)
        }

        // MARK: - 文本变化

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isUpdatingFromTextView else { return }
            handleTextChanged(in: textView)
        }

        /// 文本视图内容变化后的统一收口：实时待办渲染 + 段落属性收敛 + 回写模型。
        /// 每次按键只做一次整文序列化，结果同时留给 updateNSView 比较。
        func handleTextChanged(in textView: NSTextView) {
            isUpdatingFromTextView = true
            defer { isUpdatingFromTextView = false }

            guard let storage = textView.textStorage else { return }
            let selection = textView.selectedRange()
            let live = StickyNoteMarkdown.normalizeLiveParagraph(storage, cursorLocation: selection.location)
            pendingSeparatorLocation = live.separatorLocation
            let shift = live.cursorShift

            // 图标专用的字距/字号/颜色不带到后续输入；字体与颜色由语义属性重新推导
            let typingAttributes = StickyNoteMarkdown.canonicalTypingAttributes(textView.typingAttributes)
            if NSDictionary(dictionary: typingAttributes) != NSDictionary(dictionary: textView.typingAttributes) {
                textView.typingAttributes = typingAttributes
            }
            if shift != 0 {
                textView.setSelectedRange(NSRange(location: selection.location + shift, length: selection.length))
            }

            let markdown = DiagnosticCenter.measure("StickyNote", "serialize", threshold: 0.1) {
                StickyNoteMarkdown.serialize(storage)
            }
            lastSerializedMarkdown = markdown
            if parent.text != markdown {
                parent.text = markdown
            }

            trackUndoManager(of: textView)
        }

        /// 撤销 / 重做不会走 textDidChange，文本视图回了退、模型却没跟上。盯着文本视图的撤销栈，
        /// 撤销或重做之后把模型同步回来。（视图进窗口后才有撤销栈，所以每次内容变化都来看一眼）
        private func trackUndoManager(of textView: NSTextView) {
            let manager = textView.undoManager
            if let current = observedUndoManager, current === manager { return }
            undoCancellables.removeAll()
            observedUndoManager = manager
            guard let manager else { return }

            for name in [Notification.Name.NSUndoManagerDidUndoChange, Notification.Name.NSUndoManagerDidRedoChange] {
                NotificationCenter.default.publisher(for: name, object: manager)
                    .sink { [weak self, weak textView] _ in
                        guard let textView = textView else { return }
                        self?.handleTextChanged(in: textView)
                    }
                    .store(in: &undoCancellables)
            }
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            let pending = pendingSeparatorLocation
            pendingSeparatorLocation = nil
            if let pending, affectedCharRange.length == 0, affectedCharRange.location == pending,
               replacementString == " " || replacementString == "\t" {
                return false
            }
            return true
        }

        /// 回车：待办 / 无序列表 / 有序列表自动续传下一行；这一行只有前缀时再按回车取消——
        /// 去掉前缀、留一个空行（光标停在空行上）。
        ///
        /// 行首前缀的识别统一走 currentLineInfo（待办图标、`- [ ]`、`- `、`N. `）。
        /// 旧实现拿"去掉首尾空白后的行文本"做判断：`"- "` 被裁成 `"-"`，空列表项永远匹配不上，
        /// 在空的列表项上按回车不会取消列表，只会多出一个换行
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)),
                  let line = currentLineInfo(in: textView),
                  let text = textView.textStorage?.string else { return false }
            let string = text as NSString
            let indent = Self.indent(of: line, in: string)
            let continuation: String
            switch line.prefix {
            case .none:
                return false
            case .todo:
                // 续传为 Markdown 形式，由实时待办渲染转成图标
                continuation = "\n\(indent)- [ ] "
            case .bullet:
                continuation = "\n\(indent)- "
            case .number(let number):
                continuation = "\n\(indent)\(number + 1). "
            }

            if Self.hasBodyAfterPrefix(line, in: string) {
                textView.insertText(continuation, replacementRange: textView.selectedRange())
            } else {
                // 这一行只有前缀：去掉前缀，留一个空行
                textView.insertText("", replacementRange: Self.emptyItemRange(line, in: string))
            }
            return true
        }

        /// 行首的缩进（空格 / 制表符）
        private static func indent(of line: LineInfo, in string: NSString) -> String {
            let length = line.prefixStart - line.range.location
            return length > 0 ? string.substring(with: NSRange(location: line.range.location, length: length)) : ""
        }

        /// 这一行前缀之后还有没有正文（只有空白就算没有）
        private static func hasBodyAfterPrefix(_ line: LineInfo, in string: NSString) -> Bool {
            let start = line.prefixStart + line.prefixLength
            return !string.substring(with: NSRange(location: start, length: NSMaxRange(line.range) - start))
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// 「只有前缀」的整行里要去掉的范围：前缀连同其后的空白（不含行尾换行）
        private static func emptyItemRange(_ line: LineInfo, in string: NSString) -> NSRange {
            let lineEnd = NSMaxRange(line.range) - terminatorLength(of: line.range, in: string)
            var end = line.prefixStart + line.prefixLength
            while end < lineEnd {
                let unit = string.character(at: end)
                if unit == 0x20 || unit == 0x09 { end += 1 } else { break }
            }
            return NSRange(location: line.prefixStart, length: end - line.prefixStart)
        }

        /// 行尾换行的长度（\n 为 1，\r\n 为 2，最后一行没有换行则为 0）
        private static func terminatorLength(of lineRange: NSRange, in string: NSString) -> Int {
            guard lineRange.length > 0, string.character(at: NSMaxRange(lineRange) - 1) == 0x0A else { return 0 }
            return lineRange.length > 1 && string.character(at: NSMaxRange(lineRange) - 2) == 0x0D ? 2 : 1
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }

        // MARK: - Markdown Conversion（薄包装，纯逻辑在 StickyNoteMarkdown）

        func markdownToAttributed(_ markdown: String) -> NSAttributedString {
            StickyNoteMarkdown.render(markdown)
        }

        func attributedToMarkdown(_ attributedString: NSAttributedString) -> String {
            StickyNoteMarkdown.serialize(attributedString)
        }
    }
}

/// 自定义 NSTextView 以处理特殊的交互和显示
class StickyNoteTextView: NSTextView {
    /// 粘贴来源。默认系统剪贴板；单元测试注入独立命名的 pasteboard，避免覆盖用户剪贴板。
    var pasteSource: NSPasteboard?

    /// 覆盖粘贴方法：纯文本按 Markdown 渲染后走可撤销插入（进撤销栈、广播 NSText.didChangeNotification）
    override func paste(_ sender: Any?) {
        guard let plainText = (pasteSource ?? .general).string(forType: .string) else {
            super.paste(sender)
            return
        }
        let coordinator = delegate as? StickyNoteEditor.Coordinator
        Self.insertPastedText(plainText, into: self, rendering: coordinator?.markdownToAttributed ?? StickyNoteMarkdown.render)
    }

    /// 粘贴的核心逻辑（可测，不碰剪贴板）：替换当前选区，光标落在粘贴内容之后
    static func insertPastedText(_ plainText: String, into textView: NSTextView, rendering: (String) -> NSAttributedString) {
        guard !plainText.isEmpty else { return }
        textView.breakUndoCoalescing()
        textView.insertText(rendering(plainText), replacementRange: textView.selectedRange())
    }

    /// 切换 `location` 处待办图标的勾选状态（可撤销）。只有该位置确实是图标字符才生效。
    @discardableResult
    func toggleTodoIcon(at location: Int) -> Bool {
        guard let storage = textStorage, location >= 0, location < storage.length else { return false }
        let unit = (storage.string as NSString).character(at: location)
        guard StickyNoteMarkdown.isTodoIconUnit(unit) else { return false }
        let checked = unit == StickyNoteMarkdown.checkedIconUnit
        let inherited = storage.attributes(at: location, effectiveRange: nil)
        breakUndoCoalescing()
        insertText(StickyNoteMarkdown.todoIcon(checked: !checked, inheriting: inherited), replacementRange: NSRange(location: location, length: 1))
        return true
    }

    override func mouseDown(with event: NSEvent) {
        // 1. 先尝试检测是否点击在待办图标上
        if let layoutManager = layoutManager, let textContainer = textContainer, let storage = textStorage {
            let point = convert(event.locationInWindow, from: nil)

            // 关键：调整坐标以考虑 textContainerInset
            let adjustedPoint = NSPoint(
                x: point.x - textContainerInset.width,
                y: point.y - textContainerInset.height
            )

            // 获取点击位置的字符索引
            var fraction: CGFloat = 0
            let glyphIndex = layoutManager.glyphIndex(for: adjustedPoint, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

            if charIndex < storage.length, toggleTodoIcon(at: charIndex) {
                return
            }
        }

        super.mouseDown(with: event)
    }

    /// 键盘事件处理回调 - 在默认处理之前调用
    /// 返回 true 表示事件已处理，不会继续传递
    var onKeyDown: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        // 先让回调处理事件
        if let callback = onKeyDown, callback(event) {
            return // 事件已被处理，不继续传递
        }
        super.keyDown(with: event)
    }

    // 更彻底地拦截键盘事件，阻止 interpretKeyEvents
    override func interpretKeyEvents(_ eventArray: [NSEvent]) {
        // 检查第一个事件是否被回调处理
        if let event = eventArray.first, let callback = onKeyDown, callback(event) {
            return // 事件已被处理，不传递给 interpretKeyEvents
        }
        super.interpretKeyEvents(eventArray)
    }
}
