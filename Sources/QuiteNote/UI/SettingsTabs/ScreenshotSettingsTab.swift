import SwiftUI

/// 截图设置标签页视图
struct ScreenshotSettingsTab: View {
    @ObservedObject private var prefs = PreferencesManager.shared
    @State private var isRecording = false
    @State private var screenCaptureGranted = false
    @State private var accessibilityGranted = false
    @State private var isWindowHighlightEnabled = false

    // 定时器，每 2 秒刷新一次权限状态
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            permissionSection

            if screenCaptureGranted && accessibilityGranted {
                shortcutSection
                behaviorSection
                previewSection
                windowHighlightSection  // ✅ 新增：窗口高亮测试
            } else {
                permissionRequiredHint
                previewSection // 即使没有权限也允许测试预览 UI
                windowHighlightSection  // ✅ 新增：窗口高亮测试（不需要权限）
            }
        }
        .onAppear {
            // 页面打开时立即执行一次强制权限请求/检查
            autoRequestPermissions()
        }
        .onReceive(timer) { _ in
            updatePermissionStatus()
        }
        .onDisappear {
            // 页面关闭时停止窗口高亮
            if isWindowHighlightEnabled {
                WindowHighlightController.shared.stopHighlight()
                isWindowHighlightEnabled = false
            }
        }
    }
    
    // MARK: - Preview Section

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                LucideView(name: .camera, size: 16, color: .themePurple400)
                Text("UI 预览测试")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
            }

            Text("无需截图权限即可预览截图后的操作界面，方便验证 UI 样式。")
                .font(.themeCaption)
                .foregroundColor(.themeTextTertiary)

            Button(action: {
                NotificationCenter.default.post(name: NSNotification.Name("qn.screenshot.test"), object: nil)
            }) {
                HStack(spacing: 8) {
                    LucideView(name: .eye, size: 14, color: .white)
                    Text("打开预览界面")
                        .font(.themeBody)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.themeStatusLoading)
                .cornerRadius(8)
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Color.themeCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorderSubtle))
    }

    // MARK: - Window Highlight Section (✅ 新增)

    private var windowHighlightSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                LucideView(name: .square, size: 16, color: .themeBlue400)
                Text("窗口高亮测试")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
            }

            Text("无需截图权限即可测试窗口高亮功能，验证多屏幕和样式效果。")
                .font(.themeCaption)
                .foregroundColor(.themeTextTertiary)

            Button(action: {
                if isWindowHighlightEnabled {
                    WindowHighlightController.shared.stopHighlight()
                    isWindowHighlightEnabled = false
                } else {
                    WindowHighlightController.shared.startHighlight()
                    isWindowHighlightEnabled = true
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isWindowHighlightEnabled ? "xmark.circle" : "square")
                        .foregroundColor(.white)
                    Text(isWindowHighlightEnabled ? "停止高亮" : "启动高亮")
                        .font(.themeBody)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isWindowHighlightEnabled ? Color.themeStatusError : Color.themeStatusSuccess)
                .cornerRadius(8)
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Color.themeCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorderSubtle))
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
                        HStack(spacing: 4) {
                            let flags = NSEvent.ModifierFlags(rawValue: UInt(prefs.screenshotShortcutFlags))
                            if flags.contains(.command) { shortcutBadge("⌘") }
                            if flags.contains(.shift) { shortcutBadge("⇧") }
                            if flags.contains(.option) { shortcutBadge("⌥") }
                            if flags.contains(.control) { shortcutBadge("⌃") }
                        }
                        
                        TextField("", text: Binding(
                            get: { prefs.screenshotShortcut.uppercased() },
                            set: { newValue in
                                if let char = newValue.last {
                                    prefs.setScreenshotShortcut(String(char).lowercased())
                                } else if newValue.isEmpty {
                                    prefs.setScreenshotShortcut("")
                                }
                            }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .frame(width: 20)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.themeHoverMedium)
                        .cornerRadius(4)
                        .foregroundColor(.themeTextPrimary)
                    }
                    .padding(8)
                    .background(Color.themeInput)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeBorderSubtle))
                }
                
                Text("修改后需重启应用生效。默认：⌘ + ⇧ + S")
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
