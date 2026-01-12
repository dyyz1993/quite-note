import SwiftUI
import AppKit
import os.log

// MARK: - Notification Names

extension Notification.Name {
    static let arrowUp = Notification.Name("arrowUp")
    static let arrowDown = Notification.Name("arrowDown")
    static let arrowLeft = Notification.Name("arrowLeft")
    static let arrowRight = Notification.Name("arrowRight")
    static let tabKeyPressed = Notification.Name("tabKeyPressed")
    static let enterKeyPressed = Notification.Name("enterKeyPressed")
}

// MARK: - Custom NSPanel for Click Support

/// 自定义 NSPanel，允许接收点击事件但不抢焦点
class NonFocusableNSPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}

// MARK: - Symbol Toolbar Button

/// 符号工具栏按钮 - StickyNote 工具栏中的符号入口
struct SymbolToolbarButton: View {
    // ⭐ 修复：使用 @ObservedObject 访问单例，确保 SwiftUI 正确订阅
    @ObservedObject private var configManager = SymbolConfigManager.shared

    var body: some View {
        Button(action: {
            print("[DEBUG] ========== SymbolToolbarButton START ==========")
            print("[DEBUG] Button clicked at \(Date())")

            // ⭐ 先检查总配置数
            print("[DEBUG] Total configs in manager: \(configManager.configs.count)")
            for config in configManager.configs {
                print("[DEBUG]   - Config: \(config.metadata.name), enabled: \(config.metadata.enabled)")
            }

            let enabled = configManager.enabledConfigs
            print("[DEBUG] Enabled configs: \(enabled.count)")
            let categories = enabled.flatMap { $0.menus }.sorted { $0.sort < $1.sort }
            print("[DEBUG] Total categories: \(categories.count)")
            print("[DEBUG] Category names: \(categories.map { $0.title })")

            if categories.isEmpty {
                print("[DEBUG] ⚠️ WARNING: No categories found!")
                // ⭐ 如果没有分类，尝试重新加载配置
                print("[DEBUG] Attempting to reload configs...")
                configManager.loadConfigs()
                print("[DEBUG] After reload - Total configs: \(configManager.configs.count)")
            } else {
                print("[DEBUG] Calling showBrowser...")
                SymbolBrowserManager.shared.showBrowser(categories: categories)
                print("[DEBUG] showBrowser returned")
            }
            print("[DEBUG] ========== SymbolToolbarButton END ==========")
        }) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 11))
                .foregroundColor(.themeTextSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("符号浏览器")
    }
}

// MARK: - Symbol Browser Manager

/// 符号浏览面板管理器 - 单例
/// 负责显示和管理符号浏览面板（SymbolBrowserPanel）
/// 面板特性：280x300 尺寸，Tab 布局，失焦自动关闭，仅向当前 note 插入符号
class SymbolBrowserManager {
    static let shared = SymbolBrowserManager()

    private var panel: NonFocusableNSPanel?
    private var hostingView: NSHostingView<SymbolBrowserContentView>?
    private var parentWindow: NSWindow?
    private var keyboardEventHandler: Any?
    // ⭐ 添加面板创建时间戳，用于防止过早关闭
    private var panelCreationTime: Date?

    // os_log logger
    private let logger = OSLog(subsystem: "com.quitenote.symbol", category: "BrowserPanel")

    private init() {}

    func showBrowser(categories: [SymbolMenu]) {
        print("[DEBUG] ========== SymbolBrowserManager.showBrowser called ==========")
        print("[DEBUG] Categories count: \(categories.count)")
        print("[DEBUG] Current panel exists: \(panel != nil)")
        print("[DEBUG] Current panel isVisible: \(panel?.isVisible ?? false)")
        os_log("[SymbolBrowserPanel] showBrowser called, categories count: %d", type: .info, categories.count)

        // ⭐ 关键修复：先完全清理之前的状态
        closeBrowser()

        // ⭐ 直接创建新面板（不使用延迟）
        createAndShowPanel(categories: categories)
    }

