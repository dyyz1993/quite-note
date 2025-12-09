import SwiftUI
import AppKit

/// 原生 NSSlider 封装，保证在 macOS 上的拖拽/点击交互稳定
struct NativeSlider: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double? = nil
    var onChange: ((Double) -> Void)? = nil

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: context.coordinator, action: #selector(Coordinator.onChanged(_:)))
        slider.isContinuous = true
        slider.controlSize = .small
        slider.allowsTickMarkValuesOnly = false
        slider.numberOfTickMarks = 0
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return slider
    }

    func updateNSView(_ nsView: NSSlider, context: Context) {
        if nsView.doubleValue != value { nsView.doubleValue = value }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: NativeSlider
        init(_ parent: NativeSlider) { self.parent = parent }
        
        @objc func onChanged(_ sender: NSSlider) {
            var v = sender.doubleValue
            if let step = parent.step, step > 0 {
                let steps = round(v / step)
                v = steps * step
                sender.doubleValue = v
            }
            parent.value = v
            parent.onChange?(v)
        }
    }
}

/// 包含标题与数值显示的行控件，搭配 NativeSlider
struct NativeSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var displayValue: String? = nil
    var step: Double? = nil
    var onChange: ((Double) -> Void)? = nil
    
    /**
     * 计算当前值的显示文本
     * 根据不同的 label 显示不同的单位
     */
    private var currentValueText: String {
        if let displayValue = displayValue {
            return displayValue
        } else {
            if label.contains("触发长度") {
                return "> \(Int(value)) 字符"
            } else if label.contains("长度限制") {
                return "\(Int(value)) 字符"
            } else if label.contains("保留条数") {
                return "\(Int(value)) 条"
            } else if label.contains("防抖") {
                return String(format: "%.1f 秒", value)
            } else {
                return "\(Int(value))"
            }
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Label(label, systemImage: "slider.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundColor(.themeGray400)
                Spacer()
                Text(currentValueText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.themeBlue400)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.themeBlue500.opacity(0.1))
                    .cornerRadius(4)
                    .allowsHitTesting(false)
            }
            NativeSlider(value: $value, range: range, step: step, onChange: onChange)
                .frame(height: 16)
        }
    }
}
