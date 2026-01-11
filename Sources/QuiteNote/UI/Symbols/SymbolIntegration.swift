import SwiftUI
import Combine

// MARK: - Custom NSPanel for Click Support

/// 自定义 NSPanel，允许接收点击事件
/// NSPanel 默认的 canBecomeKey 返回 false，导致无法接收鼠标事件
class ClickableNSPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        print("[ClickableNSPanel] ✅ mouseDown event received: \(event)")
        super.mouseDown(with: event)
    }
}

// MARK: - Custom NSHostingView for Click Support

/// 自定义 NSHostingView，确保能正确传递点击事件到 SwiftUI
class ClickableNSHostingView<Content: View>: NSHostingView<Content> {
    override func mouseDown(with event: NSEvent) {
        print("[ClickableNSHostingView] ✅ mouseDown event received: \(event)")
        super.mouseDown(with: event)
    }

    override var acceptsFirstResponder: Bool { true }
}

// MARK: - Logging Helper

/// 追加日志到文件
private func appendLog(_ message: String, toPath path: String) {
    // 确保文件存在
    if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil, attributes: nil)
    }

    if let fileHandle = FileHandle(forWritingAtPath: path) {
        defer { fileHandle.closeFile() }
        fileHandle.seekToEndOfFile()
        if let data = message.data(using: .utf8) {
            fileHandle.write(data)
        }
    }
}

// MARK: - Associated Keys

private struct AssociatedKeys {
    static var symbolDetector = "symbolDetector"
    static var symbolSuggestionPanelHost = "symbolSuggestionPanelHost"
    static var symbolPanelWindow = "symbolPanelWindow"
    static var symbolTextView = "symbolTextView"
    static var symbolSelectedIndex = "symbolSelectedIndex"
    static var symbolKeyMonitor = "symbolKeyMonitor"
    static var symbolSelectionState = "symbolSelectionState"
    static var symbolPanelAboveCursor = "symbolPanelAboveCursor" // 跟踪面板是否在光标上方
    static var symbolPanelAnchorPoint = "symbolPanelAnchorPoint" // 固定参考点（用于面板高度变化时保持位置稳定）
}

/// 符号选择状态管理器 - 使用 ObservableObject 确保 SwiftUI 能正确更新
class SymbolSelectionState: ObservableObject {
    @Published var selectedIndex: Int = 0
}

/// 符号快捷功能集成到 StickyNote
extension StickyNoteEditor.Coordinator {
    // MARK: - Public Methods for Coordinator to Call

    /// Public method that can be called from Coordinator's showSymbolSuggestionPanel
    func showSymbolSuggestionPanelExtension(at cursorInfo: CursorLocationInfo?, triggerText: String, suggestions: [SymbolItem], parentWindow: NSWindow?) {
        let logPath = "/tmp/quitenote-symbol-debug.log"
        let timestamp = Date()
        let logMsg = "[SymbolIntegration] [\(timestamp)] showSymbolSuggestionPanelExtension called: cursorInfo=\(cursorInfo?.debugDescription ?? "nil"), trigger='\(triggerText)', suggestions=\(suggestions.count)\n"
        print(logMsg)
        appendLog(logMsg, toPath: logPath)

        guard let cursorInfo = cursorInfo else {
            print("[SymbolIntegration] ⚠️ cursorInfo 为 nil，无法显示面板")
            return
        }

        // Store trigger info for the extension methods to use
        self.updateSymbolTriggerInfo(triggerText: triggerText, suggestions: suggestions)

        // Call the existing implementation
        self.performShowSymbolSuggestionPanel(at: cursorInfo, triggerText: triggerText, suggestions: suggestions, parentWindow: parentWindow)
    }

    /// Public method that can be called from Coordinator's hideSymbolSuggestionPanel
    func hideSymbolSuggestionPanelExtension() {
        // Call the existing implementation
        self.performHideSymbolSuggestionPanel()
    }

    /// Store trigger info temporarily
    private func updateSymbolTriggerInfo(triggerText: String, suggestions: [SymbolItem]) {
        // The extension uses its own state management via associated objects
        // This is just a placeholder if we need to pass additional info
    }

    // The actual implementation (renamed from private methods to allow calling)
    private func performShowSymbolSuggestionPanel(at cursorInfo: CursorLocationInfo, triggerText: String, suggestions: [SymbolItem], parentWindow: NSWindow?) {
        // This is the original showSymbolSuggestionPanel implementation
        // We'll call the original method by its original name
        self.internalShowSymbolSuggestionPanel(at: cursorInfo, triggerText: triggerText, suggestions: suggestions, parentWindow: parentWindow)
    }

    private func performHideSymbolSuggestionPanel() {
        // This is the original hideSymbolSuggestionPanel implementation
        self.internalHideSymbolSuggestionPanel()
    }
    // MARK: - Helper Properties

