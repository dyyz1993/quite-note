import SwiftUI
import UniformTypeIdentifiers

/// 右上角设置面板：AI、记录、窗口标签页
struct SettingsOverlayView: View {
    @ObservedObject var store: RecordStore
    @ObservedObject var bluetooth: BluetoothManager
    @ObservedObject private var prefs = PreferencesManager.shared
    @Binding var showSettings: Bool
    private let allowsDismissal: Bool
    @State private var tab: String
    @State private var isTestingConnection = false
    @State private var windowLock = false
    @State private var animationsEnabled = true
    @State private var rememberWindowPosition = true
    /// 反馈表单状态（视图与 footer「发送反馈」主按钮共享）
    @StateObject private var feedbackModel = FeedbackFormModel()

    init(
        store: RecordStore,
        bluetooth: BluetoothManager,
        showSettings: Binding<Bool>,
        initialTab: String = "ai",
        allowsDismissal: Bool = true
    ) {
        self.store = store
        self.bluetooth = bluetooth
        self._showSettings = showSettings
        self._tab = State(initialValue: initialTab)
        self.allowsDismissal = allowsDismissal
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
        .onAppear {
            // 状态栏菜单「用户反馈…」入口：打开设置并直接切到反馈 Tab（flag 由 StatusBarController 写入）
            if UserDefaults.standard.bool(forKey: "qn.openFeedbackTabOnShow") {
                tab = "feedback"
                UserDefaults.standard.removeObject(forKey: "qn.openFeedbackTabOnShow")
            }
        }
    }
    
    /// 头部视图
    private var headerView: some View {
        HStack(spacing: 12) {
            if allowsDismissal {
                Button(action: { withAnimation { showSettings = false } }) {
                    LucideView(name: .chevronLeft, size: 20, color: .themeTextSecondary)
                        .padding(6)
                        .background(Color.themeHoverLight)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            
            Text("偏好设置")
                .font(.themeH2)
                .foregroundColor(.themeTextPrimary)
            
            Spacer()
            
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
                TabButtonLucide(key: "clipboard", label: "剪贴板", icon: .clipboardList, current: $tab)
                TabButtonLucide(key: "launcher", label: "启动器", icon: .appWindowMac, current: $tab)
                TabButtonLucide(key: "window", label: "悬浮窗", icon: .layout, current: $tab)
                TabButtonLucide(key: "screenshot", label: "截图", icon: .camera, current: $tab)
                TabButtonLucide(key: "recording", label: "录屏", icon: .video, current: $tab)
                TabButtonLucide(key: "file", label: "文件", icon: .folder, current: $tab)
                TabButtonLucide(key: "memory", label: "监控", icon: .cpu, current: $tab)
                TabButtonLucide(key: "symbols", label: "符号", icon: .square, current: $tab)
                TabButtonLucide(key: "feedback", label: "反馈", icon: .bug, current: $tab)
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
                case "clipboard": ClipboardSettingsTab()
                case "launcher": LauncherSettingsTab()
                case "window": WindowSettingsTab()
                case "screenshot": ScreenshotSettingsTab()
                case "recording": RecordingSettingsTab()
                case "file": FileSettingsTab(store: store)
                case "memory": MemorySettingsTab()
                case "symbols": SymbolSettingsTab()
                case "feedback": FeedbackSettingsTab(model: feedbackModel)
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
                } else if tab == "clipboard" {
                    Text("存储: 本机 ClipboardHistory 库")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                    Text("OCR: 本地 Vision · 不联网")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                } else if tab == "launcher" {
                    Text("应用目录: \(AppCatalogStore.shared.apps.count) 个应用")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                    Text("拼音转换: 本地 CoreFoundation · 不联网")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                } else if tab == "feedback" {
                    Text("提交后开发者手机实时收到推送")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                    Text(feedbackModel.attachments.isEmpty
                         ? "未附截图（⌘V 可粘贴）"
                         : "已附 \(feedbackModel.attachments.count) 张截图")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                } else if tab == "symbols" {
                    Text("符号库: \(SymbolConfigManager.shared.configs.count) 个")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                    Text("触发前缀: :/")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                    // P2.2: 清除图标缓存按钮
                    Button(action: {
                        NotificationCenter.default.post(name: NSNotification.Name("ClearIconCache"), object: nil)
                    }) {
                        HStack(spacing: 4) {
                            LucideView(name: .refreshCw, size: 10, color: .themeBlue400)
                            Text("重载图标")
                        }
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeBlue400)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.themeBlue500.opacity(0.1))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .help("清除图标缓存并重新加载")
                } else {
                    Text("设置已就绪")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                }
            }
            
            Spacer()

            // 主按钮按 Tab 定制：只有真"提交"类 Tab 才有按钮（反馈=发送反馈）。
            // 其余 Tab 偏好均为即时写入（改动即生效），无保存语义 → 不放按钮
            //（2026-09-11 与用户确认）。未来引入草稿/显式保存模式的 Tab，
            // 必须做脏检测（无改动时禁用）再放"保存"按钮。
            if tab == "feedback" {
                Button(action: {
                    feedbackModel.sendFeedback(entry: "prefs")
                }) {
                    HStack(spacing: 8) {
                        if feedbackModel.sending {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            LucideView(name: .upload, size: 16, color: .white)
                        }
                        Text(feedbackModel.sending ? "发送中…" : "发送反馈")
                    }
                    .font(.themeBody)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(feedbackModel.canSubmit ? Color.themeBlue600 : Color.themeGray600)
                    .cornerRadius(10)
                    .shadow(color: feedbackModel.canSubmit ? Color.themeShadowBlue : .clear, radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .disabled(!feedbackModel.canSubmit)
            }
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
