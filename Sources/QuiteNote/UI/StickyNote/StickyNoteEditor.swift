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
struct StickyNoteEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 12
    var isFocused: Bool // 新增：从外部控制焦点
    var onFocusChange: (Bool) -> Void
    var commandPublisher: AnyPublisher<StickyNoteCommand, Never>? = nil // 新增：接收外部命令
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .clear
        
        let textView = StickyNoteTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true // 必须为 true 以支持图标
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.autoresizingMask = [.width]
        
        // 1. 强制绘制背景但设为透明，移除 Layer 干扰
        textView.drawsBackground = true
        textView.backgroundColor = .clear
        
        // 2. 关键：确保渲染一致性
        let textColor = NSColor.white
        let baseFontSize: CGFloat = 12 // 调整：从 13 减小到 12
        let font = NSFont.systemFont(ofSize: baseFontSize)
        
        // 3. 窗口/光标设置 - 禁用所有导致抖动的自动调整
        textView.insertionPointColor = .white
        textView.font = font
        textView.textColor = textColor
        
        // 固定内边距，确保内容不随焦点位移
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.lineFragmentPadding = 0 
        
        // 预设段落样式，固定行高，防止抖动
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4 // 调整：从 5 减小到 4
        paragraphStyle.minimumLineHeight = 18 // 调整：从 20 减小到 18
        paragraphStyle.maximumLineHeight = 18 // 调整：从 20 减小到 18
        
        textView.typingAttributes = [
            .foregroundColor: textColor,
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
        
        // 设置文本容器属性
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        
        // 禁用干扰功能
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        
        // 4. 内容设置
        let attributedString = context.coordinator.markdownToAttributed(text)
        textView.textStorage?.setAttributedString(attributedString)
        
        // 5. 设置命令订阅
        context.coordinator.setupCommandSubscription(for: textView)

        // 6. 设置符号检测 - 直接调用而不通过扩展
        context.coordinator.setupSymbolDetectionDirectly(for: textView)

        // 强制布局刷新
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        
        scrollView.documentView = textView
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? StickyNoteTextView else { return }

        // 只有当外部 text 真正变化且不是由内部触发时才同步
        if !context.coordinator.isUpdatingFromTextView {
            // 获取当前文本的 Markdown，并进行简单的内容比较（忽略格式差异导致的微小变化）
            let currentMarkdown = context.coordinator.attributedToMarkdown(textView.attributedString())

            print("[DEBUG] updateNSView - currentMarkdown: \(currentMarkdown.prefix(50)), text: \(text.prefix(50))")

            // 如果内容确实不一致，才进行全量更新
            if currentMarkdown != text {
                print("[DEBUG] updateNSView - Content changed, updating...")
                let selectedRange = textView.selectedRange()
                let attributedString = context.coordinator.markdownToAttributed(text)

                textView.textStorage?.beginEditing()
                textView.textStorage?.setAttributedString(attributedString)
                textView.textStorage?.endEditing()

                // 尽可能保持光标位置
                let newRange = NSRange(location: min(selectedRange.location, (textView.string as NSString).length), length: 0)
                textView.setSelectedRange(newRange)
            } else {
                print("[DEBUG] updateNSView - Content same, skipping update")
            }
        }

        // 焦点同步
        if isFocused && textView.window?.firstResponder != textView {
            DispatchQueue.main.async {
                if textView.window?.makeFirstResponder(textView) == true {
                    // 成功获取焦点后，确保光标可见
                    textView.scrollToEndOfDocument(nil)
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: StickyNoteEditor
        var isUpdatingFromTextView = false
        var cancellables = Set<AnyCancellable>()  // Internal access for SymbolIntegration extension
        var textView: NSTextView?  // Internal access for SymbolIntegration extension

        // Symbol detection state
        private var symbolDetector: SymbolTriggerDetector?
        private var symbolSelectionState: SymbolSelectionState?

        init(_ parent: StickyNoteEditor) {
            self.parent = parent
            super.init()
            // Initialize symbol detection state
            self.symbolSelectionState = SymbolSelectionState()
        }

        func setupCommandSubscription(for textView: NSTextView) {
            self.textView = textView
            parent.commandPublisher?
                .receive(on: RunLoop.main)
                .sink { [weak self] command in
                    self?.handleCommand(command)
                }
                .store(in: &cancellables)
        }

        // Direct symbol detection setup (moved from extension)
        func setupSymbolDetectionDirectly(for textView: NSTextView) {
            let timestamp = Date()
            let logMessage = "[StickyNoteEditor.Coordinator] [\(timestamp)] ========== 设置符号检测（直接方法）==========\n"
            print(logMessage)

            // Write to file for debugging
            let logPath = "/tmp/quitenote-symbol-debug.log"
            let fileLog = logMessage + "textView: \(textView)\n"
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(fileLog.data(using: .utf8)!)
                fileHandle.closeFile()
            } else {
                try? fileLog.write(toFile: logPath, atomically: true, encoding: .utf8)
            }

            print("[StickyNoteEditor.Coordinator] textView: \(textView)")

            // ⭐ 重要：调用 SymbolIntegration 的 setupSymbolDetection 来存储 symbolTextView
            self.setupSymbolDetection(for: textView)

            // Initialize symbol detector if needed
            if symbolDetector == nil {
                symbolDetector = SymbolTriggerDetector()
                print("[StickyNoteEditor.Coordinator] 创建 SymbolTriggerDetector")
            }

            // Check config loading
            let configCount = SymbolConfigManager.shared.configs.count
            print("[StickyNoteEditor.Coordinator] 当前已加载 \(configCount) 个符号配置")

            if configCount == 0 {
                print("[StickyNoteEditor.Coordinator] ⚠️ 警告：没有加载任何配置！")
            }

            // Monitor text changes
            NotificationCenter.default.publisher(for: NSText.didChangeNotification, object: textView)
                .sink { [weak self, weak textView] notification in
                    guard let self = self, let textView = textView else { return }
                    let timestamp = Date()
                    let logMsg = "[StickyNoteEditor.Coordinator] [\(timestamp)] 🔔 文本变化通知\n"
                    print(logMsg)

                    // Write to file
                    let logPath = "/tmp/quitenote-symbol-debug.log"
                    let fileLog = logMsg + "文本长度: \(textView.string.count), 光标位置: \(textView.selectedRange().location)\n"
                    if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(fileLog.data(using: .utf8)!)
                        fileHandle.closeFile()
                    } else {
                        try? fileLog.write(toFile: logPath, atomically: true, encoding: .utf8)
                    }

                    self.handleSymbolDetection(textView: textView)
                }
                .store(in: &cancellables)

            print("[StickyNoteEditor.Coordinator] ✅ 符号检测设置完成，已监听文本变化")
        }

        private func handleSymbolDetection(textView: NSTextView) {
            let logPath = "/tmp/quitenote-symbol-debug.log"
            let timestamp = Date()

            guard let detector = symbolDetector else {
                let logMsg = "[StickyNoteEditor.Coordinator] [\(timestamp)] ⚠️ symbolDetector 为 nil\n"
                print(logMsg)
                try? logMsg.write(toFile: logPath, atomically: true, encoding: .utf8)
                return
            }

            let text = textView.string
            let cursorPosition = textView.selectedRange().location

            let logMsg = "[StickyNoteEditor.Coordinator] [\(timestamp)] 执行符号检测，文本: '\(text)', 长度: \(text.count), 光标位置: \(cursorPosition)\n"
            print(logMsg)

            // Write to file
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(logMsg.data(using: .utf8)!)
                fileHandle.closeFile()
            } else {
                try? logMsg.write(toFile: logPath, atomically: true, encoding: .utf8)
            }

            // Detect trigger
            detector.detectTrigger(in: text, cursorPosition: cursorPosition)

            // Debug output
            if let trigger = detector.detectedTrigger {
                let successMsg = "[StickyNoteEditor.Coordinator] [\(timestamp)] ✅ 检测到触发词: ':/\(trigger)' (长度: \(trigger.count)), 建议: \(detector.suggestions.count) 个\n"
                print(successMsg)

                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(successMsg.data(using: .utf8)!)
                    fileHandle.closeFile()
                } else {
                    try? successMsg.write(toFile: logPath, atomically: true, encoding: .utf8)
                }

                // Show suggestion panel
                showSymbolSuggestionPanel(for: textView, triggerText: trigger, suggestions: detector.suggestions)
            } else {
                let failMsg = "[StickyNoteEditor.Coordinator] [\(timestamp)] 未检测到触发词\n"
                print(failMsg)

                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(failMsg.data(using: .utf8)!)
                    fileHandle.closeFile()
                } else {
                    try? failMsg.write(toFile: logPath, atomically: true, encoding: .utf8)
                }

                hideSymbolSuggestionPanel()
            }
        }

        private func showSymbolSuggestionPanel(for textView: NSTextView, triggerText: String, suggestions: [MatchedSymbolItem]) {
            let logPath = "/tmp/quitenote-symbol-debug.log"
            let timestamp = Date()
            let logMsg = "[StickyNoteEditor.Coordinator] [\(timestamp)] 显示符号建议面板: trigger='\(triggerText)', suggestions=\(suggestions.count)\n"
            print(logMsg)

            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(logMsg.data(using: .utf8)!)
                fileHandle.closeFile()
            } else {
                try? logMsg.write(toFile: logPath, atomically: true, encoding: .utf8)
            }

            // Get cursor location info for panel positioning (includes line rect to avoid overlapping text)
            let cursorInfo = textView.cursorLocationInfo()

            // Call the extension method to show the panel
            // This uses the SymbolIntegration extension's implementation
            self.showSymbolSuggestionPanelExtension(at: cursorInfo, triggerText: triggerText, suggestions: suggestions, parentWindow: textView.window)
        }

        private func hideSymbolSuggestionPanel() {
            let logPath = "/tmp/quitenote-symbol-debug.log"
            let timestamp = Date()
            let logMsg = "[StickyNoteEditor.Coordinator] [\(timestamp)] 隐藏符号建议面板\n"
            print(logMsg)

            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(logMsg.data(using: .utf8)!)
                fileHandle.closeFile()
            } else {
                try? logMsg.write(toFile: logPath, atomically: true, encoding: .utf8)
            }

            // Call the extension method to hide the panel
            self.hideSymbolSuggestionPanelExtension()
        }

        private func handleCommand(_ command: StickyNoteCommand) {
            guard self.textView != nil else { return }
            
            switch command {
            case .toggleBold:
                toggleAttribute(key: NSAttributedString.Key("isBold"), value: true) { storage, range, isAdding in
                    if let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
                        let newFont = isAdding ? 
                            NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : 
                            NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                        storage.addAttribute(.font, value: newFont, range: range)
                    }
                }
            case .toggleStrikethrough:
                toggleAttribute(key: NSAttributedString.Key("isStrikethrough"), value: true) { storage, range, isAdding in
                    if isAdding {
                        storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    } else {
                        storage.removeAttribute(.strikethroughStyle, range: range)
                    }
                }
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

        private func toggleAttribute(key: NSAttributedString.Key, value: Any, customAction: (NSTextStorage, NSRange, Bool) -> Void) {
            guard let textView = self.textView, let storage = textView.textStorage else { return }
            let range = textView.selectedRange()
            
            textView.breakUndoCoalescing()
            storage.beginEditing()
            
            if range.length > 0 {
                // 1. 检查选中区域是否已经全部拥有该属性
                var allHave = true
                storage.enumerateAttributes(in: range, options: []) { attrs, subRange, _ in
                    if attrs[key] == nil {
                        allHave = false
                    }
                }
                
                let isAdding = !allHave
                
                if isAdding {
                    storage.addAttribute(key, value: value, range: range)
                } else {
                    storage.removeAttribute(key, range: range)
                }
                customAction(storage, range, isAdding)
            } else {
                // 2. 无选中时更新 typingAttributes
                var attrs = textView.typingAttributes
                let isAdding = attrs[key] == nil
                
                if isAdding {
                    attrs[key] = value
                } else {
                    attrs.removeValue(forKey: key)
                }
                
                // 执行自定义动作（针对 typingAttributes 的模拟）
                if let font = attrs[.font] as? NSFont {
                     let newFont = isAdding ? 
                         NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : 
                         NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                     attrs[.font] = newFont
                 }
                
                if key == NSAttributedString.Key("isStrikethrough") {
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
            guard let color = NSColor(hex: sanitizedHex) else { return }
            
            let range = textView.selectedRange()
            let key = NSAttributedString.Key("customColor")
            
            textView.breakUndoCoalescing()
            storage.beginEditing()
            
            if range.length > 0 {
                storage.addAttribute(key, value: sanitizedHex, range: range)
                storage.addAttribute(.foregroundColor, value: color, range: range)
            } else {
                var attrs = textView.typingAttributes
                attrs[key] = sanitizedHex
                attrs[.foregroundColor] = color
                textView.typingAttributes = attrs
            }
            
            storage.endEditing()
            textView.didChangeText()
        }

        private func toggleList(prefix: String) {
            guard let textView = self.textView else { return }
            let content = textView.string as NSString
            let range = textView.selectedRange()
            let lineRange = content.lineRange(for: NSRange(location: range.location, length: 0))
            let lineContent = content.substring(with: lineRange)
            
            let trimmedLine = lineContent.trimmingCharacters(in: .whitespaces)
            let indent = String(lineContent.prefix(while: { $0.isWhitespace }))
            
            var newLineContent = ""
            
            if prefix == "- " {
                if trimmedLine.hasPrefix("- ") {
                    newLineContent = indent + String(trimmedLine.dropFirst(2))
                } else {
                    // 如果有其它列表前缀，先移除
                    let cleaned = removeListPrefixes(trimmedLine)
                    newLineContent = indent + "- " + cleaned
                }
            } else if prefix == "1. " {
                if let _ = try? NSRegularExpression(pattern: "^\\d+\\. ").firstMatch(in: trimmedLine, options: [], range: NSRange(location: 0, length: trimmedLine.utf16.count)) {
                    newLineContent = indent + removeListPrefixes(trimmedLine)
                } else {
                    let cleaned = removeListPrefixes(trimmedLine)
                    // 查找上一行是否有序号
                    let prevNumber = findPreviousListNumber(content, currentLineRange: lineRange)
                    newLineContent = indent + "\(prevNumber + 1). " + cleaned
                }
            }
            
            textView.insertText(newLineContent, replacementRange: lineRange)
            textView.didChangeText()
        }
        
        private func removeListPrefixes(_ line: String) -> String {
            var result = line
            let patterns = ["^- \\[ \\] ", "^- \\[x\\] ", "^- ", "^\\d+\\. ", "^☐ ", "^☑ "]
            for p in patterns {
                if let regex = try? NSRegularExpression(pattern: p, options: []) {
                    result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
                }
            }
            return result.trimmingCharacters(in: .whitespaces)
        }
        
        private func findPreviousListNumber(_ content: NSString, currentLineRange: NSRange) -> Int {
            if currentLineRange.location == 0 { return 0 }
            let prevLineRange = content.lineRange(for: NSRange(location: currentLineRange.location - 1, length: 0))
            let prevLine = content.substring(with: prevLineRange).trimmingCharacters(in: .whitespaces)
            
            if let match = try? NSRegularExpression(pattern: "^(\\d+)\\. ").firstMatch(in: prevLine, options: [], range: NSRange(location: 0, length: prevLine.utf16.count)) {
                if let range = Range(match.range(at: 1), in: prevLine), let num = Int(prevLine[range]) {
                    return num
                }
            }
            return 0
        }

        private func resetFormatting() {
            guard let textView = self.textView else { return }
            let range = textView.selectedRange()
            let storage = textView.textStorage
            
            textView.breakUndoCoalescing()
            storage?.beginEditing()
            
            let keys: [NSAttributedString.Key] = [
                .foregroundColor,
                NSAttributedString.Key("customColor")
            ]
            
            if range.length > 0 {
                // 1. 针对选中区域重置颜色
                for key in keys {
                    storage?.removeAttribute(key, range: range)
                }
                storage?.addAttribute(.foregroundColor, value: NSColor.white, range: range)
            }
            
            // 2. 无论是否有选中，都重置 typingAttributes，确保后续输入为白色
            var attrs = textView.typingAttributes
            attrs.removeValue(forKey: .foregroundColor)
            attrs.removeValue(forKey: NSAttributedString.Key("customColor"))
            attrs[.foregroundColor] = NSColor.white
            textView.typingAttributes = attrs
            
            storage?.endEditing()
            textView.didChangeText()
        }

        private func toggleTodoAtCurrentLine() {
            guard let textView = self.textView, let storage = textView.textStorage else { return }
            let content = textView.string as NSString
            let range = textView.selectedRange()
            let lineRange = content.lineRange(for: NSRange(location: range.location, length: 0))
            let lineContent = content.substring(with: lineRange)
            
            // 1. 识别当前行状态
            let trimmedLine = lineContent.trimmingCharacters(in: .whitespaces)
            let indent = String(lineContent.prefix(while: { $0.isWhitespace }))
            
            var currentStatus: Int = 0 // 0: None, 1: Unfinished, 2: Finished
            if trimmedLine.hasPrefix("☐") || trimmedLine.hasPrefix("- [ ]") {
                currentStatus = 1
            } else if trimmedLine.hasPrefix("☑") || trimmedLine.hasPrefix("- [x]") {
                currentStatus = 2
            }
            
            // 2. 清理现有前缀
            var cleanedLine = trimmedLine
            let patterns = ["^☐\\s*", "^☑\\s*", "^-\\s*\\[\\s*\\]\\s*", "^-\\s*\\[x\\]\\s*"]
            for p in patterns {
                if let regex = try? NSRegularExpression(pattern: p, options: []) {
                    cleanedLine = regex.stringByReplacingMatches(in: cleanedLine, options: [], range: NSRange(location: 0, length: cleanedLine.utf16.count), withTemplate: "")
                }
            }
            
            // 3. 生成新内容
            var newLineContent = ""
            switch currentStatus {
            case 0: newLineContent = indent + "- [ ] " + cleanedLine
            case 1: newLineContent = indent + "- [x] " + cleanedLine
            case 2: newLineContent = indent + cleanedLine
            default: break
            }
            
            // 4. 使用 textStorage 直接操作，避免 insertText 的副作用
            storage.beginEditing()
            isUpdatingFromTextView = true
            
            let attrString = markdownToAttributed(newLineContent)
            storage.replaceCharacters(in: lineRange, with: attrString)
            
            // 5. 强制重置这一行的正文样式，防止属性污染
            let newLineRange = (storage.string as NSString).lineRange(for: NSRange(location: lineRange.location, length: 0))
            let baseFontSize: CGFloat = 12
            let font = NSFont.systemFont(ofSize: baseFontSize)
            let textColor = NSColor.white
            
            // 找到图标后的起始位置 (如果有图标)
            let updatedText = (storage.string as NSString).substring(with: newLineRange)
            let iconPattern = "^(☐|☑)\\s*"
            var textOffset = 0
            if let iconRegex = try? NSRegularExpression(pattern: iconPattern, options: []),
               let match = iconRegex.firstMatch(in: updatedText, options: [], range: NSRange(location: 0, length: updatedText.utf16.count)) {
                textOffset = match.range.length
            }
            
            let textPartRange = NSRange(location: newLineRange.location + textOffset, length: newLineRange.length - textOffset)
            if textPartRange.length > 0 {
                storage.addAttribute(.font, value: font, range: textPartRange)
                storage.addAttribute(.foregroundColor, value: textColor, range: textPartRange)
            }
            
            // 6. 重置 typingAttributes，防止新输入的文字变大变绿
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            paragraphStyle.minimumLineHeight = 18
            paragraphStyle.maximumLineHeight = 18
            
            textView.typingAttributes = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle
            ]
            
            isUpdatingFromTextView = false
            storage.endEditing()
            
            // 保持光标位置
            let newCursorLocation = min(storage.length, newLineRange.location + newLineRange.length)
            textView.setSelectedRange(NSRange(location: newCursorLocation, length: 0))
            
            textView.didChangeText()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if isUpdatingFromTextView { return }
            
            isUpdatingFromTextView = true
            
            // 1. 强制清理：移除那些不再是图标但还保留着 isTodoIcon 属性的残留
            cleanupOrphanedAttributes(textView)
            
            // 2. 实时渲染：将 Markdown 待办前缀原地替换为图标
            renderTodoIconsInPlace(textView)
            
            let newText = attributedToMarkdown(textView.attributedString())
            if parent.text != newText {
                parent.text = newText
            }
            isUpdatingFromTextView = false
        }

        /// 清理残留属性，防止删除图标后正文文字继承了 isTodoIcon 或颜色属性
        private func cleanupOrphanedAttributes(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            
            storage.beginEditing()
            storage.enumerateAttribute(NSAttributedString.Key("isTodoIcon"), in: fullRange, options: []) { value, range, _ in
                if value != nil {
                    let substring = (storage.string as NSString).substring(with: range)
                    // 如果这个范围内的字符不是我们定义的图标字符，则移除该属性
                    if !substring.contains("☐") && !substring.contains("☑") {
                        storage.removeAttribute(NSAttributedString.Key("isTodoIcon"), range: range)
                        // 同时重置颜色和字体为标准样式
                        let baseFontSize: CGFloat = 12
                        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: baseFontSize), range: range)
                        storage.addAttribute(.foregroundColor, value: NSColor.white, range: range)
                    }
                }
            }
            storage.endEditing()
        }
        
        /// 在 NSTextStorage 中原地替换 Markdown 待办前缀为图标，确保实时渲染
        private func renderTodoIconsInPlace(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let content = storage.string as NSString
            let pattern = "- \\[( |x)\\]"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
            
            let matches = regex.matches(in: content as String, options: [], range: NSRange(location: 0, length: content.length))
            if matches.isEmpty { return }
            
            let selectedRange = textView.selectedRange()
            var cursorOffset = 0
            var currentOffset = 0
            let baseFontSize: CGFloat = 12
            
            // 基础样式
            let baseFont = NSFont.systemFont(ofSize: baseFontSize)
            let baseTextColor = NSColor.white
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            paragraphStyle.minimumLineHeight = 18
            paragraphStyle.maximumLineHeight = 18
            
            storage.beginEditing()
            for match in matches {
                let adjustedRange = NSRange(location: match.range.location + currentOffset, length: match.range.length)
                let matchString = (storage.string as NSString).substring(with: adjustedRange)
                let isChecked = matchString.contains("x")
                
                let iconString = isChecked ? "☑ " : "☐ "
                let attrIcon = NSMutableAttributedString(string: iconString)
                let iconFont = NSFont.systemFont(ofSize: baseFontSize + 2)
                
                attrIcon.addAttributes([
                    .font: iconFont,
                    .paragraphStyle: paragraphStyle,
                    NSAttributedString.Key("isTodoIcon"): isChecked
                ], range: NSRange(location: 0, length: 1))
                
                if isChecked {
                    attrIcon.addAttribute(.foregroundColor, value: NSColor(red: 74/255, green: 222/255, blue: 128/255, alpha: 0.9), range: NSRange(location: 0, length: 1))
                } else {
                    let secondaryColor = NSColor(red: 156/255, green: 163/255, blue: 175/255, alpha: 1.0)
                    attrIcon.addAttribute(.foregroundColor, value: secondaryColor, range: NSRange(location: 0, length: 1))
                }
                
                // 替换内容
                storage.replaceCharacters(in: adjustedRange, with: attrIcon)
                
                // 关键：紧接着图标后的文字，强制重置回基础样式，防止污染后续输入
                let nextCharRange = NSRange(location: adjustedRange.location + attrIcon.length, length: 0)
                // 获取当前行的范围，重置该行剩余部分的样式
                let lineRange = (storage.string as NSString).lineRange(for: nextCharRange)
                let restOfLineRange = NSRange(location: nextCharRange.location, length: lineRange.location + lineRange.length - nextCharRange.location)
                
                if restOfLineRange.length > 0 {
                    storage.addAttribute(.font, value: baseFont, range: restOfLineRange)
                    storage.addAttribute(.foregroundColor, value: baseTextColor, range: restOfLineRange)
                }
                
                let diff = attrIcon.length - adjustedRange.length
                currentOffset += diff
                
                if adjustedRange.location < selectedRange.location {
                    cursorOffset += diff
                }
            }
            
            // 重置 typingAttributes 确保新输入的文字正常
            textView.typingAttributes = [
                .font: baseFont,
                .foregroundColor: baseTextColor,
                .paragraphStyle: paragraphStyle
            ]
            
            storage.endEditing()
            
            let newLocation = max(0, selectedRange.location + cursorOffset)
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))
        }
        
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            return true 
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // 处理回车自动补全
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let string = textView.string as NSString
                let range = textView.selectedRange()
                let lineRange = string.lineRange(for: NSRange(location: range.location, length: 0))
                let lineContent = string.substring(with: lineRange)
                
                let trimmedLine = lineContent.trimmingCharacters(in: .whitespaces)
                let indent = String(lineContent.prefix(while: { $0.isWhitespace }))

                // 1. 处理待办列表续传 (支持图标形式和 Markdown 形式)
                let isTodoIcon = lineContent.contains("☐") || lineContent.contains("☑")
                let isTodoMarkdown = trimmedLine.hasPrefix("- [ ]") || trimmedLine.hasPrefix("- [x]")
                
                if isTodoIcon || isTodoMarkdown {
                    if trimmedLine == "☐" || trimmedLine == "☑" || trimmedLine == "- [ ]" || trimmedLine == "- [x]" {
                        // 如果只有图标或前缀，回车则取消
                        textView.insertText("", replacementRange: lineRange)
                        textView.insertText("\n", replacementRange: NSRange(location: lineRange.location, length: 0))
                    } else {
                        // 统一续传为 Markdown 形式，由 renderTodoIconsInPlace 自动转为图标
                        textView.insertText("\n\(indent)- [ ] ", replacementRange: range)
                    }
                    return true
                }
                
                // 2. 处理无序列表续传 (排除掉待办的情况)
                if trimmedLine.hasPrefix("- ") {
                    if trimmedLine == "- " {
                        textView.insertText("", replacementRange: lineRange)
                        textView.insertText("\n", replacementRange: NSRange(location: lineRange.location, length: 0))
                    } else {
                        textView.insertText("\n\(indent)- ", replacementRange: range)
                    }
                    return true
                }
                
                // 3. 处理有序列表续传
                if let match = try? NSRegularExpression(pattern: "^(\\d+)\\. ").firstMatch(in: trimmedLine, options: [], range: NSRange(location: 0, length: trimmedLine.utf16.count)) {
                    if let numRange = Range(match.range(at: 1), in: trimmedLine), let num = Int(trimmedLine[numRange]) {
                        if trimmedLine == "\(num). " {
                            textView.insertText("", replacementRange: lineRange)
                            textView.insertText("\n", replacementRange: NSRange(location: lineRange.location, length: 0))
                        } else {
                            textView.insertText("\n\(indent)\(num + 1). ", replacementRange: range)
                        }
                        return true
                    }
                }
            }
            return false
        }
        
        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true)
        }
        
        func textDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }

        // MARK: - Markdown Conversion
        
        func markdownToAttributed(_ markdown: String) -> NSAttributedString {
               print("[DEBUG] markdownToAttributed called, input: \(markdown.prefix(100))")
               let attributedString = NSMutableAttributedString(string: markdown)
               let fullRange = NSRange(location: 0, length: (markdown as NSString).length)
               
               // 1. 设置基础一致样式 - 必须与 makeNSView 保持绝对一致
               let baseFontSize: CGFloat = 12
               let font = NSFont.systemFont(ofSize: baseFontSize)
               let textColor = NSColor.white
               
               let paragraphStyle = NSMutableParagraphStyle()
               paragraphStyle.lineSpacing = 4
               paragraphStyle.minimumLineHeight = 18
               paragraphStyle.maximumLineHeight = 18
               
               attributedString.addAttribute(.font, value: font, range: fullRange)
               attributedString.addAttribute(.foregroundColor, value: textColor, range: fullRange)
               attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
               
               // 2. 处理图标 - [ ] 和 - [x]
               let pattern = "- \\[( |x)\\]"
               let regex = try? NSRegularExpression(pattern: pattern, options: [])
               
               let matches = regex?.matches(in: markdown, options: [], range: NSRange(location: 0, length: (markdown as NSString).length)) ?? []
               
               // 从后往前替换，避免 offset 问题
               for match in matches.reversed() {
                   let matchRange = match.range
                   let matchString = (markdown as NSString).substring(with: matchRange)
                   let isChecked = matchString.contains("x")
                   
                   let iconString = isChecked ? "☑ " : "☐ "
                   let attrIcon = NSMutableAttributedString(string: iconString)
                   // 统一图标字体和大小，确保尺寸一致
                   let iconFont = NSFont.systemFont(ofSize: baseFontSize + 2)
                   attrIcon.addAttribute(.font, value: iconFont, range: NSRange(location: 0, length: 1))
                   // 已完成为绿色，未完成为次要文字颜色 (themeGray400)
                   let secondaryColor = NSColor(red: 156/255, green: 163/255, blue: 175/255, alpha: 1.0)
                   attrIcon.addAttribute(.foregroundColor, value: isChecked ? NSColor.systemGreen : secondaryColor, range: NSRange(location: 0, length: 1))
                   attrIcon.addAttribute(NSAttributedString.Key("isTodoIcon"), value: isChecked, range: NSRange(location: 0, length: 1))
                   // 也要给图标加上段落样式，防止行高变化
                   attrIcon.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: (iconString as NSString).length))
                   
                   attributedString.replaceCharacters(in: matchRange, with: attrIcon)
               }
            
            // 2. 处理加粗 **text**
            let boldPattern = "\\*\\*(.*?)\\*\\*"
            if let boldRegex = try? NSRegularExpression(pattern: boldPattern, options: []) {
                let boldMatches = boldRegex.matches(in: attributedString.string, options: [], range: NSRange(location: 0, length: attributedString.length))
                print("[DEBUG] Found \(boldMatches.count) bold matches")
                for match in boldMatches.reversed() {
                    let contentRange = match.range(at: 1)
                    if let font = attributedString.attribute(.font, at: contentRange.location, effectiveRange: nil) as? NSFont {
                        let boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                        attributedString.addAttribute(.font, value: boldFont, range: contentRange)
                        // 移除标记符
                        attributedString.deleteCharacters(in: NSRange(location: match.range.location + match.range.length - 2, length: 2))
                        attributedString.deleteCharacters(in: NSRange(location: match.range.location, length: 2))
                        // 添加自定义属性以便转回 Markdown
                        let newRange = NSRange(location: match.range.location, length: contentRange.length)
                        attributedString.addAttribute(NSAttributedString.Key("isBold"), value: true, range: newRange)
                    }
                }
            }
            
            // 3. 处理删除线 ~~text~~
            let strikePattern = "~~(.*?)~~"
            if let strikeRegex = try? NSRegularExpression(pattern: strikePattern, options: []) {
                let strikeMatches = strikeRegex.matches(in: attributedString.string, options: [], range: NSRange(location: 0, length: attributedString.length))
                for match in strikeMatches.reversed() {
                    let contentRange = match.range(at: 1)
                    attributedString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
                    // 移除标记符
                    attributedString.deleteCharacters(in: NSRange(location: match.range.location + match.range.length - 2, length: 2))
                    attributedString.deleteCharacters(in: NSRange(location: match.range.location, length: 2))
                    // 添加自定义属性
                    let newRange = NSRange(location: match.range.location, length: contentRange.length)
                    attributedString.addAttribute(NSAttributedString.Key("isStrikethrough"), value: true, range: newRange)
                }
            }
            
            // 4. 处理下划线 <u>text</u>
            let underlinePattern = "<u>(.*?)</u>"
            if let underlineRegex = try? NSRegularExpression(pattern: underlinePattern, options: []) {
                let underlineMatches = underlineRegex.matches(in: attributedString.string, options: [], range: NSRange(location: 0, length: attributedString.length))
                for match in underlineMatches.reversed() {
                    let contentRange = match.range(at: 1)
                    attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
                    // 移除标记符
                    attributedString.deleteCharacters(in: NSRange(location: match.range.location + match.range.length - 4, length: 4))
                    attributedString.deleteCharacters(in: NSRange(location: match.range.location, length: 3))
                    // 添加自定义属性
                    let newRange = NSRange(location: match.range.location, length: contentRange.length)
                    attributedString.addAttribute(NSAttributedString.Key("isUnderline"), value: true, range: newRange)
                }
            }

            // 5. 处理颜色 [c:hex]text[/c]
            let colorPattern = "\\[c:(#?[0-9a-fA-F]{3,8})\\](.*?)\\[/c\\]"
            if let colorRegex = try? NSRegularExpression(pattern: colorPattern, options: []) {
                let colorMatches = colorRegex.matches(in: attributedString.string, options: [], range: NSRange(location: 0, length: attributedString.length))
                for match in colorMatches.reversed() {
                    let hex = (attributedString.string as NSString).substring(with: match.range(at: 1))
                    let contentRange = match.range(at: 2)
                    // 移除 # 前缀
                    let sanitizedHex = hex.replacingOccurrences(of: "#", with: "")
                    if let color = NSColor(hex: sanitizedHex) {
                        attributedString.addAttribute(.foregroundColor, value: color, range: contentRange)
                        // 移除标记符：先移除后面的 [/c]
                        attributedString.deleteCharacters(in: NSRange(location: match.range.location + match.range.length - 4, length: 4))
                        // 再移除前面的 [c:hex]
                        let prefixLength = 3 + hex.count + 1 // [c: + hex + ]
                        attributedString.deleteCharacters(in: NSRange(location: match.range.location, length: prefixLength))

                        // 重新获取当前 range 并添加自定义属性
                        let finalRange = NSRange(location: match.range.location, length: contentRange.length)
                        attributedString.addAttribute(NSAttributedString.Key("customColor"), value: sanitizedHex, range: finalRange)
                    } else {
                        // 如果颜色解析失败，移除标记符，保留内容
                        print("[DEBUG] Failed to parse color: \(hex)")
                        // 移除标记符：先移除后面的 [/c]
                        attributedString.deleteCharacters(in: NSRange(location: match.range.location + match.range.length - 4, length: 4))
                        // 再移除前面的 [c:hex]
                        let prefixLength = 3 + hex.count + 1
                        attributedString.deleteCharacters(in: NSRange(location: match.range.location, length: prefixLength))
                    }
                }
            }
            
            return attributedString
        }
        
        func attributedToMarkdown(_ attributedString: NSAttributedString) -> String {
            print("[DEBUG] attributedToMarkdown called")
            let result = NSMutableAttributedString(attributedString: attributedString)
            
            // 按照从后往前的顺序处理，避免索引偏移
            var i = result.length - 1
            while i >= 0 {
                var range = NSRange()
                
                // 1. 处理自定义属性
                
                // 处理颜色 [c:hex]text[/c]
                if let hex = result.attribute(NSAttributedString.Key("customColor"), at: i, effectiveRange: &range) as? String {
                    result.insert(NSAttributedString(string: "[/c]"), at: range.location + range.length)
                    result.insert(NSAttributedString(string: "[c:\(hex)]"), at: range.location)
                    result.removeAttribute(NSAttributedString.Key("customColor"), range: range)
                    // 注意：这里不需要 continue，因为颜色内部可能还有加粗
                    i = range.location - 1
                    continue
                }
                
                // 处理删除线 ~~text~~
                if let _ = result.attribute(NSAttributedString.Key("isStrikethrough"), at: i, effectiveRange: &range) {
                    result.insert(NSAttributedString(string: "~~"), at: range.location + range.length)
                    result.insert(NSAttributedString(string: "~~"), at: range.location)
                    result.removeAttribute(NSAttributedString.Key("isStrikethrough"), range: range)
                    i = range.location - 1
                    continue
                }
                
                // 处理下划线 <u>text</u>
                if let _ = result.attribute(NSAttributedString.Key("isUnderline"), at: i, effectiveRange: &range) {
                    result.insert(NSAttributedString(string: "</u>"), at: range.location + range.length)
                    result.insert(NSAttributedString(string: "<u>"), at: range.location)
                    result.removeAttribute(NSAttributedString.Key("isUnderline"), range: range)
                    i = range.location - 1
                    continue
                }

                // 处理加粗 **text**
                if let _ = result.attribute(NSAttributedString.Key("isBold"), at: i, effectiveRange: &range) {
                    result.insert(NSAttributedString(string: "**"), at: range.location + range.length)
                    result.insert(NSAttributedString(string: "**"), at: range.location)
                    result.removeAttribute(NSAttributedString.Key("isBold"), range: range)
                    i = range.location - 1
                    continue
                }
                
                // 2. 处理图标 (属性或字面量)
                
                // 处理带属性的待办图标
                if let isChecked = result.attribute(NSAttributedString.Key("isTodoIcon"), at: i, effectiveRange: &range) as? Bool {
                    let markdown = isChecked ? "- [x]" : "- [ ]"
                    result.replaceCharacters(in: range, with: markdown)
                    i = range.location - 1
                    continue
                }
                
                // 处理字面量待办图标 (☐, ☑)
                let char = (result.string as NSString).substring(with: NSRange(location: i, length: 1))
                if char == "☐" {
                    result.replaceCharacters(in: NSRange(location: i, length: 1), with: "- [ ]")
                    i -= 1
                    continue
                } else if char == "☑" {
                    result.replaceCharacters(in: NSRange(location: i, length: 1), with: "- [x]")
                    i -= 1
                    continue
                }
                
                i -= 1
            }

            let markdown = result.string
            print("[DEBUG] attributedToMarkdown output: \(markdown.prefix(100))")
            return markdown
        }
    }
}

