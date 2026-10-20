import SwiftUI

/// 工具栏按钮 hover tooltip：常驻悬浮在按钮正上方（鼠标移开才消失，不自动关闭）。
/// tooltip 作为按钮自身 overlay 渲染（top 对齐 + 上移），天然跟随按钮位置，无需坐标换算；
/// allowsHitTesting(false) 保证 tooltip 不拦截鼠标（否则会遮挡按钮导致 hover 丢失、闪烁）。
private struct ToolbarHoverTooltip: ViewModifier {
    let text: String
    @Binding var tooltipText: String
    @Binding var showTooltip: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if showTooltip && tooltipText == text {
                    Text(text)
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.themeShadowHeavy)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .fixedSize()
                        .offset(y: -24)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .onHover { hovering in
                if hovering {
                    tooltipText = text
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showTooltip = true
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showTooltip = false
                    }
                }
            }
    }
}

/// Pure geometry for toolbar placement. Keeping this separate from SwiftUI makes
/// the edge cases testable without constructing a screenshot overlay.
enum V2AnnotationToolbarGeometry {
    static func mainToolbarCenter(
        in screen: CGRect,
        selection: CGRect,
        toolbarSize: CGSize,
        expandedContentRect: CGRect? = nil,
        spacing: CGFloat,
        margin: CGFloat
    ) -> CGPoint {
        // The hard screen constraint must include every visible layer. A toolbar
        // centered in-bounds can still put its above/below popover out of bounds.
        let mainRect = CGRect(origin: .zero, size: toolbarSize)
        let expandedRect = expandedContentRect ?? mainRect
        let contentMinX = min(mainRect.minX, expandedRect.minX)
        let contentMinY = min(mainRect.minY, expandedRect.minY)
        let contentMaxX = max(mainRect.maxX, expandedRect.maxX)
        let contentMaxY = max(mainRect.maxY, expandedRect.maxY)
        let idealX = selection.midX
        let minX = screen.minX + margin + toolbarSize.width / 2 - contentMinX
        let maxX = screen.maxX - margin - max(toolbarSize.width / 2, contentMaxX - toolbarSize.width / 2)
        let x = min(max(idealX, minX), max(minX, maxX))

        // Bounds for the main toolbar center, including any expanded layer.
        let minY = screen.minY + margin + toolbarSize.height / 2 - contentMinY
        let maxY = screen.maxY - margin - max(toolbarSize.height / 2, contentMaxY - toolbarSize.height / 2)
        let belowY = selection.maxY + spacing + toolbarSize.height / 2
        if belowY <= maxY {
            return CGPoint(x: x, y: max(belowY, minY))
        }

        let aboveY = selection.minY - spacing - toolbarSize.height / 2
        let clampedAboveY = min(max(aboveY, minY), max(minY, maxY))
        return CGPoint(x: x, y: clampedAboveY)
    }
}

private enum RecordingAudioPreset: CaseIterable, Identifiable {
    case demo, voiceover, meeting, silent

    var id: Self { self }
    var title: String {
        switch self {
        case .demo: return "操作演示"
        case .voiceover: return "口播教程"
        case .meeting: return "会议解说"
        case .silent: return "静音录屏"
        }
    }
    var icon: String {
        switch self {
        case .demo: return "speaker.wave.2.fill"
        case .voiceover: return "mic.fill"
        case .meeting: return "person.2.fill"
        case .silent: return "speaker.slash.fill"
        }
    }
    var systemAudio: Bool { self == .demo || self == .meeting }
    var microphone: Bool { self == .voiceover || self == .meeting }
}

