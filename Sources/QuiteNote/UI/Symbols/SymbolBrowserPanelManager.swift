import SwiftUI
import AppKit

// MARK: - Symbol Browser Panel State

/// 符号浏览器面板状态（ObservableObject，用于 SwiftUI 观察）
class SymbolBrowserPanelState: ObservableObject {
    @Published var currentMenuIndex: Int = 0
    @Published var currentSelectionIndex: Int = 0

    // 每个分组独立的选中索引
    private(set) var selectionIndices: [Int: Int] = [:]

    func switchMenu(to newIndex: Int, oldIndex: Int) {
        // 保存旧分组的选择
        selectionIndices[oldIndex] = currentSelectionIndex
        // 恢复新分组的选择
        currentSelectionIndex = selectionIndices[newIndex] ?? 0
        currentMenuIndex = newIndex
        print("[SymbolBrowserPanelState] Switched menu: \(oldIndex) -> \(newIndex), selection: \(currentSelectionIndex)")
    }

    func updateSelection(_ newIndex: Int) {
        currentSelectionIndex = newIndex
        selectionIndices[currentMenuIndex] = newIndex
        print("[SymbolBrowserPanelState] Updated selection for menu \(currentMenuIndex): \(newIndex)")
    }
}

/// 符号浏览器面板管理器
///
/// 使用 ObservableObject 管理面板状态，通过 StickyNoteTextView.onKeyDown 处理键盘事件
/// 使用单例模式确保全局只有一个实例，避免多个窗口间的状态混乱
class SymbolBrowserPanelManager: ObservableObject {
    // MARK: - Singleton

    static let shared = SymbolBrowserPanelManager()

    /// 面板是否可见（供其他组件检查，避免 ESC 键冲突）
    static var isPanelVisible: Bool {
        shared.panelWindow?.isVisible == true
    }

    private var configManager: SymbolConfigManager { SymbolConfigManager.shared }

    // MARK: - Published State (使用状态类)

    @Published var panelState = SymbolBrowserPanelState()
    @Published var panelWindow: NSPanel?

    // MARK: - Private State

    private var menus: [SymbolMenu] = []
    private var backgroundView: NSView?
    private var buttonFrame: CGRect = .zero
    private var targetWindowUUID: UUID?
    private var currentTextView: StickyNoteTextView? // 保存 TextView 引用用于清理回调

    // 私有初始化方法（单例模式）
    private init() {
        print("[SymbolBrowserPanelManager] Singleton instance created")
    }

    // MARK: - Public Methods

    /// 切换面板显示状态
    func togglePanel(from window: StickyNoteWindow, at buttonFrame: CGRect) {
        self.buttonFrame = buttonFrame

        if let window = panelWindow, window.isVisible {
            closePanel()
        } else {
            showPanel(from: window, at: buttonFrame)
        }
    }

