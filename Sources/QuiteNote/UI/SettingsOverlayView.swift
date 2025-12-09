import SwiftUI
import UniformTypeIdentifiers

/// 右上角设置面板：AI、记录、蓝牙、窗口标签页
struct SettingsOverlayView: View {
    @ObservedObject var store: RecordStore
    @ObservedObject var bluetooth: BluetoothManager
    @Binding var showSettings: Bool
    @State private var tab: String
    @State private var isTestingConnection = false
    @State private var windowLock = false
    @State private var animationsEnabled = true
    @State private var rememberWindowPosition = true

    init(store: RecordStore, bluetooth: BluetoothManager, showSettings: Binding<Bool>, initialTab: String = "ai") {
        self.store = store
        self.bluetooth = bluetooth
        self._showSettings = showSettings
        self._tab = State(initialValue: initialTab)
    }

    /// 构建设置面板 UI，右上角浮层
    var body: some View {
        VStack(spacing: 0) {
            headerView
            tabsView
            contentView
            footerView
        }
        .background(Color.themeBackground.opacity(0.9)) // bg-gray-900/90
    }
    
    /// 头部视图
    private var headerView: some View {
        HStack(spacing: 8) {
            Button(action: { withAnimation { showSettings = false } }) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18)) // size=18
                    .foregroundColor(.themeGray400)
                    .padding(4)
                    .background(Color.clear)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            
            Text("偏好设置")
                .font(.system(size: 16, weight: .semibold)) // text-base
                .foregroundColor(.themeGray100)
            
            Spacer()
            