    private func createAndShowPanel(categories: [SymbolMenu]) {
        print("[DEBUG] Creating new panel...")

        // 打印分类信息用于调试
        for (index, category) in categories.enumerated() {
            print("[DEBUG] Category \(index): \(category.title), icon: \(category.icon ?? "nil"), symbols: \(category.symbols.count)")
            os_log("[SymbolBrowserPanel] Category %d: %@, icon: %@, symbols: %d", type: .info, index, category.title, category.icon ?? "nil", category.symbols.count)
        }

        // 获取当前关键窗口 - 失焦时用来对比
        let currentKeyWindow = NSApp.keyWindow
        self.parentWindow = currentKeyWindow

        // 面板尺寸
        let panelWidth: CGFloat = 280
        let panelHeight: CGFloat = 300

        // 获取当前鼠标位置
        let mouseLocation = NSEvent.mouseLocation
        os_log("[SymbolBrowserPanel] Mouse location: %@", type: .info, NSStringFromPoint(mouseLocation))

        // ⭐ 修复：找到鼠标所在的实际屏幕，而不是主屏幕
        let mouseScreen = NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? NSScreen.main

        print("[DEBUG] Mouse location: \(mouseLocation)")
        print("[DEBUG] Screen frame: \(mouseScreen?.frame ?? .zero)")

        // 创建面板
        let panel = NonFocusableNSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = false

        // ⭐ 修复：简化位置计算，确保在屏幕内
        var origin = mouseLocation
        origin.x = mouseLocation.x - panelWidth / 2  // 居中
        origin.y = mouseLocation.y - panelHeight - 10  // 在鼠标上方10px

        // 确保面板在屏幕内
        if let screen = mouseScreen {
            let screenFrame = screen.frame
            // 确保不超出屏幕边界
            if origin.x < screenFrame.minX { origin.x = screenFrame.minX + 10 }
            if origin.x + panelWidth > screenFrame.maxX { origin.x = screenFrame.maxX - panelWidth - 10 }
            if origin.y < screenFrame.minY { origin.y = screenFrame.minY + 10 }
            if origin.y + panelHeight > screenFrame.maxY { origin.y = screenFrame.maxY - panelHeight - 10 }
        }

        print("[DEBUG] Panel origin: \(origin)")
        os_log("[SymbolBrowserPanel] Initial origin: %@", type: .info, NSStringFromPoint(origin))

        panel.setFrameOrigin(origin)

        // 创建内容视图
        let contentView = SymbolBrowserContentView(
            categories: categories,
            onClose: { [weak self] in
                os_log("[SymbolBrowserPanel] onClose callback called", type: .info)
                self?.closeBrowser()
            },
            onInsertSymbol: { [weak self] symbol in
                os_log("[SymbolBrowserPanel] onInsertSymbol callback called: %@", type: .info, symbol.content)
                self?.insertSymbol(symbol)
            }
        )

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        // ⭐ 设置键盘事件处理器（使用实例变量存储）
        setupKeyboardEventHandler(for: panel)

        // 显示面板
        panel.orderFrontRegardless()

        print("[DEBUG] Panel ordered front")
        print("[DEBUG] Panel isVisible: \(panel.isVisible)")
        print("[DEBUG] Panel frame: \(panel.frame)")
        print("[DEBUG] Panel level: \(panel.level.rawValue)")
        print("[DEBUG] Panel contentView: \(panel.contentView != nil ? "YES" : "NO")")

        os_log("[SymbolBrowserPanel] Panel ordered front, isVisible: %d, frame: %@", type: .info, panel.isVisible, NSStringFromRect(panel.frame))

        self.panel = panel
        self.hostingView = hostingView
        // ⭐ 记录面板创建时间
        self.panelCreationTime = Date()

        // 监听窗口关闭
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: panel
        )

