import SwiftUI
import Combine

/// 贴纸视图：多页切换、Markdown 编辑、拖动、缩放
///
/// 视图树保持静态：工具栏、失焦蒙层、缩放手柄、提示条常驻，只用透明度和命中测试切换。
/// NSHostingView 里"内容插入/移除的过渡动画"与"窗口逐帧缩放"并发会触发约束循环
/// （主面板五连闪退的根因，见 AGENTS.md「浮球边缘闪跳修复」），便利贴从结构上避开
struct StickyNoteView: View {
    @State var note: StickyNoteModel
    @State private var isDragHandleHovered = false
    @FocusState private var isFocused: Bool
    /// 失焦后收起工具栏，直到鼠标回来或重新聚焦
    @State private var controlsHidden = false
    @State private var hintMessage = ""
    @State private var hintVisible = false
    @State private var hintToken = 0

    // 命令发布者，用于工具栏与编辑器的通信
    private let commandPublisher = PassthroughSubject<StickyNoteCommand, Never>()
    private static let hintDuration: TimeInterval = 1.8

    private var controlsVisible: Bool { isFocused && !controlsHidden }

    var body: some View {
        let projectInfo = note.extractProjectInfo()
        let noteColor = note.color.background
        ZStack(alignment: .bottom) {
            // 背景和主体
            VStack(spacing: 0) {
                // 顶部拖拽手柄 - 固定高度，不随状态改变
                ZStack(alignment: .topTrailing) {
                    Rectangle()
                        .fill(noteColor)
                        .frame(height: 24)
                        .overlay(
                            Capsule()
                                .fill(isDragHandleHovered ? Color.themeBlue400 : Color.themeTextTertiary.opacity(0.3))
                                .frame(width: 24, height: 3)
                        )
                        .overlay(Color.themeBlue500.opacity(isDragHandleHovered ? 0.10 : 0))
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering { isDragHandleHovered = true }
                        }

                    // 右上角 Space 固定状态指示器
                    LucideView(name: .pin, size: 8, color: .themeGreen500)
                        .opacity(note.pinnedToAllSpaces ? 1 : 0)
                        .padding(.trailing, 6)
                        .padding(.top, 4)
                        .help("固定到所有 Space")
                }

                // 内容区域 - 占据剩余所有空间
                StickyNoteEditor(
                    text: Binding(
                        get: { note.currentContent },
                        set: { value in
                            guard value != note.currentContent else { return }
                            note.currentContent = value
                            StickyNoteManager.shared.updateContent(
                                noteID: note.id,
                                pages: note.pages,
                                currentPageIndex: note.currentPageIndex
                            )
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
                .padding(.bottom, 42) // 始终为工具栏预留底部空间：既不遮住最后一行，也不抖动
                .focused($isFocused)
                // 底部控制条 - 浮在预留空间之上
                .overlay(alignment: .bottom) {
                    // 必须用 overlay，不能和编辑区放进同一个 ZStack：那样工具栏一宽，整个容器
                    // 就跟着变宽并居中，编辑区被挤得左移、每行开头裁掉（默认宽度下就发生过）
                    StickyNoteToolbar(note: $note, onCommand: { command in
                        commandPublisher.send(command)
                    })
                    .padding(.bottom, 6)
                    .opacity(controlsVisible ? 1 : 0)
                    .allowsHitTesting(controlsVisible)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(noteColor.opacity(isFocused ? 0.98 : 0.9))
            }
            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue))

            // 边框 - 使用第一行颜色（白色/浅色则用默认边框）
            .overlay(
                RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                    .stroke(borderColor(projectInfo.color), lineWidth: 1)
                    .allowsHitTesting(false)
            )

            // 失焦蒙层 - 盖住正文，显示项目名；首行为空时没有项目名可显示，不盖
            ZStack {
                noteColor.opacity(0.7)
                    .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue))
                Text(projectInfo.name)
                    .font(.themeH2)
                    .foregroundColor(projectInfo.color ?? .themeTextPrimary)
            }
            .opacity(isFocused || projectInfo.name.isEmpty ? 0 : 1)
            .allowsHitTesting(false)

            // 调整尺寸的三个点
            HStack {
                ResizeHandle(edge: .bottomLeading, noteID: note.id)
                Spacer()
                ResizeHandle(edge: .bottom, noteID: note.id)
                Spacer()
                ResizeHandle(edge: .bottomTrailing, noteID: note.id)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)
        }
        .frame(minWidth: StickyNoteGeometry.minimumSize.width, minHeight: StickyNoteGeometry.minimumSize.height)
        // Keep the drag target above decorations and below the system resize edge.
        .overlay(alignment: .top) {
            StickyNoteDragRegion { isDragHandleHovered = $0 }
                .frame(height: 20)
                .padding(.top, 4)
        }
        // 短暂提示（保存到记录、固定状态等）
        .overlay(alignment: .top) {
            Text(hintMessage)
                .font(.themeCaption)
                .foregroundColor(.themeTextPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.themeGray800.opacity(0.96)))
                .overlay(Capsule().stroke(Color.themeBorder, lineWidth: 1))
                .padding(.top, 28)
                .opacity(hintVisible ? 1 : 0)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
        .onHover { hovering in
            if hovering {
                withAnimation(.themeDuration300) { controlsHidden = false }
            }
        }
        .onChange(of: isFocused) { focused in
            if focused {
                controlsHidden = false
            }
        }
        // 通知处理
        .onReceive(NotificationCenter.default.publisher(for: QuiteNoteNotification.stickyNoteBlur.name)) { notification in
            if notification.object as? UUID == note.id, isFocused {
                withAnimation(.themeDuration300) {
                    controlsHidden = true
                    isFocused = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            // 只认自己这张窗口：别的便利贴失焦不该连带这里一起收起工具栏
            if (notification.object as? StickyNoteWindow)?.id == note.id, isFocused {
                withAnimation(.themeDuration300) {
                    controlsHidden = true
                    isFocused = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: QuiteNoteNotification.stickyNoteFocus.name)) { notification in
            if let focusID = notification.object as? UUID, focusID == note.id, !isFocused {
                controlsHidden = false
                isFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // 应用重新激活时只有 key window 的那张进入聚焦态（原来所有便利贴同时亮工具栏）
            if (NSApp.keyWindow as? StickyNoteWindow)?.id == note.id, !isFocused {
                controlsHidden = false
                isFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: QuiteNoteNotification.stickyNoteSyncChanged.name)) { notification in
            // 只更新 syncRecordId，不整体替换 note，避免冲掉正在编辑的内容
            if let syncID = notification.object as? UUID, syncID == note.id {
                note.syncRecordId = notification.userInfo?["recordId"] as? UUID
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: QuiteNoteNotification.stickyNoteContentUpdated.name)) { notification in
            if let updatedID = notification.object as? UUID, updatedID == note.id,
               let updatedNote = StickyNoteManager.shared.notes.first(where: { $0.id == note.id }) {
                note = updatedNote
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: QuiteNoteNotification.stickyNoteHint.name)) { notification in
            if notification.object as? UUID == note.id, let message = notification.userInfo?["message"] as? String {
                showHint(message)
            }
        }
    }

    // MARK: - Helper Methods

    private func showHint(_ message: String) {
        hintMessage = message
        withAnimation(.themeDuration300) { hintVisible = true }
        hintToken += 1
        let token = hintToken
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hintDuration) {
            // 期间又来了新提示，由新的那次的定时负责收起
            guard token == hintToken else { return }
            withAnimation(.themeDuration300) { hintVisible = false }
        }
    }

    private func borderColor(_ projectColor: Color?) -> Color {
        guard let projectColor = projectColor,
              // 检查是否是白色/浅色（是则用默认边框）
              let components = projectColor.cgColor?.components,
              components.count >= 3,
              !(components[0] > 0.9 && components[1] > 0.9) else {
            return .themeBorder
        }
        return projectColor
    }
}

extension StickyNoteManager.SyncFailure {
    /// 给用户看的一句话说明；nil 表示不用提示
    var hintMessage: String? {
        switch self {
        case .noteMissing: return nil
        case .blankContent: return "内容为空，没有可保存的内容"
        case .storeUnavailable: return "记录库尚未就绪，稍后再试"
        case .recordMissing: return "原记录已不存在，已转为未同步；再点一次可另存为新记录"
        case .updateFailed(let message): return "更新记录失败：\(message)"
        case .saveFailed: return "保存到记录失败"
        }
    }
}

/// 底部工具栏组件
///
/// 两档布局，ViewThatFits 选第一个在当前宽度下放得下的：
/// - 常规：待办 / 加粗 / 删除线 / 符号 / 文字颜色 · 页码 · 便签底色 / 同步 / 关闭
/// - 紧凑：文字颜色、便签底色、页码收进「更多」菜单，按钮缩到 14pt（最窄 150pt 的便签也放得下）
struct StickyNoteToolbar: View {
    @Binding var note: StickyNoteModel
    var onCommand: (StickyNoteCommand) -> Void
    /// 上一次因同步失败而拒绝关闭的时间。记录库出问题时更新记录会一直失败，
    /// 便利贴不能因此永远关不掉：短时间内再点一次就放弃未同步的修改直接关闭
    @State private var refusedCloseAt: Date?
    private static let forceCloseWindow: TimeInterval = 8

    private var isSynced: Bool { note.syncRecordId != nil }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            regularBar
            compactBar
        }
        .padding(.horizontal, 8)
    }

