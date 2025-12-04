import SwiftUI

/// 右上角设置面板：AI、记录、蓝牙、窗口标签页
struct SettingsOverlayView: View {
    @ObservedObject var store: RecordStore
    @ObservedObject var bluetooth: BluetoothManager
    @Binding var showSettings: Bool
    @State private var tab: String = "ai"

    /// 构建设置面板 UI，右上角浮层
    var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar (Tabs)
            VStack(spacing: 4) {
                TabButton(key: "ai", label: "AI 提炼设置", icon: "sparkles", current: $tab)
                TabButton(key: "history", label: "记录设置", icon: "server.rack", current: $tab)
                TabButton(key: "bluetooth", label: "蓝牙设置", icon: "bluetooth", current: $tab)
                TabButton(key: "window", label: "悬浮窗设置", icon: "macwindow", current: $tab)
                Spacer()
            }
            .frame(width: 140)
            .padding(12)
            .background(Color.black.opacity(0.2)) // bg-black/20
            .overlay(Rectangle().frame(width: 1).foregroundColor(Color.themeBorder), alignment: .trailing)
            
            // Right Content
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("偏好设置")
                        .font(.system(size: 14, weight: .semibold)) // text-sm font-semibold
                        .foregroundColor(.themeTextPrimary)
                    Spacer()
                    Button(action: { withAnimation { showSettings = false } }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14))
                            .foregroundColor(.themeGray500)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .frame(height: 48) // h-12
                .background(Color.white.opacity(0.05)) // bg-white/5
                .overlay(Rectangle().frame(height: 1).foregroundColor(Color.themeBorder), alignment: .bottom)
                
                // Scrollable Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch tab {
                        case "ai": aiTab
                        case "history": historyTab
                        case "bluetooth": bluetoothTab
                        case "window": windowTab
                        default: EmptyView()
                        }
                    }
                    .padding(24)
                }
                
                // Footer
                HStack(spacing: 12) {
                    Spacer()
                    Button(action: { withAnimation { showSettings = false } }) {
                        Text("取消")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.themeGray400)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        withAnimation { showSettings = false }
                        // Save action is implicit with bindings, but we can add explicit save here if needed
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                            Text("保存")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.themeBlue600) // bg-blue-600
                        .cornerRadius(6)
                        .shadow(color: Color.themeBlue900.opacity(0.2), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .frame(height: 56) // h-14
                .background(Color.black.opacity(0.2))
                .overlay(Rectangle().frame(height: 1).foregroundColor(Color.themeBorder), alignment: .top)
            }
        }
        .frame(width: 600, height: 450)
        .background(Color.themeBackground)
        .cornerRadius(12)
        .shadow(radius: 20)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))
    }

    /// AI 设置内容
    private var aiTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Toggle Section
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").foregroundColor(.themeYellow400).font(.system(size: 14))
                        Text("AI 自动提炼")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.themeTextPrimary)
                    }
                    Text("开启后自动为新记录生成标题和总结。")
                        .font(.system(size: 10))
                        .foregroundColor(.themeGray500)
                }
                Spacer()
                CustomToggle(isOn: Binding(
                    get: { store.enableAI },
                    set: { store.enableAI = $0; store.savePreferences() }
                ))
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05)))
            
            if store.enableAI {
                // Sliders
                VStack(alignment: .leading, spacing: 16) {
                    Text("提炼行为约束")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.themeGray300)
                        
                    CustomSlider(label: "总结触发长度", value: Binding(
                        get: { Double(store.summaryTrigger) }, set: { store.summaryTrigger = Int($0); store.savePreferences() }
                    ), range: 10...500, displayValue: "> \(store.summaryTrigger) 字符")
                    
                    CustomSlider(label: "标题长度限制", value: Binding(
                        get: { Double(store.titleLimit) }, set: { store.titleLimit = Int($0); store.savePreferences() }
                    ), range: 10...40, displayValue: "\(store.titleLimit) 字符")
                    
                    CustomSlider(label: "总结长度限制", value: Binding(
                        get: { Double(store.summaryLimit) }, set: { store.summaryLimit = Int($0); store.savePreferences() }
                    ), range: 50...300, displayValue: "\(store.summaryLimit) 字符")
                }
                .padding(16)
                .background(Color.black.opacity(0.2))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05)))
                
                // Provider Selection
                VStack(alignment: .leading, spacing: 8) {
                    Label("模型服务商与连接", systemImage: "link")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.themeGray400)
                    
                    HStack(spacing: 8) {
                        ProviderButton(title: "Google Gemini", isSelected: store.aiProvider == .gemini) { store.setAIProvider(.gemini) }
                        ProviderButton(title: "OpenAI GPT", isSelected: store.aiProvider == .openai) { store.setAIProvider(.openai) }
                        ProviderButton(title: "Local LLM", isSelected: store.aiProvider == .local) { store.setAIProvider(.local) }
                    }
                }
                
                // API Config
                VStack(spacing: 12) {
                    CustomTextField(label: "API Key", placeholder: "sk-...", text: Binding(
                        get: { KeychainHelper.shared.read(service: "QuiteNote", account: "openai_api_key") ?? "" },
                        set: { KeychainHelper.shared.write(service: "QuiteNote", account: "openai_api_key", value: $0) }
                    ), isSecure: true)
                    
                    CustomTextField(label: "Base URL / Model", placeholder: "https://api.openai.com/v1", text: Binding(
                        get: { (store.ai as? AIService)?.openAIBaseURL ?? "https://api.openai.com/v1" },
                        set: { store.configureOpenAI(apiKey: KeychainHelper.shared.read(service: "QuiteNote", account: "openai_api_key") ?? "", baseURL: $0, model: (store.ai as? AIService)?.openAIModel ?? "gpt-4o-mini") }
                    ))
                }
                .padding(16)
                .background(Color.black.opacity(0.2))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05)))
            }
        }
    }

    /// 记录设置内容
    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("自动去重").font(.system(size: 14, weight: .medium)).foregroundColor(.themeTextPrimary)
                    Text("10分钟内重复内容仅更新时间戳").font(.system(size: 10)).foregroundColor(.themeGray500)
                }
                Spacer()
                CustomToggle(isOn: Binding(
                    get: { store.dedupEnabled }, set: { store.dedupEnabled = $0; store.savePreferences() }
                ))
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05)))
            
            VStack(spacing: 16) {
                CustomSlider(label: "记录保留条数", value: Binding(
                    get: { Double(store.maxRecords) }, set: { store.maxRecords = Int($0); store.savePreferences() }
                ), range: 50...1000, displayValue: "\(store.maxRecords) 条")
            }
            .padding(16)
            .background(Color.black.opacity(0.2))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05)))
            
            // Clear History Button
            Button(action: {
                store.clearAll()
                store.postLightHint("已清空所有记录")
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text("清空所有记录")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.themeRed500.opacity(0.8))
                .cornerRadius(8)
                .shadow(color: Color.themeRed500.opacity(0.2), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
        }
    }

    /// 蓝牙设置内容
    private var bluetoothTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("连接状态").font(.system(size: 14, weight: .medium)).foregroundColor(.themeTextPrimary)
                    Text(bluetooth.connectedDeviceName != nil ? "已连接: \(bluetooth.connectedDeviceName!)" : (bluetooth.state == .poweredOn ? "未连接" : "蓝牙未开启"))
                        .font(.system(size: 10))
                        .foregroundColor(bluetooth.connectedDeviceName != nil ? .themeGreen400 : .themeGray500)
                }
                Spacer()
                Button(action: {
                    if bluetooth.connectedDeviceName != nil { bluetooth.disconnect() } else { bluetooth.startScanning() }
                }) {
                    Text(bluetooth.connectedDeviceName != nil ? "断开" : "连接")
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.themeBlue600)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05)))
            
            VStack(spacing: 16) {
                CustomSlider(label: "硬件防抖 (秒)", value: Binding(
                    get: { bluetooth.debounceInterval }, set: { bluetooth.debounceInterval = $0 }
                ), range: 0.5...3.0, displayValue: String(format: "%.1f s", bluetooth.debounceInterval))
            }
            .padding(16)
            .background(Color.black.opacity(0.2))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05)))
        }
    }

    /// 悬浮窗设置内容
    private var windowTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToggleRow(title: "位置锁定", subtitle: "开启后悬浮窗不可拖拽移动", isOn: Binding(
                get: { PreferencesManager.shared.windowLock },
                set: { PreferencesManager.shared.setWindowLock($0); NotificationCenter.default.post(name: .windowLockChanged, object: $0) }
            ))
            
            ToggleRow(title: "动效开关", subtitle: "开启/关闭窗口淡入淡出动画", isOn: Binding(
                get: { PreferencesManager.shared.animationsEnabled },
                set: { PreferencesManager.shared.setAnimationsEnabled($0); NotificationCenter.default.post(name: .animationsEnabledChanged, object: $0) }
            ))
        }
    }
}

