import SwiftUI

/// 符号设置标签页
struct SymbolSettingsTab: View {
    @StateObject private var configManager = SymbolConfigManager.shared
    @State private var showingImport = false
    @State private var showingEditor = false
    @State private var selectedConfig: SymbolConfig?
    @State private var editingConfig: SymbolConfig?

    var body: some View {
        VStack(spacing: 0) {
            // 标题区域
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("符号配置管理")
                        .font(.themeH3)
                        .foregroundColor(Color.themeTextPrimary)

                    Text("管理符号库配置和触发词")
                        .font(.themeCaption)
                        .foregroundColor(Color.themeTextTertiary)
                }

                Spacer()

                // 操作按钮
                HStack(spacing: 12) {
                    Button(action: { showingImport = true }) {
                        Label("导入配置", systemImage: "plus")
                            .font(.themeBody)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.themeBlue600)
                            .cornerRadius(8)
                            .shadow(color: Color.themeShadowBlue, radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: { exportAll() }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12))
                            .foregroundColor(Color.themeTextSecondary)
                            .frame(width: 32, height: 32)
                            .background(Color.themeHoverLight)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.themeBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: { resetToDefault() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                            .foregroundColor(Color.themeTextSecondary)
                            .frame(width: 32, height: 32)
                            .background(Color.themeHoverLight)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.themeBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(24)
            .padding(.bottom, 16)

            Divider()
                .background(Color.themeBorder)

            // 配置列表
            ScrollView {
                VStack(spacing: 16) {
                    if configManager.configs.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(configManager.configs) { config in
                            SymbolConfigCard(
                                config: config,
                                onEdit: { editConfig(config) },
                                onDelete: { deleteConfig(config) },
                                onDuplicate: { duplicateConfig(config) }
                            )
                        }
                    }
                }
                .padding(24)
            }

            Divider()
                .background(Color.themeBorder)

            // 底部信息
            HStack {
                Text("配置文件: \(configManager.configs.count) 个")
                    .font(.themeCaption)
                    .foregroundColor(Color.themeTextTertiary)

                Spacer()

                Button(action: { saveAll() }) {
                    Text("保存设置")
                        .font(.themeBody)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.themeBlue600)
                        .cornerRadius(8)
                        .shadow(color: Color.themeShadowBlue, radius: 4, x: 0, y: 2)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: { closeSettings() }) {
                    Text("关闭")
                        .font(.themeBody)
                        .foregroundColor(Color.themeTextSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.themeHoverLight)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.themeBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(20)
        }
        .background(Color.themeBackground)
        .sheet(isPresented: $showingImport) {
            SymbolImportView(isPresented: $showingImport)
        }
        .sheet(isPresented: $showingEditor) {
            if let config = editingConfig {
                SymbolConfigEditorView(
                    config: config,
                    isPresented: $showingEditor,
                    onSave: { updatedConfig in
                        saveConfig(updatedConfig)
                    }
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "text.badge.xmark")
                .font(.system(size: 64))
                .foregroundColor(Color.themeGray600)

            VStack(spacing: 8) {
                Text("暂无符号配置")
                    .font(.themeH3)
                    .foregroundColor(Color.themeTextPrimary)

                Text("点击导入配置添加符号库")
                    .font(.themeCaption)
                    .foregroundColor(Color.themeTextTertiary)
            }

            Button(action: { showingImport = true }) {
                Label("导入默认配置", systemImage: "plus")
                    .font(.themeBody)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.themeBlue600)
                    .cornerRadius(8)
                    .shadow(color: Color.themeShadowBlue, radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Actions

    private func editConfig(_ config: SymbolConfig) {
        editingConfig = config
        showingEditor = true
    }

    private func deleteConfig(_ config: SymbolConfig) {
        guard config.metadata.name != "默认符号库" else {
            // 显示错误提示
            return
        }

        do {
            try configManager.deleteConfig(config)
        } catch {
            print("[SymbolSettingsTab] 删除配置失败: \(error)")
        }
    }

    private func duplicateConfig(_ config: SymbolConfig) {
        var duplicatedMetadata = config.metadata
        duplicatedMetadata.name = "\(config.metadata.name) 副本"
        duplicatedMetadata.priority = configManager.configs.count + 1

        let duplicated = SymbolConfig(
            metadata: duplicatedMetadata,
            global: config.global,
            menus: config.menus
        )

        do {
            try configManager.saveConfig(duplicated)
        } catch {
            print("[SymbolSettingsTab] 复制配置失败: \(error)")
        }
    }

    private func saveConfig(_ config: SymbolConfig) {
        do {
            try configManager.saveConfig(config)
        } catch {
            print("[SymbolSettingsTab] 保存配置失败: \(error)")
        }
    }

    private func exportAll() {
        let yamlString = configManager.configs
            .map { $0.toYaml() }
            .joined(separator: "\n\n---\n\n")

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(yamlString, forType: .string)

        print("[SymbolSettingsTab] 已导出所有配置到剪贴板")
    }

    private func resetToDefault() {
        configManager.resetToDefault()
    }

    private func saveAll() {
        // 触发保存通知
        NotificationCenter.default.post(name: .symbolsDidChange, object: nil)
    }

    private func closeSettings() {
        NotificationCenter.default.post(name: .closeSettings, object: nil)
    }
}

// MARK: - Symbol Config Card

struct SymbolConfigCard: View {
    let config: SymbolConfig
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            // 图标
            Text(config.metadata.iconDisplay)
                .font(.system(size: 32))

            VStack(alignment: .leading, spacing: 6) {
                // 名称
                HStack(spacing: 8) {
                    Text(config.metadata.name)
                        .font(.themeBody)
                        .foregroundColor(Color.themeTextPrimary)
                        .fontWeight(.medium)

                    if !config.metadata.enabled {
                        Text("已禁用")
                            .font(.themeCaptionSmall)
                            .foregroundColor(Color.themeTextTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.themeHoverLight)
                            .cornerRadius(4)
                    }
                }

                // 统计信息
                Text(statsText)
                    .font(.themeCaptionSmall)
                    .foregroundColor(Color.themeTextTertiary)
            }

            Spacer()

            // 操作按钮
            if isHovered {
                HStack(spacing: 4) {
                    actionButton(systemImage: "pencil", action: onEdit)
                    actionButton(systemImage: "doc.on.doc", action: onDuplicate)
                    if config.metadata.name != "默认符号库" {
                        actionButton(systemImage: "trash", action: onDelete)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.themeHoverLight)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.themeBorder, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var statsText: String {
        let stats = config.stats
        var parts: [String] = []
        parts.append("\(stats.menuCount) 个分类")
        parts.append("\(stats.symbolCount) 个符号")
        if stats.conflictCount > 0 {
            parts.append("\(stats.conflictCount) 个冲突")
        }
        return parts.joined(separator: " · ")
    }

    private func actionButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundColor(Color.themeTextSecondary)
                .frame(width: 28, height: 28)
                .background(Color.themeHoverMedium)
                .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let symbolsDidChange = Notification.Name("symbolsDidChange")
    static let closeSettings = Notification.Name("closeSettings")
}

// MARK: - Font Extensions

extension Font {
    // 注意：这些定义与 Font+Theme.swift 冲突，已禁用
    // 请使用 Font+Theme.swift 中的定义
    // static let themeH1: Font = .system(size: 18, weight: .bold)
    // static let themeH2: Font = .system(size: 16, weight: .semibold)
    // static let themeH3: Font = .system(size: 14, weight: .medium)
    // static let themeBody: Font = .system(size: 13)
    // static let themeCaption: Font = .system(size: 11)
    // static let themeCaptionSmall: Font = .system(size: 10)
}
