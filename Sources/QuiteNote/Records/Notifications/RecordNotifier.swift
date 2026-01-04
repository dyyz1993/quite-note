import Foundation
import Combine

/// 记录通知器：负责发送 Toast 和 Light Hint 通知
final class RecordNotifier {
    // MARK: - Published Properties

    @Published var lightHint: String? = nil
    @Published var toast: ToastMessage? = nil
    @Published var confirmConfig: ConfirmConfig? = nil

    // MARK: - 动画状态追踪

    private var lastProcessedAISuccessAt: Date?
    private var lastProcessedPasteSuccessAt: Date?

    @Published var lastAISuccessAt: Date? = nil
    @Published var lastPasteSuccessAt: Date? = nil

    // MARK: - Light Hint

    /// 发送轻量提示（悬浮窗右下角气泡）
    func postLightHint(_ text: String) {
        lightHint = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.lightHint = nil
        }
    }

    // MARK: - Toast

    /// 顶部右侧 Toast 提示
    func postToast(_ text: String, type: String = "info") {
        toast = ToastMessage(text: text, type: type)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.toast = nil
        }
    }

    // MARK: - Confirmation Dialog

    /// 显示统一确认对话框
    func confirm(
        title: String,
        message: String,
        confirmTitle: String = "确定",
        cancelTitle: String? = "取消",
        isDestructive: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        confirmConfig = ConfirmConfig(
            title: title,
            message: message,
            confirmTitle: confirmTitle,
            cancelTitle: cancelTitle,
            isDestructive: isDestructive,
            action: action
        )
    }

    /// 隐藏确认对话框
    func dismissConfirm() {
        confirmConfig = nil
    }

    // MARK: - 动画状态

    /// 记录 AI 成功时间
    func markAISuccess() {
        lastAISuccessAt = Date()
    }

    /// 记录粘贴成功时间
    func markPasteSuccess() {
        lastPasteSuccessAt = Date()
    }

    /// 检查是否应该显示 AI 成功动画
    /// 只有当成功时间真正更新且与上次处理的时间不同时才返回 true
    func shouldShowAISuccessAnimation() -> Bool {
        guard let newSuccessTime = lastAISuccessAt else { return false }

        // 如果没有处理过的时间，或者时间不同，则应该显示动画
        if lastProcessedAISuccessAt == nil || lastProcessedAISuccessAt! != newSuccessTime {
            lastProcessedAISuccessAt = newSuccessTime
            return true
        }

        return false
    }

    /// 检查是否应该显示粘贴成功动画
    /// 只有当粘贴成功时间真正更新且与上次处理的时间不同时才返回 true
    func shouldShowPasteSuccessAnimation() -> Bool {
        guard let newSuccessTime = lastPasteSuccessAt else { return false }

        // 如果没有处理过的时间，或者时间不同，则应该显示动画
        if lastProcessedPasteSuccessAt == nil || lastProcessedPasteSuccessAt! != newSuccessTime {
            lastProcessedPasteSuccessAt = newSuccessTime
            return true
        }

        return false
    }
}