        // ⭐ 延迟监听父窗口失焦 - 增加延迟时间，避免面板打开时立即触发关闭
        // 给面板足够的时间完全打开后再开始监听
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self, let parentWindow = self.parentWindow else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.parentWindowDidResignKey(_:)),
                name: NSWindow.didResignKeyNotification,
                object: parentWindow
            )
            os_log("[SymbolBrowserPanel] Started monitoring parent window: %@", type: .info, parentWindow.title)
            print("[DEBUG] Started monitoring parent window for resign key")
        }

        // 监听应用失焦 - 当整个应用切换到后台时关闭符号浏览器
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    func closeBrowser() {
        print("[DEBUG] ========== closeBrowser called ==========")
        print("[DEBUG] Panel exists: \(panel != nil)")
        print("[DEBUG] Keyboard event handler exists: \(keyboardEventHandler != nil)")

        // ⭐ 关键修复：清理键盘事件监听器
        if let handler = keyboardEventHandler {
            NSEvent.removeMonitor(handler)
            keyboardEventHandler = nil
            print("[DEBUG] Keyboard event handler removed")
        }

        // 移除所有观察者
        if let panel = panel {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: panel)
        }
        if let parentWindow = parentWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: parentWindow)
        }
        NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)

        // 关闭并清理面板
        panel?.close()
        panel = nil
        hostingView = nil
        parentWindow = nil
        // ⭐ 清理创建时间戳
        panelCreationTime = nil

        print("[DEBUG] ========== closeBrowser completed ==========")
    }

    @objc private func windowWillClose(_ notification: Notification) {
        os_log("[SymbolBrowserPanel] Window will close", type: .info)
        closeBrowser()
    }

    @objc private func parentWindowDidResignKey(_ notification: Notification) {
        // ⭐ 关键修复：检查面板是否刚创建，防止焦点变化时序问题导致过早关闭
        guard let creationTime = panelCreationTime else {
            closeBrowser()
            return
        }

        let timeSinceCreation = Date().timeIntervalSince(creationTime)
        // 如果面板创建不到 0.5 秒，不响应父窗口失焦事件
        if timeSinceCreation < 0.5 {
            print("[DEBUG] Panel created \(timeSinceCreation * 1000)ms ago, ignoring parent window resign key")
            return
        }

        print("[DEBUG] Parent window did resign key, closing browser (panel created \(timeSinceCreation * 1000)ms ago)")
        os_log("[SymbolBrowserPanel] Parent window did resign key, closing browser", type: .info)
        closeBrowser()
    }

    @objc private func appDidResignActive(_ notification: Notification) {
        os_log("[SymbolBrowserPanel] App did resign active, closing browser", type: .info)
        closeBrowser()
    }

    private func insertSymbol(_ symbol: SymbolItem) {
        // ⭐ 修复：获取当前关键窗口的 textView，只向当前窗口发送通知
        if let currentWindow = NSApp.keyWindow,
           let contentView = currentWindow.contentView,
           let textView = findTextView(in: contentView) {
            // 使用 textView 的内存地址作为标识
            let textViewAddress = Unmanaged.passUnretained(textView).toOpaque()

            NotificationCenter.default.post(
                name: .insertSymbolFromBrowser,
                object: nil,
                userInfo: [
                    "symbol": symbol,
                    "mode": "browser",
                    "targetTextView": textViewAddress
                ]
            )
            os_log("[SymbolBrowserPanel] Insert symbol to textView: %lx", type: .info, Int(bitPattern: textViewAddress))
        } else {
            // 回退：如果没有找到 textView，使用旧方式（所有窗口都会响应）
            NotificationCenter.default.post(
                name: .insertSymbolFromBrowser,
                object: nil,
                userInfo: ["symbol": symbol, "mode": "browser"]
            )
        }
        // 插入后关闭面板
        closeBrowser()
    }

    /// 递归查找 NSTextView
    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }
        for subview in view.subviews {
            if let found = findTextView(in: subview) {
                return found
            }
        }
        return nil
    }

    /// 设置键盘事件处理器
    private func setupKeyboardEventHandler(for panel: NSPanel) {
        print("[DEBUG] Setting up keyboard event handler...")

        // ⭐ 关键修复：使用实例变量存储监听器，而不是 objc_setAssociatedObject
        keyboardEventHandler = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self = self, let panel = panel, panel.isVisible else {
                // 如果面板不存在或不可见，不处理事件
                return event
            }

            let keyCode = event.keyCode

            // ESC 键关闭面板
            if keyCode == 53 {
                print("[DEBUG] ESC pressed, closing browser")
                self.closeBrowser()
                return nil
            }

            // Tab 键切换 tab
            if keyCode == 48 { // Tab
                print("[DEBUG] Tab pressed, switching tab")
                NotificationCenter.default.post(name: .tabKeyPressed, object: nil)
                return nil
            }

            // Enter/Return 键确认
            if keyCode == 36 { // Enter
                print("[DEBUG] Enter pressed, inserting symbol")
                NotificationCenter.default.post(name: .enterKeyPressed, object: nil)
                return nil
            }

            // 方向键
            switch keyCode {
            case 126: // Up
                print("[DEBUG] Up arrow pressed")
                NotificationCenter.default.post(name: .arrowUp, object: nil)
                return nil
            case 125: // Down
                print("[DEBUG] Down arrow pressed")
                NotificationCenter.default.post(name: .arrowDown, object: nil)
                return nil
            case 123: // Left
                print("[DEBUG] Left arrow pressed")
                NotificationCenter.default.post(name: .arrowLeft, object: nil)
                return nil
            case 124: // Right
                print("[DEBUG] Right arrow pressed")
                NotificationCenter.default.post(name: .arrowRight, object: nil)
                return nil
            default:
                break
            }

            return event
        }

        print("[DEBUG] Keyboard event handler set up successfully")
    }
}

