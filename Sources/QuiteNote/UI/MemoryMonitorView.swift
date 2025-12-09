import SwiftUI
import AppKit

/// 内存监控视图，显示当前应用的内存使用情况
struct MemoryMonitorView: View {
    @StateObject private var memoryManager = MemoryManager.shared
    @State private var currentMemoryUsage: Int64 = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("内存监控")
                .font(.themeH1)
                .foregroundColor(.themeTextPrimary)
            
            // 内存使用情况
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("当前内存使用:")
                        .font(.system(size: 14))
                        .foregroundColor(.themeTextSecondary)
                    
                    Spacer()
                    
                    Text(formatMemorySize(currentMemoryUsage))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(memoryColor)
                }
                
                // 内存使用进度条
                ProgressView(value: memoryUsagePercentage)
                    .progressViewStyle(LinearProgressViewStyle(tint: memoryColor))
                    .scaleEffect(y: 1.5)
                
                HStack {
                    Text("警告级别:")
                        .font(.system(size: 14))
                        .foregroundColor(.themeTextSecondary)
                    
                    Spacer()
                    
                    Text(memoryWarningText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(memoryColor)
                }
            }
            .padding()
            .background(Color.themeItem)
            .cornerRadius(8)
            
            // 操作按钮
            HStack {
                Button(action: {
                    memoryManager.triggerMemoryOptimization()
                    updateMemoryUsage()
                }) {
                    HStack {
                        LucideView(name: .cpu, size: 14, color: .white)
                        Text("优化内存")
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.themeBlue500)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                
                Spacer()
                
                if memoryManager.isOptimizing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("优化中...")
                            .font(.system(size: 12))
                            .foregroundColor(.themeTextSecondary)
                    }
                }
            }
        }
        .onAppear {
            updateMemoryUsage()
        }
        .onChange(of: memoryManager.memoryWarningLevel) { _ in
            // 当内存警告级别变化时，更新内存使用量
            updateMemoryUsage()
        }
    }
    
    /// 内存使用百分比
    private var memoryUsagePercentage: Double {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        return min(Double(currentMemoryUsage) / Double(totalMemory), 1.0)
    }
    
    /// 内存颜色
    private var memoryColor: Color {
        switch memoryManager.memoryWarningLevel {
        case .normal:
            return .themeGreen500
        case .warning:
            return .themeYellow500
        case .critical:
            return .themeRed500
        }
    }
    
    /// 内存警告文本
    private var memoryWarningText: String {
        switch memoryManager.memoryWarningLevel {
        case .normal:
            return "正常"
        case .warning:
            return "警告"
        case .critical:
            return "严重"
        }
    }
    
    /// 格式化内存大小
    private func formatMemorySize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }
    
    /// 更新内存使用情况
    private func updateMemoryUsage() {
        currentMemoryUsage = memoryManager.getCurrentMemoryUsage()
    }
    

}

#Preview {
    MemoryMonitorView()
        .padding()
        .frame(width: 300)
        .background(Color.themeBackground)
}