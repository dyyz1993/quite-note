import SwiftUI

/// 贴纸视图 - 支持多页切换、Markdown 输入、尺寸调整
struct StickyNoteView: View {
    @State var note: StickyNoteModel
    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @State private var showControlsOverride: Bool = false // 强制隐藏控制条
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // 背景和主体
            VStack(spacing: 0) {
                // 内容区域
                ScrollView {
                    // 使用 TextEditor 并尝试简单的 Markdown 样式（如果系统支持）
                    TextEditor(text: Binding(
                        get: { note.currentContent },
                        set: { val in 
                            handleTextChange(val)
                        }
                    ))
                    .font(.themeBody)
                    .foregroundColor(.themeTextPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(ThemeSpacing.px2.rawValue)
                    .frame(minHeight: 150)
                }
                .background(Color.themeBackground.opacity(isFocused && !showControlsOverride ? 0.95 : 0.7)) // 失焦降低透明度
                .focused($isFocused)
                .overlay(
                    // 简单的待办点击层（如果需要，这只是一个示意，真正的交互需要更复杂的自定义 TextEditor）
                    Group {
                        if note.currentContent.contains("- [ ]") || note.currentContent.contains("- [x]") {
                            // 这里可以添加逻辑，但 SwiftUI 原生 TextEditor 不支持内联点击
                        }
                    }
                )
                
                // 底部控制条 (仅在获得焦点时显示)
                if isFocused && !showControlsOverride {
                    HStack(spacing: ThemeSpacing.px2.rawValue) {
                        // 1. 编辑工具组 (待办、加粗)
                        HStack(spacing: 12) {
                            Button(action: { toggleTodo() }) {
                                LucideView(name: .check, size: 11, color: .themeTextSecondary)
                            }
                            .buttonStyle(.plain)
                            .help("待办列表")
                            
                            Button(action: { toggleBold() }) {
                                LucideView(name: .bold, size: 11, color: .themeTextSecondary)
                            }
                            .buttonStyle(.plain)
                            .help("加粗")
                        }
                        .padding(.leading, 12) // 往里缩一点，避免干扰左下角手柄
                        
                        Spacer()
                        
                        // 2. 页面切换组 (1 2 3)
                        HStack(spacing: 8) {
                            ForEach(0..<note.pages.count, id: \.self) { index in
                                Button(action: {
                                    note.currentPageIndex = index
                                    StickyNoteManager.shared.updateNote(note)
                                }) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 10, weight: note.currentPageIndex == index ? .bold : .regular))
                                        .foregroundColor(note.currentPageIndex == index ? .themeTextPrimary : .themeTextTertiary)
                                        .frame(width: 18, height: 18)
                                        .background(note.currentPageIndex == index ? Color.themeHoverStrong : Color.clear)
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        Spacer()
                        
                        // 3. 操作组 (存入记录、删除)
                        HStack(spacing: 12) {
                            Button(action: { 
                                StickyNoteManager.shared.saveToRecords(note: note)
                                // 存入后清空当前页内容
                                note.currentContent = ""
                                StickyNoteManager.shared.updateNote(note)
                            }) {
                                LucideView(name: .save, size: 11, color: .themeTextSecondary)
                            }
                            .buttonStyle(.plain)
                            .help("存入记录并清空")
                            
                            Button(action: {
                                StickyNoteManager.shared.deleteNote(note)
                            }) {
                                LucideView(name: .trash, size: 13, color: .themeStatusError.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .help("删除贴纸")
                        }
                        .padding(.trailing, 12) // 往里缩一点，避免干扰右下角手柄
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                    .background(Color.themeGray800) // 使用实色背景，防止透明度过高看不清
                    .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue))
            .overlay(
                RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                    .stroke(isFocused && !showControlsOverride ? Color.themeBlue500.opacity(0.8) : Color.themeBorder, lineWidth: 1)
            )
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StickyNoteBlur"))) { notification in
                    // 这里的通知由 StickyNoteWindow 发出，确保失焦时立即隐藏
                    if let blurId = notification.object as? UUID, blurId == note.id {
                        showControlsOverride = true
                        isFocused = false
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
    
    /// 处理文本变化，支持自动补全
    private func handleTextChange(_ newValue: String) {
        var processedValue = newValue
        
        // 自动补全待办事项: 如果当前行以 - [ ] 或 - [x] 开头，且用户按下了换行
        if newValue.count > note.currentContent.count && newValue.hasSuffix("\n") {
            let lines = note.currentContent.components(separatedBy: .newlines)
            if let lastLine = lines.last {
                let trimmed = lastLine.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- [ ]") {
                    processedValue += "- [ ] "
                } else if trimmed.hasPrefix("- [x]") {
                    processedValue += "- [ ] " // 默认补全未完成
                }
            }
        }
        
        note.currentContent = processedValue
        StickyNoteManager.shared.updateNote(note)
    }
    
    private func toggleTodo() {
        let content = note.currentContent
        var lines = content.components(separatedBy: .newlines)
        
        // 简单逻辑：如果是空或者最后一行没有待办，则添加；否则切换最后一行的状态
        if let lastLine = lines.last {
            if lastLine.trimmingCharacters(in: .whitespaces).hasPrefix("- [ ]") {
                lines[lines.count - 1] = lastLine.replacingOccurrences(of: "- [ ]", with: "- [x]")
            } else if lastLine.trimmingCharacters(in: .whitespaces).hasPrefix("- [x]") {
                lines[lines.count - 1] = lastLine.replacingOccurrences(of: "- [x]", with: "- [ ]")
            } else {
                lines[lines.count - 1] = "- [ ] " + lastLine
            }
        } else {
            lines.append("- [ ] ")
        }
        
        note.currentContent = lines.joined(separator: "\n")
        StickyNoteManager.shared.updateNote(note)
    }
    
    private func toggleBold() {
        // 使用 Lucide 图标替换原来的 B 文本 (已经在 body 中修改过调用处)
        // 简单实现：在当前内容末尾添加 **
        note.currentContent += "****"
        StickyNoteManager.shared.updateNote(note)
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