// MARK: - Helper Components

struct TabButton: View {
    let key: String
    let label: String
    let icon: String
    @Binding var current: String

    var body: some View {
        Button(action: { withAnimation { current = key } }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .foregroundColor(current == key ? .themeBlue400 : .themeGray400)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(current == key ? Color.themeBlue500.opacity(0.1) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ProviderButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .frame(maxWidth: .infinity)
                .foregroundColor(isSelected ? Color.themeAccentHover : .gray)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.themeAccent.opacity(0.2) : Color.white.opacity(0.05))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Color.themeAccent : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct CustomTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold)) // text-[10px] font-bold
                .foregroundColor(.themeGray500) // text-gray-500
                .textCase(.uppercase) // uppercase
                .tracking(0.5) // tracking-wider
            
            if isSecure {
                SecureField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12)) // text-xs
                    .padding(8)
                    .background(Color.black.opacity(0.4)) // bg-black/40
                    .cornerRadius(8) // rounded-lg
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeBorder)) // border-white/10
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12)) // text-xs
                    .padding(8)
                    .background(Color.black.opacity(0.4)) // bg-black/40
                    .cornerRadius(8) // rounded-lg
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeBorder)) // border-white/10
            }
        }
    }
}

struct CustomSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let displayValue: String
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(label).font(.system(size: 12)).foregroundColor(.themeGray400)
                Spacer()
                Text(displayValue)
                    .font(.system(size: 12, design: .monospaced)) // text-xs
                    .foregroundColor(.themeBlue400) // text-blue-400
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.themeBlue400.opacity(0.1)) // bg-blue-400/10
                    .cornerRadius(4)
            }
            // Custom Slider Implementation
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.themeGray700) // bg-gray-700
                        .frame(height: 6)
                    
                    Capsule()
                        .fill(Color.themeBlue500) // accent-blue-500
                        .frame(width: geometry.size.width * CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)), height: 6)
                }
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let percent = min(max(0, value.location.x / geometry.size.width), 1)
                    self.value = range.lowerBound + (range.upperBound - range.lowerBound) * Double(percent)
                })
            }
            .frame(height: 6)
        }
    }
}

struct CustomToggle: View {
    @Binding var isOn: Bool
    
    var body: some View {
        Button(action: { withAnimation(.spring(response: 0.3)) { isOn.toggle() } }) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Color.themeBlue500 : Color.themeGray600) // bg-blue-500 : bg-gray-600
                    .frame(width: 40, height: 20) // w-10 h-5
                
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12) // w-3 h-3
                    .padding(4)
                    .shadow(radius: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium)) // text-sm font-medium
                    .foregroundColor(.themeTextPrimary) // text-gray-200
                Text(subtitle)
                    .font(.system(size: 10)) // text-[10px]
                    .foregroundColor(.themeGray500) // text-gray-500
            }
            Spacer()
            CustomToggle(isOn: $isOn)
        }
        .padding(12)
        .background(Color.white.opacity(0.05)) // bg-white/5
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeBorder))
    }
}
