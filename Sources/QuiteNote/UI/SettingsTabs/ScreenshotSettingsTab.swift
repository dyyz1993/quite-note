import SwiftUI

/// 截图设置标签页视图
struct ScreenshotSettingsTab: View {
    @ObservedObject private var prefs = PreferencesManager.shared
    @State private var isRecording = false
    @State private var screenCaptureGranted = false
    @State private var accessibilityGranted = false

    // 定时器，每 2 秒刷新一次权限状态
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            permissionSection

            if screenCaptureGranted && accessibilityGranted {
                shortcutSection
                behaviorSection
            } else {
                permissionRequiredHint
            }
        }
        .onAppear {
            // 页面打开时立即执行一次强制权限请求/检查
            autoRequestPermissions()
        }
        .onReceive(timer) { _ in
            updatePermissionStatus()
        }
    }
    
    private func autoRequestPermissions() {
        // 1. 更新当前状态
        updatePermissionStatus()
        
        // 2. 如果没有权限，则尝试请求（这会触发系统弹窗或静默检查）
        if !screenCaptureGranted {
            _ = ScreenshotService.shared.checkAndRequestPermission()
        }
        
        if !accessibilityGranted {
            _ = ScreenshotService.shared.checkAccessibilityPermission(prompt: true)
        }
        
        // 3. 再次更新状态
        updatePermissionStatus()
    }
    
    private var permissionRequiredHint: some View {
        VStack(spacing: 12) {
            LucideView(name: .shield, size: 32, color: .themeTextTertiary)
            Text("请先完成上方权限授权")
                .font(.themeBody)
                .foregroundColor(.themeTextSecondary)
            Text("获得授权后即可配置快捷键和截图行为")
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
        accessibilityGranted = ScreenshotService.shared.checkAccessibilityPermission(prompt: false)
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
            
            Divider().background(Color.themeBorderSubtle)
            
            // 辅助功能权限
            permissionRow(
                title: "辅助功能权限",
                description: "需要此权限才能监听全局快捷键 (⌘+⇧+S)。",
                isGranted: accessibilityGranted,
                action: {
                    if !accessibilityGranted {
                        let granted = ScreenshotService.shared.checkAccessibilityPermission(prompt: true)
                        if !granted {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
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
        }
        .padding(20)
        .background(Color.themeCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorderSubtle))
    }
}
