import SwiftUI
import Combine

/// 贴纸视图 - 支持多页切换、Markdown 输入、尺寸调整
struct StickyNoteView: View {
    @State var note: StickyNoteModel
    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @State private var showControlsOverride: Bool = false // 强制隐藏控制条
    
    // 命令发布者，用于工具栏与编辑器的通信
    private let commandPublisher = PassthroughSubject<StickyNoteCommand, Never>()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // 背景和主体
            VStack(spacing: 0) {
                // 顶部拖拽手柄 - 固定高度，不随状态改变
                Rectangle()
                    .fill(Color.themeBackground)
                    .frame(height: 14)
                    .overlay(
                        Capsule()
                            .fill(Color.themeTextTertiary.opacity(0.3))
                            .frame(width: 24, height: 3)
                    )
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering { isHovered = true }
                    }
                
                // 内容区域 - 占据剩余所有空间
                ZStack(alignment: .bottom) {
                    StickyNoteEditor(
                        text: Binding(
                            get: { note.currentContent },
                            set: { val in 
                                note.currentContent = val
                                StickyNoteManager.shared.updateNote(note)
                            }
                        ),
                        fontSize: 13,
                        isFocused: isFocused,
                        onFocusChange: { focused in
                            if isFocused != focused {
                                withAnimation(.themeDuration300) {
                                    isFocused = focused
                                }
                            }
                        },
                        commandPublisher: commandPublisher.eraseToAnyPublisher()
                    )
                    .padding(.bottom, 42) // 核心：始终保留底部预留空间，防止工具栏遮挡最后一行文字，同时保证不抖动
                    .focused($isFocused)
                    
                    // 底部控制条 - 浮动在预留空间之上
                    if isFocused && !showControlsOverride {
                        StickyNoteToolbar(note: $note, isFocused: $isFocused, onCommand: { command in
                            commandPublisher.send(command)
                        })
                        .padding(.bottom, 6)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.themeBackground.opacity(isFocused ? 0.98 : 0.9))
            }
            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue))
            .overlay(
                RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                    .stroke(isFocused ? Color.themeBlue500.opacity(0.5) : Color.themeBorder, lineWidth: 1)
            )
            // ... 保持原有通知处理不变 ...
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StickyNoteBlur"))) { notification in
                    // 这里的通知由 StickyNoteWindow 发出，确保失焦时立即隐藏
                    if let blurId = notification.object as? UUID, blurId == note.id {
                        withAnimation(.themeDuration300) {
                            showControlsOverride = true
                            isFocused = false
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
                    // 监听窗口失去 key 状态，确保失焦逻辑触发
                    if let window = notification.object as? NSWindow, 
                       (window as? StickyNoteWindow)?.contentView is NSHostingView<StickyNoteView> {
                        withAnimation(.themeDuration300) {
                            showControlsOverride = true
                            isFocused = false
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StickyNoteFocus"))) { notification in
                    // 这里的通知由 StickyNoteWindow 发出，确保获得焦点时直接可以输入
                    if let focusId = notification.object as? UUID, focusId == note.id {
                        showControlsOverride = false
                        isFocused = true
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    // 应用重新激活时，如果窗口是 key，尝试聚焦编辑器
                    if let window = NSApp.keyWindow, (window as? StickyNoteWindow)?.contentView is NSHostingView<StickyNoteView> {
                        isFocused = true
                    }
                }
            
            // 调整尺寸的三个点
            if isFocused && !showControlsOverride {
                HStack {
                    ResizeHandle(edge: .bottomLeading, note: $note)
                    Spacer()
                    ResizeHandle(edge: .bottom, note: $note)
                    Spacer()
                    ResizeHandle(edge: .bottomTrailing, note: $note)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 2)
            }
        }
        .frame(minWidth: 150, minHeight: 100)
        .onHover { hovering in
            withAnimation(.themeDuration300) {
                isHovered = hovering
                if hovering {
                    showControlsOverride = false
                }
            }
        }
        .onChange(of: isFocused) { focused in
            if focused {
                showControlsOverride = false
            }
        }
    }
    
    // MARK: - Helper Methods

    private func saveToRecords() {
        StickyNoteManager.shared.saveToRecords(note: note)
        // 存入后清空当前页内容
        note.currentContent = ""
        StickyNoteManager.shared.updateNote(note)
    }
}

/// 底部工具栏组件
struct StickyNoteToolbar: View {
    @Binding var note: StickyNoteModel
    @FocusState.Binding var isFocused: Bool
    var onCommand: (StickyNoteCommand) -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            // 1. 编辑工具组
            HStack(spacing: 8) {
                StickyNoteToolbarButton(name: .square, tooltip: "待办列表", action: { onCommand(.toggleTodo) })
                StickyNoteToolbarButton(name: .bold, tooltip: "加粗", action: { onCommand(.toggleBold) })
                StickyNoteToolbarButton(name: .strikethrough, tooltip: "删除线", action: { onCommand(.toggleStrikethrough) })
                
                // 颜色选择器
                HStack(spacing: 4) {
                    ColorDot(color: .themeYellow400, hex: "FACC15", onCommand: onCommand)
                    ColorDot(color: .themeBlue400, hex: "60A5FA", onCommand: onCommand)
                    ColorDot(color: .themeGreen400, hex: "4ADE80", onCommand: onCommand)
                    ColorDot(color: .themeRed400, hex: "F87171", onCommand: onCommand)
                    
                    Button(action: { onCommand(.resetFormat) }) {
                        Image(systemName: "arrow.counterclockwise.circle")
                            .font(.system(size: 10))
                            .foregroundColor(.themeTextTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("重置颜色")
                }
                .padding(.horizontal, 4)
                .background(Color.themeHoverLight.cornerRadius(4))
            }
            
            Spacer(minLength: 4)
            
            // 2. 页面切换组
            HStack(spacing: 4) {
                ForEach(0..<note.pages.count, id: \.self) { index in
                    Button(action: {
                        note.currentPageIndex = index
                        StickyNoteManager.shared.updateNote(note)
                    }) {
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: note.currentPageIndex == index ? .bold : .medium))
                            .foregroundColor(note.currentPageIndex == index ? .themeTextPrimary : .themeTextTertiary)
                            .frame(width: 16, height: 16)
                            .background(note.currentPageIndex == index ? Color.themeHoverStrong : Color.clear)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer(minLength: 4)
            
            // 3. 操作组
            HStack(spacing: 8) {
                StickyNoteToolbarButton(name: .save, tooltip: "存入并清空", action: { 
                    StickyNoteManager.shared.saveToRecords(note: note)
                    note.currentContent = ""
                    StickyNoteManager.shared.updateNote(note)
                })
                
                StickyNoteToolbarButton(name: .trash, tooltip: "删除贴纸", color: .themeStatusError.opacity(0.9), action: {
                    StickyNoteManager.shared.deleteNote(note)
                })
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.themeCard.opacity(0.98))
                .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.horizontal, 8)
    }
}

/// 工具栏按钮封装
struct StickyNoteToolbarButton: View {
    let name: IconName
    let tooltip: String
    var color: Color = .themeTextSecondary
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            LucideView(name: name, size: 12, color: color)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}


/// 颜色选择小圆点组件
struct ColorDot: View {
    let color: Color
    let hex: String
    var onCommand: (StickyNoteCommand) -> Void
    
    var body: some View {
        Button(action: {
            onCommand(.applyColor(hex: hex))
        }) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .buttonStyle(.plain)
    }
}

/// 调整尺寸的手柄
struct ResizeHandle: View {
    enum Edge {
        case bottomLeading, bottom, bottomTrailing
    }
    
    let edge: Edge
    @Binding var note: StickyNoteModel
    
    var body: some View {
        Circle()
            .fill(Color.themeTextTertiary.opacity(0.5))
            .frame(width: 6, height: 6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateFrame(with: value.translation)
                    }
                    .onEnded { _ in
                        StickyNoteManager.shared.updateNote(note)
                    }
            )
            .onHover { hovering in
                if hovering {
                    switch edge {
                    case .bottomLeading: NSCursor.resizeLeftRight.push()
                    case .bottom: NSCursor.resizeUpDown.push()
                    case .bottomTrailing: NSCursor.resizeLeftRight.push()
                    }
                } else {
                    NSCursor.pop()
                }
            }
    }
    
    private func updateFrame(with translation: CGSize) {
        // 查找当前窗口
        guard let window = NSApp.windows.first(where: { ($0 as? StickyNoteWindow)?.contentView is NSHostingView<StickyNoteView> }) else { return }
        
        var newFrame = window.frame
        switch edge {
        case .bottomLeading:
            newFrame.size.width -= translation.width
            newFrame.size.height += translation.height
            newFrame.origin.x += translation.width
            newFrame.origin.y -= translation.height
        case .bottom:
            newFrame.size.height += translation.height
            newFrame.origin.y -= translation.height
        case .bottomTrailing:
            newFrame.size.width += translation.width
            newFrame.size.height += translation.height
            newFrame.origin.y -= translation.height
        }
        
        // 限制最小尺寸
        if newFrame.size.width >= 150 && newFrame.size.height >= 100 {
            window.setFrame(newFrame, display: true)
        }
    }
}

extension Notification.Name {
    static let stickyNoteFrameChanged = Notification.Name("stickyNoteFrameChanged")
}

extension Animation {
    static let themeDuration300 = Animation.easeOut(duration: 0.3)
}
