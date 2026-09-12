import SwiftUI

/// 截图设置标签页视图
struct ScreenshotSettingsTab: View {
    @ObservedObject private var prefs = PreferencesManager.shared
    @State private var isRecording = false
    @State private var screenCaptureGranted = false

    // 定时器，每 2 秒刷新一次权限状态
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            permissionSection

            if screenCaptureGranted {
                shortcutSection
                behaviorSection
            } else {
                permissionRequiredHint
            }
        }
        .onAppear {
            // 设置页只展示当前状态；用户主动点击授权按钮时才请求系统权限。
            updatePermissionStatus()
        }
        .onReceive(timer) { _ in
            updatePermissionStatus()
        }
    }
    
    private var permissionRequiredHint: some View {
        VStack(spacing: 12) {
            LucideView(name: .shield, size: 32, color: .themeTextTertiary)
            Text("请先完成上方权限授权")
                .font(.themeBody)
                .foregroundColor(.themeTextSecondary)
            Text("屏幕录制授权后即可配置截图行为")
                .font(.themeCaption)
                .foregroundColor(.themeTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.themeCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorderSubtle, style: StrokeStyle(lineWidth: 1, dash: [4])))
    }
    
    private func updatePermissionStatus() {
        screenCaptureGranted = ScreenshotService.shared.checkScreenCapturePermission()
    }

    // MARK: - 保存目录

    private var saveDirectoryDescription: String {
        let raw = prefs.screenshotSaveDirectory
        if raw.isEmpty { return "未选择（首次导出时会要求选择）" }
        if case .failure = UserExportDirectory.configuredDirectory() {
            return "目录授权已失效，请重新选择"
        }
        // 用 ~ 缩写 home 目录，显示更友好
        return raw.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "选择截图、录屏和快剪的保存目录（所有后续导出都会保存到此目录）"
        if panel.runModal() == .OK, let url = panel.url {
            prefs.setScreenshotSaveDirectory(url)
        }
    }
    
    // MARK: - Shortcut Section
    
    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                LucideView(name: .keyboard, size: 16, color: .themeBlue400)
                Text("快捷键配置")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
            }
            
            VStack(spacing: 12) {
                HStack {
                    Text("截图快捷键")
                        .font(.themeBody)
                        .foregroundColor(.themeTextSecondary)
                    Spacer()
                    
                    HStack(spacing: 8) {
                        ShortcutRecorderView(
                            shortcut: Binding(
                                get: { prefs.screenshotShortcut },
                                set: { prefs.setScreenshotShortcut($0) }
                            ),
                            modifiers: Binding(
                                get: { prefs.screenshotShortcutFlags },
                                set: { prefs.setScreenshotShortcutFlags($0) }
                            )
                        )
                        
                        if !prefs.screenshotShortcut.isEmpty {
                            Button(action: {
                                prefs.setScreenshotShortcut("")
                                prefs.setScreenshotShortcutFlags(0)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.themeTextTertiary)
                            }
                            .buttonStyle(.plain)
                            .help("重置快捷键")
                        }
                    }
                    .padding(8)
                    .background(Color.themeInput)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeBorderSubtle))
                }
                
                Text("点击上方框进行录入。修改后立即生效。默认：⌘ + ⇧ + S")
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(20)
        .background(Color.themeCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorderSubtle))
    }
    
    private func shortcutBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.themeHoverMedium)
            .cornerRadius(4)
            .foregroundColor(.themeTextPrimary)
    }
    
    // MARK: - Permission Section
    
    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                LucideView(name: .shield, size: 16, color: .themeStatusSuccess)
                Text("权限申请")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
            }
            
            // 屏幕录制权限
            permissionRow(
                title: "屏幕录制权限",
                description: "截图功能需要此权限才能捕获屏幕内容。",
                isGranted: screenCaptureGranted,
                action: {
                    if !screenCaptureGranted {
                        let granted = ScreenshotService.shared.checkAndRequestPermission()
                        if !granted {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            )
            
        }
        .padding(20)
        .background(Color.themeCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorderSubtle))
    }
    
    private func permissionRow(title: String, description: String, isGranted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.themeBody)
                        .foregroundColor(.themeTextSecondary)
                    
                    if isGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.themeStatusSuccess)
                    }
                }
                
                Text(description)
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
            }
            Spacer()
            
            Button(action: action) {
                Text(isGranted ? "已授权" : "去授权")
                    .font(.themeCaption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isGranted ? Color.themeHoverMedium : Color.themeBlue600)
                    .foregroundColor(isGranted ? .themeTextTertiary : .white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isGranted)
        }
    }
    
    // MARK: - Behavior Section
    
    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                LucideView(name: .settings, size: 16, color: .themeTextSecondary)
                Text("截图行为")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
            }
            
            HStack {
                Text("默认存入剪贴板")
                    .font(.themeBody)
                    .foregroundColor(.themeTextSecondary)
                Spacer()
                CustomToggle(isOn: Binding(
                    get: { prefs.screenshotSaveToClipboard },
                    set: { prefs.setScreenshotSaveToClipboard($0) }
                ))
            }

            Divider().background(Color.themeBorderSubtle)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("保存目录")
                        .font(.themeBody)
                        .foregroundColor(.themeTextSecondary)
                    Text(saveDirectoryDescription)
                        .font(.themeCaption)
                        .foregroundColor(.themeTextTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()

                HStack(spacing: 8) {
                    Button(action: chooseSaveDirectory) {
                        Text("选择…")
                            .font(.themeCaption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.themeBlue600)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    if !prefs.screenshotSaveDirectory.isEmpty {
                        Button(action: { prefs.setScreenshotSaveDirectory("") }) {
                            Text("清除")
                                .font(.themeCaption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.themeHoverMedium)
                                .foregroundColor(.themeTextSecondary)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider().background(Color.themeBorderSubtle)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("保存后复制文件路径")
                        .font(.themeBody)
                        .foregroundColor(.themeTextSecondary)
                    Text("保存成功后，自动把文件的绝对路径复制到剪贴板")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextTertiary)
                }
                Spacer()
                CustomToggle(isOn: Binding(
                    get: { prefs.screenshotCopyPathAfterSave },
                    set: { prefs.setScreenshotCopyPathAfterSave($0) }
                ))
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("保存截图最大条数")
                        .font(.themeBody)
                        .foregroundColor(.themeTextSecondary)
                    Text("超过此数量后将自动删除最早的截图记录")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextTertiary)
                }
                Spacer()
                
                HStack(spacing: 8) {
                    TextField("", value: Binding(
                        get: { prefs.maxScreenshots },
                        set: { prefs.setMaxScreenshots($0) }
                    ), formatter: NumberFormatter())
                        .textFieldStyle(.plain)
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .padding(6)
                        .background(Color.themeInput)
                        .cornerRadius(6)
                    
                    Text("条")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextSecondary)
                }
            }
        }
        .padding(20)
        .background(Color.themeCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorderSubtle))
    }
}
