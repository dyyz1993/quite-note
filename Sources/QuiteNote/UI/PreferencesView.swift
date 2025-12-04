import SwiftUI

/// 偏好设置窗口：分标签页配置蓝牙、记录、AI、窗体与热力图
struct PreferencesView: View {
    @State private var enableAI: Bool = true
    @State private var titleLimit: Int = 20
    @State private var summaryTrigger: Int = 20
    @State private var summaryLimit: Int = 100

    /// 构建偏好设置基本页面
    var body: some View {
        TabView {
            Form {
                Toggle("启用 AI 自动提炼", isOn: $enableAI)
                Stepper("标题长度限制：\(titleLimit)", value: $titleLimit, in: 15...30)
                Stepper("总结触发长度：\(summaryTrigger)", value: $summaryTrigger, in: 0...200)
                Stepper("总结长度限制：\(summaryLimit)", value: $summaryLimit, in: 50...200)
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

