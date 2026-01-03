import SwiftUI

/// YellowWireframe 可见性测试视图
/// 用于验证不同参数组合下线框的可见性
struct YellowWireframeTestView: View {
    @State private var showHandles = false
    @State private var isDashed = true
    @State private var opacity: Double = 1.0
    @State private var showBackground = false
    @State private var isEditing = false
    @State private var isLongScreenshotMode = false

    var body: some View {
        VStack(spacing: 20) {
            Text("YellowWireframe 可见性测试")
                .font(.title)
                .padding()

            // 测试区域
            ZStack {
                // 背景
                Color.gray.opacity(0.3)

                // 测试线框
                let rect = CGRect(x: 50, y: 50, width: 200, height: 150)
                YellowWireframe(
                    rect: rect,
                    label: "200 x 150",
                    isDashed: isDashed,
                    showBackground: showBackground,
                    isEditing: isEditing,
                    isLongScreenshotMode: isLongScreenshotMode,
                    opacity: opacity,
                    showHandles: showHandles
                )
            }
            .frame(width: 350, height: 300)
            .border(Color.black, width: 1)

            // 控制面板
            VStack(alignment: .leading, spacing: 10) {
                Toggle("显示手柄 (showHandles)", isOn: $showHandles)
                Toggle("虚线 (isDashed)", isOn: $isDashed)
                Toggle("显示背景 (showBackground)", isOn: $showBackground)
                Toggle("编辑模式 (isEditing)", isOn: $isEditing)
                Toggle("长图模式 (isLongScreenshotMode)", isOn: $isLongScreenshotMode)

                HStack {
                    Text("透明度 (opacity):")
                    Slider(value: $opacity, in: 0...1)
                    Text("\(opacity, specifier: "%.2f")")
                        .frame(width: 40)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)

            // 测试说明
            VStack(alignment: .leading, spacing: 5) {
                Text("测试说明:")
                    .font(.headline)
                Text("• 线框应该在灰色背景上清晰可见")
                Text("• 透明度为 0 时线框不可见")
                Text("• showHandles=true 且 isEditing=false 且 isLongScreenshotMode=false 时显示 8 个手柄")
                Text("• showBackground 参数当前未使用")
            }
            .font(.caption)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }
}

#Preview {
    YellowWireframeTestView()
}