    /// 显示面板
    func showPanel(from window: StickyNoteWindow, at buttonFrame: CGRect) {
        print("[SymbolBrowserPanelManager] showPanel called")
        // 保存目标窗口的 UUID
        targetWindowUUID = window.uuid
        print("[SymbolBrowserPanelManager] Target window UUID: \(window.uuid.uuidString)")

        self.buttonFrame = buttonFrame

        // 1. 计算按钮位置
        var buttonBottomY: CGFloat
        var buttonCenterX: CGFloat

        if buttonFrame == .zero {
            let windowFrame = window.frame
            buttonBottomY = windowFrame.minY
            buttonCenterX = windowFrame.midX
        } else {
            let windowHeight = window.frame.height
            let buttonBottomInWindow = windowHeight - buttonFrame.maxY
            let buttonPoint = NSPoint(x: buttonFrame.midX, y: buttonBottomInWindow)
            let screenPoint = window.convertPoint(toScreen: buttonPoint)
            buttonBottomY = screenPoint.y
            buttonCenterX = screenPoint.x
        }

        // 2. 计算面板位置
        let panelSize = NSSize(width: 320, height: 360)
        let panelOrigin = calculatePanelPosition(
            buttonCenterX: buttonCenterX,
            buttonBottomY: buttonBottomY,
            panelSize: panelSize
        )

        // 3. 创建面板 - 使用 ClickableNSPanel 允许正确参与响应链
        let panel = ClickableNSPanel(
            contentRect: NSRect(origin: panelOrigin, size: panelSize),
            styleMask: [.borderless],  // ⭐ 移除 .nonactivatingPanel，只保留 .borderless
            backing: .buffered,
            defer: false
        )

        panel.level = NSWindow.Level.popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = true

        // 4. 获取所有分组
        menus = configManager.configs.flatMap { $0.menus }.sorted { $0.sort < $1.sort }

        // 调试：打印所有菜单的 icon
        print("[SymbolBrowserPanelManager] 📋 加载了 \(menus.count) 个分组:")
        for (index, menu) in menus.enumerated() {
            print("[SymbolBrowserPanelManager]   [\(index)] \(menu.title) - icon: \(menu.icon ?? "nil")")
        }

        // 4.5. 设置初始选中位置到中心（重置状态）
        panelState = SymbolBrowserPanelState()  // 重置状态
        if !menus.isEmpty {
            let firstMenuSymbolCount = menus[0].symbols.count
            let centerIndex = max(0, firstMenuSymbolCount / 2)
            panelState.updateSelection(centerIndex)
            print("[SymbolBrowserPanelManager] ✅ 设置初始选中位置到中心: \(centerIndex)")
        }

        // 5. 创建 SwiftUI 内容（使用 Wrapper 和 @ObservedObject）
        let hostingView = NSHostingView(rootView: SymbolBrowserPanelWrapper(
            menus: menus,
            panelState: panelState,
            onClose: { [weak self] in
                self?.closePanel()
            },
            onSelect: { [weak self] symbol in
                self?.insertSymbol(symbol)
            }
        ))
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = hostingView

        // 6. ⭐ 关键修复：先设置 StickyNoteTextView 的键盘回调（在显示面板之前！）
        if let contentView = window.contentView,
           let stickyTextView = findStickyNoteTextView(in: contentView) {
            currentTextView = stickyTextView

            stickyTextView.onKeyDown = { [weak self] event in
                guard let self = self,
                      self.panelWindow?.isVisible == true else {
                    return false
                }
                return self.handleKeyEvent(event)
            }
            print("[SymbolBrowserPanelManager] ✅ 设置键盘回调到 StickyNoteTextView")
        } else {
            print("[SymbolBrowserPanelManager] ⚠️ 未找到 StickyNoteTextView")
        }

        // 7. 添加为父窗口的子窗口
        window.addChildWindow(panel, ordered: .above)

        // 8. ⭐ 关键：立即恢复焦点（在显示面板之前）
        if let stickyTextView = currentTextView {
            window.makeFirstResponder(stickyTextView)
            print("[SymbolBrowserPanelManager] ✅ 设置 StickyNoteTextView 为 First Responder")
        }

        // 9. 显示面板（使用 orderFrontRegardless 而不是 orderFront）
        panel.orderFrontRegardless()
        panelWindow = panel

        // 10. 添加点击外部关闭的背景视图
        addClickOutsideBackground(to: window, panel: panel)

        print("[SymbolBrowserPanelManager] Panel shown successfully")
    }

    /// 关闭面板
    func closePanel() {
        print("[SymbolBrowserPanelManager] Closing panel")

        // 1. 清理键盘回调
        if let textView = currentTextView {
            textView.onKeyDown = nil
            currentTextView = nil
            print("[SymbolBrowserPanelManager] ✅ 清理键盘回调")
        }

        // 2. 移除背景视图
        backgroundView?.removeFromSuperview()
        backgroundView = nil

        // 3. 关闭面板
        panelWindow?.close()
        panelWindow = nil

        // 4. 重置状态（创建新的状态实例）
        panelState = SymbolBrowserPanelState()
    }

    // MARK: - Private Methods

    /// 查找 StickyNoteTextView（递归搜索视图层级）
    private func findStickyNoteTextView(in view: NSView) -> StickyNoteTextView? {
        if let textView = view as? StickyNoteTextView {
            return textView
        }
        for subview in view.subviews {
            if let found = findStickyNoteTextView(in: subview) {
                return found
            }
        }
        return nil
    }