/// 自定义 NSTextView 以处理特殊的交互和显示
class StickyNoteTextView: NSTextView {
    /// 覆盖粘贴方法，保留颜色格式，但清除其他富文本格式
    override func paste(_ sender: Any?) {
        // 从剪贴板读取数据
        let pasteboard = NSPasteboard.general

        // 优先读取纯文本
        guard let plainText = pasteboard.string(forType: .string) else {
            super.paste(sender)
            return
        }

        // 获取当前选区
        let selectedRange = self.selectedRange()

        // 转换纯文本为带样式的 NSAttributedString，处理颜色标记
        let baseFontSize: CGFloat = 12
        let font = NSFont.systemFont(ofSize: baseFontSize)
        let textColor = NSColor.white
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.minimumLineHeight = 18
        paragraphStyle.maximumLineHeight = 18

        // 创建基础样式
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]

        // 使用 markdownToAttributed 来处理粘贴的文本
        // 这样可以保留颜色、加粗、删除线等格式
        let coordinator = delegate as? StickyNoteEditor.Coordinator
        let attributedString = coordinator?.markdownToAttributed(plainText) ?? NSMutableAttributedString(string: plainText, attributes: baseAttributes)

        // 插入处理后的文本
        textStorage?.beginEditing()
        textStorage?.replaceCharacters(in: selectedRange, with: attributedString)
        textStorage?.endEditing()

