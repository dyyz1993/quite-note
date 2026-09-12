import Foundation

/// QuiteNote 统一通知系统
/// 所有通知使用 "qn." 前缀，避免命名冲突
enum QuiteNoteNotification {
    // MARK: - 蓝牙相关

    /// 蓝牙按钮触发剪贴板捕获
    case bluetoothCaptureClipboard

    /// 蓝牙按钮切换历史面板
    case bluetoothToggleHistory

    /// 蓝牙按钮触发截图
    case bluetoothCaptureScreenshot

    // MARK: - UI 相关

    /// 显示设置面板
    case showSettings

    /// 窗口锁定状态改变
    case windowLockChanged

    /// 动画开关状态改变
    case animationsEnabledChanged

    // MARK: - 记录相关

    /// 记录已添加
    case recordAdded

    /// 记录已更新
    case recordUpdated

    /// 记录已删除
    case recordDeleted

    /// 展开/折叠记录卡片
    case expandRecord

    // MARK: - 便签相关

    /// 便签保存完成（用于通知 StickyNoteManager 标记已同步）
    case stickyNoteSaveCompleted

    /// 从记录打开便签
    case openStickyNoteFromRecord

    // MARK: - 浮动面板相关

    /// 从球模式恢复到面板
    case restoreFromBall

    /// 更新球位置
    case updateBallPosition

    /// 松手后吸附浮球到屏幕边缘（由控制器以 panel.frame 为准计算）
    case snapBallToEdge

    // MARK: - AI 相关

    /// AI 处理开始
    case aiProcessingStarted

    /// AI 处理完成
    case aiProcessingCompleted

    /// AI 处理失败
    case aiProcessingFailed

    // MARK: - 剪贴板历史相关

    /// 新的剪贴板条目被捕获（userInfo: id）
    case clipboardEntryAdded

    /// 打开/切换剪贴板历史面板
    case toggleClipboardHistoryPanel

    /// 剪贴板历史面板已显示（视图据此重置搜索并聚焦）
    case clipboardPanelDidShow

    /// 剪贴板面板已成为 key window（控制器在 windowDidBecomeKey 发出——
    /// 事件驱动聚焦的锚点，替代定时轮询补拉）
    case clipboardPanelDidBecomeKey

    /// 剪贴板条目 OCR 完成（userInfo: id）
    case clipboardOCRCompleted

    // MARK: - 应用启动器相关

    /// 应用启动器面板已显示（视图据此重置搜索、聚焦并重接键盘处理器）
    case appLauncherPanelDidShow

    /// 应用目录扫描完成（视图据此用最新目录重算当前查询）
    case appLauncherCatalogDidUpdate

    // MARK: - 系统相关

    /// 需要内存优化
    case memoryOptimizationNeeded

    /// 将 enum case 转换为 Notification.Name
    var name: Notification.Name {
        switch self {
        case .bluetoothCaptureClipboard:
            return Notification.Name("qn.bluetooth.capture.clipboard")
        case .bluetoothToggleHistory:
            return Notification.Name("qn.bluetooth.toggle.history")
        case .bluetoothCaptureScreenshot:
            return Notification.Name("qn.bluetooth.capture.screenshot")
        case .showSettings:
            return Notification.Name("qn.ui.showSettings")
        case .windowLockChanged:
            return Notification.Name("qn.ui.windowLock.changed")
        case .animationsEnabledChanged:
            return Notification.Name("qn.ui.animations.changed")
        case .recordAdded:
            return Notification.Name("qn.record.added")
        case .recordUpdated:
            return Notification.Name("qn.record.updated")
        case .recordDeleted:
            return Notification.Name("qn.record.deleted")
        case .expandRecord:
            return Notification.Name("qn.record.expand")
        case .stickyNoteSaveCompleted:
            return Notification.Name("qn.stickynote.save.completed")
        case .openStickyNoteFromRecord:
            return Notification.Name("qn.stickynote.open.from.record")
        case .restoreFromBall:
            return Notification.Name("qn.panel.restoreFromBall")
        case .updateBallPosition:
            return Notification.Name("qn.panel.updateBallPosition")
        case .snapBallToEdge:
            return Notification.Name("qn.panel.snapBallToEdge")
        case .aiProcessingStarted:
            return Notification.Name("qn.ai.started")
        case .aiProcessingCompleted:
            return Notification.Name("qn.ai.completed")
        case .aiProcessingFailed:
            return Notification.Name("qn.ai.failed")
        case .clipboardEntryAdded:
            return Notification.Name("qn.clipboard.entry.added")
        case .toggleClipboardHistoryPanel:
            return Notification.Name("qn.clipboard.toggle.panel")
        case .clipboardPanelDidShow:
            return Notification.Name("qn.clipboard.panel.didShow")
        case .clipboardPanelDidBecomeKey:
            return Notification.Name("qn.clipboard.panel.didBecomeKey")
        case .clipboardOCRCompleted:
            return Notification.Name("qn.clipboard.ocr.completed")
        case .appLauncherPanelDidShow:
            return Notification.Name("qn.launcher.panel.didShow")
        case .appLauncherCatalogDidUpdate:
            return Notification.Name("qn.launcher.catalog.didUpdate")
        case .memoryOptimizationNeeded:
            return Notification.Name("qn.system.memory.optimization")
        }
    }
}

// MARK: - 便捷方法

extension QuiteNoteNotification {

    /// 发送通知
    /// - Parameters:
    ///   - notification: 通知类型
    ///   - object: 发送者对象
    ///   - userInfo: 附加信息
    static func post(_ notification: QuiteNoteNotification, object: Any? = nil, userInfo: [String: Any]? = nil) {
        NotificationCenter.default.post(name: notification.name, object: object, userInfo: userInfo)
    }

    /// 订阅通知（闭包方式）
    /// - Parameters:
    ///   - notification: 通知类型
    ///   - observer: 观察者对象
    ///   - handler: 通知处理回调
    /// - Returns: 观察者对象（用于后续移除）
    @discardableResult
    static func observe(
        _ notification: QuiteNoteNotification,
        observer: AnyObject,
        handler: @escaping (Notification) -> Void
    ) -> NSObjectProtocol {
        return NotificationCenter.default.addObserver(forName: notification.name, object: nil, queue: .main) { note in
            handler(note)
        }
    }
}
