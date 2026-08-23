import SwiftUI
import AppKit

/// 设置 → 剪贴板（PRD 8：总开关 / 记录内容 / OCR / 快捷键 / 保留 / 隐私）
struct ClipboardSettingsTab: View {
    @ObservedObject private var prefs = PreferencesManager.shared
    @ObservedObject private var store = ClipboardHistoryStore.shared
    @State private var showClearAllConfirm = false
    @State private var showDeleteDataConfirm = false
    @State private var newExcludedApp = ""
    @State private var accessibilityGranted = ClipboardPasteService.canSimulatePaste

    /// 冲突状态轮询（偏好变化 → MainApp 延迟 0.1s refresh 后更新）
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            masterSection
            if prefs.clipboardHistoryEnabled {
                captureSection
                ocrSection
            }
            shortcutSection
            retentionSection
            privacySection
        }
        .onAppear {
            store.refreshDiskUsage()
        }
        .onReceive(timer) { _ in
            accessibilityGranted = ClipboardPasteService.canSimulatePaste
            store.refreshDiskUsage() // 占用随捕获/清理动态变化
        }
    }

    // MARK: - 8.1 总开关

    private var masterSection: some View {
        section(title: "剪贴板历史", icon: .clipboardList) {
            VStack(spacing: 12) {
                ToggleRow(
                    title: "启用剪贴板历史",
                    subtitle: statusSubtitle,
                    isOn: Binding(
                        get: { prefs.clipboardHistoryEnabled },
                        set: { prefs.setClipboardHistoryEnabled($0) }
                    )
                )

                HStack(spacing: 8) {
                    Button {
                        Task { @MainActor in
                            ClipboardHistoryPanelController.shared.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            LucideView(name: .history, size: 13, color: .themeBlue400)
                            Text("打开剪贴板历史")
                        }
                        .font(.themeBody)
                    }
                    .buttonStyle(.bordered)

                    if prefs.clipboardHistoryEnabled && !prefs.isClipboardPaused {
                        Button("暂停 1 小时") {
                            prefs.setClipboardPausedUntil(Date().addingTimeInterval(3600))
                        }
                        .buttonStyle(.bordered)
                        Button("暂停到明天") {
                            var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                            comps.day! += 1; comps.hour = 0; comps.minute = 0
                            prefs.setClipboardPausedUntil(Calendar.current.date(from: comps))
                        }
                        .buttonStyle(.bordered)
                    } else if prefs.isClipboardPaused {
                        Button("恢复记录") { prefs.setClipboardPausedUntil(nil) }
                            .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }

                if !accessibilityGranted {
                    HStack(spacing: 6) {
                        LucideView(name: .alertTriangle, size: 12, color: .themeYellow500)
                        Text("缺少辅助功能权限：粘贴将降级为仅复制")
                            .font(.themeCaption)
                            .foregroundColor(.themeYellow500)
                        Button("去授权") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
        }
    }

    private var statusSubtitle: String {
        if !prefs.clipboardHistoryEnabled { return "已关闭：不记录新内容，已有历史仍可查看" }
        if !prefs.clipboardOnboarded { return "首次引导未完成，将在打开历史面板时确认" }
        if prefs.isClipboardPaused {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return "已暂停，至 \(f.string(from: prefs.clipboardPausedUntil ?? Date()))"
        }
        return "正在记录 · 当前 \(store.entries.count) 条"
    }

    // MARK: - 8.2 记录内容

    private var captureSection: some View {
        section(title: "记录内容", icon: .filter) {
            VStack(spacing: 12) {
                ToggleRow(title: "记录文本", subtitle: "普通文字、代码、命令",
                          isOn: Binding(get: { prefs.clipboardRecordText }, set: { prefs.setClipboardRecordText($0) }))
                ToggleRow(title: "记录图片", subtitle: "保存原图并生成缩略图",
                          isOn: Binding(get: { prefs.clipboardRecordImage }, set: { prefs.setClipboardRecordImage($0) }))
                ToggleRow(title: "记录链接", subtitle: "完整匹配 URL 的文本",
                          isOn: Binding(get: { prefs.clipboardRecordLink }, set: { prefs.setClipboardRecordLink($0) }))
                ToggleRow(title: "记录文件", subtitle: "文件路径或文件引用",
                          isOn: Binding(get: { prefs.clipboardRecordFile }, set: { prefs.setClipboardRecordFile($0) }))
                ToggleRow(title: "记录来源应用", subtitle: "关闭后条目不显示来自哪个 App",
                          isOn: Binding(get: { prefs.clipboardRecordSourceApp }, set: { prefs.setClipboardRecordSourceApp($0) }))
            }
        }
    }

    // MARK: - 8.3 图片 OCR

    private var ocrSection: some View {
        section(title: "图片文字识别（OCR）", icon: .scanText) {
            VStack(spacing: 12) {
                ToggleRow(title: "启用图片 OCR", subtitle: "本地 Vision 识别，不联网、不上传",
                          isOn: Binding(get: { prefs.clipboardEnableOCR }, set: { prefs.setClipboardEnableOCR($0) }))
                if prefs.clipboardEnableOCR {
                    ToggleRow(title: "中文识别（简体）", subtitle: "zh-Hans",
                              isOn: Binding(get: { prefs.clipboardOCRChinese }, set: { prefs.setClipboardOCRChinese($0) }))
                    ToggleRow(title: "英文识别", subtitle: "en-US",
                              isOn: Binding(get: { prefs.clipboardOCREnglish }, set: { prefs.setClipboardOCREnglish($0) }))
                    ToggleRow(title: "OCR 失败自动重试", subtitle: "失败后自动重试一次",
                              isOn: Binding(get: { prefs.clipboardOCRAutoRetry }, set: { prefs.setClipboardOCRAutoRetry($0) }))
                    Button {
                        clearOCRMetadata()
                    } label: {
                        HStack(spacing: 6) {
                            LucideView(name: .eraser, size: 12, color: .themeTextSecondary)
                            Text("清除全部 OCR 元数据")
                        }
                        .font(.themeBody)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - 8.4 快捷键

    private var shortcutSection: some View {
        section(title: "快捷键", icon: .keyboard) {
            VStack(spacing: 12) {
                HStack {
                    Text("打开历史面板")
                        .font(.themeBody)
                        .foregroundColor(.themeTextSecondary)
                    Spacer()
                    ShortcutRecorderView(
                        shortcut: Binding(
                            get: { prefs.clipboardOpenShortcut },
                            set: { prefs.setClipboardOpenShortcut($0) }
                        ),
                        modifiers: Binding(
                            get: { prefs.clipboardOpenShortcutFlags },
                            set: { prefs.setClipboardOpenShortcutFlags($0) }
                        )
                    )
                }

                if KeyboardShortcutManager.clipboardShortcutConflict {
                    HStack(spacing: 6) {
                        LucideView(name: .alertTriangle, size: 12, color: .themeStatusError)
                        Text("快捷键与系统或其他应用冲突，未能注册，请换一组")
                            .font(.themeCaption)
                            .foregroundColor(.themeStatusError)
                    }
                }

                HStack {
                    Text("立即采集当前剪贴板")
                        .font(.themeBody)
                        .foregroundColor(.themeTextSecondary)
                    Spacer()
                    Text("⌥⌘C（全局，固定）")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextTertiary)
                }
                Text("窗口内：↑↓ 选择 · Return 粘贴 · ⌘1–9 直接粘贴 · ⌘S 加入闪记 · ⌘P 置顶")
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
            }
        }
    }

    // MARK: - 8.5 历史保留

    private var retentionSection: some View {
        section(title: "历史保留", icon: .timer) {
            VStack(spacing: 12) {
                HStack {
                    Text("最大保存条数")
                        .font(.themeBody)
                        .foregroundColor(.themeTextSecondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { prefs.clipboardMaxEntries },
                        set: { prefs.setClipboardMaxEntries($0); store.cleanExpiredNow() }
                    )) {
                        ForEach([100, 200, 500, 1000, 2000], id: \.self) { Text("\($0) 条").tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }

                HStack {
                    Text("自动过期时间")
                        .font(.themeBody)
                        .foregroundColor(.themeTextSecondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { prefs.clipboardRetentionDays },
                        set: { prefs.setClipboardRetentionDays($0); store.cleanExpiredNow() }
                    )) {
                        Text("7 天").tag(7)
                        Text("30 天").tag(30)
                        Text("90 天").tag(90)
                        Text("1 年").tag(365)
                        Text("永不过期").tag(-1)
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                Text("置顶条目和已加入闪记的条目不会自动清理；图片原图随条目一起清理")
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)

                // 当前占用（附件图片 + 数据库），随捕获/清理动态刷新
                HStack(spacing: 6) {
                    LucideView(name: .hardDrive, size: 12, color: .themeBlue400)
                    Text("当前占用 \(ByteCountFormatter.string(fromByteCount: store.diskUsageBytes, countStyle: .file))")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextSecondary)
                    Text("（含图片附件与数据库）")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                }

                HStack(spacing: 8) {
                    Button("立即清理过期记录") { store.cleanExpiredNow() }
                        .buttonStyle(.bordered)
                    Button("打开数据目录") { openDataDirectory() }
                        .buttonStyle(.bordered)
                    Button(showClearAllConfirm ? "确认清空？" : "清空全部历史") {
                        if showClearAllConfirm {
                            store.clearAll()
                            showClearAllConfirm = false
                        } else {
                            showClearAllConfirm = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showClearAllConfirm = false }
                        }
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(showClearAllConfirm ? .themeStatusError : nil)
                    Text("当前 \(store.entries.count) 条")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                    Spacer()
                }
                Text("清空历史不会删除已加入闪记的正式记录")
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
            }
        }
    }

    // MARK: - 8.6 隐私

    private var privacySection: some View {
        section(title: "隐私", icon: .shieldCheck) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    LucideView(name: .hardDrive, size: 13, color: .themeGreen500)
                    Text("所有剪贴板内容仅保存在本机；OCR 使用系统本地 Vision，不上传任何服务器")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextSecondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("排除应用（不记录这些 App 复制的内容，密码管理器已默认排除）")
                        .font(.themeBody)
                        .foregroundColor(.themeTextSecondary)
                    ForEach(prefs.clipboardExcludedBundleIDs, id: \.self) { bundleID in
                        HStack {
                            LucideView(name: .shield, size: 12, color: .themeTextTertiary)
                            Text(bundleID)
                                .font(.themeCaption)
                                .monospaced()
                                .foregroundColor(.themeTextPrimary)
                            Spacer()
                            Button {
                                var list = prefs.clipboardExcludedBundleIDs
                                list.removeAll { $0 == bundleID }
                                prefs.setClipboardExcludedBundleIDs(list)
                            } label: {
                                LucideView(name: .x, size: 11, color: .themeTextTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.themeInput)
                        .cornerRadius(6)
                    }
                    HStack {
                        TextField("输入应用 Bundle ID，如 com.example.app", text: $newExcludedApp)
                            .textFieldStyle(.plain)
                            .font(.themeCaption)
                            .foregroundColor(.themeTextPrimary)
                            .onSubmit(addExcludedApp)
                        Button("添加", action: addExcludedApp)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.themeInput)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.themeBorderSubtle))
                }

                Button(showDeleteDataConfirm ? "再次点击确认删除" : "删除所有剪贴板数据") {
                    if showDeleteDataConfirm {
                        store.clearAll()
                        showDeleteDataConfirm = false
                    } else {
                        showDeleteDataConfirm = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showDeleteDataConfirm = false }
                    }
                }
                .buttonStyle(.bordered)
                .foregroundColor(showDeleteDataConfirm ? .themeStatusError : nil)
            }
        }
    }

    // MARK: - 操作

    private func addExcludedApp() {
        let trimmed = newExcludedApp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = prefs.clipboardExcludedBundleIDs
        guard !list.contains(trimmed) else { return }
        list.append(trimmed)
        prefs.setClipboardExcludedBundleIDs(list)
        newExcludedApp = ""
    }

    /// 清除 OCR 元数据：所有图片条目 OCR 文本/状态重置为关闭（原图保留）
    private func clearOCRMetadata() {
        for entry in store.entries where entry.type == .image {
            ClipboardHistoryStore.shared.updateOCR(id: entry.id, text: nil, status: .disabled)
        }
    }

    private func openDataDirectory() {
        let dir = FileCoordinator.shared.getDirectoryURL(for: .clipboard)
        NSWorkspace.shared.open(dir.deletingLastPathComponent()) // Attachments 根目录
    }

    // MARK: - 分区容器

    private func section<Content: View>(title: String, icon: IconName, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                LucideView(name: icon, size: 16, color: .themeBlue400)
                Text(title)
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
            }
            content()
        }
        .padding(16)
        .background(Color.themeCard)
        .cornerRadius(12)
    }
}
