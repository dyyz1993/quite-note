import SwiftUI

/// 记录设置标签页视图
struct HistorySettingsTab: View {
    @ObservedObject var store: RecordStore

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 自动去重开关
            dedupSection

            // 记录统计
            recordsInfoSection

            // 数据管理
            dataManagementSection
        }
    }

    // MARK: - Auto Dedup Section

    private var dedupSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("自动去重")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.themeTextPrimary)
                Text("10分钟内重复内容仅更新时间戳")
                    .font(.system(size: 10))
                    .foregroundColor(.themeGray500)
            }
            Spacer()
            CustomToggle(isOn: Binding(
                get: { store.dedupEnabled },
                set: { store.dedupEnabled = $0; store.savePreferences() }
            ))
        }
        .padding(16)
        .background(Color.themeHoverLight)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeHoverLight).allowsHitTesting(false))
    }

    // MARK: - Records Info Section

    private var recordsInfoSection: some View {
        HStack(spacing: 16) {
            LucideView(name: .database, size: 32, color: .themeBlue400)
                .frame(width: 56, height: 56)
                .background(Color.themeActive)
                .cornerRadius(28)

            VStack(alignment: .leading, spacing: 4) {
                Text("记录统计")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
                Text("共 \(store.records.count) 条记录")
                    .font(.themeBody)
                    .foregroundColor(.themeTextSecondary)
            }

            Spacer()
        }
        .padding(20)
        .background(Color.themeGray800.opacity(0.4) as Color)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeHoverLight as Color))
    }

    // MARK: - Data Management Section

    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                LucideView(name: .slidersHorizontal, size: 16, color: .themeBlue400)
                Text("数据管理")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
            }

            // 导入按钮
            Button(action: {
                importRecordsWithOpenPanel()
            }) {
                HStack {
                    LucideView(name: .upload, size: 12, color: .themeGray400)
                    Text("导入记录 (Markdown)")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.themeGray400)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeHoverMedium, lineWidth: 1).allowsHitTesting(false))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            // 导出按钮
            Button(action: {
                exportRecordsWithSavePanel()
            }) {
                HStack {
                    LucideView(name: .fileText, size: 12, color: .themeGray400)
                    Text("导出所有记录 (Markdown/TXT)")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.themeGray400)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeHoverMedium, lineWidth: 1).allowsHitTesting(false))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            // 清空按钮（带确认）
            Button(action: {
                store.confirm(
                    title: "确认清空",
                    message: "确定要清空所有记录吗？此操作不可撤销。",
                    confirmTitle: "清空",
                    isDestructive: true
                ) {
                    clearAllRecords()
                }
            }) {
                HStack {
                    LucideView(name: .trash2, size: 12, color: .themeRed500)
                    Text("清空所有记录")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.themeRed500)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.themeRed500.opacity(0.2))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeRed500.opacity(0.3), lineWidth: 1).allowsHitTesting(false))
                .shadow(color: Color.themeRed500.opacity(0.1), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
    }

    // MARK: - Methods

    /// 选择附件存储目录
    private func selectAttachmentsFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.title = "选择附件存储目录"
        openPanel.prompt = "选择"
        openPanel.level = .modalPanel
        
        // 默认定位到当前存储位置
        openPanel.directoryURL = store.currentAttachmentsDirectory

        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                DispatchQueue.main.async {
                    store.attachmentsPath = url.path
                    store.savePreferences()
                }
            }
        }
    }

    /// 使用 NSOpenPanel 导入记录（让用户选择文件）
    private func importRecordsWithOpenPanel() {
        let openPanel = NSOpenPanel()
        // 使用允许的文件类型，支持 .md 和 .txt
        openPanel.allowedContentTypes = [.text, .plainText]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.title = "选择要导入的记录文件"
        openPanel.prompt = "导入"
        // 设置为模态窗口，层级最高
        openPanel.level = .modalPanel
        
        // 尝试定位到当前附件目录，方便导入备份的文件
        openPanel.directoryURL = store.currentAttachmentsDirectory

        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                do {
                    let markdownContent = try String(contentsOf: url, encoding: .utf8)
                    let count = self.store.importFromMarkdown(markdownContent)
                    DispatchQueue.main.async {
                        let message = count > 0 ? "成功导入 \(count) 条记录" : "未找到可导入的记录，请检查文件格式"
                        self.store.confirm(
                            title: "导入结果",
                            message: message,
                            confirmTitle: "确定",
                            cancelTitle: nil
                        )
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.store.confirm(
                            title: "导入失败",
                            message: error.localizedDescription,
                            confirmTitle: "确定",
                            cancelTitle: nil
                        )
                    }
                }
            }
        }
    }

    /// 使用 NSSavePanel 导出记录（让用户选择保存位置）
    private func exportRecordsWithSavePanel() {
        let markdownContent = store.exportMarkdown()

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        savePanel.nameFieldStringValue = "QuiteNote_导出_\(formatter.string(from: Date())).md"
        // 设置为模态窗口，层级最高
        savePanel.level = .modalPanel

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try markdownContent.write(to: url, atomically: true, encoding: .utf8)
                    DispatchQueue.main.async {
                        self.store.postToast("导出成功！文件已保存至: \(url.path)", type: "success")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.store.postToast("导出失败: \(error.localizedDescription)", type: "error")
                    }
                }
            }
        }
    }

    /// 清空所有记录
    private func clearAllRecords() {
        store.clearAll()
        store.postToast("已清空所有记录", type: "success")
    }
}