// MARK: - Symbol Browser Content View

/// 符号浏览器内容视图 - Tab 形式展示分组
struct SymbolBrowserContentView: View {
    let categories: [SymbolMenu]
    let onClose: () -> Void
    let onInsertSymbol: (SymbolItem) -> Void

    @State private var selectedTabIndex = 0
    @State private var selectedSymbolIndex: Int?

    private var currentSymbols: [SymbolItem] {
        guard selectedTabIndex < categories.count else { return [] }
        return categories[selectedTabIndex].symbols
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部 Tab 栏
            tabBarView

            // 分隔线
            Rectangle()
                .fill(Color.themeBorder)
                .frame(height: 1)

            // 符号网格
            symbolGridView

            // 底部提示
            bottomView
        }
        .background(Color.themeBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.themeBorder, lineWidth: 1)
        )
        .shadow(color: Color.themeShadowHeavy, radius: 10, x: 0, y: 2)
        .frame(width: 280, height: 300)
        .onAppear {
            // 默认选中第一个符号
            if !currentSymbols.isEmpty {
                selectedSymbolIndex = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .arrowUp)) { _ in
            handleArrowKey(.up)
        }
        .onReceive(NotificationCenter.default.publisher(for: .arrowDown)) { _ in
            handleArrowKey(.down)
        }
        .onReceive(NotificationCenter.default.publisher(for: .arrowLeft)) { _ in
            handleArrowKey(.left)
        }
        .onReceive(NotificationCenter.default.publisher(for: .arrowRight)) { _ in
            handleArrowKey(.right)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabKeyPressed)) { _ in
            handleTabKey()
        }
        .onReceive(NotificationCenter.default.publisher(for: .enterKeyPressed)) { _ in
            handleEnterKey()
        }
    }

    // MARK: - Keyboard Navigation

    private enum ArrowKey {
        case up, down, left, right
    }

    private func handleArrowKey(_ key: ArrowKey) {
        guard let currentIndex = selectedSymbolIndex,
              !currentSymbols.isEmpty else {
            if !currentSymbols.isEmpty {
                selectedSymbolIndex = 0
            }
            return
        }

        let columns = 4
        let rowCount = (currentSymbols.count + columns - 1) / columns
        let currentRow = currentIndex / columns
        let currentCol = currentIndex % columns
        var newIndex = currentIndex

        switch key {
        case .up:
            if currentRow > 0 {
                newIndex = (currentRow - 1) * columns + currentCol
                if newIndex >= currentSymbols.count {
                    newIndex = currentSymbols.count - 1
                }
            } else {
                // 在第一行，向上键切换到上一个 tab
                switchToPreviousTab()
                return
            }
        case .down:
            if currentRow < rowCount - 1 {
                newIndex = (currentRow + 1) * columns + currentCol
                if newIndex >= currentSymbols.count {
                    newIndex = currentIndex
                }
            } else {
                // 在最后一行，向下键切换到下一个 tab
                switchToNextTab()
                return
            }
        case .left:
            if currentCol > 0 {
                newIndex = currentIndex - 1
            } else if currentRow > 0 {
                // 在行首，向左键移动到上一行末尾
                let prevRowLastIndex = (currentRow - 1) * columns + min(columns - 1, currentSymbols.count - 1 - (currentRow - 1) * columns)
                newIndex = min(prevRowLastIndex, currentSymbols.count - 1)
            } else {
                // 在第一个符号，向左键切换到上一个 tab
                switchToPreviousTab()
                return
            }
        case .right:
            if currentCol < columns - 1 && currentIndex < currentSymbols.count - 1 {
                newIndex = currentIndex + 1
            } else if currentIndex < currentSymbols.count - 1 {
                // 在行末，向右键移动到下一行开头
                newIndex = min(currentIndex + 1, currentSymbols.count - 1)
            } else {
                // 在最后一个符号，向右键切换到下一个 tab
                switchToNextTab()
                return
            }
        }

        selectedSymbolIndex = min(newIndex, currentSymbols.count - 1)
    }

    private func handleTabKey() {
        switchToNextTab()
    }

    private func handleEnterKey() {
        guard let index = selectedSymbolIndex,
              index < currentSymbols.count else { return }
        onInsertSymbol(currentSymbols[index])
    }

    private func switchToNextTab() {
        guard !categories.isEmpty else { return }
        let newIndex = (selectedTabIndex + 1) % categories.count
        selectedTabIndex = newIndex
        selectedSymbolIndex = 0
    }

    private func switchToPreviousTab() {
        guard !categories.isEmpty else { return }
        let newIndex = (selectedTabIndex - 1 + categories.count) % categories.count
        selectedTabIndex = newIndex
        selectedSymbolIndex = 0
    }

    private var tabBarView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(categories.enumerated()), id: \.offset) { index, category in
                    categoryTabButton(index: index, category: category)
                }
                // 添加右边距，确保最后一个 tab 不会被关闭按钮遮挡
                Spacer().frame(width: 30)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Color.themeBackground)
        .overlay(
            // 关闭按钮放在右上角
            VStack {
                HStack {
                    Spacer()
                    closeButton
                }
                Spacer()
            }
            .padding(.trailing, 8)
            .padding(.top, 6)
        )
    }

    private func categoryTabButton(index: Int, category: SymbolMenu) -> some View {
        let isSelected = selectedTabIndex == index
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTabIndex = index
            }
        }) {
            HStack(spacing: 2) {
                Text(category.icon ?? "📁")
                    .font(.system(size: 12))
                // 只有选中时才显示文字
                if isSelected {
                    Text(category.title)
                        .font(.themeCaptionSmall)
                }
            }
            .padding(.horizontal, isSelected ? 8 : 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.themeActive : Color.clear)
            )
            .foregroundColor(isSelected ? .themeBlue500 : .themeTextSecondary)
        }
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 10))
                .foregroundColor(.themeTextTertiary)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help("关闭 (ESC)")
    }

    private var symbolGridView: some View {
        Group {
            if selectedTabIndex < categories.count {
                let category = categories[selectedTabIndex]
                ScrollView {
                    let columns = [
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6)
                    ]

                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(category.symbols.enumerated()), id: \.element.id) { index, symbol in
                            SymbolGridItem(
                                symbol: symbol,
                                onInsert: onInsertSymbol,
                                isSelected: selectedSymbolIndex == index
                            )
                        }
                    }
                    .padding(8)
                }
                .background(Color.themeItem)
            }
        }
    }

    private var bottomView: some View {
        HStack(spacing: 8) {
            Text("Tab: 切换 | ←→↑↓: 选择 | Enter: 确认")
                .font(.themeCaptionTiny)
                .foregroundColor(.themeTextTertiary)
            Spacer()
            Text("ESC: 关闭")
                .font(.themeCaptionTiny)
                .foregroundColor(.themeTextTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.themeBackground)
    }
}

// MARK: - Symbol Grid Item

/// 符号网格项
struct SymbolGridItem: View {
    let symbol: SymbolItem
    let onInsert: (SymbolItem) -> Void
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        Button(action: { onInsert(symbol) }) {
            VStack(spacing: 2) {
                // Emoji 图标
                Text(symbol.content)
                    .font(.system(size: 20))
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected || isHovering ? Color.themeActive : Color.themeItem)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.themeBlue500 : Color.clear, lineWidth: 2)
                    )

                // 始终显示描述文案
                Text(symbol.desc)
                    .font(.themeCaptionTiny)
                    .foregroundColor(isSelected ? .themeBlue500 : .themeTextSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxHeight: 28)
            }
            .frame(maxWidth: .infinity)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected || isHovering ? Color.themeHoverLight : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
