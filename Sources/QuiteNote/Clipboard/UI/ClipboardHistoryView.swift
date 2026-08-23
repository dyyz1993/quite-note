import SwiftUI
import AppKit
import Combine

/// 剪贴板历史筛选（PRD 7.1 筛选栏）
enum ClipboardFilter: String, CaseIterable {
    case all, text, image, link, file, pinned, saved

    var label: String {
        switch self {
        case .all: return "全部"
        case .text: return "文本"
        case .image: return "图片"
        case .link: return "链接"
        case .file: return "文件"
        case .pinned: return "置顶"
        case .saved: return "已加入闪记"
        }
    }

    var icon: IconName {
        switch self {
        case .all: return .list
        case .text: return .type
        case .image: return .image
        case .link: return .link
        case .file: return .fileText
        case .pinned: return .pin
        case .saved: return .check
        }
    }

    func matches(_ entry: ClipboardEntry) -> Bool {
        switch self {
        case .all: return true
        case .text: return entry.type == .text
        case .image: return entry.type == .image
        case .link: return entry.type == .link
        case .file: return entry.type == .file
        case .pinned: return entry.isPinned
        case .saved: return entry.savedRecordID != nil
        }
    }
}

/// 剪贴板历史主面板（视觉按用户指定的 Alfred「All Snippets」参考样式复刻：
/// 浅色 + 紫色标题栏 + 白色卡片行 + 底部过滤输入行）
///
/// 崩溃红线遵守：本窗口由 NSHostingView 承载且内容较重——内容切换一律瞬时
/// （不用 withAnimation/transition），不持窗口 frame 做逐帧动画。
/// 输入状态由 ClipboardHistoryViewModel（class）承载，规避 struct 捕获副本写 @State 不可靠的问题。
struct ClipboardHistoryView: View {
    let controller: ClipboardHistoryPanelController
    @ObservedObject private var store = ClipboardHistoryStore.shared
    @ObservedObject private var prefs = PreferencesManager.shared
    @StateObject private var vm = ClipboardHistoryViewModel()

    @State private var hint: String?
    @FocusState private var searchFocused: Bool

    /// 当前可见条目：类型筛选 → 防抖搜索（PRD 9.2）
    private var visibleEntries: [ClipboardEntry] {
        let filtered = store.entries.filter { vm.filter.matches($0) }
        return ClipboardSearchService.search(vm.debouncedQuery, in: filtered)
    }

    init(controller: ClipboardHistoryPanelController) {
        self.controller = controller
    }

