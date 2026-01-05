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
        
        let area = NSTrackingArea(
            rect: self.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }
    
    override func mouseEntered(with event: NSEvent) {
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
        
        // 鼠标离开时延迟 0.3s 放弃 Key 状态，防止误触
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self, let window = self.window else { return }
            
            // 检查鼠标当前是否真的在窗口外
            let mouseLocation = NSEvent.mouseLocation
            let screenFrame = window.frame
            if !NSMouseInRect(mouseLocation, screenFrame, false) {
                if window.isKeyWindow {
                    window.resignKey()
                    // 通知视图强制更新焦点状态
                    NotificationCenter.default.post(name: NSNotification.Name("StickyNoteBlur"), object: self.noteId)
                }
            }
        }
    }
}
