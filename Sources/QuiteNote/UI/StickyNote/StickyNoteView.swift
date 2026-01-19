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
                ZStack(alignment: .topTrailing) {
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

                    // 右上角 Space 固定状态指示器
                    if note.pinnedToAllSpaces {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.themeGreen500)
                            .padding(.trailing, 6)
                            .padding(.top, 4)
                            .help("固定到所有 Space (⌘⌥P 切换)")
                    }
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

            // 边框 - 使用第一行颜色（如果不是白色）
            .overlay(
                RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                    .stroke(borderColor, lineWidth: 1)
            )

            // 失焦蒙层 - 显示项目名
            if !isFocused {
                let projectName = projectInfo.name
                if !projectName.isEmpty {
                    ZStack {
                        // 半透明蒙层
                        Color.themeBackground.opacity(0.7)
                            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue))

                        // 项目名显示
                        VStack(spacing: 4) {
                            if let projectColor = projectInfo.color {
                                // 使用第一行的颜色作为项目名颜色
                                Text(projectName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(projectColor)
                            } else {
                                Text(projectName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.themeTextPrimary)
                            }
                        }
                    }
                    .transition(.opacity)
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
        // 通知处理
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StickyNoteBlur"))) { notification in
            // 这里的通知由 StickyNoteWindow 发出，确保失焦时立即隐藏
            // 增加状态检查：只有当前是聚焦状态才处理，避免重复触发
            if let blurId = notification.object as? UUID, blurId == note.id, isFocused {
                withAnimation(.themeDuration300) {
                    showControlsOverride = true
                    isFocused = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            // 监听窗口失去 key 状态，确保失焦逻辑触发
            // 增加窗口类型检查和状态检查，防止多个窗口互相干扰
            if let window = notification.object as? StickyNoteWindow,
               window.contentView is NSHostingView<StickyNoteView>,
               isFocused {
                withAnimation(.themeDuration300) {
                    showControlsOverride = true
                    isFocused = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StickyNoteFocus"))) { notification in
            // 这里的通知由 StickyNoteWindow 发出，确保获得焦点时直接可以输入
            // 增加状态检查：只有当前不是聚焦状态才处理，避免重复触发
            if let focusId = notification.object as? UUID {
                print("[DEBUG StickyNoteView] Received StickyNoteFocus - noteId: \(note.id), focusId: \(focusId), match: \(focusId == note.id), current isFocused: \(isFocused)")
                if focusId == note.id, !isFocused {
                    showControlsOverride = false
                    isFocused = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // 应用重新激活时，如果窗口是 key，尝试聚焦编辑器
            if let window = NSApp.keyWindow, (window as? StickyNoteWindow)?.contentView is NSHostingView<StickyNoteView> {
                isFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StickyNoteSyncStatusChanged"))) { notification in
            // 监听同步状态变化，只更新 syncRecordId 属性，避免替换整个 note 导致内容丢失
            if let syncId = notification.object as? UUID, syncId == note.id,
               let recordId = notification.userInfo?["recordId"] as? UUID {
                note.syncRecordId = recordId  // 只更新 syncRecordId，不替换整个 note
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StickyNoteContentUpdated"))) { notification in
            // 监听内容更新，从记录重新打开时使用
            if let updatedId = notification.object as? UUID, updatedId == note.id {
                // 从 StickyNoteManager 获取最新的便签数据
                if let updatedNote = StickyNoteManager.shared.notes.first(where: { $0.id == note.id }) {
                    note = updatedNote
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var projectInfo: (name: String, color: Color?) {
        note.extractProjectInfo()
    }

    private var borderColor: Color {
        let projectInfo = note.extractProjectInfo()
        if let projectColor = projectInfo.color {
            // 检查是否是白色/浅色（如果是白色则使用默认边框）
            if let cgColor = projectColor.cgColor,
               let components = cgColor.components,
               components.count >= 3,
               components[1] > 0.9 && components[0] > 0.9 {
                return Color.themeBorder
            }
            return projectColor
        }
        return Color.themeBorder
    }

    // MARK: - Helper Methods

    private func saveToRecords() {
        StickyNoteManager.shared.saveToRecords(note: note)
        // 不再清空内容，保持便签内容
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

                // 符号按钮
                SymbolToolbarButton()

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
                        print("[DEBUG] 页面按钮点击: index=\(index), 页面数=\(note.pages.count)")
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
            .onAppear {
                print("[DEBUG] StickyNoteToolbar 页面数量: \(note.pages.count)")
            }

            Spacer(minLength: 4)

            // 3. 操作组
            HStack(spacing: 8) {
                // 同步按钮：根据是否已同步显示不同状态
                if note.syncRecordId != nil {
                    // 已同步：显示绿色同步按钮，点击更新记录
                    StickyNoteToolbarButton(name: .refreshCw, tooltip: "更新记录", color: .themeGreen500, action: {
                        // 从 StickyNoteManager 获取最新的便签数据（包含最新输入内容）
                        if let latestNote = StickyNoteManager.shared.notes.first(where: { $0.id == note.id }) {
                            StickyNoteManager.shared.saveToRecords(note: latestNote)
                        }
                    })
                } else {
                    // 未同步：显示白色同步按钮，点击保存到记录
                    StickyNoteToolbarButton(name: .refreshCw, tooltip: "保存到记录", color: .themeTextSecondary, action: {
                        // 从 StickyNoteManager 获取最新的便签数据（包含最新输入内容）
                        if let latestNote = StickyNoteManager.shared.notes.first(where: { $0.id == note.id }) {
                            StickyNoteManager.shared.saveToRecords(note: latestNote)
                        }
                    })
                }

                // 关闭按钮（关闭前如果已同步则更新记录）
                StickyNoteToolbarButton(name: .x, tooltip: "关闭贴纸", color: .themeTextSecondary, action: {
                    // 关闭时清除 Space 固定状态，确保下次打开时不固定
                    note.pinnedToAllSpaces = false
                    StickyNoteManager.shared.updateNote(note)

                    // 如果已同步，关闭前更新记录内容
                    if let recordId = note.syncRecordId,
                       // 从 StickyNoteManager 获取最新的便签数据（包含最新的位置）
                       let latestNote = StickyNoteManager.shared.notes.first(where: { $0.id == note.id }) {
                        let content = StickyNoteManager.shared.formatPagesForSaving(latestNote.pages)
                        let title = latestNote.extractNoteTitle()

                        NotificationCenter.default.post(
                            name: NSNotification.Name("StickyNoteUpdateRecord"),
                            object: nil,
                            userInfo: [
                                "recordId": recordId,
                                "content": content,
                                "noteFrame": latestNote.frame,  // 使用最新的 frame
                                "title": title,
                                "noteId": latestNote.id
                            ]
                        )

                        // 延迟关闭，确保更新操作完成（避免竞态条件）
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            StickyNoteManager.shared.removeNote(id: note.id)
                        }
                    } else {
                        // 未同步，立即关闭
                        StickyNoteManager.shared.removeNote(id: note.id)
                    }
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
