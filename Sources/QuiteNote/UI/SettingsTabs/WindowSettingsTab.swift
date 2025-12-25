import SwiftUI

/// 窗口设置标签页视图
struct WindowSettingsTab: View {
    @State private var windowLock = false
    @State private var animationsEnabled = true
    @State private var rememberWindowPosition = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
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
}
