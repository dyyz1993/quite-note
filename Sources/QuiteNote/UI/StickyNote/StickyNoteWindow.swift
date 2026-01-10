import AppKit
import SwiftUI

/// 贴纸窗口 - 全屏浮动、无边框、最高层级
class StickyNoteWindow: NSPanel, NSWindowDelegate {
    private var trackingArea: NSTrackingArea?
    private var focusTimer: Timer?
    private var noteId: UUID
    private var note: StickyNoteModel
    
    init(note: StickyNoteModel) {
        self.noteId = note.id
        self.note = note
        super.init(
            contentRect: note.frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        
        self.delegate = self
        self.isFloatingPanel = true
        self.level = .mainMenu + 1
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true 
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isOpaque = false
        
        // 设置 SwiftUI 视图
        let rootView = StickyNoteView(note: note)
        let hostingView = StickyNoteHostingView(rootView: rootView, noteId: note.id)
        self.contentView = hostingView
    }
    
    // 允许获取焦点
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
    
    // MARK: - NSWindowDelegate
    
    func windowDidMove(_ notification: Notification) {
        note.frame = self.frame
        StickyNoteManager.shared.updateNote(note)
    }
    
    func windowDidResize(_ notification: Notification) {
        note.frame = self.frame
        StickyNoteManager.shared.updateNote(note)
    }
}

/// 自定义 HostingView 以处理鼠标进入/离开事件
class StickyNoteHostingView<Content: View>: NSHostingView<Content> {
    private var trackingArea: NSTrackingArea?
    private var focusTimer: Timer?
    private var blurWorkItem: DispatchWorkItem? // 新增：可取消的失焦任务
    private let noteId: UUID

    init(rootView: Content, noteId: UUID) {
        self.noteId = noteId
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init(rootView: Content) {
        fatalError("init(rootView:) has not been implemented")
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }

        // 关键修复：扩大追踪区域，包含窗口的所有边缘
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect
        ]

        let area = NSTrackingArea(
            rect: self.bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        // 取消之前的失焦任务
        blurWorkItem?.cancel()
        blurWorkItem = nil

        focusTimer?.invalidate()
        focusTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.window?.makeKeyAndOrderFront(nil)
            // 通知视图强制获取焦点，实现直接输入
            NotificationCenter.default.post(name: NSNotification.Name("StickyNoteFocus"), object: self.noteId)
        }
    }

    override func mouseExited(with event: NSEvent) {
        focusTimer?.invalidate()
        focusTimer = nil

        // 取消之前的失焦任务
        blurWorkItem?.cancel()

        // 创建新的失焦任务
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, let window = self.window else { return }

            // 检查窗口是否仍然存在且可见
            guard window.isVisible else { return }

            // 获取当前鼠标位置（屏幕坐标）
            let mouseLocation = NSEvent.mouseLocation

            // 检查鼠标是否在窗口范围内（增加更宽容的 20px 容错边距）
            let windowFrame = window.frame.insetBy(dx: -20, dy: -20)
            let isMouseStillInside = windowFrame.contains(mouseLocation)

            if !isMouseStillInside {
                // 如果正在编辑，除非鼠标离开更远（150px），否则不失焦
                if let textView = window.firstResponder as? NSTextView, textView.isEditable {
                    let extendedFrame = window.frame.insetBy(dx: -150, dy: -150)
                    if extendedFrame.contains(mouseLocation) {
                        return
                    }
                }

                // 执行失焦 - 只有当窗口确实是 key 且鼠标离开了才尝试 resign
                if window.isKeyWindow {
                    NotificationCenter.default.post(name: NSNotification.Name("StickyNoteBlur"), object: self.noteId)
                }
            }
        }

        blurWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    deinit {
        // 清理所有任务
        focusTimer?.invalidate()
        focusTimer = nil
        blurWorkItem?.cancel()
        blurWorkItem = nil
    }
}
