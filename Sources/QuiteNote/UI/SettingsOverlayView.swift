import SwiftUI
import UniformTypeIdentifiers

/// 右上角设置面板：AI、记录、蓝牙、窗口标签页
struct SettingsOverlayView: View {
    @ObservedObject var store: RecordStore
    @ObservedObject var bluetooth: BluetoothManager
    @ObservedObject private var prefs = PreferencesManager.shared
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
        HStack(spacing: 12) {
            Button(action: { withAnimation { showSettings = false } }) {
                LucideView(name: .chevronLeft, size: 20, color: .themeTextSecondary)
                    .padding(6)
                    .background(Color.themeHoverLight)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            
            Text("偏好设置")
                .font(.themeH2)
                .foregroundColor(.themeTextPrimary)
            
            Spacer()
            
            // Bluetooth Status Icon
            HStack(spacing: 6) {
               if let name = bluetooth.connectedDeviceName {
                   LucideView(name: .bluetooth, size: 14, color: .themeBlue400)
                   Text(name)
                       .font(.themeCaption)
                       .foregroundColor(.themeBlue400)
               } else if bluetooth.state == .poweredOn {
                   LucideView(name: .bluetooth, size: 14, color: .themeYellow500)
               } else {
                   LucideView(name: .bluetoothOff, size: 14, color: .themeTextTertiary)
               }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.themeHoverLight)
            .cornerRadius(12)
            .onTapGesture {
               withAnimation { tab = "bluetooth" }
            }
            .pointingHandCursor()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.themeGray900.opacity(0.8))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.themeBorder).allowsHitTesting(false), alignment: .bottom)
    }
    
    /// 标签页视图
    private var tabsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                TabButtonLucide(key: "ai", label: "AI", icon: .sparkles, current: $tab)
                TabButtonLucide(key: "history", label: "记录", icon: .database, current: $tab)
                TabButtonLucide(key: "bluetooth", label: "蓝牙", icon: .bluetooth, current: $tab)
                TabButtonLucide(key: "window", label: "悬浮窗", icon: .layout, current: $tab)
                TabButtonLucide(key: "screenshot", label: "截图", icon: .camera, current: $tab)
                TabButtonLucide(key: "file", label: "文件", icon: .folder, current: $tab)
                TabButtonLucide(key: "memory", label: "监控", icon: .cpu, current: $tab)
                TabButtonLucide(key: "symbols", label: "符号", icon: .square, current: $tab)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .background(Color.themeGray800.opacity(0.5))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.themeBorder).allowsHitTesting(false), alignment: .bottom)
    }
    
    /// 内容视图
    @ViewBuilder
    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch tab {
                case "ai": AISettingsTab(store: store, isTestingConnection: $isTestingConnection)
                case "history": HistorySettingsTab(store: store)
                case "bluetooth": BluetoothSettingsTab(bluetooth: bluetooth)
                case "window": WindowSettingsTab()
                case "screenshot": ScreenshotSettingsTab()
                case "file": FileSettingsTab(store: store)
                case "memory": MemorySettingsTab()
                case "symbols": SymbolSettingsTab()
                default: EmptyView()
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    /// 底部视图
    private var footerView: some View {
        HStack {
            // API Key / Status Info
            VStack(alignment: .leading, spacing: 4) {
                if tab == "ai" {
                    HStack(spacing: 4) {
                        LucideView(name: .link, size: 10, color: .themeTextTertiary)
                        Text("API: OpenAI")
                            .font(.themeCaptionSmall)
                            .monospaced()
                            .foregroundColor(.themeTextTertiary)
                    }
                    HStack(spacing: 4) {
                        LucideView(name: .box, size: 10, color: .themeTextTertiary)
                        Text("Model: \((store.ai as? AIService)?.openAIModel ?? "unknown")")
                            .font(.themeCaptionSmall)
                            .monospaced()
                            .foregroundColor(.themeTextTertiary)
                    }
                } else if tab == "history" {
                    Text("记录条数: \(store.records.count)")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                    Text("AI 提炼: \(store.enableAI ? "已开启" : "已关闭")")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                } else if tab == "symbols" {
                    Text("符号库: \(SymbolConfigManager.shared.configs.count) 个")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                    Text("触发前缀: :/")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                } else {
                    Text(tab == "bluetooth" ? "蓝牙设备状态" : "设置已就绪")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
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
                .font(.themeBody)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.themeBlue600)
                .cornerRadius(10)
                .shadow(color: Color.themeShadowBlue, radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(20)
        .background(Color.themeGray900.opacity(0.6))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.themeBorder).allowsHitTesting(false), alignment: .top)
    }
}

// MARK: - Helper Components

/// 变量徽章
struct VariableBadge: View {
    let text: String
    var color: Color = .themeBlue400
    
    var body: some View {
        Text(text)
            .font(.themeCaptionTiny)
            .monospaced()
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(color.opacity(0.2), lineWidth: 0.5)
            )
    }
}

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
            .foregroundColor(isSelected ? .white : .themeTextSecondary)
            .background(isSelected ? Color.themeSelected : Color.themeHoverLight)
            .cornerRadius(16) // rounded-full
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.themeBorder, lineWidth: isSelected ? 0 : 1)
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
                LucideView(name: icon, size: 12, color: isSelected ? .white : .themeTextSecondary)
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
            }
            .padding(.horizontal, 12) // px-3
            .padding(.vertical, 6) // py-1.5
            .foregroundColor(isSelected ? .white : .themeGray400)
            .background(isSelected ? Color.themeSelected : Color.themeHoverLight)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.themeBorder, lineWidth: isSelected ? 0 : 1)
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
                .foregroundColor(isSelected ? .white : .themeTextSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.themeSelected : Color.themeHoverLight)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.themeBorder, lineWidth: 1).allowsHitTesting(false))
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
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.themeCaptionSmall)
                .fontWeight(.bold)
                .foregroundColor(.themeTextSecondary)
                .textCase(.uppercase)
                .tracking(1)
            
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.themeBody)
            .foregroundColor(.themeTextPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.themeInput)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.themeBorder, lineWidth: 1)
            )
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
        .background(Color.themeHoverLight)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeBorderSubtle).allowsHitTesting(false))
    }
}
