import SwiftUI

/// 窗口设置标签页视图
struct WindowSettingsTab: View {
    @State private var windowLock = false
    @State private var animationsEnabled = true
    @State private var rememberWindowPosition = true
    @State private var launchAtLogin = false
    @State private var loginItemNeedsApproval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ToggleRow(title: "开机自启动", subtitle: "登录 macOS 后自动在菜单栏启动；建议先将 App 放入「应用程序」等稳定位置", isOn: $launchAtLogin)
                .onAppear {
                    launchAtLogin = PreferencesManager.shared.launchAtLogin
                    loginItemNeedsApproval = PreferencesManager.shared.loginItemNeedsApproval
                }
                .onChange(of: launchAtLogin) { newValue in
                    // 设置失败时回读系统实际状态回退开关（也覆盖用户去系统设置手动改动的场景）
                    guard PreferencesManager.shared.setLaunchAtLogin(newValue) else {
                        launchAtLogin = PreferencesManager.shared.launchAtLogin
                        return
                    }
                    loginItemNeedsApproval = PreferencesManager.shared.loginItemNeedsApproval
                }

            if loginItemNeedsApproval {
                loginItemApprovalHint
            }

            ToggleRow(title: "位置锁定", subtitle: "开启后悬浮窗不可拖拽移动", isOn: $windowLock)
                .onAppear {
                    windowLock = PreferencesManager.shared.windowLock
                }
                .onChange(of: windowLock) { newValue in
                    PreferencesManager.shared.setWindowLock(newValue)
                    QuiteNoteNotification.post(.windowLockChanged, object: newValue)
                }

            ToggleRow(title: "动效开关", subtitle: "开启/关闭窗口淡入淡出动画", isOn: $animationsEnabled)
                .onAppear {
                    animationsEnabled = PreferencesManager.shared.animationsEnabled
                }
                .onChange(of: animationsEnabled) { newValue in
                    PreferencesManager.shared.setAnimationsEnabled(newValue)
                    QuiteNoteNotification.post(.animationsEnabledChanged, object: newValue)
                }

            ToggleRow(title: "记忆位置", subtitle: "开启后记住并恢复窗口上次的位置", isOn: $rememberWindowPosition)
                .onAppear {
                    rememberWindowPosition = PreferencesManager.shared.rememberWindowPosition
                }
                .onChange(of: rememberWindowPosition) { newValue in
                    PreferencesManager.shared.setRememberWindowPosition(newValue)
                }
        }
    }

    /// 注册被系统挂起（.requiresApproval）时的引导行：去登录项列表放行
    private var loginItemApprovalHint: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("待系统确认").font(.system(size: 14, weight: .medium)).foregroundColor(.themeTextPrimary)
                Text("需在「系统设置 → 通用 → 登录项」中允许 QuiteNote").font(.system(size: 10)).foregroundColor(.themeYellow500)
            }
            Spacer()
            Button(action: openLoginItemsSettings) {
                Text("打开设置")
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
        .padding(16)
        .background(Color.themeHoverLight)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeBorderSubtle).allowsHitTesting(false))
    }

    private func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
