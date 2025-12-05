import SwiftUI

/// 偏好设置窗口：分标签页配置蓝牙、记录、AI、窗体与热力图
struct PreferencesView: View {
    @ObservedObject var store: RecordStore
    @ObservedObject var bluetooth: BluetoothManager

    init(store: RecordStore, bluetooth: BluetoothManager) {
        self.store = store
        self.bluetooth = bluetooth
    }

    /// 构建偏好设置基本页面
    var body: some View {
        TabView {
            Form {
                Toggle("启用 AI 自动提炼", isOn: Binding(
                    get: { store.enableAI },
                    set: { store.enableAI = $0; store.savePreferences() }
                ))

                if store.enableAI {
                    NativeSliderRow(label: "标题长度限制", value: Binding(
                        get: { Double(store.titleLimit) }, set: { store.titleLimit = Int($0); store.savePreferences() }
                    ), range: 15...30, displayValue: "\(store.titleLimit) 字符")

                    NativeSliderRow(label: "总结触发长度", value: Binding(
                        get: { Double(store.summaryTrigger) }, set: { store.summaryTrigger = Int($0); store.savePreferences() }
                    ), range: 0...200, displayValue: "> \(store.summaryTrigger) 字符")

                    NativeSliderRow(label: "总结长度限制", value: Binding(
                        get: { Double(store.summaryLimit) }, set: { store.summaryLimit = Int($0); store.savePreferences() }
                    ), range: 50...200, displayValue: "\(store.summaryLimit) 字符")
                }
            }
            .padding()
            .tabItem { Label("AI 提炼设置", systemImage: "sparkles") }

            Text("蓝牙设置占位")
                .padding()
                .tabItem { Label("蓝牙设置", systemImage: "link") }

            Text("记录设置占位")
                .padding()
                .tabItem { Label("记录设置", systemImage: "note.text") }

            Text("悬浮窗设置占位")
                .padding()
                .tabItem { Label("悬浮窗设置", systemImage: "rectangle.on.rectangle") }

            Text("热力图设置占位")
                .padding()
                .tabItem { Label("热力图设置", systemImage: "chart.xyaxis.line") }
        }
        .frame(width: 520, height: 360)
    }
}