    /// 处理键盘事件
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard panelWindow != nil, panelWindow?.isVisible == true else {
            return false
        }

        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])

        // 获取当前组的符号
        guard panelState.currentMenuIndex < menus.count else { return false }
        let currentSymbols = menus[panelState.currentMenuIndex].symbols
        let count = currentSymbols.count

        // ESC - 关闭面板
        if keyCode == 53 {
            print("[SymbolBrowserPanelManager] ESC pressed, closing panel")
            closePanel()
            return true
        }

        // Tab / Shift+Tab - 切换分组（不是切换 emoji）
        if keyCode == 48 {
            let menuCount = menus.count
            guard menuCount > 0 else { return false }

            let oldIndex = panelState.currentMenuIndex
            let newIndex: Int
            if modifiers.contains(.shift) {
                newIndex = (oldIndex - 1 + menuCount) % menuCount
            } else {
                newIndex = (oldIndex + 1) % menuCount
            }

            // ⭐ 使用状态类的方法切换分组
            DispatchQueue.main.async {
                self.panelState.switchMenu(to: newIndex, oldIndex: oldIndex)
            }
            return true
        }

        // Enter - 插入选中的符号
        if keyCode == 36 {
            if panelState.currentSelectionIndex < count {
                insertSymbol(currentSymbols[panelState.currentSelectionIndex])
            }
            return true
        }

        // 方向键 - 上下左右移动选择
        if keyCode == 123 {  // Left Arrow
            if panelState.currentSelectionIndex > 0 {
                DispatchQueue.main.async {
                    self.panelState.updateSelection(self.panelState.currentSelectionIndex - 1)
                }
            }
            return true
        }
        if keyCode == 124 {  // Right Arrow
            if panelState.currentSelectionIndex < count - 1 {
                DispatchQueue.main.async {
                    self.panelState.updateSelection(self.panelState.currentSelectionIndex + 1)
                }
            }
            return true
        }
        if keyCode == 125 {  // Down Arrow
            let columns = 4  // ⭐ 修复：使用实际列数 4，而不是硬编码 5
            if panelState.currentSelectionIndex + columns < count {
                DispatchQueue.main.async {
                    self.panelState.updateSelection(self.panelState.currentSelectionIndex + columns)
                }
            }
            return true
        }
        if keyCode == 126 {  // Up Arrow
            let columns = 4  // ⭐ 修复：使用实际列数 4
            if panelState.currentSelectionIndex >= columns {
                DispatchQueue.main.async {
                    self.panelState.updateSelection(self.panelState.currentSelectionIndex - columns)
                }
            }
            return true
        }

        return false
    }

    /// 计算面板位置
    private func calculatePanelPosition(buttonCenterX: CGFloat, buttonBottomY: CGFloat, panelSize: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else {
            return NSPoint(
                x: buttonCenterX - panelSize.width / 2,
                y: buttonBottomY - panelSize.height - 8
            )
        }

        let screenFrame = screen.visibleFrame
        var panelOrigin = NSPoint.zero
        let gap: CGFloat = 8

        // 垂直方向：显示在按钮下方
        panelOrigin.y = buttonBottomY - panelSize.height - gap

        // 检查是否会超出屏幕底部
        if panelOrigin.y < screenFrame.minY {
            panelOrigin.y = buttonBottomY + gap
        }

        // 水平方向：居中对齐
        panelOrigin.x = buttonCenterX - panelSize.width / 2

        // 右边界检测
        if panelOrigin.x + panelSize.width > screenFrame.maxX {
            panelOrigin.x = screenFrame.maxX - panelSize.width - gap
        }

        // 左边界检测
        if panelOrigin.x < screenFrame.minX {
            panelOrigin.x = screenFrame.minX + gap
        }

        return panelOrigin
    }

    /// 添加点击外部关闭的背景视图
    private func addClickOutsideBackground(to window: NSWindow, panel: NSPanel) {
        let backgroundView = ClickHandlingView(frame: window.contentView?.bounds ?? .zero)
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NSColor.clear.cgColor
        backgroundView.onClick = { [weak self] in
            self?.closePanel()
        }

        if let contentView = window.contentView {
            contentView.addSubview(backgroundView, positioned: .below, relativeTo: nil)
            self.backgroundView = backgroundView
        }
    }

    /// 插入符号
    private func insertSymbol(_ symbol: SymbolItem) {
        print("[SymbolBrowserPanelManager] Inserting symbol: \(symbol.content)")

        // 只向触发面板的窗口发送通知
        guard let uuid = targetWindowUUID else {
            print("[SymbolBrowserPanelManager] ⚠️ 没有目标窗口 UUID，无法插入符号")
            closePanel()
            return
        }

        // 使用 UUID 作为窗口标识符
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertSymbolFromBrowser"),
            object: nil,
            userInfo: [
                "symbol": symbol.content,
                "windowUUID": uuid.uuidString
            ]
        )

        print("[SymbolBrowserPanelManager] 已发送符号插入通知到窗口 UUID: \(uuid.uuidString)")
        closePanel()
    }
}

// MARK: - Symbol Browser Panel Wrapper

/// 符号浏览器面板包装器（用于 NSHostingView）
/// 使用 @ObservedObject 让 SwiftUI 能够观察状态变化
struct SymbolBrowserPanelWrapper: View {
    let menus: [SymbolMenu]
    @ObservedObject var panelState: SymbolBrowserPanelState
    let onClose: () -> Void
    let onSelect: (SymbolItem) -> Void

    var body: some View {
        SymbolBrowserPanel(
            menus: menus,
            currentMenuIndex: Binding(
                get: { panelState.currentMenuIndex },
                set: { panelState.currentMenuIndex = $0 }
            ),
            selectedIndex: Binding(
                get: { panelState.currentSelectionIndex },
                set: { panelState.currentSelectionIndex = $0 }
            ),
            onClose: onClose,
            onSelect: onSelect
        )
    }
}

// MARK: - Click Handling View

class ClickHandlingView: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
