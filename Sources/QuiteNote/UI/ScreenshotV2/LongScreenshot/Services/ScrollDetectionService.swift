import Foundation
import AppKit
import os.log

private let logger = Logger(subsystem: "com.quitenote.app", category: "ScrollDetection")

/// 滚动方向枚举
enum ScrollDirection {
    case none
    case up
    case down
}

/// 滚动检测服务
/// 负责监听全局滚动事件并累计滚动距离
@MainActor
class ScrollDetectionService {
    private var scrollEventHandler: Any?
    private var accumulatedDistance: CGFloat = 0
    private var threshold: CGFloat = 500
    private var selection: CGRect = .zero
    private var screen: NSScreen?
    private var onThresholdReached: (() -> Void)?
    private var lastScrollDirection: ScrollDirection = .none  // 新增：记录上一次滚动方向
    private var lastCaptureTime: Date?  // ✅ 新增：上次捕获时间
    private let minCaptureInterval: TimeInterval = 0.05  // ✅ 修复：减少到50ms（防止跳帧）

    /// 开始监听滚动事件
    func startMonitoring(
        selection: CGRect,
        screen: NSScreen,
        threshold: CGFloat,
        onThresholdReached: @escaping () -> Void
    ) {
        self.selection = selection
        self.screen = screen
        self.threshold = threshold
        self.onThresholdReached = onThresholdReached
        self.accumulatedDistance = 0
        self.lastScrollDirection = .none  // 重置滚动方向

        logger.info("开始监听滚动事件，阈值: \(threshold)")

        // 移除旧的监听器（如果存在）
        stopMonitoring()

        // 添加全局滚动事件监听
        // ⚠️ 使用 addGlobalMonitorForEvents 而不是 addLocalMonitorForEvents
        // 因为需要监听其他应用（如浏览器）的滚动事件
        scrollEventHandler = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self else { return }

            // 只在捕获模式下处理
            guard V2PrimaryScreenStateManager.shared.isCapturing else {
                return
            }

            // 获取滚动增量（负值表示向上滚动，正值表示向下滚动）
            let deltaY = -event.scrollingDeltaY

            // 只处理垂直滚动
            guard deltaY != 0 else {
                return
            }

            // ✨ 智能滚动方向检测
            let currentDirection: ScrollDirection = deltaY > 0 ? .down : .up

            if currentDirection == .down {
                // 向下滚动 - 正向累计
                if self.lastScrollDirection == .up {
                    // 从向上滚动切换到向下滚动，重置累计
                    logger.debug("检测到方向切换（上→下），重置累计距离")
                    self.accumulatedDistance = abs(deltaY)
                } else {
                    // 继续向下滚动，正常累计
                    self.accumulatedDistance += abs(deltaY)
                }
                self.lastScrollDirection = .down
            } else {
                // 向上滚动 - 减少累计距离
                if self.lastScrollDirection == .down {
                    // 从向下滚动切换到向上滚动，减少累计
                    logger.debug("检测到方向切换（下→上），减少累计距离")
                    self.accumulatedDistance = max(0, self.accumulatedDistance - abs(deltaY))
                } else {
                    // 继续向上滚动，不累计
                    logger.debug("持续向上滚动，忽略")
                }
                self.lastScrollDirection = .up
            }

            logger.debug("滚动: \(deltaY > 0 ? "↓" : "↑") \(abs(deltaY))px, 累计: \(self.accumulatedDistance)px")

            // 检查是否达到阈值
            if self.accumulatedDistance >= self.threshold {
                logger.info("达到滚动阈值: \(self.accumulatedDistance)px")

                // ✅ 检查最小采样间隔
                if let lastTime = self.lastCaptureTime {
                    let elapsed = Date().timeIntervalSince(lastTime)
                    if elapsed < self.minCaptureInterval {
                        logger.debug("采样间隔太短（\(elapsed)s)，跳过此次捕获")
                        // 不重置累计距离，继续累积
                        return
                    }
                }

                // ✅ 修复：保留超出部分的累计距离，不丢失滚动
                let excessDistance = self.accumulatedDistance - self.threshold
                self.accumulatedDistance = excessDistance  // 保留超出部分
                self.lastCaptureTime = Date()

                logger.info("触发捕获，保留超出距离: \(excessDistance)px")

                // 触发回调（在主线程）
                DispatchQueue.main.async {
                    onThresholdReached()
                }
            }

            // ⚠️ GlobalMonitor 不需要返回 event，事件已经自动传播到目标应用
        }

        logger.info("滚动监听器已添加")
    }

    /// 停止监听滚动事件
    func stopMonitoring() {
        if let handler = scrollEventHandler {
            NSEvent.removeMonitor(handler)
            scrollEventHandler = nil
            logger.info("滚动监听器已移除")
        }
    }

    /// 重置累计距离
    func resetDistance() {
        accumulatedDistance = 0
        logger.debug("累计距离已重置")
    }

    /// 获取当前累计距离
    func getCurrentDistance() -> CGFloat {
        return accumulatedDistance
    }
}
