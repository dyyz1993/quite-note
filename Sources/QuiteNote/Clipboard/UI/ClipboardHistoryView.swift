import SwiftUI
import AppKit

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

/// 剪贴板历史主面板（PRD 7：搜索 + 筛选 + 列表 + 快捷键提示）
///
/// 崩溃红线遵守：本窗口由 NSHostingView 承载且内容较重——内容切换一律瞬时
/// （不用 withAnimation/transition），不持窗口 frame 做逐帧动画。
struct ClipboardHistoryView: View {
    let controller: ClipboardHistoryPanelController
    @ObservedObject private var store = ClipboardHistoryStore.shared
    @ObservedObject private var prefs = PreferencesManager.shared

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var filter: ClipboardFilter = .all
    @State private var selectedIndex = 0
    @State private var hint: String?
    @FocusState private var searchFocused: Bool

    init(controller: ClipboardHistoryPanelController) {
        self.controller = controller
    }

    /// 当前可见条目：类型筛选 → 防抖搜索（PRD 9.2）
    private var visibleEntries: [ClipboardEntry] {
        var list = store.entries.filter { filter.matches($0) }
        list = ClipboardSearchService.search(debouncedQuery, in: list)
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            filterBar
            divider
            if prefs.clipboardOnboarded {
                contentArea
                footerBar
            } else {
                ClipboardOnboardingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.themeBackground)
        .overlay(alignment: .top) {
            if let hint {
                ClipboardHintBanner(text: hint)
            }
        }
        .onAppear {
            searchFocused = true
            controller.onKeyAction = { [self] action in handleKey(action) }
        }
        .onDisappear {
            controller.onKeyAction = nil
        }
        .onChange(of: searchText) { newValue in
            scheduleSearchDebounce(newValue)
        }
    }

    // MARK: - 顶部（PRD 7.1：标题 / 搜索 / 记录状态 / 设置 / 关闭）