/// V2 标注工具栏 - 完整的 11 种标注工具（精致的浮动子工具栏设计）
private struct ToolbarGroupFrameKey: PreferenceKey {
    static var defaultValue: [AnnotationToolGroup: CGRect] { [:] }
    static func reduce(value: inout [AnnotationToolGroup: CGRect], nextValue: () -> [AnnotationToolGroup: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

struct V2AnnotationToolbar: View {
    @ObservedObject var stateManager: V2PrimaryScreenStateManager
    @Binding var expandedContentRect: CGRect?

    init(
        stateManager: V2PrimaryScreenStateManager,
        expandedContentRect: Binding<CGRect?> = .constant(nil)
    ) {
        self.stateManager = stateManager
        self._expandedContentRect = expandedContentRect
    }

    private let colors: [Color] = [.red, .yellow, .green, .blue, .white, .black]
    /// 录制音频快选弹层（▾）：两路独立开关，写入 PreferencesManager 与设置页共用
    @State private var audioSystem = PreferencesManager.shared.recordingSystemAudio
    @State private var audioMicrophone = PreferencesManager.shared.recordingMicrophone
    @State private var cursorMode: V2RecordingCursorMode =
        V2RecordingCursorMode(rawValue: PreferencesManager.shared.recordingCursorMode) ?? .keep
    // P2.1: 自定义 tooltip 状态（tooltip 由每个按钮的 overlay 自渲染）
    @State private var tooltipText: String = ""
    @State private var showTooltip: Bool = false
    @State private var mainToolbarSize: CGSize = .zero
    @State private var secondaryToolbarSize: CGSize = .zero
    @State private var groupButtonFrames: [AnnotationToolGroup: CGRect] = [:]

    var body: some View {
        ZStack(alignment: .top) {
            // 1. 子工具栏（浮动在主工具栏上方）
            if let group = stateManager.expandedToolbarGroup,
               let tools = getSubTools(for: group), tools.count > 1 {
                subToolbar(for: tools)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { secondaryToolbarSize = geo.size }
                                .onChange(of: geo.size) { secondaryToolbarSize = $0 }
                        }
                    )
                    .offset(y: -60)
                    .onHover { hovering in
                        stateManager.isMouseOverUI = hovering
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 2. 主工具栏
            mainToolbarContent

            // 3. 音频快选弹层（浮动在主工具栏下方，右对齐录制按钮）
            if stateManager.isAudioPickerVisible {
                audioPickerPopover
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { secondaryToolbarSize = geo.size }
                                .onChange(of: geo.size) { secondaryToolbarSize = $0 }
                        }
                    )
                    .offset(y: 54)
                    .onHover { hovering in
                        stateManager.isMouseOverUI = hovering
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: stateManager.expandedToolbarGroup)
        .coordinateSpace(name: "V2AnnotationToolbar")
        .frame(maxWidth: 650) // 恢复宽度，新交互更省空间
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { mainToolbarSize = geo.size }
                    .onChange(of: geo.size) { mainToolbarSize = $0 }
            }
        )
        .onAppear { updateExpandedContentRect() }
        .onChange(of: stateManager.expandedToolbarGroup) { _ in updateExpandedContentRect() }
        .onChange(of: stateManager.isAudioPickerVisible) { _ in updateExpandedContentRect() }
        .onPreferenceChange(ToolbarGroupFrameKey.self) { frames in
            groupButtonFrames = frames
            updateExpandedContentRect()
        }
        .onChange(of: mainToolbarSize) { _ in updateExpandedContentRect() }
        .onChange(of: secondaryToolbarSize) { _ in updateExpandedContentRect() }
    }

    private var mainToolbarContent: some View {
        HStack(spacing: 12) {
            toolSelectionGroup
            
            if stateManager.selectedTool.supportsColor {
                colorSelectionGroup
            }
            
            if stateManager.selectedTool.supportsSize {
                sizeSelectionGroup
            }
            
            // ✨ 新增：放大镜倍率调节
            if stateManager.selectedTool == .magnifier || (stateManager.selectedTool == .cursor && isSelectedElementMagnifier) {
                magnifierScaleGroup
            }
            
            Divider().frame(height: 24).background(Color.white.opacity(0.2))
            actionButtonsGroup
            Divider().frame(width: 1, height: 24).background(Color.white.opacity(0.2))

            // OCR 文字识别按钮：对选区最终图跑本地 Vision 识别
            Button(action: {
                NotificationCenter.default.post(name: NSNotification.Name("OCRScreenshot"), object: nil)
            }) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.indigo.opacity(0.8), Color.indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 34, height: 34)

                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .modifier(ToolbarHoverTooltip(text: "文字识别 (⌘O)", tooltipText: $tooltipText, showTooltip: $showTooltip))

            // P3.3: 保存按钮 (Command+S) - 使用 SF Symbols
            Button(action: {
                NotificationCenter.default.post(name: NSNotification.Name("SaveScreenshot"), object: nil)
            }) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.blue.opacity(0.8), Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 34, height: 34)

                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .modifier(ToolbarHoverTooltip(text: "保存文件并复制路径 (⌘S)", tooltipText: $tooltipText, showTooltip: $showTooltip))

            // P3.3: 复制按钮 (Command+C) - 使用 SF Symbols
            Button(action: {
                NotificationCenter.default.post(name: NSNotification.Name("CopyScreenshot"), object: nil)
            }) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.green.opacity(0.8), Color.green],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 34, height: 34)

                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .modifier(ToolbarHoverTooltip(text: "复制到剪贴板 (⌘C)", tooltipText: $tooltipText, showTooltip: $showTooltip))

            // 区域录屏按钮：退出截图会话，对当前选区开始实时录制 (Command+R)
            Button(action: {
                NotificationCenter.default.post(name: NSNotification.Name("RecordScreenshot"), object: nil)
            }) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.themeRed500.opacity(0.85), Color.themeRed500],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 34, height: 34)

                    Image(systemName: "record.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .modifier(ToolbarHoverTooltip(text: "录制视频 (⌘R)", tooltipText: $tooltipText, showTooltip: $showTooltip))

            // 音频快选 ▾：选择本次录制的音频来源（两路独立开关，与设置页共用存储）
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    stateManager.isAudioPickerVisible.toggle()
                }
            }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(audioSystem || audioMicrophone ? .themeStatusSuccess : .white.opacity(0.55))
                    .frame(width: 16, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(ToolbarHoverTooltip(text: "录制音频：\(audioDescription)", tooltipText: $tooltipText, showTooltip: $showTooltip))

            // 用户反馈入口（刻意低调：小号半透明图标收在工具栏末尾，不与主操作抢占视觉——产品决策见 AGENTS.md）
            Button(action: {
                NotificationCenter.default.post(name: NSNotification.Name("FeedbackScreenshot"), object: nil)
            }) {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 22, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(ToolbarHoverTooltip(text: "反馈问题（自动附带当前截图）", tooltipText: $tooltipText, showTooltip: $showTooltip))
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.themeShadowHeavy.opacity(0.7))
        )
    }

    private var sizeSelectionGroup: some View {
        Group {
            Divider().frame(height: 24).background(Color.themeBorderSubtle)
            V2SizeDragControl(stateManager: stateManager)
        }
    }

    private var magnifierScaleGroup: some View {
        Group {
            Divider().frame(height: 24).background(Color.themeBorderSubtle)
            V2MagnifierScaleControl(stateManager: stateManager)
        }
    }

    private var isSelectedElementMagnifier: Bool {
        if let id = stateManager.selectedElementId,
           let element = stateManager.elements.first(where: { $0.id == id }) {
            return element.tool == .magnifier
        }
        return false
    }

    /// Popover bounds are in main-toolbar-local coordinates, so the floating
    /// container can include them in its hard screen-edge constraint.
    private func updateExpandedContentRect() {
        guard mainToolbarSize.width > 0, secondaryToolbarSize.width > 0 else {
            if expandedContentRect != nil {
                expandedContentRect = nil
            }
            return
        }

        let isSubToolbar = stateManager.expandedToolbarGroup != nil
        guard isSubToolbar || stateManager.isAudioPickerVisible else {
            if expandedContentRect != nil {
                expandedContentRect = nil
            }
            return
        }

        guard let group = stateManager.expandedToolbarGroup,
              let anchorRect = groupButtonFrames[group] else {
            if !isSubToolbar {
                updateAudioContentRect()
            } else if expandedContentRect != nil {
                expandedContentRect = nil
            }
            return
        }

        // The sub-toolbar is anchored to its owning group button's center. Only
        // the combined screen-edge constraint may move it away from that anchor.
        let expandedRect = CGRect(
            origin: CGPoint(
                x: anchorRect.midX - secondaryToolbarSize.width / 2,
                y: -60
            ),
            size: secondaryToolbarSize
        )
        expandedContentRect = clampedExpandedRect(expandedRect)
    }

    private func updateAudioContentRect() {
        let expandedRect = CGRect(
            origin: CGPoint(
                x: mainToolbarSize.width - secondaryToolbarSize.width,
                y: 54
            ),
            size: secondaryToolbarSize
        )
        expandedContentRect = clampedExpandedRect(expandedRect)
    }

    /// Preserve the primary requirement that every expanded control stays
    /// reachable while waiting for the exact screen size in the floating shell.
    private func clampedExpandedRect(_ expandedRect: CGRect) -> CGRect {
        let screenMaxX = max(mainToolbarSize.width, 1512)
        let minX: CGFloat = 0
        let maxX = screenMaxX - expandedRect.width
        let clampedX = min(max(expandedRect.minX, minX), max(minX, maxX))
        return CGRect(origin: CGPoint(x: clampedX, y: expandedRect.minY), size: expandedRect.size)
    }

    private var toolSelectionGroup: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationToolGroup.allCases, id: \.self) { group in
                groupButton(group)
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.4))
        .cornerRadius(8)
    }

    private var colorSelectionGroup: some View {
        Group {
            Divider().frame(height: 24).background(Color.white.opacity(0.2))

            HStack(spacing: 6) {
                ForEach(colors, id: \.self) { color in
                    colorButton(color)
                }
            }
            .padding(6)
            .background(Color.themeShadowMedium)
            .cornerRadius(8)
        }
    }

    private func colorButton(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 18, height: 18)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: stateManager.selectedColor == color ? 2 : 0)
            )
            .onTapGesture {
                stateManager.selectedColor = color
            }
    }

    private var actionButtonsGroup: some View {
        HStack(spacing: 8) {
            actionButton(icon: .rotateCcw, action: { stateManager.undoLastElement() }, tooltip: "撤销")
            actionButton(icon: .trash2, action: {
                if let id = stateManager.selectedElementId {
                    stateManager.elements.removeAll { $0.id == id }
                    stateManager.selectedElementId = nil
                }
            }, tooltip: "删除选中")
            actionButton(icon: .trash, action: { stateManager.clearElements() }, tooltip: "清空全部")
        }
    }

    /// 子工具栏
    private func subToolbar(for tools: [AnnotationTool]) -> some View {
        HStack(spacing: 8) {
            ForEach(tools, id: \.self) { tool in
                Button(action: {
                    stateManager.updateTool(tool)
                    AnnotationSettings.shared.setLastTool(tool)

                    // ✨ 选择标注工具时自动进入编辑模式
                    if tool != .cursor {
                        stateManager.setEditing(true)
                    }

                    stateManager.expandedToolbarGroup = nil // 选中后关闭
                }) {
                    LucideView(
                        name: IconName(rawValue: tool.rawValue) ?? .penTool,
                        size: 16,
                        color: stateManager.selectedTool == tool ? .white : Color.white.opacity(0.6)
                    )
                    .frame(width: 30, height: 30)
                    .background(stateManager.selectedTool == tool ? Color.themeBlue500.opacity(0.6) : Color.white.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.themeBackground.opacity(0.95))
                .shadow(color: Color.themeShadowMedium, radius: 5, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func getSubTools(for group: AnnotationToolGroup) -> [AnnotationTool]? {
        let tools = AnnotationTool.allCases.filter { $0.group == group }
        return tools.count > 1 ? tools : nil
    }

    /// 工具组按钮
    @ViewBuilder
    private func groupButton(_ group: AnnotationToolGroup) -> some View {
        let tools = AnnotationTool.allCases.filter { $0.group == group }
        let isSelected = stateManager.selectedTool.group == group
        let lastTool = AnnotationSettings.shared.getLastTool(for: group)

        Button(action: {
            stateManager.updateTool(lastTool)
            AnnotationSettings.shared.setLastTool(lastTool)

            // ✨ 选择标注工具时自动进入编辑模式
            if lastTool != .cursor {
                stateManager.setEditing(true)
            }

            if tools.count > 1 {
                if isSelected && stateManager.expandedToolbarGroup == group {
                    stateManager.expandedToolbarGroup = nil
                } else {
                    stateManager.expandedToolbarGroup = group
                }
            } else {
                stateManager.expandedToolbarGroup = nil
            }
        }) {
            LucideView(
                name: IconName(rawValue: isSelected ? stateManager.selectedTool.rawValue : lastTool.rawValue) ?? .penTool,
                size: 18,
                color: isSelected ? .white : .white.opacity(0.5)
            )
            .frame(width: 34, height: 34)
            .background(isSelected ? Color.blue.opacity(0.8) : Color.clear)
            .cornerRadius(8)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ToolbarGroupFrameKey.self,
                        value: [group: geo.frame(in: .named("V2AnnotationToolbar"))]
                    )
                }
            )
        }
        .buttonStyle(.plain)
    }

    /// P2.1: 操作按钮 - 常驻 tooltip 悬浮在按钮正上方
    private func actionButton(icon: IconName, action: @escaping () -> Void, tooltip: String, primary: Bool = false) -> some View {
        Button(action: action) {
            LucideView(name: icon, size: 18, color: .white)
                .frame(width: 34, height: 34)
                .background(primary ? Color.themeBlue500 : Color.white.opacity(0.1))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .modifier(ToolbarHoverTooltip(text: tooltip, tooltipText: $tooltipText, showTooltip: $showTooltip))
    }

    // MARK: - 录制音频快选

    private var audioDescription: String {
        switch (audioSystem, audioMicrophone) {
        case (true, true): return "系统声 + 麦克风"
        case (true, false): return "仅系统声"
        case (false, true): return "仅麦克风（口播）"
        case (false, false): return "无声"
        }
    }

    /// ▾ 弹层：录制前配置（音频两开关 + 鼠标模式）；写入偏好即长期记忆
    private var audioPickerPopover: some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.px1.rawValue + 2) {
            Text("本次录制配置（会被记住）")
                .font(.themeCaption)
                .foregroundColor(.themeTextTertiary)

            Text("快速预设")
                .font(.themeCaptionSmall)
                .foregroundColor(.themeTextTertiary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(RecordingAudioPreset.allCases) { preset in
                    presetButton(preset)
                }
            }

            audioToggleRow(isOn: $audioSystem,
                           icon: "speaker.wave.2.fill",
                           title: "系统声音",
                           subtitle: "电脑播放的")

            audioToggleRow(isOn: $audioMicrophone,
                           icon: "mic.fill",
                           title: "麦克风",
                           subtitle: "口播解说")

            Divider().frame(height: 1).background(Color.themeBorderSubtle)

            // 鼠标模式：保留 / 隐藏 / 点击高亮（14.2+）
            HStack(spacing: ThemeSpacing.px2.rawValue) {
                Text("鼠标")
                    .font(.themeBody)
                    .foregroundColor(.themeTextPrimary)
                Spacer()
                Picker("", selection: Binding(
                    get: { cursorMode },
                    set: { newValue in
                        cursorMode = newValue
                        PreferencesManager.shared.setRecordingCursorMode(newValue)
                    })) {
                    ForEach(V2RecordingCursorMode.allCases, id: \.self) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            .padding(.vertical, ThemeSpacing.px1.rawValue)

            HStack(spacing: ThemeSpacing.px2.rawValue) {
                Text("倒计时")
                    .font(.themeBody)
                    .foregroundColor(.themeTextPrimary)
                Spacer()
                Picker("", selection: Binding(
                    get: { PreferencesManager.shared.recordingCountdownSeconds },
                    set: { PreferencesManager.shared.setRecordingCountdownSeconds($0) })) {
                    Text("关闭").tag(0)
                    Text("3 秒").tag(3)
                    Text("5 秒").tag(5)
                }
                .pickerStyle(.menu)
                .controlSize(.small)
            }

            Text("口播=只勾麦克风 · 会议=都勾 · 演示=只勾系统声")
                .font(.themeCaptionSmall)
                .foregroundColor(.themeTextTertiary)
        }
        .padding(ThemeSpacing.px3.rawValue)
        .frame(width: 240, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                .fill(Color.themeGray900.opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                        .stroke(Color.themeBorderSubtle, lineWidth: 1)
                )
        )
        .onDisappear {
            // 弹层收起时把选择持久化（与设置页同一个存储）
            PreferencesManager.shared.setRecordingSystemAudio(audioSystem)
            PreferencesManager.shared.setRecordingMicrophone(audioMicrophone)
        }
    }

    private func presetButton(_ preset: RecordingAudioPreset) -> some View {
        let selected = audioSystem == preset.systemAudio && audioMicrophone == preset.microphone
        return Button(action: {
            audioSystem = preset.systemAudio
            audioMicrophone = preset.microphone
            PreferencesManager.shared.setRecordingSystemAudio(audioSystem)
            PreferencesManager.shared.setRecordingMicrophone(audioMicrophone)
        }) {
            HStack(spacing: 5) {
                Image(systemName: preset.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(preset.title)
                    .font(.themeCaptionSmall)
                    .lineLimit(1)
            }
            .foregroundColor(selected ? .white : .themeTextSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: ThemeRadius.sm.rawValue)
                    .fill(selected ? Color.themeBlue600.opacity(0.85) : Color.themeGray700)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ThemeRadius.sm.rawValue)
                    .stroke(selected ? Color.themeBlue400 : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(preset.title)
    }

    private func audioToggleRow(isOn: Binding<Bool>, icon: String, title: String, subtitle: String) -> some View {
        Button(action: {
            isOn.wrappedValue.toggle()
            PreferencesManager.shared.setRecordingSystemAudio(audioSystem)
            PreferencesManager.shared.setRecordingMicrophone(audioMicrophone)
        }) {
            HStack(spacing: ThemeSpacing.px2.rawValue + 2) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(isOn.wrappedValue ? .themeStatusSuccess : .themeTextTertiary)
                    .frame(width: 16)
                Text(title)
                    .font(.themeBody)
                    .foregroundColor(.themeTextPrimary)
                Text(subtitle)
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
                Spacer()
                // 自绘勾选框（与主题一致的极简样式）
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isOn.wrappedValue ? Color.themeStatusSuccess : Color.themeBorderSubtle, lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    if isOn.wrappedValue {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.themeStatusSuccess)
                    }
                }
            }
            .padding(.vertical, ThemeSpacing.px1.rawValue)
            .padding(.horizontal, ThemeSpacing.px1.rawValue + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