    // MARK: - 两档布局

    private var regularBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                primaryButtons(size: 16)
                StickyNoteTextColorMenu(size: 16) { onCommand($0) }
            }
            Spacer(minLength: 4)
            pageButtons
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                StickyNoteColorButton(note: $note)
                    .frame(width: 16, height: 16)
                syncButton(size: 16)
                closeButton(size: 16)
            }
        }
        .modifier(ToolbarChrome(horizontalPadding: 8))
    }

    // 实测宽 131pt（「更多」是原生菜单控件，最窄 24pt）。最窄的便签 150pt，扣掉两侧边距剩 134pt
    private var compactBar: some View {
        HStack(spacing: 2) {
            primaryButtons(size: 14)
            moreMenu(size: 14)
            syncButton(size: 14)
            closeButton(size: 14)
        }
        .modifier(ToolbarChrome(horizontalPadding: 4))
    }

    // MARK: - 各组按钮

    /// 两档都有的一组：待办 / 加粗 / 删除线 / 符号
    private func primaryButtons(size: CGFloat) -> some View {
        HStack(spacing: size >= 16 ? 8 : 3) {
            StickyNoteToolbarButton(name: .square, tooltip: "待办列表", size: size) { onCommand(.toggleTodo) }
            StickyNoteToolbarButton(name: .bold, tooltip: "加粗", size: size) { onCommand(.toggleBold) }
            StickyNoteToolbarButton(name: .strikethrough, tooltip: "删除线", size: size) { onCommand(.toggleStrikethrough) }
            SymbolToolbarButton(size: size)
        }
    }

    /// 页码切换（常规栏里是三个小按钮）
    private var pageButtons: some View {
        HStack(spacing: 4) {
            ForEach(Array(note.pages.indices), id: \.self) { index in
                let isCurrent = note.currentPageIndex == index
                Button(action: { selectPage(index) }) {
                    Text("\(index + 1)")
                        .font(.themeCaptionSmall.weight(isCurrent ? .bold : .medium))
                        .foregroundColor(isCurrent ? .themeTextPrimary : .themeTextTertiary)
                        .frame(width: 16, height: 16)
                        .background(isCurrent ? Color.themeHoverStrong : Color.clear)
                        .cornerRadius(ThemeRadius.sm.rawValue)
                }
                .buttonStyle(.plain)
                .help("第 \(index + 1) 页")
            }
        }
    }

    private func selectPage(_ index: Int) {
        note.currentPageIndex = index
        StickyNoteManager.shared.setCurrentPage(noteID: note.id, pageIndex: index)
    }

    /// 紧凑栏的「更多」：常规栏里放不下的文字颜色、便签底色、页码收进这里
    private func moreMenu(size: CGFloat) -> some View {
        Menu {
            Menu(L("sticky.toolbar.textColor", fallback: "文字颜色")) {
                StickyNoteTextColorItems(onCommand: onCommand)
            }
            Menu(L("sticky.toolbar.noteColor", fallback: "便签底色")) {
                StickyNoteColorItems(note: $note)
            }
            Divider()
            Menu(L("sticky.toolbar.pages", fallback: "页面")) {
                ForEach(Array(note.pages.indices), id: \.self) { index in
                    Button(String(format: L("sticky.toolbar.pageFormat", fallback: "第 %d 页"), index + 1)) {
                        selectPage(index)
                    }
                }
            }
        } label: {
            LucideView(name: .slidersHorizontal, size: 12, color: .themeTextSecondary)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("sticky.toolbar.more", fallback: "更多"))
    }

    /// 未同步 = 保存到记录，已同步 = 用便利贴的最新内容更新记录
    private func syncButton(size: CGFloat) -> some View {
        StickyNoteToolbarButton(
            name: .refreshCw,
            tooltip: isSynced ? "更新记录" : "保存到记录",
            color: isSynced ? .themeGreen500 : .themeTextSecondary,
            size: size
        ) {
            let wasSynced = isSynced
            switch StickyNoteManager.shared.syncToRecord(noteID: note.id) {
            case .success:
                StickyNoteManager.shared.showHint(wasSynced ? "记录已更新" : "已保存到记录", for: note.id)
            case .failure(let failure):
                if let message = failure.hintMessage {
                    StickyNoteManager.shared.showHint(message, for: note.id)
                }
            }
        }
    }

    /// 关闭按钮：已同步的便利贴先把最新内容写进记录，写不进去就不关
    private func closeButton(size: CGFloat) -> some View {
        StickyNoteToolbarButton(name: .x, tooltip: "关闭贴纸", color: .themeTextSecondary, size: size) {
            closeNote()
        }
    }

    private func closeNote() {
        if note.syncRecordId != nil {
            let forced = refusedCloseAt.map { Date().timeIntervalSince($0) < Self.forceCloseWindow } ?? false
            if !forced {
                switch StickyNoteManager.shared.syncToRecord(noteID: note.id) {
                case .success:
                    break
                case .failure(.updateFailed):
                    // 没能把最新内容写进记录就关掉，这次编辑就没了：先不关，提示再点一次
                    refusedCloseAt = Date()
                    StickyNoteManager.shared.showHint("更新失败，未关闭；再点一次放弃修改并关闭", for: note.id)
                    return
                case .failure:
                    // 记录已不存在（关联随之解除）、内容已清空、记录库不可用：按未同步的便利贴正常关闭
                    break
                }
            }
        }
        StickyNoteManager.shared.removeNote(id: note.id)
    }
}