            // Bluetooth Status Icon (Added based on feedback)
            HStack(spacing: 6) {
               if let name = bluetooth.connectedDeviceName {
                   Image(systemName: "bluetooth")
                       .foregroundColor(.themeBlue400)
                   Text(name)
                       .font(.system(size: 12))
                       .foregroundColor(.themeBlue400)
               } else if bluetooth.state == .poweredOn {
                   Image(systemName: "bluetooth")
                       .foregroundColor(.themeYellow500)
               } else {
                   Image(systemName: "bluetooth.slash")
                       .foregroundColor(.themeGray500)
               }
            }
            .font(.system(size: 14))
            .padding(.trailing, 4)
            .onTapGesture {
               withAnimation { tab = "bluetooth" }
            }
            .pointingHandCursor()
        }
        .padding(.horizontal, 24) // px-6
        .padding(.vertical, 16) // py-4
        .background(Color.themeGray900.opacity(0.8)) // bg-gray-900/80
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.themeBorder).allowsHitTesting(false), alignment: .bottom)
    }
    
    /// 标签页视图
    private var tabsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { // gap-2
                TabButtonLucide(key: "ai", label: "AI 提炼设置", icon: .sparkles, current: $tab)
                TabButtonLucide(key: "history", label: "记录设置", icon: .database, current: $tab)
                TabButtonLucide(key: "bluetooth", label: "蓝牙设置", icon: .bluetooth, current: $tab)
                TabButtonLucide(key: "window", label: "悬浮窗设置", icon: .appWindowMac, current: $tab)
                TabButtonLucide(key: "memory", label: "内存监控", icon: .cpu, current: $tab)
            }
            .padding(.horizontal, 24) // px-6
            .padding(.vertical, 12) // py-3
        }
        .background(Color.themeGray800.opacity(0.8)) // bg-gray-800/80
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.themeBorder).allowsHitTesting(false), alignment: .bottom)
    }
    
    /// 内容视图
    @ViewBuilder
    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { // 回到 VStack，LazyVStack 在某些情况下可能导致性能问题
                switch tab {
                case "ai": aiTab
                case "history": historyTab
                case "bluetooth": bluetoothTab
                case "window": windowTab
                case "memory": memoryTab
                default: EmptyView()
                }
            }
            .padding(24) // p-6
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Fill available space
    }
    
    /// 底部视图
    private var footerView: some View {
        HStack {
            // API Key / Status Info (Added based on feedback "缺少数据")
            VStack(alignment: .leading, spacing: 2) {
                if tab == "ai" {
                    Text("API: \(store.aiProvider == .openai ? "OpenAI" : "Local")")
                         .font(.system(size: 10, design: .monospaced))
                         .foregroundColor(.themeGray500)
                    Text(store.aiProvider == .openai ? "Model: \((store.ai as? AIService)?.openAIModel ?? "unknown")" : "Local Service")
                         .font(.system(size: 10, design: .monospaced))
                         .foregroundColor(.themeGray600)
                } else if tab == "history" {
                     Text("记录条数: \(store.records.count) (已过滤: 0)")
                         .font(.system(size: 10))
                         .foregroundColor(.themeGray500)
                     Text("AI: \(store.enableAI ? "ON" : "OFF") (阈值 > \(store.summaryTrigger) 字符)")
                         .font(.system(size: 10))
                         .foregroundColor(.themeGray600)
                }
            }
            
            Spacer()
            Button(action: {
                withAnimation { showSettings = false }
                store.postToast("配置已保存。", type: "success")
            }) {
                HStack(spacing: 8) {
                    LucideView(name: .save, size: 16, color: .white)
                    Text("保存设置")
                }
                .font(.system(size: 14, weight: .medium)) // text-sm
                .foregroundColor(.white)
                .padding(.horizontal, 16) // px-4
                .padding(.vertical, 8) // py-2
                .background(Color.themeBlue600) // bg-blue-600
                .cornerRadius(8) // rounded-lg
                .shadow(color: Color.themeBlue600.opacity(0.2), radius: 10, y: 5) // shadow-lg
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(16) // p-4
        .background(Color.themeGray900.opacity(0.5)) // bg-gray-900/50
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.themeBorder).allowsHitTesting(false), alignment: .top)
    }

    /// AI 设置内容
    private var aiTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Toggle Section
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        LucideView(name: .sparkles, size: 14, color: .themeYellow500)
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
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05)).allowsHitTesting(false))
            
            if store.enableAI {
                // Sliders
                VStack(alignment: .leading, spacing: 16) {
                    Text("提炼行为约束")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.themeGray300)
                        
                    NativeSliderRow(label: "总结触发长度", value: Binding(
                        get: { Double(store.summaryTrigger) }, set: { store.summaryTrigger = Int($0); store.savePreferences() }
                    ), range: 10...500)

                    NativeSliderRow(label: "标题长度限制", value: Binding(
                        get: { Double(store.titleLimit) }, set: { store.titleLimit = Int($0); store.savePreferences() }
                    ), range: 10...40)

                    NativeSliderRow(label: "总结长度限制", value: Binding(
                        get: { Double(store.summaryLimit) }, set: { store.summaryLimit = Int($0); store.savePreferences() }
                    ), range: 50...300)
                }
                .padding(16)
                .background(Color.black.opacity(0.2))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05)).allowsHitTesting(false))
                
                // Provider Selection
                VStack(alignment: .leading, spacing: 8) {
                    LucideLabel(icon: .link, text: "模型服务商与连接", size: 12, color: .themeGray400)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.themeGray400)
                    
                    HStack(spacing: 8) {
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
                    
                    CustomTextField(label: "Base URL", placeholder: "https://api.openai.com/v1", text: Binding(
                        get: { (store.ai as? AIService)?.openAIBaseURL ?? "https://api.openai.com/v1" },
                        set: { store.configureOpenAI(apiKey: KeychainHelper.shared.read(service: "QuiteNote", account: "openai_api_key") ?? "", baseURL: $0, model: (store.ai as? AIService)?.openAIModel ?? "gpt-4o-mini") }
                    ))
                    
                    CustomTextField(label: "Model", placeholder: "gpt-4o-mini", text: Binding(
                        get: { (store.ai as? AIService)?.openAIModel ?? "gpt-4o-mini" },
                        set: { store.configureOpenAI(apiKey: KeychainHelper.shared.read(service: "QuiteNote", account: "openai_api_key") ?? "", baseURL: (store.ai as? AIService)?.openAIBaseURL ?? "https://api.openai.com/v1", model: $0) }
                    ))
                    
                    // API测试按钮
                    Button(action: {
                        testAPIConnection()
                    }) {
                        HStack {
                            if isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                LucideView(name: .check, size: 12, color: .white)
                            }
                            Text(isTestingConnection ? "测试中..." : "测试连接")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.themeBlue600)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isTestingConnection)
                }
                .padding(16)
                .background(Color.black.opacity(0.2))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05)).allowsHitTesting(false))
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
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05)).allowsHitTesting(false))
            
            VStack(spacing: 16) {
                NativeSliderRow(label: "记录保留条数", value: Binding(
                    get: { Double(store.maxRecords) }, set: { store.maxRecords = Int($0); store.savePreferences() }
                ), range: 50...1000, step: 50)
                
                Text("当前版本模拟限制在 \(store.maxRecords) 条。生产版可配置。")
                    .font(.system(size: 10))
                    .foregroundColor(.themeGray500)
            }
            .padding(16)
            .background(Color.black.opacity(0.2))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05)).allowsHitTesting(false))
            
            // Export Button
            Button(action: {
                exportRecords()
            }) {
                HStack {
                    LucideView(name: .fileText, size: 12, color: .themeGray400)
                    Text("导出所有记录 (Markdown/TXT)")
                }
                .font(.system(size: 12, weight: .medium)) // text-xs
                .foregroundColor(.themeGray400)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1).allowsHitTesting(false))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .onHover { isHovered in
                if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            
            // Clear History Button
            Button(action: {
                store.clearAll()
                store.postToast("已清空所有记录", type: "success")
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

    /// 蓝牙设置内容
    private var bluetoothTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("连接状态").font(.system(size: 14, weight: .medium)).foregroundColor(.themeTextPrimary)
                    Text(bluetooth.connectedDeviceName != nil ? "已连接: \(bluetooth.connectedDeviceName!)" : (bluetooth.state == .poweredOn ? "未连接" : "蓝牙未开启"))
                        .font(.system(size: 10))
                        .foregroundColor(bluetooth.connectedDeviceName != nil ? .themeGreen500 : .themeGray500)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button(action: {
                        bluetooth.startScanning()
                    }) {
                        Text("扫描设备")
                            .font(.system(size: 12))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.themeBlue600)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    if bluetooth.connectedDeviceName != nil {
                        Button(action: {
                            bluetooth.disconnect()
                        }) {
                            Text("断开")
                                .font(.system(size: 12))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.themeRed600)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05)).allowsHitTesting(false))
            
            // 设备列表
            if !bluetooth.discoveredPeripherals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("发现的设备")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.themeGray400)
                    
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(bluetooth.discoveredPeripherals, id: \.identifier) { peripheral in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(peripheral.name ?? "未知设备")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.themeTextPrimary)
                                        Text(peripheral.identifier.uuidString)
                                            .font(.system(size: 10))
                                            .foregroundColor(.themeGray500)
                                    }
                                    
                                    Spacer()
                                    
                                    if bluetooth.connectedDeviceName == peripheral.name {
                                        Text("已连接")
                                            .font(.system(size: 10))
                                            .foregroundColor(.themeGreen500)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.themeGreen500.opacity(0.2))
                                            .cornerRadius(4)
                                    } else {
                                        Button(action: {
                                            bluetooth.connect(to: peripheral)
                                        }) {
                                            Text("连接")
                                                .font(.system(size: 10))
                                                .foregroundColor(.themeBlue500)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.themeBlue500.opacity(0.2))
                                                .cornerRadius(4)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05)).allowsHitTesting(false))
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
            
            VStack(spacing: 16) {
                NativeSliderRow(label: "硬件防抖", value: Binding(
                    get: { bluetooth.debounceInterval }, set: { bluetooth.debounceInterval = $0 }
                ), range: 0.5...3.0)
            }
            .padding(16)
            .background(Color.black.opacity(0.2))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05)).allowsHitTesting(false))
        }
    }

    /// 悬浮窗设置内容
    private var windowTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToggleRow(title: "位置锁定", subtitle: "开启后悬浮窗不可拖拽移动", isOn: $windowLock)
                .onAppear {
                    windowLock = PreferencesManager.shared.windowLock
                }
                .onChange(of: windowLock) { newValue in
                    PreferencesManager.shared.setWindowLock(newValue)
                    NotificationCenter.default.post(name: .windowLockChanged, object: newValue)
                }
            
            ToggleRow(title: "动效开关", subtitle: "开启/关闭窗口淡入淡出动画", isOn: $animationsEnabled)
                .onAppear {
                    animationsEnabled = PreferencesManager.shared.animationsEnabled
                }
                .onChange(of: animationsEnabled) { newValue in
                    PreferencesManager.shared.setAnimationsEnabled(newValue)
                    NotificationCenter.default.post(name: .animationsEnabledChanged, object: newValue)
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
    
    /// 内存监控内容
    private var memoryTab: some View {
        MemoryMonitorView()
    }
    
    /// 导出记录功能
    private func exportRecords() {
        // 生成导出内容
        let markdownContent = store.exportMarkdown()
        
        // 创建保存面板
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        savePanel.nameFieldStringValue = "QuiteNote_导出_\(formatter.string(from: Date())).md"
        
        // 显示保存面板并处理用户选择
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try markdownContent.write(to: url, atomically: true, encoding: .utf8)
                    DispatchQueue.main.async {
                        store.postToast("导出成功！文件已保存至: \(url.path)", type: "success")
                    }
                } catch {
                    DispatchQueue.main.async {
                        store.postToast("导出失败: \(error.localizedDescription)", type: "error")
                    }
                }
            }
        }
    }
    
    /// 测试API连接
    private func testAPIConnection() {
        isTestingConnection = true
        
        guard let aiService = store.ai as? AIService else {
            store.postToast("AI服务不可用", type: "error")
            isTestingConnection = false
            return
        }
        
        aiService.testConnection { result in
            DispatchQueue.main.async {
                self.isTestingConnection = false
                
                switch result {
                case .success:
                    self.store.postToast("API连接测试成功！", type: "success")
                case .failure(let error):
                    self.store.postToast("API连接测试失败: \(error.localizedDescription)", type: "error")
                }
            }
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
        let isSelected = current == key
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { current = key } }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
            }
            .padding(.horizontal, 12) // px-3
            .padding(.vertical, 6) // py-1.5
            .foregroundColor(isSelected ? .white : .themeGray400)
            .background(isSelected ? Color.themeBlue600 : Color.white.opacity(0.05))
            .cornerRadius(16) // rounded-full
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

