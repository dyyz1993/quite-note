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
                        .background(Color.white.opacity(0.05))
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
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05)))
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
                    .background(Color.white.opacity(0.05))
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
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05)))
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                LucideView(name: .database, size: 16, color: .themeYellow500)
                Text("存储统计报告")
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("--- ATTACHMENT STORAGE REPORT ---")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.themeGray400)
                        .padding(.bottom, 4)

                    HStack {
                        Text("TOTAL VOLUME")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.themeGray500)
                        Spacer()
                        Text(stats.formattedTotalSize)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.themeBlue400)
                    }
                    
                    HStack {
                        Text("FILE COUNT")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.themeGray500)
                        Spacer()
                        Text("\(stats.fileCount)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.themePurple400)
                    }
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.05))
                                .frame(height: 6)
                            
                            HStack(spacing: 0) {
                                let sortedTypes = stats.typeDistribution.sorted { $0.value > $1.value }.prefix(4)
                                ForEach(Array(sortedTypes.enumerated()), id: \.offset) { index, item in
                                    let width = geo.size.width * CGFloat(item.value) / CGFloat(max(1, stats.totalSize))
                                    Rectangle()
                                        .fill(colorForIndex(index))
                                        .frame(width: width, height: 6)
                                }
                            }
                        }
                    }
                    .frame(height: 6)
                    .cornerRadius(3)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("+-- DISTRIBUTION ------------------+")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.themeGray600)
                        
                        let sortedTypes = stats.typeDistribution.sorted { $0.value > $1.value }.prefix(5)
                        if sortedTypes.isEmpty {
                            Text("|  (No data available)              |")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.themeGray500)
                        } else {
                            ForEach(Array(sortedTypes), id: \.key) { ext, size in
                                let formattedSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                                let extStr = ".\(ext)"
                                let extPadding = String(repeating: " ", count: max(1, 10 - extStr.count))
                                let sizePadding = String(repeating: " ", count: max(1, 15 - formattedSize.count))
                                Text("|  \(extStr)\(extPadding):\(sizePadding)\(formattedSize)  |")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.themeGray400)
                            }
                        }
                        
                        Text("+----------------------------------+")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.themeGray600)
                    }
                    .padding(.top, 4)
                }
                .padding(16)
                .background(Color.themeInput.opacity(0.5))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.05)))
            }
        }
        .padding(20)
        .background(Color.themeGray800.opacity(0.4))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05)))
    }

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                LucideView(name: .alertTriangle, size: 16, color: .themeRed500)
                Text("危险区域")
                    .font(.themeH2)
                    .foregroundColor(.themeRed500)
            }
            
            Button(action: { showResetConfirm = true }) {
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
            .alert("确认重置", isPresented: $showResetConfirm) {
                Button("取消", role: .cancel) {}
                Button("确认重置", role: .destructive) {
                    PreferencesManager.shared.resetAll()
                    store.loadPreferences()
                    preferredEditor = "System Default"
                    refreshStats()
                }
            } message: {
                Text("这将重置 AI 提示词、编辑器偏好、路径配置等所有设置到默认状态。此操作不可撤销。")
            }
        }
        .padding(20)
        .background(Color.themeGray800.opacity(0.4))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05)))
    }
    
    private func copyPathToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(store.currentAttachmentsDirectory.path, forType: .string)
    }

    private func refreshStats() {
        stats = StorageManager.shared.calculateStats(for: store.currentAttachmentsDirectory)
    }
    
    private func colorForIndex(_ index: Int) -> Color {
        let colors: [Color] = [.themeBlue500, .themePurple500, .themeGreen500, .themeYellow500, .themeRed500]
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