/// 工具栏的底：圆角卡片 + 一圈很淡的描边
private struct ToolbarChrome: ViewModifier {
    var horizontalPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                    .fill(Color.themeCard.opacity(0.98))
                    .shadow(color: Color.themeShadowMedium, radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                    .stroke(Color.themeWhite20, lineWidth: 0.5)
            )
    }
}

/// 文字颜色菜单的内容（四个颜色 + 重置）：常规栏里是独立的菜单，紧凑栏里是「更多」的子菜单
struct StickyNoteTextColorItems: View {
    var onCommand: (StickyNoteCommand) -> Void

    private static let colors: [(name: String, hex: String)] = [
        (L("sticky.textColor.yellow", fallback: "黄"), "FACC15"),
        (L("sticky.textColor.blue", fallback: "蓝"), "60A5FA"),
        (L("sticky.textColor.green", fallback: "绿"), "4ADE80"),
        (L("sticky.textColor.red", fallback: "红"), "F87171"),
    ]

    var body: some View {
        ForEach(Self.colors, id: \.hex) { color in
            Button { onCommand(.applyColor(hex: color.hex)) } label: {
                HStack(spacing: 6) {
                    Image(nsImage: StickyNoteColor.circleSwatch(hex: color.hex))
                    Text(color.name)
                }
            }
        }
        Divider()
        Button { onCommand(.resetFormat) } label: {
            Text(L("sticky.toolbar.resetTextColor", fallback: "重置颜色"))
        }
    }
}

