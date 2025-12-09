import AppKit

/// 触觉反馈管理器，提供震动反馈功能
class HapticFeedbackManager {
    
    /// 单例实例
    static let shared = HapticFeedbackManager()
    
    private init() {}
    
    /// 执行轻微震动反馈
    func lightImpact() {
        performFeedback(.generic)
    }
    
    /// 执行中等强度震动反馈
    func mediumImpact() {
        performFeedback(.generic)
    }
    
    /// 执行强烈震动反馈
    func heavyImpact() {
        performFeedback(.generic)
    }
    
    /// 执行成功反馈
    func success() {
        performFeedback(.generic)
    }
    
    /// 执行错误反馈
    func error() {
        performFeedback(.generic)
    }
    
    /// 执行警告反馈
    func warning() {
        performFeedback(.generic)
    }
    
    /// 执行选择反馈（用于滚动、选择等操作）
    func selectionChanged() {
        performFeedback(.generic)
    }
    
    /// 执行实际的触觉反馈
    private func performFeedback(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        // 在主线程上执行触觉反馈
        DispatchQueue.main.async {
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
        }
    }
}