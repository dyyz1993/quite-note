import SwiftUI
import AppKit

/// 内存监控视图，显示系统内存使用情况
struct MemoryMonitorView: View {
    @StateObject private var memoryManager = MemoryManager.shared
    @State private var systemMemoryUsage: Int64 = 0
    @State private var appMemoryUsage: Int64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 状态卡片
            statusSection

            // 详细信息
            detailSection

            // 操作按钮
            actionSection
        }
        .onAppear {
            updateMemoryUsage()
        }
        .onChange(of: memoryManager.memoryWarningLevel) { _ in
            updateMemoryUsage()
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        HStack(spacing: 16) {
            // 图标圆圈
            memoryIcon
                .frame(width: 56, height: 56)
                .background(memoryColor.opacity(0.2))
                .cornerRadius(28)

            VStack(alignment: .leading, spacing: 4) {
                Text("内存状态")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
                Text(memoryStatusDescription)
                    .font(.themeCaption)
                    .foregroundColor(.themeTextTertiary)
            }

            Spacer()

            // 内存大小显示
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatMemorySize(systemMemoryUsage))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(memoryColor)
                Text(memoryWarningText)
                    .font(.system(size: 11))
                    .foregroundColor(.themeTextTertiary)
            }
        }
        .padding(20)
        .background(Color.themeGray800.opacity(0.4) as Color)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05) as Color))
    }

    private var memoryIcon: some View {
        Group {
            switch memoryManager.memoryWarningLevel {
            case .normal:
                LucideView(name: .cpu, size: 28, color: .themeGreen500)
            case .warning:
                LucideView(name: .cpu, size: 28, color: .themeYellow500)
            case .critical:
                LucideView(name: .cpu, size: 28, color: .themeRed500)
            }
        }
    }

    private var memoryStatusDescription: String {
        switch memoryManager.memoryWarningLevel {
        case .normal:
            return "系统内存正常"
        case .warning:
            return "系统内存偏高"
        case .critical:
            return "系统内存严重"
        }
    }

    // MARK: - Detail Section

    private var detailSection: some View {
        VStack(spacing: 8) {
            // 系统内存使用进度
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("系统使用率")
                        .font(.system(size: 12))
                        .foregroundColor(.themeTextSecondary)
                    Spacer()
                    Text("\(Int(memoryUsagePercentage * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(memoryColor)
                }

                ProgressView(value: memoryUsagePercentage)
                    .progressViewStyle(LinearProgressViewStyle(tint: memoryColor))
                    .scaleEffect(y: 1.5)
            }

            // 内存数据行（应用占用 + 总内存）
            HStack(spacing: 16) {
                // 应用内存
                HStack(spacing: 6) {
                    LucideView(name: .appWindowMac, size: 12, color: .themeTextTertiary)
                    Text("应用")
                        .font(.system(size: 11))
                        .foregroundColor(.themeTextTertiary)
                    Text(formatMemorySize(appMemoryUsage))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.themeTextSecondary)
                }

                Spacer()

                // 总内存
                HStack(spacing: 6) {
                    LucideView(name: .hardDrive, size: 12, color: .themeTextTertiary)
                    Text("总计")
                        .font(.system(size: 11))
                        .foregroundColor(.themeTextTertiary)
                    Text(formatMemorySize(Int64(ProcessInfo.processInfo.physicalMemory)))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.themeTextSecondary)
                }
            }
        }
        .padding(12)
        .background(Color.themeGray800.opacity(0.3))
        .cornerRadius(8)
    }

    // MARK: - Action Section

    private var actionSection: some View {
        HStack(spacing: 12) {
            // 优化内存按钮
            Button(action: {
                memoryManager.triggerMemoryOptimization()
                updateMemoryUsage()
            }) {
                HStack(spacing: 6) {
                    LucideView(name: .cpu, size: 14, color: .white)
                    Text("优化内存")
                }
                .font(.themeBody)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.themeBlue600)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            Spacer()

            // 优化状态
            if memoryManager.isOptimizing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("优化中...")
                        .font(.system(size: 12))
                        .foregroundColor(.themeTextSecondary)
                }
            }
        }
    }

    // MARK: - Computed Properties

    /// 内存使用百分比（系统）
    private var memoryUsagePercentage: Double {
        return memoryManager.getSystemMemoryUsagePercentage()
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

    // MARK: - Methods

    /// 格式化内存大小
    private func formatMemorySize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }

    /// 更新内存使用情况
    private func updateMemoryUsage() {
        systemMemoryUsage = memoryManager.getSystemUsedMemory()
        appMemoryUsage = memoryManager.getCurrentMemoryUsage()
    }
}

#Preview {
    MemoryMonitorView()
        .padding()
        .frame(width: 350)
        .background(Color.themeBackground)
}