/// 「文字颜色」按钮：原生菜单，按住拖到颜色上松手就能选中
struct StickyNoteTextColorMenu: View {
    var size: CGFloat = 16
    var onCommand: (StickyNoteCommand) -> Void

    var body: some View {
        Menu {
            StickyNoteTextColorItems(onCommand: onCommand)
        } label: {
            LucideView(name: .palette, size: 12, color: .themeTextSecondary)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("文字颜色")
    }
}

/// 便签底色按钮：自绘色环 + 原生菜单。按下即弹出菜单，拖到颜色上松手就选中（一次抬指）。
///
/// 不用 SwiftUI 的 Menu（.borderlessButton）：那种菜单按钮画不出 SwiftUI 图形（Circle 的位置
/// 是空的，只画得出 Image）；换成图片后，选完颜色色环又会一直半亮、要再开一次菜单才恢复
/// （2026-11-25 测试机真鼠标实测）。这里自己画、自己弹 NSMenu，状态完全可控
struct StickyNoteColorButton: NSViewRepresentable {
    @Binding var note: StickyNoteModel

    func makeNSView(context: Context) -> StickyNoteColorButtonView {
        let view = StickyNoteColorButtonView()
        view.onSelect = { color in
            guard color != note.color else { return }
            note.color = color
            StickyNoteManager.shared.setColor(noteID: note.id, color: color)
        }
        view.color = note.color
        return view
    }