    private var headerView: some View {
        HStack(spacing: 12) {
            LucideView(name: .clipboardList, size: 18, color: .themeBlue400)
            Text("剪贴板历史")
                .font(.themeH2)
                .foregroundColor(.themeTextPrimary)

            searchField
                .frame(maxWidth: .infinity)

            recordingStatusBadge

            circleButton(icon: .settings, help: "剪贴板设置") {
                QuiteNoteNotification.post(.showSettings, object: nil, userInfo: ["tab": "clipboard"])
            }
            circleButton(icon: .x, help: "关闭 (Esc)") {
                controller.hide()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            LucideView(name: .search, size: 13, color: .themeTextTertiary)
            TextField("搜索文本、链接、图片文字、来源应用…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.themeBody)
                .foregroundColor(.themeTextPrimary)
                .focused($searchFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    LucideView(name: .circleX, size: 12, color: .themeTextTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.themeInput)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeBorderSubtle))
    }

    /// 记录状态：正在记录 / 已暂停 / 未启用（PRD 7.1）
    private var recordingStatusBadge: some View {
        Group {
            if !prefs.clipboardHistoryEnabled {
                statusPill(text: "未启用", color: .themeTextTertiary, icon: .circleX)
            } else if prefs.isClipboardPaused {
                Button {
                    prefs.setClipboardPausedUntil(nil)
                    showHint("已恢复记录")
                } label: {
                    HStack(spacing: 4) {
                        LucideView(name: .play, size: 11, color: .themeYellow500)
                        Text("已暂停，点击恢复")
                            .font(.themeCaption)
                            .foregroundColor(.themeYellow500)
                    }
                }
                .buttonStyle(.plain)
            } else {
                statusPill(text: "正在记录", color: .themeStatusSuccess, icon: .circle)
            }
        }
    }

    private func statusPill(text: String, color: Color, icon: IconName) -> some View {
        HStack(spacing: 4) {
            LucideView(name: icon, size: 10, color: color)
            Text(text)
                .font(.themeCaption)
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }

    private func circleButton(icon: IconName, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideView(name: icon, size: 14, color: .themeTextSecondary)
                .frame(width: 28, height: 28)
                .background(Color.themeHoverLight)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(help)
    }

    // MARK: - 筛选栏

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(ClipboardFilter.allCases, id: \.self) { item in
                let isSelected = filter == item
                Button {
                    filter = item
                    selectedIndex = 0
                } label: {
                    HStack(spacing: 4) {
                        LucideView(name: item.icon, size: 11, color: isSelected ? .white : .themeTextSecondary)
                        Text(item.label)
                            .font(.themeCaption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundColor(isSelected ? .white : .themeTextSecondary)
                    .background(isSelected ? Color.themeSelected : Color.themeHoverLight)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.clear : Color.themeBorderSubtle))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("\(visibleEntries.count) 条")
                .font(.themeCaptionSmall)
                .foregroundColor(.themeTextTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.themeGray900.opacity(0.5))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.themeBorder)
            .frame(height: 1)
    }

    // MARK: - 内容区

    private var contentArea: some View {
        VStack(spacing: 0) {
            if visibleEntries.isEmpty {
                emptyStateView
            } else {
                entryList
                // 选中图片时的更大预览（PRD 7.4），OCR 失败可在此重试
                if selectedEntry?.type == .image {
                    ClipboardImagePreviewStrip(entry: selectedEntry!) {
                        if let id = selectedEntry?.id {
                            ClipboardOCRQueue.shared.retry(entryID: id)
                            showHint("OCR 重试中…")
                        }
                    }
                    .background(Color.themeGray900.opacity(0.5))
                    .overlay(alignment: .top) { divider }
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
                            isSelected: index == selectedIndex
                        ) {
                            selectedIndex = index
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
                        .onTapGesture { selectedIndex = index }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onChange(of: selectedIndex) { newValue in
                guard visibleEntries.indices.contains(newValue) else { return }
                proxy.scrollTo(visibleEntries[newValue].id, anchor: .center)
            }
        }
    }

    /// 空态区分：无历史 / 搜索无结果 / 暂停（PRD 7.5）
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            if !debouncedQuery.isEmpty {
                LucideView(name: .search, size: 36, color: .themeTextTertiary)
                Text("没有匹配「\(debouncedQuery)」的结果")
                    .font(.themeBody)
                    .foregroundColor(.themeTextSecondary)
            } else if prefs.clipboardHistoryEnabled && prefs.isClipboardPaused {
                LucideView(name: .pause, size: 36, color: .themeYellow500)
                Text("剪贴板记录已暂停")
                    .font(.themeBody)
                    .foregroundColor(.themeTextSecondary)
                Button("恢复记录") { prefs.setClipboardPausedUntil(nil) }
                    .buttonStyle(.borderedProminent)
            } else if !ClipboardPasteService.canSimulatePaste {
                LucideView(name: .keyboard, size: 36, color: .themeTextTertiary)
                Text("没有历史记录")
                    .font(.themeBody)
                    .foregroundColor(.themeTextSecondary)
                ClipboardPermissionHint()
            } else {
                LucideView(name: .clipboard, size: 36, color: .themeTextTertiary)
                Text("没有历史记录")
                    .font(.themeBody)
                    .foregroundColor(.themeTextSecondary)
                Text("复制的内容会自动出现在这里")
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 底部快捷键提示（PRD 7.3）

    private var footerBar: some View {
        HStack(spacing: 16) {
            Text("↑↓ 选择")
            Text("Return 粘贴")
            Text("⌘1–9 直接粘贴")
            Text("⌘S 加入闪记")
            Text("⌘P 置顶")
            Text("Esc 关闭")
            Spacer()
            if !ClipboardPasteService.canSimulatePaste {
                Text("缺少辅助功能权限：粘贴将降级为复制")
                    .foregroundColor(.themeYellow500)
            }
        }
        .font(.themeCaptionSmall)
        .foregroundColor(.themeTextTertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.themeGray900.opacity(0.6))
    }

    // MARK: - 行为

    private var selectedEntry: ClipboardEntry? {
        visibleEntries.indices.contains(selectedIndex) ? visibleEntries[selectedIndex] : nil
    }

    private func scheduleSearchDebounce(_ newValue: String) {
        // PRD 9.2：150–300ms 防抖（model 里没法存 workItem，用静态 holder）
        ClipboardSearchDebounce.schedule(newValue) { query in
            debouncedQuery = query
            selectedIndex = 0
        }
    }

    private func handleKey(_ action: ClipboardPanelKeyAction) {
        switch action {
        case .moveUp:
            if selectedIndex > 0 { selectedIndex -= 1 }
        case .moveDown:
            if selectedIndex < visibleEntries.count - 1 { selectedIndex += 1 }
        case .pasteSelected:
            if let entry = selectedEntry { paste(entry) }
        case .pasteIndex(let n):
            // ⌘1–9 作用于当前可见列表
            if visibleEntries.indices.contains(n - 1) {
                paste(visibleEntries[n - 1])
            }
        case .saveToFlash:
            if let entry = selectedEntry { saveToFlash(entry) }
        case .togglePin:
            if let entry = selectedEntry { store.togglePin(id: entry.id) }
        case .deleteSelected:
            deleteAt(selectedIndex)
        case .focusSearch:
            searchFocused = true
        }
    }

    private func paste(_ entry: ClipboardEntry) {
        ClipboardPasteService.shared.paste(entry) {
            controller.hide()
        } completion: { [self] outcome in
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
        if selectedIndex >= visibleEntries.count - 1 {
            selectedIndex = max(0, visibleEntries.count - 2)
        }
        showHint("已删除")
    }

    private func showHint(_ text: String) {
        hint = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [self] in
            if hint == text { hint = nil }
        }
    }
}

/// 搜索防抖（150–300ms，PRD 9.2）：独立 holder 规避 struct View 无法持有 mutable workItem
@MainActor
enum ClipboardSearchDebounce {
    private static var workItem: DispatchWorkItem?
    private static let interval: TimeInterval = 0.2

    static func schedule(_ query: String, fire: @escaping (String) -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            fire(trimmed)
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
    }
}

/// 顶部轻提示横幅（降级提示等）
struct ClipboardHintBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            LucideView(name: .alertTriangle, size: 12, color: .themeYellow500)
            Text(text)
                .font(.themeCaption)
                .foregroundColor(.themeTextPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.themeGray800)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeBorder))
        .shadow(color: Color.themeShadowMedium, radius: 8, y: 4)
        .padding(.top, 52)
        .transition(.opacity) // 纯渲染层透明度，不触发布局约束（窗口内容切换仍瞬时）
    }
}

/// 无辅助功能权限提示（PRD 7.5 / 15）
struct ClipboardPermissionHint: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("未检测到辅助功能权限")
                .font(.themeCaption)
                .foregroundColor(.themeYellow500)
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
        VStack(spacing: 20) {
            LucideView(name: .clipboardList, size: 44, color: .themeBlue400)
            Text("开启剪贴板历史")
                .font(.themeH1)
                .foregroundColor(.themeTextPrimary)
            Text("复制过的文本、链接、图片和文件会自动保存在这里，\n随时用 \(shortcutLabel) 找回和快速粘贴。")
                .font(.themeBody)
                .foregroundColor(.themeTextSecondary)
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
            .background(Color.themeCard)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.themeBorderSubtle))

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

            Text("已启用本功能的老用户升级后也会看到此说明；可随时在 设置 → 剪贴板 中调整或关闭")
                .font(.themeCaptionSmall)
                .foregroundColor(.themeTextTertiary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func privacyRow(icon: IconName, text: String) -> some View {
        HStack(spacing: 8) {
            LucideView(name: icon, size: 13, color: .themeBlue400)
            Text(text)
                .font(.themeCaption)
                .foregroundColor(.themeTextSecondary)
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