struct TabButtonLucide: View {
    let key: String
    let label: String
    let icon: IconName
    @Binding var current: String
    
    var body: some View {
        let isSelected = current == key
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { current = key } }) {
            HStack(spacing: 4) {
                LucideView(name: icon, size: 12, color: isSelected ? .white : .themeGray400)
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
            }
            .padding(.horizontal, 12) // px-3
            .padding(.vertical, 6) // py-1.5
            .foregroundColor(isSelected ? .white : .themeGray400)
            .background(isSelected ? Color.themeBlue600 : Color.white.opacity(0.05))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}
struct CustomToggle: View {
    @Binding var isOn: Bool
    
    var body: some View {
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
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3)) {
                isOn.toggle()
            }
        }
        .pointingHandCursor()
    }
}

struct ProviderButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? .white : .themeGray400)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.themeBlue600 : Color.white.opacity(0.05))
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.1), lineWidth: 1).allowsHitTesting(false))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
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
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.themeGray500)
                .textCase(.uppercase) // uppercase tracking-wider
                .tracking(1)
            
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(.themeGray200)
            .padding(8)
            .background(Color.black.opacity(0.4)) // bg-black/40
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.themeBorder).allowsHitTesting(false))
        }
    }
}

struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundColor(.themeTextPrimary)
                Text(subtitle).font(.system(size: 10)).foregroundColor(.themeGray500)
            }
            Spacer()
            CustomToggle(isOn: $isOn)
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05)).allowsHitTesting(false))
    }
}