    func updateNSView(_ view: StickyNoteColorButtonView, context: Context) {
        view.color = note.color
    }
}

final class StickyNoteColorButtonView: NSView {
    /// 在菜单里选了颜色
    var onSelect: ((StickyNoteColor) -> Void)?
    var color: StickyNoteColor = .standard {
        didSet { if oldValue != color { needsDisplay = true } }
    }

    private static let diameter: CGFloat = 13
    /// 菜单弹在按钮上方，留一点间隙 */
    private static let menuGap: CGFloat = 4

    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = "便签底色"
        setAccessibilityElement(true)
        setAccessibilityRole(.popUpButton)
        setAccessibilityLabel("便签底色")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 焦点留给编辑区：点这个按钮不能把键盘焦点从正文里拿走 */
    override var acceptsFirstResponder: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        // 在 mouseDown 里同步弹出：菜单接管后续的拖动和松开
        showMenu()
    }

    /// 辅助功能按压（VoiceOver、界面自动化）：弹出要异步，否则这次按压请求会一直阻塞到菜单关闭
    override func accessibilityPerformPress() -> Bool {
        DispatchQueue.main.async { [weak self] in self?.showMenu() }
        return true
    }

    private func showMenu() {
        let menu = NSMenu()
        for (index, option) in StickyNoteColor.allCases.enumerated() {
            let item = NSMenuItem(title: option.name, action: #selector(picked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.image = StickyNoteColor.menuSwatchImage(color: option, isSelected: option == color)
            menu.addItem(item)
        }
        menu.update()
        // popUp 把菜单的「顶边」放在给定的点上（视图坐标系，原点在左下角）。要菜单整体在按钮
        // 上方、右边缘和按钮对齐（按钮在工具栏最右侧一组里，左对齐会伸出便签）：
        // 顶边 = 按钮顶边 + 间隙 + 菜单高度。屏幕放不下时系统会自己挪
        let top = NSPoint(x: bounds.width - menu.size.width, y: bounds.height + Self.menuGap + menu.size.height)
        menu.popUp(positioning: nil, at: top, in: self)
    }

    @objc private func picked(_ sender: NSMenuItem) {
        onSelect?(StickyNoteColor.allCases[sender.tag])
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(x: (bounds.width - Self.diameter) / 2, y: (bounds.height - Self.diameter) / 2,
                          width: Self.diameter, height: Self.diameter)
        (NSColor(hex: color.accentHex) ?? .white).setFill()
        NSBezierPath(ovalIn: rect).fill()
        let ring = StickyNoteColor.ringWidth(forDiameter: Self.diameter)
        (NSColor(hex: color.backgroundHex) ?? .black).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: ring, dy: ring)).fill()
    }
}

/// 便签底色的菜单内容（紧凑栏「更多」菜单里的子菜单）。当前底色带勾
struct StickyNoteColorItems: View {
    @Binding var note: StickyNoteModel