    /// Helper property to access textView without ambiguity
    private var symbolTextView: NSTextView? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.symbolTextView) as? NSTextView }
        set { objc_setAssociatedObject(self, &AssociatedKeys.symbolTextView, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// 符号选择状态
    private var symbolSelectionState: SymbolSelectionState {
        if let state = objc_getAssociatedObject(self, &AssociatedKeys.symbolSelectionState) as? SymbolSelectionState {
            return state
        }
        let state = SymbolSelectionState()
        objc_setAssociatedObject(self, &AssociatedKeys.symbolSelectionState, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return state
    }

    /// 当前选中的建议索引（保持兼容性）
    private var symbolSelectedIndex: Int {
        get { objc_getAssociatedObject(self, &AssociatedKeys.symbolSelectedIndex) as? Int ?? 0 }
        set { objc_setAssociatedObject(self, &AssociatedKeys.symbolSelectedIndex, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// 键盘事件监听器
    private var symbolKeyMonitor: Any? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.symbolKeyMonitor) }
        set { objc_setAssociatedObject(self, &AssociatedKeys.symbolKeyMonitor, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// 面板是否在光标上方（用于筛选时保持位置基准）
    private var symbolPanelAboveCursor: Bool {
        get { objc_getAssociatedObject(self, &AssociatedKeys.symbolPanelAboveCursor) as? Bool ?? false }
        set { objc_setAssociatedObject(self, &AssociatedKeys.symbolPanelAboveCursor, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// 固定参考点（用于面板高度变化时保持位置稳定）
    /// 首次创建面板时保存，更新时使用保存的参考点而非当前的 cursorInfo.lineRect
    private var symbolPanelAnchorPoint: NSPoint? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.symbolPanelAnchorPoint) as? NSPoint }
        set { objc_setAssociatedObject(self, &AssociatedKeys.symbolPanelAnchorPoint, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    // MARK: - Symbol Integration State

    private var symbolDetector: SymbolTriggerDetector {
        if let detector = objc_getAssociatedObject(self, &AssociatedKeys.symbolDetector) as? SymbolTriggerDetector {
            return detector
        }
        let detector = SymbolTriggerDetector()
        objc_setAssociatedObject(self, &AssociatedKeys.symbolDetector, detector, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return detector
    }

    private var symbolSuggestionPanelHost: NSHostingView<SymbolSuggestionPanelWrapper>? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.symbolSuggestionPanelHost) as? NSHostingView<SymbolSuggestionPanelWrapper> }
        set { objc_setAssociatedObject(self, &AssociatedKeys.symbolSuggestionPanelHost, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var symbolPanelWindow: NSPanel? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.symbolPanelWindow) as? NSPanel }
        set { objc_setAssociatedObject(self, &AssociatedKeys.symbolPanelWindow, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    // MARK: - Setup Symbol Detection

    func setupSymbolDetection(for textView: NSTextView) {
        print("[SymbolIntegration] 设置符号检测，textView: \(textView)")
        // Store reference to textView for later use
        symbolTextView = textView

        // 检查配置是否已加载
        let configCount = SymbolConfigManager.shared.configs.count
        print("[SymbolIntegration] 当前已加载 \(configCount) 个符号配置")

        // 监听文本变化
        NotificationCenter.default.publisher(for: NSText.didChangeNotification, object: textView)
            .sink { [weak self, weak textView] _ in
                guard let textView = textView else { return }
                self?.handleSymbolDetection(textView: textView)
            }
            .store(in: &cancellables)

        // ⭐ 关键修复：监听窗口失焦通知，隐藏联想面板
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
            .sink { [weak self] notification in
                guard let self = self else { return }
                // 检查失焦的窗口是否是我们关心的窗口
                if let window = notification.object as? NSWindow,
                   window == self.symbolTextView?.window {
                    print("[SymbolIntegration] 窗口失焦，隐藏联想面板")
                    self.internalHideSymbolSuggestionPanel()
                    self.symbolDetector.clearDetection()
                }
            }
            .store(in: &cancellables)

        // ⭐ 关键修复：监听文本编辑器失焦通知，隐藏联想面板
        NotificationCenter.default.publisher(for: NSText.didEndEditingNotification, object: textView)
            .sink { [weak self] _ in
                guard let self = self else { return }
                print("[SymbolIntegration] 文本编辑器失焦，隐藏联想面板")
                self.internalHideSymbolSuggestionPanel()
                self.symbolDetector.clearDetection()
            }
            .store(in: &cancellables)

        // 监听工具栏按钮点击 - 打开符号浏览器
        NotificationCenter.default.publisher(for: .showSymbolBrowser)
            .sink { [weak self, weak textView] _ in
                guard let self = self, let textView = textView else { return }
                print("[SymbolIntegration] 打开符号浏览器")
                SymbolBrowserBridge.shared.show(from: textView)
            }
            .store(in: &cancellables)

        // 监听符号浏览器选择 - 插入符号
        NotificationCenter.default.publisher(for: .insertSymbolFromBrowser)
            .sink { [weak self, weak textView] notification in
                guard let self = self, let textView = textView else { return }
                if let userInfo = notification.userInfo {
                    // 检查是否是 floating 或 inline 模式
                    if let mode = userInfo["mode"] as? String,
                       let symbol = userInfo["symbol"] as? SymbolItem {
                        print("[SymbolIntegration] \(mode)模式插入符号: \(symbol.content)")
                        self.insertSymbolDirectly(textView: textView, symbol: symbol)
                    }
                    // 旧模式：直接传递 newText 和 newCursorPos
                    else if let newText = userInfo["newText"] as? String,
                            let newCursorPos = userInfo["newCursorPos"] as? Int {
                        print("[SymbolIntegration] 插入符号: newCursorPos=\(newCursorPos)")
                        self.insertSymbolText(textView: textView, newText: newText, newCursorPos: newCursorPos)
                    }
                }
            }
            .store(in: &cancellables)

        print("[SymbolIntegration] 符号检测设置完成")
    }

    private func handleSymbolDetection(textView: NSTextView) {
        let text = textView.string
        let cursorPosition = textView.selectedRange().location

        // 检测触发词
        symbolDetector.detectTrigger(in: text, cursorPosition: cursorPosition)

        // 调试输出
        if let trigger = symbolDetector.detectedTrigger {
            print("[SymbolIntegration] 检测到触发词: ':/\(trigger)' (长度: \(trigger.count)), 建议: \(symbolDetector.suggestions.count) 个")
        } else {
            print("[SymbolIntegration] 未检测到触发词")
        }

        // 更新联想面板
        updateSymbolSuggestionPanel(textView: textView)
    }

    private func updateSymbolSuggestionPanel(textView: NSTextView) {
        // 如果没有检测到触发词，隐藏面板
        guard let triggerText = symbolDetector.detectedTrigger,
              !symbolDetector.suggestions.isEmpty else {
            internalHideSymbolSuggestionPanel()
            return
        }

        // 获取光标位置信息（包含文本行矩形，确保不遮挡输入文本）
        guard let cursorInfo = textView.cursorLocationInfo() else {
            print("[SymbolIntegration] ⚠️ 无法获取光标位置信息")
            return
        }

        // 显示联想面板（传递完整的光标位置信息）
        internalShowSymbolSuggestionPanel(at: cursorInfo, triggerText: triggerText, suggestions: symbolDetector.suggestions, parentWindow: textView.window)
    }

    private func internalShowSymbolSuggestionPanel(at cursorInfo: CursorLocationInfo, triggerText: String, suggestions: [SymbolItem], parentWindow: NSWindow?) {
        let logPath = "/tmp/quitenote-symbol-debug.log"
        let timestamp = Date()
        let logMsg = "[SymbolIntegration] [\(timestamp)] internalShowSymbolSuggestionPanel: cursorPosition=\(cursorInfo.cursorPosition), lineRect=\(cursorInfo.lineRect), trigger='\(triggerText)', suggestions=\(suggestions.count)\n"
        print(logMsg)
        appendLog(logMsg, toPath: logPath)

        // 检查面板是否已存在
        let panelExists = symbolPanelWindow != nil
        let hostExists = symbolSuggestionPanelHost != nil
        let logMsg2 = "[SymbolIntegration] 面板状态: panelExists=\(panelExists), hostExists=\(hostExists)\n"
        print(logMsg2)
        appendLog(logMsg2, toPath: logPath)

        // 重置选中索引（每次显示面板时都重置）
        symbolSelectionState.selectedIndex = 0

        // 计算面板大小
        let panelWidth: CGFloat = 300
        let newPanelHeight = calculatePanelHeight(for: suggestions)

        // 如果面板已存在，更新内容和位置
        if let existingWindow = symbolPanelWindow,
           let existingHost = symbolSuggestionPanelHost {
            let logMsg3 = "[SymbolIntegration] 面板已存在，更新内容和位置。现有窗口 frame: \(existingWindow.frame), isVisible: \(existingWindow.isVisible)\n"
            print(logMsg3)
            appendLog(logMsg3, toPath: logPath)

            // ⭐ 关键修复：更新面板时，使用保存的固定参考点而非当前的 cursorInfo.lineRect
            // 这样可以确保面板高度变化时，锚点保持不变，不会"飘走"

            // 读取保存的固定参考点
            guard let anchorPoint = symbolPanelAnchorPoint else {
                // 如果没有保存的参考点（异常情况），回退到使用当前 cursorInfo
                appendLog("[SymbolIntegration] ⚠️ 缺少保存的参考点，回退到当前 cursorInfo\n", toPath: logPath)
                let panelOrigin: NSPoint
                if symbolPanelAboveCursor {
                    panelOrigin = cursorInfo.panelPositionAbove(height: newPanelHeight, gap: 8)
                } else {
                    panelOrigin = cursorInfo.panelPositionBelow(height: newPanelHeight, gap: 8)
                }
                // 保存当前参考点供下次使用
                symbolPanelAnchorPoint = NSPoint(x: cursorInfo.lineRect.midX, y: symbolPanelAboveCursor ? cursorInfo.lineRect.maxY : cursorInfo.lineRect.minY)

                appendLog("[SymbolIntegration] 更新面板位置: \(panelOrigin), 大小: \(panelWidth)x\(newPanelHeight), aboveCursor: \(symbolPanelAboveCursor)\n", toPath: logPath)

                SymbolSuggestionPanelBridge.setPanelVisible(true)

                // 更新内容和位置
                let wrapper = SymbolSuggestionPanelWrapper(
                    triggerText: triggerText,
                    suggestions: suggestions,
                    selectionState: symbolSelectionState,
                    onSelect: { [weak self] symbol in
                        self?.insertSelectedSymbol(symbol)
                    }
                )
                existingHost.rootView = wrapper

                // 更新面板位置和大小
                let newFrame = NSRect(origin: panelOrigin, size: NSSize(width: panelWidth, height: newPanelHeight))
                existingWindow.setFrame(newFrame, display: true, animate: false)

                setupKeyboardMonitor()
                return
            }

            appendLog("[SymbolIntegration] 📍 使用保存的参考点: \(anchorPoint)\n", toPath: logPath)

            // 使用保存的固定参考点计算面板位置
            let panelOrigin: NSPoint
            if symbolPanelAboveCursor {
                // 面板在上方：面板底部固定在 anchorPoint.y + gap
                // anchorPoint.y 是文本行顶部 (lineRect.maxY)
                panelOrigin = NSPoint(x: cursorInfo.cursorPosition.x, y: anchorPoint.y + 8)
            } else {
                // 面板在下方：面板顶部固定在 anchorPoint.y - gap
                // anchorPoint.y 是文本行底部 (lineRect.minY)
                panelOrigin = NSPoint(x: cursorInfo.cursorPosition.x, y: anchorPoint.y - 8 - newPanelHeight)
            }

            appendLog("[SymbolIntegration] 更新面板位置: \(panelOrigin), 大小: \(panelWidth)x\(newPanelHeight), aboveCursor: \(symbolPanelAboveCursor)\n", toPath: logPath)

            // ⭐ 关键修复：确保面板可见性标记为 true（防止边界情况）
            SymbolSuggestionPanelBridge.setPanelVisible(true)

            // 更新内容和位置
            let wrapper = SymbolSuggestionPanelWrapper(
                triggerText: triggerText,
                suggestions: suggestions,
                selectionState: symbolSelectionState,
                onSelect: { [weak self] symbol in
                    self?.insertSelectedSymbol(symbol)
                }
            )
            existingHost.rootView = wrapper

            // 更新面板位置和大小
            let newFrame = NSRect(origin: panelOrigin, size: NSSize(width: panelWidth, height: newPanelHeight))
            existingWindow.setFrame(newFrame, display: true, animate: false)

            // ⭐ 关键修复：每次面板显示时都重新设置键盘监听，不检查 symbolKeyMonitor
            // 这样可以确保键盘回调始终使用最新的面板状态
            setupKeyboardMonitor()

            return
        }

        appendLog("[SymbolIntegration] 面板不存在，开始创建新面板\n", toPath: logPath)

        appendLog("[SymbolIntegration] 计算面板大小: \(panelWidth)x\(newPanelHeight)\n", toPath: logPath)

        // ⭐ 关键修复：首次创建面板时，判断应该显示在上方还是下方
        // 使用默认高度（300px）来判断，确保位置一致
        let defaultPanelHeight: CGFloat = 300
        var panelOrigin: NSPoint
        var showAboveCursor = false

        // 检查屏幕可用空间，决定面板位置
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let spaceBelow = cursorInfo.lineRect.minY - screenFrame.minY

            // 如果下方的空间不足以容纳默认高度的面板，则显示在上方
            if spaceBelow < defaultPanelHeight + 8 { // +8 for gap
                showAboveCursor = true
                panelOrigin = cursorInfo.panelPositionAbove(height: newPanelHeight, gap: 8)
            } else {
                showAboveCursor = false
                panelOrigin = cursorInfo.panelPositionBelow(height: newPanelHeight, gap: 8)
            }
        } else {
            // 无法获取屏幕信息时，默认显示在下方
            showAboveCursor = false
            panelOrigin = cursorInfo.panelPositionBelow(height: newPanelHeight, gap: 8)
        }

        // 更新标志
        symbolPanelAboveCursor = showAboveCursor

        // ⭐ 关键修复：首次创建面板时，保存固定参考点
        // 这样在面板高度变化时，锚点保持不变，不会"飘走"
        if showAboveCursor {
            // 面板在上方：保存文本行顶部作为参考点
            symbolPanelAnchorPoint = NSPoint(x: cursorInfo.lineRect.midX, y: cursorInfo.lineRect.maxY)
            appendLog("[SymbolIntegration] 📍 保存上方参考点: \(symbolPanelAnchorPoint!)\n", toPath: logPath)
        } else {
            // 面板在下方：保存文本行底部作为参考点
            symbolPanelAnchorPoint = NSPoint(x: cursorInfo.lineRect.midX, y: cursorInfo.lineRect.minY)
            appendLog("[SymbolIntegration] 📍 保存下方参考点: \(symbolPanelAnchorPoint!)\n", toPath: logPath)
        }

        // ⭐ 关键修复：确保面板在屏幕边界内
        panelOrigin = adjustPanelOriginToFitScreen(
            panelOrigin: panelOrigin,
            panelWidth: panelWidth,
            panelHeight: newPanelHeight,
            cursorInfo: cursorInfo
        )

        appendLog("[SymbolIntegration] 显示联想面板，光标屏幕坐标: \(cursorInfo.cursorPosition), 面板原点: \(panelOrigin), 面板大小: \(panelWidth)x\(newPanelHeight), aboveCursor: \(symbolPanelAboveCursor)\n", toPath: logPath)
        appendLog("[SymbolIntegration] parentWindow: \(parentWindow?.debugDescription ?? "nil")\n", toPath: logPath)

        // ⭐ 修复点击问题：使用自定义 ClickableNSPanel 覆盖 canBecomeKey
        let panel = ClickableNSPanel(
            contentRect: NSRect(origin: panelOrigin, size: NSSize(width: panelWidth, height: newPanelHeight)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = true
        panel.contentView?.wantsLayer = true
        panel.alphaValue = 1.0

        appendLog("[SymbolIntegration] ✅ 面板配置 - styleMask: \(panel.styleMask), level: \(panel.level.rawValue), canBecomeKey: \(panel.canBecomeKey)\n", toPath: logPath)

        appendLog("[SymbolIntegration] 面板创建完成，level: \(panel.level.rawValue), alphaValue: \(panel.alphaValue)\n", toPath: logPath)

        let wrapper = SymbolSuggestionPanelWrapper(
            triggerText: triggerText,
            suggestions: suggestions,
            selectionState: symbolSelectionState,
            onSelect: { [weak self] symbol in
                self?.insertSelectedSymbol(symbol)
            }
        )

        // ⭐ 使用自定义 ClickableNSHostingView 确保点击事件传递
        let hostingView = ClickableNSHostingView(rootView: wrapper)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        appendLog("[SymbolIntegration] SwiftUI hosting view 已设置\n", toPath: logPath)

        // 显示面板
        if let parentWindow = parentWindow {
            parentWindow.addChildWindow(panel, ordered: .above)
            appendLog("[SymbolIntegration] 面板已添加为父窗口的子窗口\n", toPath: logPath)
            // 确保文本视图保持焦点
            if let textView = symbolTextView, let window = textView.window {
                window.makeFirstResponder(textView)
                appendLog("[SymbolIntegration] 重新设置文本视图为 firstResponder\n", toPath: logPath)
            }
        } else {
            appendLog("[SymbolIntegration] ⚠️ parentWindow 为 nil，面板将作为独立窗口显示\n", toPath: logPath)
        }

        panel.orderFrontRegardless()
        symbolPanelWindow = panel
        symbolSuggestionPanelHost = hostingView

        appendLog("[SymbolIntegration] 面板已显示，isVisible: \(panel.isVisible), frame: \(panel.frame)\n", toPath: logPath)

        // ⭐ 关键修复：标记面板为可见状态，让主窗口知道不拦截 ESC
        SymbolSuggestionPanelBridge.setPanelVisible(true)

        // ⭐ 关键修复：面板显示后立即设置键盘监听，不检查 symbolKeyMonitor
        // 这样可以确保键盘回调始终使用最新的面板状态
        setupKeyboardMonitor()

        // 验证焦点设置
        if let textView = symbolTextView, let window = textView.window {
            let firstResponderDesc = window.firstResponder.map { String(describing: $0) } ?? "nil"
            print("[SymbolIntegration] 当前 firstResponder: \(firstResponderDesc), 文本视图: \(textView)")
        }
    }

    /// 调整面板原点以确保面板在屏幕边界内
    /// 注意：不再切换到光标另一侧，因为上面/下方的决策已在主逻辑中完成
    private func adjustPanelOriginToFitScreen(panelOrigin: NSPoint, panelWidth: CGFloat, panelHeight: CGFloat, cursorInfo: CursorLocationInfo) -> NSPoint {
        var adjustedOrigin = panelOrigin

        guard let screen = NSScreen.main else {
            return adjustedOrigin
        }

        let screenFrame = screen.visibleFrame

        // 调整 x 坐标：防止面板超出屏幕左右边界
        if adjustedOrigin.x + panelWidth > screenFrame.maxX {
            adjustedOrigin.x = screenFrame.maxX - panelWidth - 10
        }
        if adjustedOrigin.x < screenFrame.minX {
            adjustedOrigin.x = screenFrame.minX + 10
        }

        // ⭐ 修复：只调整 y 坐标确保面板在屏幕边界内，不切换上下位置
        // 如果面板底部超出屏幕底部，将面板底部对齐到屏幕底部
        if adjustedOrigin.y < screenFrame.minY {
            adjustedOrigin.y = screenFrame.minY
        }
        // 如果面板顶部超出屏幕顶部，将面板顶部对齐到屏幕顶部
        if adjustedOrigin.y + panelHeight > screenFrame.maxY {
            adjustedOrigin.y = screenFrame.maxY - panelHeight
        }

        return adjustedOrigin
    }

    /// 计算面板高度
    private func calculatePanelHeight(for suggestions: [SymbolItem]) -> CGFloat {
        let rowHeight: CGFloat = 44
        let maxHeight: CGFloat = 300
        let minHeight: CGFloat = 60

        if suggestions.isEmpty {
            return minHeight
        }

        let contentHeight = CGFloat(suggestions.count) * rowHeight
        return min(max(contentHeight, minHeight), maxHeight)
    }

    private func internalHideSymbolSuggestionPanel() {
        // ⭐ 关键修复：标记面板为不可见状态，让主窗口恢复拦截 ESC
        SymbolSuggestionPanelBridge.setPanelVisible(false)

        // ⭐ 关键修复：不要清空 onKeyDown 回调，保持监听状态
        // 回调会在 handleKeyboardEvent 中检查面板状态，只有面板显示时才处理事件
        // if let textView = symbolTextView as? StickyNoteTextView {
        //     textView.onKeyDown = nil
        // }

        // ⭐ 关键修复：不要清除 symbolKeyMonitor，保持键盘监听状态
        // 这样下次面板显示时不需要重新设置回调
        // symbolKeyMonitor = nil

        // 关闭面板
        symbolPanelWindow?.close()
        symbolPanelWindow = nil
        symbolSuggestionPanelHost = nil

        // ⭐ 关键修复：清除保存的固定参考点
        symbolPanelAnchorPoint = nil

        // 清除触发检测状态，确保下次可以正常触发
        symbolDetector.clearDetection()
        print("[SymbolIntegration] 隐藏面板并清除触发检测状态")
    }

    /// 设置键盘事件监听
    private func setupKeyboardMonitor() {
        let logPath = "/tmp/quitenote-symbol-debug.log"
        appendLog("[SymbolIntegration] ========== setupKeyboardMonitor() 开始 ==========\n", toPath: logPath)

        // ⭐ 关键修复：每次面板显示时都重新设置，不检查是否已存在
        // 这样可以确保面板显示后键盘回调始终有效

        // 使用标志确保只设置一次
        guard let textView = symbolTextView else {
            appendLog("[SymbolIntegration] ⚠️ symbolTextView 为 nil\n", toPath: logPath)
            return
        }

        // 检查 window 是否可用
        guard let parentWindow = textView.window else {
            appendLog("[SymbolIntegration] ⚠️ textView.window 为 nil，延迟设置\n", toPath: logPath)
            // 延迟到下一个 runloop 设置
            DispatchQueue.main.async { [weak self] in
                self?.setupKeyboardMonitor()
            }
            return
        }

        appendLog("[SymbolIntegration] ✅ 获取到 textView 和 parentWindow: \(parentWindow.title)\n", toPath: logPath)
        appendLog("[SymbolIntegration] 当前 symbolPanelWindow: \(symbolPanelWindow != nil ? "存在" : "nil")\n", toPath: logPath)

        // 只设置 textView 的回调
        if let stickyTextView = textView as? StickyNoteTextView {
            // 先清除旧回调
            stickyTextView.onKeyDown = nil
            appendLog("[SymbolIntegration] 清除旧回调\n", toPath: logPath)

            // 设置新回调
            stickyTextView.onKeyDown = { [weak self] event in
                guard let self = self else {
                    appendLog("[SymbolIntegration] ⚠️ self 已释放\n", toPath: "/tmp/quitenote-symbol-debug.log")
                    return false
                }

                // ⭐ 关键检查：只在面板显示时处理键盘事件
                // 使用捕获的面板状态，而不是检查 symbolPanelWindow
                let panelWindow = self.symbolPanelWindow
                guard panelWindow != nil else {
                    appendLog("[SymbolIntegration] ⚠️ 面板已关闭，不处理键盘事件 (keyCode=\(event.keyCode))\n", toPath: "/tmp/quitenote-symbol-debug.log")
                    return false
                }

                let handled = self.handleKeyboardEvent(event)
                appendLog("[SymbolIntegration] 🔔 键盘事件: keyCode=\(event.keyCode), handled=\(handled)\n", toPath: "/tmp/quitenote-symbol-debug.log")
                return handled
            }

            // 标记已设置
            symbolKeyMonitor = true as AnyObject
            appendLog("[SymbolIntegration] ✅ 键盘回调已设置\n", toPath: logPath)
        } else {
            appendLog("[SymbolIntegration] ⚠️ textView 不是 StickyNoteTextView 类型: \(type(of: textView))\n", toPath: logPath)
        }
    }

    /// 处理键盘事件的统一方法
    private func handleKeyboardEvent(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        print("[SymbolIntegration] 🔔 handleKeyboardEvent: keyCode=\(keyCode), modifiers=\(modifiers), panelWindow=\(symbolPanelWindow != nil)")
        appendLog("[SymbolIntegration] 🔔 handleKeyboardEvent: keyCode=\(keyCode), modifiers=\(modifiers), panelWindow=\(symbolPanelWindow != nil)\n", toPath: "/tmp/quitenote-symbol-debug.log")

        // ⭐ 关键修复：检查面板是否真实显示（不仅仅是 window != nil）
        // 使用 isVisible 检查面板是否真的在屏幕上
        guard let panelWindow = symbolPanelWindow, panelWindow.isVisible else {
            appendLog("[SymbolIntegration] ⚠️ 面板未显示，不处理键盘事件\n", toPath: "/tmp/quitenote-symbol-debug.log")
            return false
        }

        // ESC - 取消
        if keyCode == 53 { // ESC key
            appendLog("[SymbolIntegration] ✅ ESC - 取消\n", toPath: "/tmp/quitenote-symbol-debug.log")
            internalHideSymbolSuggestionPanel()
            symbolDetector.clearDetection()
            return true // 消费事件，阻止传递给主面板
        }

        // Enter - 确认选择
        if keyCode == 36 && modifiers.isEmpty { // Enter key, no modifiers
            let suggestions = symbolDetector.suggestions
            let currentIndex = symbolSelectionState.selectedIndex
            appendLog("[SymbolIntegration] ✅ Enter - suggestions.count=\(suggestions.count), currentIndex=\(currentIndex)\n", toPath: "/tmp/quitenote-symbol-debug.log")
            if !suggestions.isEmpty && currentIndex < suggestions.count {
                let selectedSymbol = suggestions[currentIndex]
                appendLog("[SymbolIntegration] ✅ Enter - 插入符号: \(selectedSymbol.content)\n", toPath: "/tmp/quitenote-symbol-debug.log")
                insertSelectedSymbol(selectedSymbol)
            } else {
                appendLog("[SymbolIntegration] ⚠️ Enter - 条件不满足，无法插入\n", toPath: "/tmp/quitenote-symbol-debug.log")
            }
            return true // 消费事件
        }

        // Tab/Shift+Tab - 切换选择
        if keyCode == 48 { // Tab key
            let suggestions = symbolDetector.suggestions
            appendLog("[SymbolIntegration] ✅ Tab - suggestions.count=\(suggestions.count)\n", toPath: "/tmp/quitenote-symbol-debug.log")
            guard !suggestions.isEmpty else { return false }

            let count = suggestions.count
            if modifiers.contains(.shift) {
                // Shift+Tab - 向上
                symbolSelectionState.selectedIndex = (symbolSelectionState.selectedIndex - 1 + count) % count
                appendLog("[SymbolIntegration] ✅ Shift+Tab - 索引: \(symbolSelectionState.selectedIndex)\n", toPath: "/tmp/quitenote-symbol-debug.log")
            } else {
                // Tab - 向下
                symbolSelectionState.selectedIndex = (symbolSelectionState.selectedIndex + 1) % count
                appendLog("[SymbolIntegration] ✅ Tab - 索引: \(symbolSelectionState.selectedIndex)\n", toPath: "/tmp/quitenote-symbol-debug.log")
            }

            return true // 消费事件
        }

        // 上下箭头 - 切换选择
        if keyCode == 126 { // Up arrow
            let suggestions = symbolDetector.suggestions
            appendLog("[SymbolIntegration] ✅ Up - suggestions.count=\(suggestions.count)\n", toPath: "/tmp/quitenote-symbol-debug.log")
            guard !suggestions.isEmpty else {
                appendLog("[SymbolIntegration] ⚠️ Up - suggestions 为空，不处理\n", toPath: "/tmp/quitenote-symbol-debug.log")
                return false
            }
            let count = suggestions.count
            let newIndex = (symbolSelectionState.selectedIndex - 1 + count) % count
            symbolSelectionState.selectedIndex = newIndex
            appendLog("[SymbolIntegration] ✅ Up - 索引: \(symbolSelectionState.selectedIndex) -> \(newIndex)\n", toPath: "/tmp/quitenote-symbol-debug.log")
            return true // 消费事件
        }

        if keyCode == 125 { // Down arrow
            let suggestions = symbolDetector.suggestions
            appendLog("[SymbolIntegration] ✅ Down - suggestions.count=\(suggestions.count)\n", toPath: "/tmp/quitenote-symbol-debug.log")
            guard !suggestions.isEmpty else {
                appendLog("[SymbolIntegration] ⚠️ Down - suggestions 为空，不处理\n", toPath: "/tmp/quitenote-symbol-debug.log")
                return false
            }
            let newIndex = (symbolSelectionState.selectedIndex + 1) % suggestions.count
            symbolSelectionState.selectedIndex = newIndex
            appendLog("[SymbolIntegration] ✅ Down - 索引: \(symbolSelectionState.selectedIndex) -> \(newIndex)\n", toPath: "/tmp/quitenote-symbol-debug.log")
            return true // 消费事件
        }

        appendLog("[SymbolIntegration] ⚠️ 未处理的按键: keyCode=\(keyCode)\n", toPath: "/tmp/quitenote-symbol-debug.log")
        return false // 不处理其他事件
    }

    /// 刷新面板选择状态 - 由于使用了 @Published，SwiftUI 会自动更新
    private func refreshPanelSelection() {
        // 使用 @Published 后，SwiftUI 会自动检测到 selectedIndex 的变化
        // 不需要手动刷新视图
        print("[SymbolIntegration] selectedIndex 已更新为: \(symbolSelectionState.selectedIndex)")
    }

    private func insertSelectedSymbol(_ symbol: SymbolItem) {
        guard let currentTextView = symbolTextView else { return }

        let text = currentTextView.string
        let cursorPosition = currentTextView.selectedRange().location
        let logPath = "/tmp/quitenote-symbol-debug.log"

        appendLog("[SymbolIntegration] insertSelectedSymbol - symbol.content=\(symbol.content), cursorPosition=\(cursorPosition)\n", toPath: logPath)

        // 获取替换后的文本和新光标位置
        if let result = symbolDetector.insertSymbol(symbol, into: text, cursorPosition: cursorPosition) {
            appendLog("[SymbolIntegration] insertSymbol 返回 - newText.count=\(result.newText.count), newCursorPos=\(result.newCursorPos)\n", toPath: logPath)

            // ⭐ 关键修复：计算 NSString 长度（UTF-16 坐标系）
            let newTextNSString = result.newText as NSString
            let newTextLength = newTextNSString.length
            appendLog("[SymbolIntegration] newText NSString 长度: \(newTextLength), String.count: \(result.newText.count)\n", toPath: logPath)

            // 替换文本
            isUpdatingFromTextView = true

            let attrString = markdownToAttributed(result.newText)
            currentTextView.textStorage?.setAttributedString(attrString)

            // ⭐ 关键修复：确保光标位置在 NSString 长度范围内
            // result.newCursorPos 已经是 NSString 坐标系，不需要转换
            let newRange = NSRange(location: min(result.newCursorPos, newTextLength), length: 0)
            appendLog("[SymbolIntegration] 设置光标位置: \(newRange.location) (min(\(result.newCursorPos), \(newTextLength)))\n", toPath: logPath)
            currentTextView.setSelectedRange(newRange)

            // 验证光标位置
            let finalRange = currentTextView.selectedRange()
            appendLog("[SymbolIntegration] 实际光标位置: \(finalRange.location)\n", toPath: logPath)

            isUpdatingFromTextView = false

            // 通知外部更新
            let newText = attributedToMarkdown(currentTextView.attributedString())
            if parent.text != newText {
                parent.text = newText
            }

            currentTextView.didChangeText()
        } else {
            appendLog("[SymbolIntegration] insertSymbol 返回 nil\n", toPath: logPath)
        }

        // 隐藏面板并清除检测
        internalHideSymbolSuggestionPanel()
        symbolDetector.clearDetection()
    }

    /// 从浏览器插入符号（不包含触发词替换）
    private func insertSymbolText(textView: NSTextView, newText: String, newCursorPos: Int) {
        // 更新文本视图
        isUpdatingFromTextView = true

        let attrString = markdownToAttributed(newText)
        textView.textStorage?.setAttributedString(attrString)

        // 设置光标位置
        let newRange = NSRange(location: min(newCursorPos, newText.count), length: 0)
        textView.setSelectedRange(newRange)

        isUpdatingFromTextView = false

        // 通知外部更新
        let finalText = attributedToMarkdown(textView.attributedString())
        if parent.text != finalText {
            parent.text = finalText
        }

        textView.didChangeText()
    }

    /// 直接插入符号内容（内联模式使用）
    private func insertSymbolDirectly(textView: NSTextView, symbol: SymbolItem) {
        let text = textView.string
        let cursorPosition = textView.selectedRange().location

        // 直接在光标位置插入符号内容
        let nsString = text as NSString
        let newText = nsString.replacingCharacters(in: NSRange(location: cursorPosition, length: 0), with: symbol.content)
        let newCursorPos = cursorPosition + symbol.content.count

        // 更新文本视图
        isUpdatingFromTextView = true

        let attrString = markdownToAttributed(newText)
        textView.textStorage?.setAttributedString(attrString)

        // 设置光标位置
        let newRange = NSRange(location: min(newCursorPos, newText.count), length: 0)
        textView.setSelectedRange(newRange)

        isUpdatingFromTextView = false

        // 通知外部更新
        let finalText = attributedToMarkdown(textView.attributedString())
        if parent.text != finalText {
            parent.text = finalText
        }

        textView.didChangeText()
    }
}

// MARK: - Symbol Suggestion Panel Wrapper

/// 符号联想面板包装器（用于 NSHostingView）
struct SymbolSuggestionPanelWrapper: View {
    let triggerText: String
    let suggestions: [SymbolItem]
    // ⭐ 关键修复：使用 @ObservedObject 让 SwiftUI 观察 SymbolSelectionState 的变化
    @ObservedObject var selectionState: SymbolSelectionState
    let onSelect: (SymbolItem) -> Void

    var body: some View {
        SymbolSuggestionPanel(
            triggerText: triggerText,
            suggestions: suggestions,
            selectedIndex: Binding(
                get: { selectionState.selectedIndex },
                set: { selectionState.selectedIndex = $0 }
            ),
            onSelect: onSelect
        )
        .frame(maxWidth: 320, maxHeight: 300)
        .background(Color.themeGray800.opacity(0.95))
        .cornerRadius(8)
    }
}

// MARK: - Cursor Location Info

/// 光标位置信息结构体
/// 包含光标所在文本行的完整信息，用于正确定位联想面板
struct CursorLocationInfo {
    /// 光标在屏幕中的位置（文本行底部）
    let cursorPosition: NSPoint
    /// 文本行在屏幕中的完整矩形
    let lineRect: NSRect
    /// 文本行的高度
    let lineHeight: CGFloat

    /// 获取面板在光标下方的推荐位置（绝对不遮挡文本行）
    func panelPositionBelow(height panelHeight: CGFloat, gap: CGFloat = 8) -> NSPoint {
        // 面板应该在文本行下方，有足够的间隙
        // 文本行底部是 lineRect.minY（屏幕坐标系）
        // 面板顶部应该在 lineRect.minY - gap
        // 面板原点（左下角）应该在 lineRect.minY - gap - panelHeight
        return NSPoint(
            x: cursorPosition.x,
            y: lineRect.minY - gap - panelHeight
        )
    }

    /// 获取面板在光标上方的推荐位置（绝对不遮挡文本行）
    func panelPositionAbove(height panelHeight: CGFloat, gap: CGFloat = 8) -> NSPoint {
        // 面板应该在文本行上方，有足够的间隙
        // 文本行顶部是 lineRect.maxY（屏幕坐标系）
        // 面板底部应该在 lineRect.maxY + gap
        // 面板原点（左下角）应该在 lineRect.maxY + gap
        return NSPoint(
            x: cursorPosition.x,
            y: lineRect.maxY + gap
        )
    }
}

// MARK: - CursorLocationInfo Debug Description

extension CursorLocationInfo: CustomDebugStringConvertible {
    var debugDescription: String {
        return "CursorLocationInfo(cursorPosition: \(cursorPosition), lineRect: \(lineRect), lineHeight: \(lineHeight))"
    }
}

// MARK: - NSTextView Cursor Location Extension

extension NSTextView {
    /// 获取光标位置信息（用于定位浮层面板）
    /// 返回包含光标位置和文本行矩形的信息，确保面板不会遮挡输入文本
    func cursorLocationInfo() -> CursorLocationInfo? {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else {
            print("[NSTextView] ⚠️ 无法获取 layoutManager 或 textContainer")
            return nil
        }

        let cursorRange = selectedRange()
        print("[NSTextView] ========== cursorLocationInfo ==========")
        print("[NSTextView] cursorRange: \(cursorRange), bounds: \(bounds)")

        // 获取光标位置的字形范围
        let glyphRange = layoutManager.glyphRange(forCharacterRange: cursorRange, actualCharacterRange: nil)
        print("[NSTextView] glyphRange: \(glyphRange)")

        // 使用 lineFragmentRect 获取光标所在行的精确位置
        var effectiveGlyphRange: NSRange = NSRange()
        let lineFragmentRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphRange.location,
            effectiveRange: &effectiveGlyphRange,
            withoutAdditionalLayout: true
        )
        print("[NSTextView] lineFragmentRect (视图坐标): \(lineFragmentRect)")
        print("[NSTextView]  - origin: (\(lineFragmentRect.origin.x), \(lineFragmentRect.origin.y))")
        print("[NSTextView]  - size: \(lineFragmentRect.size.width) x \(lineFragmentRect.size.height)")

        // NSTextView 是翻转坐标系（原点左上角，Y向下为正）
        // lineFragmentRect 包含了当前文本行的完整矩形区域

        // 获取文本行底部的光标位置（用于面板的水平定位）
        let cursorPointInTextView = NSPoint(
            x: lineFragmentRect.minX + textContainerInset.width,
            y: lineFragmentRect.maxY  // 当前行的底部位置
        )

        // 将光标位置和文本行矩形都转换为屏幕坐标
        let cursorPointInScreen = convertPointToScreen(cursorPointInTextView)
        let lineRectInScreen = convertRectToScreen(lineFragmentRect)

        print("[NSTextView] 光标位置 (屏幕坐标): \(cursorPointInScreen)")
        print("[NSTextView] 文本行矩形 (屏幕坐标): \(lineRectInScreen)")
        print("[NSTextView] 文本行高度: \(lineFragmentRect.height)")
        print("[NSTextView] ========== 坐标计算完成 ==========")

        return CursorLocationInfo(
            cursorPosition: cursorPointInScreen,
            lineRect: lineRectInScreen,
            lineHeight: lineFragmentRect.height
        )
    }

    /// 获取光标在屏幕中的位置（用于定位浮层面板）- 兼容旧版本
    /// 返回屏幕坐标系下的光标位置（原点在屏幕左下角，Y向上为正）
    func cursorLocationInScreen() -> NSPoint {
        return cursorLocationInfo()?.cursorPosition ?? NSPoint.zero
    }

    /// 将视图坐标转换为屏幕坐标
    private func convertPointToScreen(_ point: NSPoint) -> NSPoint {
        guard let window = window else {
            print("[NSTextView] ⚠️ 无法获取窗口")
            return point
        }

        // convert(point, to: nil) 将视图坐标转换为窗口坐标
        // 注意：这会自动处理翻转坐标系
        let windowPoint = convert(point, to: nil)

        // window.convertPoint(toScreen:) 将窗口坐标转换为屏幕坐标
        let screenPoint = window.convertPoint(toScreen: windowPoint)

        return screenPoint
    }

    /// 将视图矩形转换为屏幕矩形
    private func convertRectToScreen(_ rect: NSRect) -> NSRect {
        guard let window = window else {
            print("[NSTextView] ⚠️ 无法获取窗口")
            return rect
        }

        // convert(rect, to: nil) 将视图坐标转换为窗口坐标
        let windowRect = convert(rect, to: nil)

        // 转换窗口坐标的左下角到屏幕坐标
        let windowOriginInScreen = window.convertPoint(toScreen: windowRect.origin)

        // 构建屏幕坐标系的矩形（origin 是左下角）
        let screenRect = NSRect(origin: windowOriginInScreen, size: windowRect.size)

        return screenRect
    }
}

// MARK: - Symbol Suggestion Panel Bridge

/// 符号联想面板桥接（用于全局访问面板状态）
class SymbolSuggestionPanelBridge {
    static let shared = SymbolSuggestionPanelBridge()

    private init() {}

    /// 跟踪面板是否可见（线程安全）
    private static var _isVisible = false
    private static let lock = NSLock()

    /// 检查面板是否正在显示
    static var isPanelVisible: Bool {
        lock.lock()
        let visible = _isVisible
        lock.unlock()
        return visible
    }

    /// 设置面板可见性（由 SymbolIntegration 调用）
    static func setPanelVisible(_ visible: Bool) {
        lock.lock()
        _isVisible = visible
        lock.unlock()
        print("[SymbolSuggestionPanelBridge] Panel visible: \(visible)")
    }
}

// MARK: - Symbol Browser Bridge

/// 符号浏览面板桥接（用于从工具栏打开）
class SymbolBrowserBridge: ObservableObject {
    @Published var isPresented = false

    static let shared = SymbolBrowserBridge()

    private var browserPanel: NSPanel?
    private var hostingView: NSHostingView<SymbolBrowserPanelWrapper>?

    private var targetTextView: NSTextView?

    func show(from textView: NSTextView) {
        self.targetTextView = textView

        if browserPanel == nil {
            // 创建新面板
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: NSSize(width: 400, height: 360)),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )

            panel.title = "符号库"
            panel.level = .normal // 使用普通级别，避免失焦问题
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false // 失去焦点时不隐藏

            let wrapper = SymbolBrowserPanelWrapper(
                isPresented: Binding(
                    get: { self.isPresented },
                    set: { self.isPresented = $0 }
                ),
                onSymbolSelected: { [weak self] symbol in
                    self?.insertSymbolFromBrowser(symbol)
                }
            )

            let hostingView = NSHostingView(rootView: wrapper)
            hostingView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
            panel.contentView = hostingView

            // 居中显示
            if let screen = NSScreen.main {
                let frame = panel.frame
                let screenFrame = screen.visibleFrame
                panel.setFrame(
                    NSRect(
                        origin: CGPoint(
                            x: screenFrame.midX - frame.width / 2,
                            y: screenFrame.midY - frame.height / 2
                        ),
                        size: frame.size
                    ),
                    display: true
                )
            }

            self.hostingView = hostingView
            self.browserPanel = panel
        }

        browserPanel?.makeKeyAndOrderFront(nil)
        isPresented = true
    }

    func hide() {
        browserPanel?.close()
        browserPanel = nil
        hostingView = nil
        isPresented = false
    }

    private func insertSymbolFromBrowser(_ symbol: SymbolItem) {
        guard let textView = targetTextView else { return }

        let text = textView.string
        let cursorPosition = textView.selectedRange().location

        // 直接插入符号内容
        let newText = (text as NSString).replacingCharacters(in: NSRange(location: cursorPosition, length: 0), with: symbol.content)

        // 通知外部更新
        NotificationCenter.default.post(
            name: .insertSymbolFromBrowser,
            object: nil,
            userInfo: ["newText": newText, "newCursorPos": cursorPosition + symbol.content.count]
        )

        hide()
    }
}

// MARK: - Symbol Browser Panel Wrapper

struct SymbolBrowserPanelWrapper: View {
    @Binding var isPresented: Bool
    let onSymbolSelected: (SymbolItem) -> Void

    var body: some View {
        SymbolBrowserPanel(
            isPresented: $isPresented,
            onSymbolSelected: onSymbolSelected
        )
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let insertSymbolFromBrowser = Notification.Name("insertSymbolFromBrowser")
    static let showSymbolBrowser = Notification.Name("showSymbolBrowser")
}

// MARK: - Integration with StickyNoteEditor

/// 在 StickyNoteEditor 的 makeNSView 中调用
extension StickyNoteEditor.Coordinator {
    func setupSymbolIntegration(for textView: StickyNoteTextView) {
        setupSymbolDetection(for: textView)
    }
}
