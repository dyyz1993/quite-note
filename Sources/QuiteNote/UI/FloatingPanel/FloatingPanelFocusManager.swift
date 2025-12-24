import Foundation
import AppKit

/// 窗口焦点管理器 - 负责 Activation Policy 切换和焦点获取
final class FloatingPanelFocusManager {
    private weak var panel: NSPanel?
    private var hoverFocusTimer: Timer?
    private var revertTimer: Timer?
    private var previousApp: NSRunningApplication?

    // 状态追踪
    private(set) var hoverActive: Bool = false
    private(set) var isInteracting: Bool = false
    private(set) var userHidden: Bool = false
    private var lastInteractionChange: TimeInterval = 0

    // 回调
    var onFocusLost: (() -> Void)?
    var onRevertComplete: (() -> Void)?

    init(panel: NSPanel) {
        self.panel = panel
    }

    deinit {
        cleanup()
    }

    private func cleanup() {
        hoverFocusTimer?.invalidate()
        hoverFocusTimer = nil
        revertTimer?.invalidate()
        revertTimer = nil
    }

    // MARK: - 用户隐藏状态

    /// 设置用户主动隐藏状态
    func setUserHidden(_ hidden: Bool) {
        userHidden = hidden
        if hidden {
            hoverActive = false
            revertTimer?.invalidate()
            revertTimer = nil
        }
    }

    // MARK: - 交互状态

    /// 更新交互状态（带防抖）
    func setInteracting(_ interacting: Bool) {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastInteractionChange < FloatingPanelConstants.interactionDebounceDelay,
           isInteracting == interacting {
            return
        }

        lastInteractionChange = now
        isInteracting = interacting
    }

    // MARK: - 悬停焦点管理

    /// 请求焦点（悬停触发）
    func requestFocus(reason: String, isBallMode: Bool) {
        guard !userHidden,
              let panel = panel else { return }

        // 如果已经是关键窗口，不需要再次请求焦点
        if panel.isKeyWindow { return }

        // 记录当前活跃的应用（仅在浮球模式）
        if isBallMode {
            if let frontmost = NSWorkspace.shared.frontmostApplication,
               frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
                previousApp = frontmost
            }
        }

        hoverActive = true

        DispatchQueue.main.async { [weak panel] in
            guard let panel = panel else { return }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }

    /// 取消悬停焦点
    func cancelHoverFocus() {
        hoverActive = false
        hoverFocusTimer?.invalidate()
        hoverFocusTimer = nil
    }

    /// 启动延迟聚焦定时器
    func startHoverFocusTimer(action: @escaping () -> Void) {
        hoverFocusTimer?.invalidate()
        hoverActive = true

        let timer = Timer(timeInterval: FloatingPanelConstants.hoverFocusDelay, repeats: false) { [weak self] _ in
            guard let self = self, self.hoverActive else { return }
            action()
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverFocusTimer = timer
    }

    /// 调度回退到 Accessory 模式
    func scheduleRevertToAccessory(isBallMode: Bool) {
        guard !userHidden else { return }

        hoverActive = false
        hoverFocusTimer?.invalidate()
        hoverFocusTimer = nil

        revertTimer?.invalidate()
        revertTimer = Timer.scheduledTimer(withTimeInterval: FloatingPanelConstants.revertDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            if !self.hoverActive && !self.isInteracting && !self.userHidden {
                // 还原焦点到上一个应用（仅在浮球模式）
                if isBallMode, let prevApp = self.previousApp {
                    if !prevApp.isTerminated {
                        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
                            prevApp.activate(options: .activateIgnoringOtherApps)
                        }
                    }
                    self.previousApp = nil
                }

                self.revertToAccessoryIfNeeded(isBallMode: isBallMode)
            }
        }
    }

    private func revertToAccessoryIfNeeded(isBallMode: Bool) {
        guard let panel = panel else { return }

        if !panel.isKeyWindow || isBallMode {
            NSApp.setActivationPolicy(.accessory)
            panel.orderFrontRegardless()
            onRevertComplete?()
        }
    }

    // MARK: - 窗口激活

    /// 激活应用并显示窗口
    func activateAndShow(forceCenter: Bool = false) {
        guard let panel = panel else { return }

        userHidden = false

        panel.alphaValue = 1
        panel.level = .floating

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        // 延时强化显示
        DispatchQueue.main.asyncAfter(deadline: .now() + FloatingPanelConstants.launchReinforceDelay) { [weak panel] in
            guard let panel = panel else { return }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }
    }
}