    var body: some View {
        VStack(spacing: 0) {
            if prefs.clipboardOnboarded {
                bigSearchField   // 大搜索框（唤起即聚焦，尾部内联设置图标）
                filterBar        // 轻量筛选胶囊（←→ 切换）
                contentArea      // 白卡列表
                shortcutFooter   // 底部快捷键提示 + 记录状态/保留策略
            } else {
                ClipboardOnboardingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ClipboardPalette.background)
            }
        }
        .background(ClipboardPalette.background)
        .overlay(alignment: .top) {
            if let hint {
                ClipboardHintBanner(text: hint)
            }
        }
        .onAppear {
            searchFocused = true
            controller.onKeyAction = { action in
                switch action {
                case .saveToFlash:
                    if let entry = selectedEntry { saveToFlash(entry) }
                case .focusSearch:
                    searchFocused = true
                case .escape:
                    // Alfred 式：有搜索词先清空，再按才关闭（快速退出）
                    if !vm.searchText.isEmpty || vm.filter != .all {
                        vm.resetInput()
                    } else {
                        controller.hide()
                    }
                default:
                    vm.handle(action, entries: visibleEntries) { paste($0) }
                }
            }
        }
        .onDisappear {
            controller.onKeyAction = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: QuiteNoteNotification.clipboardPanelDidShow.name)) { _ in
            // 每次面板唤起：清空搜索 + 聚焦（Alfred 式体验，PRD 7.1）
            vm.resetInput()
            searchFocused = true
        }
    }

    // MARK: - 大搜索框（顶部、醒目、唤起即聚焦；尾部内联设置图标——用户要求顶部极简）

    private var bigSearchField: some View {
        HStack(spacing: 10) {
            LucideView(name: .search, size: 17, color: ClipboardPalette.textTertiary)
            TextField("输入以搜索剪贴板内容…", text: $vm.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundColor(ClipboardPalette.textPrimary)
                .focused($searchFocused)
            if !vm.searchText.isEmpty {
                Button {
                    vm.searchText = ""
                } label: {
                    LucideView(name: .circleX, size: 14, color: ClipboardPalette.textTertiary)
                }
                .buttonStyle(.plain)
            }
            // 唯一的设置入口：内联小图标（替代整条标题栏，面板极简）
            Button {
                QuiteNoteNotification.post(.showSettings, object: nil, userInfo: ["tab": "clipboard"])
            } label: {
                LucideView(name: .settings, size: 14, color: ClipboardPalette.textTertiary)
                    .frame(width: 24, height: 24)
                    .background(ClipboardPalette.background)
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("剪贴板设置")
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(Color.white)
        .cornerRadius(9)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(searchFocused ? ClipboardPalette.accent : ClipboardPalette.inputBorder, lineWidth: searchFocused ? 1.5 : 1))
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(ClipboardPalette.background)
    }

    // MARK: - 筛选栏（浅色小胶囊，浅紫选中，←→ 键循环切换）

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(ClipboardFilter.allCases, id: \.self) { item in
                let isSelected = vm.filter == item
                Button {
                    vm.filter = item
                } label: {
                    HStack(spacing: 4) {
                        LucideView(name: item.icon, size: 11, color: isSelected ? ClipboardPalette.accent : ClipboardPalette.textTertiary)
                        Text(item.label)
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .foregroundColor(isSelected ? ClipboardPalette.accent : ClipboardPalette.textSecondary)
                    .background(isSelected ? ClipboardPalette.rowSelected : Color.white)
                    .cornerRadius(11)
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(isSelected ? ClipboardPalette.accent.opacity(0.35) : ClipboardPalette.inputBorder))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("\(visibleEntries.count) 条")
                .font(.system(size: 11))
                .foregroundColor(ClipboardPalette.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(ClipboardPalette.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ClipboardPalette.inputBorder).frame(height: 1)
        }
    }

    // MARK: - 内容区

    private var contentArea: some View {
        Group {
            if visibleEntries.isEmpty {
                emptyStateView
            } else {
                // 双栏布局（参考图）：左列表 + 右选中条目详情
                HStack(spacing: 0) {
                    entryList
                        .frame(width: 300)
                    Rectangle()
                        .fill(ClipboardPalette.inputBorder)
                        .frame(width: 1)
                    ClipboardDetailPane(entry: selectedEntry) {
                        if let id = selectedEntry?.id {
                            ClipboardOCRQueue.shared.retry(entryID: id)
                            showHint("OCR 重试中…")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var entryList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                        ClipboardEntryRow(
                            entry: entry,
                            index: index,
                            isSelected: index == vm.selectedIndex
                        ) {
                            vm.selectedIndex = index
                        } onPaste: {
                            paste(entry)
                        } onCopy: {
                            ClipboardPasteService.shared.copy(entry)
                            showHint("已复制到剪贴板")
                        } onPin: {
                            store.togglePin(id: entry.id)
                        } onSaveToFlash: {
                            saveToFlash(entry)
                        } onDelete: {
                            deleteAt(index)
                        }
                        .id(entry.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { paste(entry) }
                        .onTapGesture {
                            // 单击 = 选中并复制（用户约定：点击默认复制，回车/双击才粘贴）
                            vm.selectedIndex = index
                            ClipboardPasteService.shared.copy(entry)
                            showHint("已复制到剪贴板")
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .coordinateSpace(name: "clipScroll")
            .onChange(of: vm.selectedIndex, perform: { newValue in
                // anchor: nil = 最小滚动量让选中行可见：已可见则不动，移出视口则滚回。
                // （自定义 GeometryReader 跟踪方案已废弃：滚动不触发行内 onChange，数据必过期）
                guard visibleEntries.indices.contains(newValue) else { return }
                proxy.scrollTo(visibleEntries[newValue].id, anchor: nil)
            })
            // ↑↓ 的 SwiftUI 层兜底：焦点在搜索框且输入法/field editor 吞掉方向键时，
            // moveCommand 仍会冒泡到这里（NSEvent monitor 与此双路径，不重复触发）
            .onMoveCommand { direction in
                switch direction {
                case .up:
                    vm.handle(.moveUp, entries: visibleEntries) { paste($0) }
                case .down:
                    vm.handle(.moveDown, entries: visibleEntries) { paste($0) }
                default:
                    break
                }
            }
        }
    }

    /// 空态区分：无历史 / 搜索无结果 / 暂停（PRD 7.5）
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            if !vm.debouncedQuery.isEmpty {
                LucideView(name: .search, size: 34, color: ClipboardPalette.textTertiary)
                Text("没有匹配「\(vm.debouncedQuery)」的结果")
                    .font(.system(size: 13))
                    .foregroundColor(ClipboardPalette.textSecondary)
            } else if prefs.clipboardHistoryEnabled && prefs.isClipboardPaused {
                LucideView(name: .pause, size: 34, color: ClipboardPalette.statusPaused)
                Text("剪贴板记录已暂停")
                    .font(.system(size: 13))
                    .foregroundColor(ClipboardPalette.textSecondary)
                Button("恢复记录") { prefs.setClipboardPausedUntil(nil) }
                    .buttonStyle(.borderedProminent)
            } else if !ClipboardPasteService.canSimulatePaste {
                LucideView(name: .keyboard, size: 34, color: ClipboardPalette.textTertiary)
                Text("没有历史记录")
                    .font(.system(size: 13))
                    .foregroundColor(ClipboardPalette.textSecondary)
                ClipboardPermissionHint()
            } else {
                LucideView(name: .clipboard, size: 34, color: ClipboardPalette.textTertiary)
                Text("没有历史记录")
                    .font(.system(size: 13))
                    .foregroundColor(ClipboardPalette.textSecondary)
                Text("复制的内容会自动出现在这里")
                    .font(.system(size: 11))
                    .foregroundColor(ClipboardPalette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 底部快捷键提示（←→ 切类型 · ↑↓ 选条 · ↩ 粘贴）

    private var shortcutFooter: some View {
        HStack(spacing: 14) {
            Text("←→ 切换类型")
            Text("↑↓ 选择")
            Text("↩ 粘贴")
            Text("⌘1–9 直贴")
            Text("⌘S 闪记")
            Text("⌘P 置顶")
            Text("Esc 关闭")
            Spacer()
            if !ClipboardPasteService.canSimulatePaste {
                Text("缺辅助功能权限：粘贴降级为复制")
                    .foregroundColor(ClipboardPalette.statusPaused)
            } else if prefs.isClipboardPaused {
                Button("已暂停 · 点击恢复") {
                    prefs.setClipboardPausedUntil(nil)
                    showHint("已恢复记录")
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(ClipboardPalette.statusPaused)
            } else if !prefs.clipboardHistoryEnabled {
                Text("记录未启用")
                    .foregroundColor(ClipboardPalette.statusPaused)
            } else {
                // 保留策略透明化：让用户知道历史会自动清理、留多久
                Text("已记录 \(store.entries.count) 条 · 自动保留\(retentionLabel)")
                    .foregroundColor(ClipboardPalette.textTertiary)
            }
        }
        .font(.system(size: 11))
        .foregroundColor(ClipboardPalette.textTertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.white)
        .overlay(alignment: .top) {
            Rectangle().fill(ClipboardPalette.inputBorder).frame(height: 1)
        }
    }

    // MARK: - 行为

    private var selectedEntry: ClipboardEntry? {
        visibleEntries.indices.contains(vm.selectedIndex) ? visibleEntries[vm.selectedIndex] : nil
    }

    /// 保留策略文案（footer 右侧）：30 天 / 500 条 / 永不过期
    private var retentionLabel: String {
        let prefs = PreferencesManager.shared
        let days = prefs.clipboardRetentionDays > 0 ? "\(prefs.clipboardRetentionDays) 天" : "永久"
        return " \(days)·上限 \(prefs.clipboardMaxEntries) 条"
    }

    private func paste(_ entry: ClipboardEntry) {
        ClipboardPasteService.shared.paste(entry) {
            controller.hide()
        } completion: { outcome in
            switch outcome {
            case .pasted:
                store.markPasted(id: entry.id)
            case .copiedOnly:
                showHint("无辅助功能权限：内容已复制，请手动 ⌘V")
            case .noTarget:
                showHint("已复制到剪贴板（原应用已退出）")
            }
        }
    }

    /// 加入闪记 / 打开对应闪记（PRD 11：已加闪记再点 = 打开；正式记录删除由闪记界面处理）
    private func saveToFlash(_ entry: ClipboardEntry) {
        if let recordID = entry.savedRecordID {
            controller.onOpenFlashNote?(recordID)
            return
        }
        if ClipboardFlashNoteService.shared.save(entry) != nil {
            showHint("已加入闪记")
        } else {
            showHint("加入闪记失败")
        }
    }

    private func deleteAt(_ index: Int) {
        guard visibleEntries.indices.contains(index) else { return }
        let entry = visibleEntries[index]
        store.delete(id: entry.id)
        if vm.selectedIndex >= visibleEntries.count - 1 {
            vm.selectedIndex = max(0, visibleEntries.count - 2)
        }
        showHint("已删除")
    }

    private func showHint(_ text: String) {
        hint = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if hint == text { hint = nil }
        }
    }
}

// MARK: - ViewModel 行为扩展

extension ClipboardHistoryViewModel {
    /// 窗口按键动作（PRD 6）：纯状态部分（saveToFlash/focusSearch 由视图层处理）
    func handle(
        _ action: ClipboardPanelKeyAction,
        entries: [ClipboardEntry],
        paste: (ClipboardEntry) -> Void
    ) {
        switch action {
        case .moveUp:
            if selectedIndex > 0 { selectedIndex -= 1 }
        case .moveDown:
            if selectedIndex < entries.count - 1 { selectedIndex += 1 }
        case .switchFilterLeft:
            switchFilter(false)
        case .switchFilterRight:
            switchFilter(true)
        case .pasteSelected:
            if entries.indices.contains(selectedIndex) { paste(entries[selectedIndex]) }
        case .pasteIndex(let n):
            if entries.indices.contains(n - 1) { paste(entries[n - 1]) }
        case .togglePin:
            if entries.indices.contains(selectedIndex) {
                ClipboardHistoryStore.shared.togglePin(id: entries[selectedIndex].id)
            }
        case .deleteSelected:
            if entries.indices.contains(selectedIndex) {
                let entry = entries[selectedIndex]
                ClipboardHistoryStore.shared.delete(id: entry.id)
                if selectedIndex >= entries.count - 1 { selectedIndex = max(0, entries.count - 2) }
            }
        case .saveToFlash, .focusSearch, .escape:
            break // 视图层处理
        }
    }
}

/// 顶部轻提示横幅（降级提示等）
struct ClipboardHintBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            LucideView(name: .alertTriangle, size: 12, color: ClipboardPalette.statusPaused)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(ClipboardPalette.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.white)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ClipboardPalette.inputBorder))
        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 4)
        .padding(.top, 56)
    }
}

/// 无辅助功能权限提示（PRD 7.5 / 15）
struct ClipboardPermissionHint: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("未检测到辅助功能权限")
                .font(.system(size: 12))
                .foregroundColor(ClipboardPalette.statusPaused)
            Button("打开系统设置授权") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

/// 首次启动引导（PRD 4.1：介绍 + 隐私说明 + 默认勾选，确认后开始捕获）
struct ClipboardOnboardingView: View {
    @ObservedObject private var prefs = PreferencesManager.shared

    var body: some View {
        VStack(spacing: 18) {
            LucideView(name: .clipboardList, size: 40, color: ClipboardPalette.accent)
            Text("开启剪贴板历史")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(ClipboardPalette.textPrimary)
            Text("复制过的文本、链接、图片和文件会自动保存在这里，\n随时用 \(shortcutLabel) 找回和快速粘贴。")
                .font(.system(size: 13))
                .foregroundColor(ClipboardPalette.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // 隐私说明（PRD 15）
            VStack(alignment: .leading, spacing: 8) {
                privacyRow(icon: .hardDrive, text: "全部内容仅保存在本机，不上传任何服务器")
                privacyRow(icon: .scanText, text: "图片文字识别（OCR）使用系统本地 Vision，可关闭")
                privacyRow(icon: .shield, text: "密码管理器等敏感应用默认不记录，可在设置中管理")
                privacyRow(icon: .timer, text: "历史默认保留 30 天 / 500 条，置顶条目不清理")
            }
            .padding(14)
            .background(Color.white)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ClipboardPalette.inputBorder))

            HStack(spacing: 12) {
                Button("暂不启用") {
                    prefs.setClipboardOnboarded(true)
                    prefs.setClipboardHistoryEnabled(false)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    prefs.setClipboardOnboarded(true)
                    prefs.setClipboardHistoryEnabled(true)
                    ClipboardMonitor.shared.syncWithPreferences()
                } label: {
                    HStack(spacing: 6) {
                        LucideView(name: .check, size: 14, color: .white)
                        Text("开始记录")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Text("可随时在 设置 → 剪贴板 中调整或关闭")
                .font(.system(size: 11))
                .foregroundColor(ClipboardPalette.textTertiary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func privacyRow(icon: IconName, text: String) -> some View {
        HStack(spacing: 8) {
            LucideView(name: icon, size: 13, color: ClipboardPalette.accent)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(ClipboardPalette.textSecondary)
        }
    }

    private var shortcutLabel: String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(PreferencesManager.shared.clipboardOpenShortcutFlags))
        var label = ""
        if flags.contains(.control) { label += "⌃" }
        if flags.contains(.option) { label += "⌥" }
        if flags.contains(.shift) { label += "⇧" }
        if flags.contains(.command) { label += "⌘" }
        return label + PreferencesManager.shared.clipboardOpenShortcut.uppercased()
    }
}