        // 设置新的光标位置
        let newCursorLocation = selectedRange.location + attributedString.length
        setSelectedRange(NSRange(location: newCursorLocation, length: 0))

        // 通知代理内容已更改
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // 1. 先尝试检测是否点击在待办图标上
        if let layoutManager = layoutManager, let textContainer = textContainer {
            // 关键：调整坐标以考虑 textContainerInset
            let adjustedPoint = NSPoint(
                x: point.x - textContainerInset.width,
                y: point.y - textContainerInset.height
            )
            
            // 获取点击位置的字符索引
            var fraction: CGFloat = 0
            let glyphIndex = layoutManager.glyphIndex(for: adjustedPoint, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            
            if charIndex < textStorage?.length ?? 0 {
                let attrString = attributedString()
                var effectiveRange = NSRange()
                let value = attrString.attribute(NSAttributedString.Key("isTodoIcon"), at: charIndex, effectiveRange: &effectiveRange)
                
                // 关键校验：必须点击在图标字符（☐ 或 ☑）上才触发切换
                let char = (attrString.string as NSString).substring(with: NSRange(location: charIndex, length: 1))
                let isActuallyIcon = char == "☐" || char == "☑"
                
                if value != nil && isActuallyIcon {
                        // 切换状态
                        if let isChecked = value as? Bool {
                            let newChecked = !isChecked
                            let iconString = newChecked ? "☑ " : "☐ "
                            
                            let attrIcon = NSMutableAttributedString(string: iconString)
                            // 统一图标字体和大小，确保尺寸一致
                            let baseFontSize: CGFloat = 12
                            let iconFont = NSFont.systemFont(ofSize: baseFontSize + 2)
                            attrIcon.addAttribute(.font, value: iconFont, range: NSRange(location: 0, length: 1))
                            let secondaryColor = NSColor(red: 156/255, green: 163/255, blue: 175/255, alpha: 1.0)
                            attrIcon.addAttribute(.foregroundColor, value: newChecked ? NSColor.systemGreen : secondaryColor, range: NSRange(location: 0, length: 1))
                            attrIcon.addAttribute(NSAttributedString.Key("isTodoIcon"), value: newChecked, range: NSRange(location: 0, length: 1))
                            
                            let paragraphStyle = NSMutableParagraphStyle()
                            paragraphStyle.lineSpacing = 4
                            paragraphStyle.minimumLineHeight = 18
                            paragraphStyle.maximumLineHeight = 18
                            attrIcon.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: 1))
                            
                            // 获取协调器以设置标志位
                            let coordinator = delegate as? StickyNoteEditor.Coordinator
                            coordinator?.isUpdatingFromTextView = true
                            
                            textStorage?.beginEditing()
                            textStorage?.replaceCharacters(in: NSRange(location: charIndex, length: 1), with: attrIcon)
                            textStorage?.endEditing()
                            
                            coordinator?.isUpdatingFromTextView = false
                        
                        // 触发同步
                        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
                        return 
                    }
                }
            }
        }
        
        super.mouseDown(with: event)
    }

    /// 键盘事件处理回调 - 在默认处理之前调用
    /// 返回 true 表示事件已处理，不会继续传递
    var onKeyDown: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        print("[StickyNoteTextView] keyDown 被调用，keyCode=\(event.keyCode), onKeyDown=\(onKeyDown != nil)")

        // 先让回调处理事件
        if let callback = onKeyDown {
            let handled = callback(event)
            print("[StickyNoteTextView] 回调返回: \(handled)")
            if handled {
                return // 事件已被处理，不继续传递
            }
        }

        // 默认处理
        print("[StickyNoteTextView] 传递给 super.keyDown")
        super.keyDown(with: event)
    }

    // 更彻底地拦截键盘事件，阻止 interpretKeyEvents
    override func interpretKeyEvents(_ eventArray: [NSEvent]) {
        print("[StickyNoteTextView] interpretKeyEvents 被调用，事件数量: \(eventArray.count)")

        // 检查第一个事件是否被回调处理
        if let event = eventArray.first,
           let callback = onKeyDown {
            let handled = callback(event)
            print("[StickyNoteTextView] interpretKeyEvents 回调返回: \(handled)")
            if handled {
                return // 事件已被处理，不传递给 interpretKeyEvents
            }
        }

        print("[StickyNoteTextView] 传递给 super.interpretKeyEvents")
        super.interpretKeyEvents(eventArray)
    }
}
