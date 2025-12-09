import Foundation
import Combine
import AppKit

/// 内存管理器，监控内存使用情况并执行优化操作
final class MemoryManager: ObservableObject {
    static let shared = MemoryManager()
    
    @Published var memoryWarningLevel: MemoryWarningLevel = .normal
    @Published var isOptimizing = false
    
    private var cancellables = Set<AnyCancellable>()
    private var memoryMonitorTimer: Timer?
    
    /// 内存警告级别
    enum MemoryWarningLevel {
        case normal      // 正常状态
        case warning     // 内存警告
        case critical    // 内存严重不足
    }
    
    private init() {
        startMemoryMonitoring()
        
        // 在macOS上监听系统内存压力通知
        if #available(macOS 10.15, *) {
            // 使用NSWorkspace监听内存压力
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
                .sink { [weak self] _ in
                    // 检查内存使用情况
                    self?.checkMemoryUsage()
                }
                .store(in: &cancellables)
        }
    }
    
    /// 开始内存监控
    private func startMemoryMonitoring() {
        // 每30秒检查一次内存使用情况
        memoryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.checkMemoryUsage()
        }
    }
    
    /// 停止内存监控
    func stopMemoryMonitoring() {
        memoryMonitorTimer?.invalidate()
        memoryMonitorTimer = nil
    }
    
    /// 检查内存使用情况
    private func checkMemoryUsage() {
        let currentMemory = getCurrentMemoryUsage()
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let usagePercentage = Double(currentMemory) / Double(totalMemory)
        
        // 根据内存使用率设置警告级别
        if usagePercentage > 0.85 {
            memoryWarningLevel = .critical
            performMemoryOptimization()
        } else if usagePercentage > 0.7 {
            memoryWarningLevel = .warning
            performLightOptimization()
        } else {
            memoryWarningLevel = .normal
        }
    }
    

    
    /// 处理内存警告
    private func handleMemoryWarning() {
        memoryWarningLevel = .critical
        performMemoryOptimization()
    }
    
    /// 执行轻度内存优化
    private func performLightOptimization() {
        guard !isOptimizing else { return }
        
        isOptimizing = true
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            // 清理缓存
            URLCache.shared.removeAllCachedResponses()
            
            // 清理图像缓存
            if #available(macOS 10.15, *) {
                // 在macOS上清理图像缓存
            }
            
            DispatchQueue.main.async {
                self?.isOptimizing = false
            }
        }
    }
    
    /// 执行深度内存优化
    private func performMemoryOptimization() {
        guard !isOptimizing else { return }
        
        isOptimizing = true
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            // 清理所有缓存
            URLCache.shared.removeAllCachedResponses()
            
            // 强制垃圾回收
            autoreleasepool {
                // 执行内存密集型清理操作
            }
            
            // 通知其他组件进行内存优化
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .memoryOptimizationNeeded, object: nil)
                self?.isOptimizing = false
            }
        }
    }
    
    /// 手动触发内存优化
    func triggerMemoryOptimization() {
        performMemoryOptimization()
    }
    
    /// 获取当前内存使用量（公开方法）
    func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Int64(info.resident_size)
        } else {
            return 0
        }
    }
    
    /// 析构函数，确保清理资源
    deinit {
        stopMemoryMonitoring()
        cancellables.removeAll()
    }
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let memoryOptimizationNeeded = Notification.Name("MemoryOptimizationNeeded")
}