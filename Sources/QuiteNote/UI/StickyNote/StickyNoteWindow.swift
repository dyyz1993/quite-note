import AppKit
import SwiftUI

/// 便利贴窗口：无边框浮层，层级 mainMenu+1，悬停即可输入（nonactivating panel）
class StickyNoteWindow: NSPanel, NSWindowDelegate {
    /// 窗口唯一标识（符号浏览器等跨窗口通信用）
    let uuid = UUID()
    /// 所属便利贴的 id
    let id: UUID

    private var isPinnedToAllSpaces: Bool

    static func collectionBehavior(pinnedToAllSpaces: Bool) -> NSWindow.CollectionBehavior {
        pinnedToAllSpaces ? [.fullScreenAuxiliary, .canJoinAllSpaces] : [.fullScreenAuxiliary]
    }

    /// 按便利贴 id 找窗口。所有便利贴窗口类型相同，不能用 NSApp.windows.first 拿"当前那张"
    static func find(noteID: UUID) -> StickyNoteWindow? {
        NSApp.windows.first { ($0 as? StickyNoteWindow)?.id == noteID } as? StickyNoteWindow
    }

    init(note: StickyNoteModel) {
        id = note.id
        isPinnedToAllSpaces = note.pinnedToAllSpaces
        // 显示器拔掉或分辨率变化后，保存的位置可能整块落在屏外；窗口对象本身不再
        // 持有便签内容（旧副本回写曾把新编辑的内容冲掉），需要时都从管理器取
        let screens = StickyNoteGeometry.currentScreens()
        let fallback = NSScreen.main?.visibleFrame ?? screens.first?.visibleFrame ?? .zero
        let frame = StickyNoteGeometry.restoredFrame(note.frame, screens: screens, fallback: fallback)
        super.init(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )

        delegate = self
        isFloatingPanel = true   // 这个 setter 会把 level 重置回 .floating，必须先设它再设 level
        level = .mainMenu + 1
        collectionBehavior = Self.collectionBehavior(pinnedToAllSpaces: isPinnedToAllSpaces)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // 拖动只由顶部原生拖拽区域的 performDrag 驱动，
        // 避免背景拖动与失焦蒙层/SwiftUI 手势互相抢事件
        isMovableByWindowBackground = false
        isMovable = true
        acceptsMouseMovedEvents = true
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false
        // 常驻悬浮：App 切到后台时不能被系统收走（项目里其他面板都显式关掉）
        hidesOnDeactivate = false
        minSize = StickyNoteGeometry.minimumSize
        // 固定深色外观：窗口透明 + SwiftUI 自绘深色底，系统浅色模式下滚动条、
        // 文字选区仍要保持深色风格
        appearance = NSAppearance(named: .darkAqua)

        let hostingView = StickyNoteHostingView(rootView: StickyNoteView(note: note), noteId: note.id)
        // 不让 SwiftUI 按内容理想尺寸反向改窗口大小：尺寸只由用户拖拽决定
        hostingView.sizingOptions = []
        contentView = hostingView
    }

    // 允许获取焦点
    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { true }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        persistFrame()
    }

    func windowDidResize(_ notification: Notification) {
        persistFrame()
    }

    private func persistFrame() {
        StickyNoteManager.shared.setFrame(noteID: id, frame: frame)
    }

    /// 拖拽结束（鼠标可能在窗口外松手）后补做一次失焦判断：拖拽期间不做失焦过渡
    func blurIfMouseOutside() {
        guard StickyNoteHostingView<StickyNoteView>.shouldBlur(window: self) else { return }
        QuiteNoteNotification.post(.stickyNoteBlur, object: id)
    }

    /// 便利贴的"固定到所有 Space"状态变化
    func setPinned(_ pinned: Bool) {
        isPinnedToAllSpaces = pinned
        let behavior = Self.collectionBehavior(pinnedToAllSpaces: pinned)
        if collectionBehavior != behavior {
            collectionBehavior = behavior
        }
    }
}

/// 自定义 HostingView：处理鼠标进入/离开时的聚焦与失焦
class StickyNoteHostingView<Content: View>: NSHostingView<Content> {
    private var trackingArea: NSTrackingArea?
    private var focusTimer: Timer?
    private var blurWorkItem: DispatchWorkItem?
    private let noteID: UUID

    init(rootView: Content, noteId: UUID) {
        self.noteID = noteId
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init(rootView: Content) {
        fatalError("init(rootView:) has not been implemented")
    }

    @MainActor required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }

        // 追踪区域覆盖窗口的所有边缘
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeAlways,
            .inVisibleRect
        ]

        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        // 取消之前排下的失焦任务
        blurWorkItem?.cancel()
        blurWorkItem = nil
        scheduleHoverFocus()
    }

    override func mouseMoved(with event: NSEvent) {
        // 拖动窗口后窗口可能已不是 key、编辑器也不再是第一响应者
        if window?.isKeyWindow != true || !(window?.firstResponder is NSTextView) {
            scheduleHoverFocus()
        }
    }

    private func scheduleHoverFocus() {
        guard focusTimer == nil, NSEvent.pressedMouseButtons == 0 else { return }
        // 悬停即聚焦，但按着鼠标（拖窗口）时不抢焦点：抢焦点会打断 AppKit 的拖动循环
        focusTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.focusTimer = nil
            guard NSEvent.pressedMouseButtons == 0 else { return }
            self.window?.makeKeyAndOrderFront(nil)
            if let editor = self.findEditor(in: self) {
                self.window?.makeFirstResponder(editor)
            }
            // 通知视图进入聚焦态，实现直接输入
            QuiteNoteNotification.post(.stickyNoteFocus, object: self.noteID)
        }
    }

    private func findEditor(in view: NSView) -> StickyNoteTextView? {
        if let editor = view as? StickyNoteTextView { return editor }
        return view.subviews.lazy.compactMap { self.findEditor(in: $0) }.first
    }

    override func mouseExited(with event: NSEvent) {
        focusTimer?.invalidate()
        focusTimer = nil

        blurWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, let window = self.window else { return }
            // 按着鼠标（拖窗口、拖右下角）时不做失焦过渡：内容过渡与窗口逐帧变化并发
            // 是主面板闪退链的同款触发条件。松手后由窗口的 blurIfMouseOutside 补做
            guard NSEvent.pressedMouseButtons == 0, Self.shouldBlur(window: window) else { return }
            QuiteNoteNotification.post(.stickyNoteBlur, object: self.noteID)
        }

        blurWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    /// 鼠标已离开窗口（20px 容差）；正在编辑且鼠标还在 150px 以内时不失焦
    static func shouldBlur(window: NSWindow) -> Bool {
        guard window.isVisible, window.isKeyWindow else { return false }
        let mouseLocation = NSEvent.mouseLocation
        guard !window.frame.insetBy(dx: -20, dy: -20).contains(mouseLocation) else { return false }
        if let textView = window.firstResponder as? NSTextView, textView.isEditable,
           window.frame.insetBy(dx: -150, dy: -150).contains(mouseLocation) {
            return false
        }
        return true
    }

    deinit {
        focusTimer?.invalidate()
        focusTimer = nil
        blurWorkItem?.cancel()
        blurWorkItem = nil
    }
}