    var body: some View {
        ForEach(StickyNoteColor.allCases) { color in
            Button {
                guard color != note.color else { return }
                note.color = color
                StickyNoteManager.shared.setColor(noteID: note.id, color: color)
            } label: {
                HStack(spacing: 6) {
                    Image(nsImage: StickyNoteColor.menuSwatchImage(color: color, isSelected: color == note.color))
                    Text(color.name)
                }
            }
        }
    }
}

/// 工具栏按钮封装
struct StickyNoteToolbarButton: View {
    let name: IconName
    let tooltip: String
    var color: Color = .themeTextSecondary
    var size: CGFloat = 16
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LucideView(name: name, size: 12, color: color)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

/// 调整尺寸的手柄。窗口按便利贴 id 定位：所有便利贴窗口类型相同，早先取
/// NSApp.windows 的第一个，多张便利贴时会去改另一张的尺寸
struct ResizeHandle: View {
    enum Edge {
        case bottomLeading, bottom, bottomTrailing
    }

    let edge: Edge
    let noteID: UUID
    /// 手势开始时的窗口 frame：每一帧都在它的基础上累加位移（拿"当前 frame + 累计位移"
    /// 会越拖越快）
    @State private var baseFrame: NSRect?

    var body: some View {
        Circle()
            .fill(Color.themeTextTertiary.opacity(0.5))
            .frame(width: 6, height: 6)
            // 点击区放大到 20×10（原来只有圆点本身的 6pt，很难抓）。
            // 高度只加到 10：手柄行贴着工具栏底边，再高会盖住工具栏按钮的下半截
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        resize(translation: value.translation)
                    }
                    .onEnded { _ in
                        baseFrame = nil
                        StickyNoteWindow.find(noteID: noteID)?.blurIfMouseOutside()
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

    private func resize(translation: CGSize) {
        guard let window = StickyNoteWindow.find(noteID: noteID) else { return }
        let base = baseFrame ?? window.frame
        baseFrame = base

        var width = base.width
        var height = base.height
        var origin = base.origin
        switch edge {
        case .bottomLeading:
            width = base.width - translation.width
            origin.x = base.maxX - max(width, StickyNoteGeometry.minimumSize.width)
            height = base.height + translation.height
            origin.y = base.maxY - max(height, StickyNoteGeometry.minimumSize.height)
        case .bottom:
            height = base.height + translation.height
            origin.y = base.maxY - max(height, StickyNoteGeometry.minimumSize.height)
        case .bottomTrailing:
            width = base.width + translation.width
            height = base.height + translation.height
            origin.y = base.maxY - max(height, StickyNoteGeometry.minimumSize.height)
        }
        // 两个方向各自钳到最小尺寸：拖过头的那个轴停住，另一个轴还能继续
        window.setFrame(
            NSRect(
                x: origin.x,
                y: origin.y,
                width: max(width, StickyNoteGeometry.minimumSize.width),
                height: max(height, StickyNoteGeometry.minimumSize.height)
            ),
            display: true
        )
    }
}

// MARK: - 原生拖拽区域

/// 顶部拖拽手柄的原生封装
struct StickyNoteDragRegion: NSViewRepresentable {
    var onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> StickyNoteDragHandleView {
        let view = StickyNoteDragHandleView()
        view.onHoverChanged = onHoverChanged
        view.toolTip = "拖动以移动便签"
        return view
    }

    func updateNSView(_ nsView: StickyNoteDragHandleView, context: Context) {
        nsView.onHoverChanged = onHoverChanged
    }
}

/// 把 mouseDown 直接转交给自身所在窗口执行拖动；
/// 只用 self.window，不做全局/keyWindow 查找，避免操作到错误窗口
class StickyNoteDragHandleView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityLabel("Sticky note drag handle")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 窗口未成为 key 时首击也要开始拖动，而不是被“激活窗口”消耗
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    // 拖动完全由 mouseDown 里的 performDrag 驱动，不走背景拖动路径
    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea = hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = window, window.isMovable else { return }
        NSCursor.closedHand.set()
        window.performDrag(with: event)
        window.invalidateCursorRects(for: self)
    }
}

extension Animation {
    static let themeDuration300 = Animation.easeOut(duration: 0.3)
}
