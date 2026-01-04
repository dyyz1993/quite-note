import SwiftUI

/// 文件与存储设置标签页
struct FileSettingsTab: View {
    @ObservedObject var store: RecordStore
    @State private var stats: StorageStats = .empty
    @State private var preferredEditor: String = "System Default"
    @State private var showResetConfirm = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            statsSection
            pathSection
            editorSection
            dangerSection
        }
        .onAppear {
            preferredEditor = PreferencesManager.shared.preferredEditor
            refreshStats()
        }
    }

    // MARK: - Subviews

    private var pathSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                LucideView(name: .folder, size: 16, color: .themeBlue400)
                Text("附件存储位置")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: copyPathToClipboard) {
                        HStack(spacing: 4) {
                            LucideView(name: .copy, size: 14, color: .themeTextSecondary)
                            Text("复制路径")
                                .font(.themeCaption)
                                .foregroundColor(.themeTextSecondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.themeHoverLight)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    
                    Button(action: selectAttachmentsFolder) {
                        Text("更改目录")
                            .font(.themeCaption)
                            .fontWeight(.medium)
                            .foregroundColor(.themeBlue400)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.themeBlue500.opacity(0.15))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.currentAttachmentsDirectory.path)
                        .font(.themeCaption)
                        .foregroundColor(.themeTextSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Text("从 VS Code 等应用拖入的文件将备份到此目录。")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.themeInput.opacity(0.8))
                .cornerRadius(8)
            }
        }
        .padding(20)
        .background(Color.themeGray800.opacity(0.4))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeHoverLight))
    }

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                LucideView(name: .link, size: 16, color: .themePurple400)
                Text("外部编辑器")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
                
                Spacer()
                
                Button(action: selectCustomApp) {
                    HStack(spacing: 4) {
                        LucideView(name: .plus, size: 12, color: .themeTextSecondary)
                        Text("自定义...")
                    }
                    .font(.themeCaption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.themeHoverLight)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $preferredEditor) {
                    ForEach(FileOpener.Editor.allCases, id: \.self) { editor in
                        Text(editor.rawValue).tag(editor.rawValue)
                    }
                    
                    if !FileOpener.Editor.allCases.map({ $0.rawValue }).contains(preferredEditor) {
                        Text(URL(fileURLWithPath: preferredEditor).lastPathComponent).tag(preferredEditor)
                    }
                }
                .labelsHidden()
                .onChange(of: preferredEditor) { newValue in
                    PreferencesManager.shared.setPreferredEditor(newValue)
                }
                
                Text("选择双击记录或点击链接时首选的打开方式")
                    .font(.themeCaptionSmall)
                    .foregroundColor(.themeTextTertiary)
            }
        }
        .padding(20)
        .background(Color.themeGray800.opacity(0.4))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeHoverLight))
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                LucideView(name: .database, size: 16, color: .themeYellow500)
                Text("存储统计与管理")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
                
                Spacer()
                
                Button(action: refreshStats) {
                    LucideView(name: .refreshCw, size: 14, color: .themeBlue500)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            
            VStack(alignment: .leading, spacing: 12) {
                // 总览数据
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("总占用")
                            .font(.themeCaptionSmall)
                            .foregroundColor(.themeTextTertiary)
                        Text(stats.formattedTotalSize)
                            .font(.themeH2)
                            .foregroundColor(.themeBlue400)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("总条数")
                            .font(.themeCaptionSmall)
                            .foregroundColor(.themeTextTertiary)
                        Text("\(store.records.count) 条")
                            .font(.themeH2)
                            .foregroundColor(.themePurple400)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                                Text("截图保留上限")
                                    .font(.themeCaptionSmall)
                                    .foregroundColor(.themeTextTertiary)
                                HStack(spacing: 8) {
                                    TextField("", value: $store.maxScreenshots, formatter: NumberFormatter())
                                        .textFieldStyle(.plain)
                                        .font(.themeH2)
                                        .foregroundColor(.themeTextPrimary)
                                        .frame(width: 50)
                                        .multilineTextAlignment(.trailing)
                                        .onChange(of: store.maxScreenshots) { newValue in
                                            PreferencesManager.shared.setMaxScreenshots(newValue)
                                        }
                                    Text("条")
                                        .font(.themeCaption)
                                        .foregroundColor(.themeTextSecondary)
                                }
                            }
                }
                .padding(.bottom, 8)

                // 分类明细列表
                VStack(spacing: 1) {
                    let categories: [(RecordType, IconName, Color)] = [
                        (.screenshot, .camera, .themeBlue400),
                        (.image, .image, .themeGreen500),
                        (.file, .fileText, .themePurple400),
                        (.folder, .folder, .themeYellow500),
                        (.text, .type, .themeTextSecondary)
                    ]
                    
                    ForEach(categories, id: \.0) { type, icon, color in
                        let stat = stats.categoryStats[type] ?? StorageStats.CategoryStat(count: 0, size: 0)
                        
                        HStack(spacing: 12) {
                            LucideView(name: icon, size: 14, color: color)
                            Text(displayName(for: type))
                                .font(.themeBody)
                                .foregroundColor(.themeTextPrimary)
                            
                            Spacer()
                            
                            Text("\(stat.count) 条")
                                .font(.themeCaption)
                                .foregroundColor(.themeTextSecondary)
                            
                            if type != .text && type != .folder {
                                Text(stat.formattedSize)
                                    .font(.themeCaption)
                                    .foregroundColor(.themeTextTertiary)
                                    .frame(width: 60, alignment: .trailing)
                            } else {
                                Text("--")
                                    .font(.themeCaption)
                                    .foregroundColor(.themeTextTertiary)
                                    .frame(width: 60, alignment: .trailing)
                            }
                            
                            Button(action: { 
                                        store.confirm(
                                            title: "确认清理",
                                            message: "确定要清理所有 \(displayName(for: type)) 记录吗？关联的物理文件将被移动到废纸篓。此操作不可撤销记录本身。",
                                            confirmTitle: "确认清理",
                                            isDestructive: true
                                        ) {
                                            store.deleteRecords(ofType: type)
                                            refreshStats()
                                        }
                                    }) {
                                        LucideView(name: .trash2, size: 14, color: .themeStatusError.opacity(0.6))
                                    .padding(6)
                                    .background(Color.themeStatusError.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.themeGray800.opacity(0.2))
                    }
                }
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeBorder, lineWidth: 1))
            }
        }
        .padding(20)
        .background(Color.themeGray800.opacity(0.4))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeHoverLight))
    }

    private func displayName(for type: RecordType) -> String {
        switch type {
        case .screenshot: return "截图"
        case .image: return "照片"
        case .file: return "文件"
        case .folder: return "文件夹"
        case .text: return "纯文本"
        case .video: return "视频"
        }
    }

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                LucideView(name: .alertTriangle, size: 16, color: .themeRed500)
                Text("危险区域")
                    .font(.themeH2)
                    .foregroundColor(.themeRed500)
            }
            
            Button(action: { 
                store.confirm(
                    title: "确认重置",
                    message: "这将重置 AI 提示词、编辑器偏好、路径配置等所有设置到默认状态。此操作不可撤销。",
                    confirmTitle: "确认重置",
                    isDestructive: true
                ) {
                    PreferencesManager.shared.resetAll()
                    store.loadPreferences()
                    preferredEditor = "System Default"
                    refreshStats()
                }
            }) {
                HStack(spacing: 8) {
                    LucideView(name: .rotateCcw, size: 14, color: .themeRed400)
                    Text("恢复出厂设置 (重置所有配置)")
                        .font(.themeBody)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.themeRed500.opacity(0.1))
                .foregroundColor(.themeRed400)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeRed500.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(20)
        .background(Color.themeGray800.opacity(0.4))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeHoverLight))
    }
    
    private func copyPathToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(store.currentAttachmentsDirectory.path, forType: .string)
    }

    private func refreshStats() {
        stats = StorageManager.shared.calculateStats(for: store.currentAttachmentsDirectory, records: store.records)
    }
    
    private func colorForIndex(_ index: Int) -> Color {
        let colors: [Color] = [.themeBlue400, .themePurple400, .themeGreen400, .themeYellow400]
        return colors[index % colors.count]
    }
    
    private func selectCustomApp() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.title = "选择自定义编辑器应用"
        openPanel.prompt = "选择"
        openPanel.allowedContentTypes = [.application]
        openPanel.directoryURL = URL(fileURLWithPath: "/Applications")

        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                DispatchQueue.main.async {
                    preferredEditor = url.path
                    PreferencesManager.shared.setPreferredEditor(url.path)
                }
            }
        }
    }
    
    private func selectAttachmentsFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.title = "选择附件存储目录"
        openPanel.prompt = "选择"
        openPanel.level = .modalPanel
        openPanel.directoryURL = store.currentAttachmentsDirectory

        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                DispatchQueue.main.async {
                    store.attachmentsPath = url.path
                    store.savePreferences()
                    refreshStats()
                }
            }
        }
    }
}
