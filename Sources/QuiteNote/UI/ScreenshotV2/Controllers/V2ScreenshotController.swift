import SwiftUI
import AppKit
import os.log

private let v2Logger = Logger(subsystem: "com.quitenote.app", category: "ScreenshotV2")

/// 截图窗口控制器
@MainActor
class V2ScreenshotController {
    static var debugPanels: [NSPanel] = []
    /// ✨ 新增：屏幕到 panel 的映射，用于快速查找对应屏幕的 panel
    static var screenPanelMap: [NSScreen: NSPanel] = [:]
    private static var localMonitor: Any?
    /// 失焦自动拉回监听器（cleanup 时必须移除，否则闭包持有旧面板数组，截图结束后失焦会把已关闭的"幽灵"面板拉回前台）
    private static var resignActiveObserver: NSObjectProtocol?
    /// 焦点看门狗：截图会话存续期间，App 未活跃则每秒强制拉回
    private static var focusWatchdogTimer: Timer?

    /// ✨ 新增：互斥锁，确保同一时间只有一个截图流程在运行
    private static var isShowing = false

    /// ✨ 当前截图会话的唯一ID
    internal static var currentSessionID: UUID?

    /// 当前会话的截屏就绪进度（show() 时重置）
    private static var captureProgress = CaptureProgress(total: 0)
    /// 会话期间的 App Nap 断言（show() 持有、cleanup 释放）
    private static var sessionActivity: NSObjectProtocol?
    /// 看门狗上一次尝试激活应用的时刻（限频用）
    private static var lastWatchdogActivation: DispatchTime?
    /// 看门狗两次激活尝试之间的最小间隔：被系统拒绝激活时 activate 会同步阻塞，
    /// 每秒盲敲一次等于每秒堵一次主线程
    static let watchdogActivationInterval: Double = 3.0

    static func show() {
        // ✨ 互斥锁逻辑：如果已经在显示中，则直接返回，防止重复触发
        guard !isShowing else {
            v2Logger.info("Controller - Already showing, ignoring duplicate show() request")
            return
        }

        // 先检查是否已经有 panel，如果有也说明在显示中
        if !debugPanels.isEmpty {
            v2Logger.info("Controller - Panels not empty, ignoring show() request")
            return
        }

        isShowing = true

        // ✨ 生成新的会话ID
        let sessionID = UUID()
        currentSessionID = sessionID
        let sessionStart = DispatchTime.now()
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            // 没有屏幕就立不了面板；不解除互斥锁的话之后的截图请求会被永远忽略
            cleanup()
            isShowing = false
            currentSessionID = nil
            return
        }
        v2Logger.info("Controller - Starting new screenshot session: \(sessionID)")
        DiagnosticCenter.info("Screenshot", "截图会话开始 \(sessionID.uuidString.prefix(8))，屏幕数 \(screens.count)")

        // 清理可能残留的状态。上一轮的面板必须先收掉，否则会被截进画面
        cleanup()

        // ✨ 设置全局键盘监听
        setupKeyboardMonitor()

        v2Logger.info("Controller - Starting multi-screen debug window with REAL windows...")

        // 获取真实窗口列表（窗口吸附用）。必须在会话面板出现之前取：
        // 否则自家的全屏遮罩会被当成可吸附的窗口
        let allWindows = interactiveWindows()

        // 会话期间禁止 App Nap：和速查面板同一招（KeyWindowLadder）。accessory 应用被系统拒绝激活后
        // 跌回后台，App Nap 会给定时器和后台线程降速——截屏正是在后台线程上跑
        if sessionActivity == nil {
            sessionActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "截图会话进行中（截屏与遮罩交互）")
        }

        // 1) 截屏最先派发：它最慢，而且不依赖面板。各屏并行（后台线程），截好一块显示一块。
        //    此前是在主线程上一块屏一块屏同步截完才出遮罩：系统截屏慢的时候（2026-11-27 实测
        //    0.5~2 秒）遮罩整段冻住、点击全部迟到。现在主线程不等截屏。
        captureProgress = CaptureProgress(total: screens.count)
        DiagnosticCenter.setHangThreshold(DiagnosticCenter.screenshotHangThreshold)

        for (index, screen) in screens.enumerated() {
            // NSScreen 只在主线程读：先把截屏需要的显示 ID / 点尺寸取出来再进后台
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            let logicalSize = screen.frame.size
            DispatchQueue.global(qos: .userInitiated).async {
                let startedAt = DispatchTime.now()
                let cgImage = displayID.flatMap { CGDisplayCreateImage($0) }
                let captureSeconds = secondsSince(startedAt)
                DispatchQueue.main.async {
                    V2ScreenshotController.installCapturedScreen(
                        cgImage, logicalSize: logicalSize, screen: screen, screenIndex: index,
                        allWindows: allWindows, sessionID: sessionID,
                        sessionStart: sessionStart, captureSeconds: captureSeconds)
                }
            }
        }

        // 2) 再铺"隐形护盾"：面板内容还是空的、背景透明——不画任何像素（不会被截进画面），
        //    但已经接管鼠标和键盘，等待截屏期间点击不会穿到下面的应用
        for (index, screen) in screens.enumerated() {
            v2Logger.info("Creating debug window for Screen \(index): \(screen.frame.debugDescription, privacy: .public)")
            let panel = makeSessionPanel(for: screen)
            panel.orderFrontRegardless()
            debugPanels.append(panel)
            V2ScreenshotController.screenPanelMap[screen] = panel
        }

        // 即时反馈：光标先变十字；键盘落在鼠标所在屏的面板上，截屏完成前按 ESC 也能退出
        NSCursor.crosshair.set()
        let keyStepStart = DispatchTime.now()
        panelForMouseLocation()?.makeKey()
        logSlowStep("面板取 key", since: keyStepStart)

        // 激活应用放在最后：系统拒绝激活时这一步会同步阻塞（KeyWindowLadder 实测，
        // 单步可到 0.8 秒以上），放后面即使堵住主线程也不耽误后台截屏
        let activateStart = DispatchTime.now()
        NSApp.activate(ignoringOtherApps: true)
        logSlowStep("激活应用", since: activateStart)
    }

    /// 会话启动 / 看门狗里的同步 AppKit 调用耗时超过 slowStepThreshold 就落日志——
    /// 这些调用平时不到 1ms，慢了就是被系统阻塞（被拒状态下的 activate / makeKey）
    static let slowStepThresholdMS: Double = 80

    private static func logSlowStep(_ name: String, since start: DispatchTime) {
        let ms = secondsSince(start) * 1000
        if ms > slowStepThresholdMS {
            DiagnosticCenter.warning("Screenshot", "\(name)耗时 \(Int(ms))ms（平时不到 1ms，疑似被系统阻塞）")
        }
    }

    /// 某一屏截好了：把带冻结画面的视图装进该屏的面板。面板此前是隐形护盾，装完即可见、可交互。
    /// 会话已结束（或被新会话取代）时丢弃这帧。
    private static func installCapturedScreen(_ cgImage: CGImage?, logicalSize: CGSize, screen: NSScreen,
                                              screenIndex: Int, allWindows: [WindowInfo], sessionID: UUID,
                                              sessionStart: DispatchTime, captureSeconds: Double) {
        guard currentSessionID == sessionID, let panel = screenPanelMap[screen] else { return }

        let snapshot = snapshotImage(from: cgImage, logicalSize: logicalSize)
        if cgImage == nil {
            DiagnosticCenter.warning("Screenshot", "屏\(screenIndex) 截屏失败，界面使用纯色底图")
        }
        let view = V2ScreenshotView(screen: screen, snapshot: snapshot, screenIndex: screenIndex,
                                    allWindows: allWindows, sessionID: sessionID)

        DiagnosticCenter.measure("Screenshot", "遮罩安装 屏\(screenIndex)", threshold: 0.1) {
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(origin: .zero, size: logicalSize)
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentView = hostingView
        }

        // 耗时落日志：下次再"截图慢"，直接看每块屏是截屏慢还是装遮罩慢
        let sinceStart = secondsSince(sessionStart)
        var progress = captureProgress
        let complete = progress.markReady(at: sinceStart)
        captureProgress = progress
        let sinceStartMS = Int(sinceStart * 1000)
        DiagnosticCenter.info("Screenshot", "截屏就绪 屏\(screenIndex)：截屏 \(Int(captureSeconds * 1000))ms · 距会话开始 \(sinceStartMS)ms")
        if complete {
            let firstMS = Int((progress.firstReadyAt ?? 0) * 1000)
            DiagnosticCenter.info("Screenshot", "遮罩全部就绪：首屏 \(firstMS)ms · 全部 \(sinceStartMS)ms（共 \(progress.total) 屏）")
        }
    }

    /// 截屏就绪进度：记总屏数与已就绪数，全部就绪时能报出首屏 / 全量耗时（纯值类型，可单测）
    struct CaptureProgress: Equatable {
        let total: Int
        private(set) var ready = 0
        /// 第一块屏就绪的时刻（秒，相对会话开始）
        private(set) var firstReadyAt: TimeInterval?

        /// 标记一屏就绪；返回是否刚好全部就绪
        @discardableResult
        mutating func markReady(at seconds: TimeInterval) -> Bool {
            ready += 1
            if firstReadyAt == nil { firstReadyAt = seconds }
            return ready >= total
        }

        var isComplete: Bool { ready >= total }
    }

    /// 会话面板：screenSaver 级、透明、无边框。刚建出来时里面什么都还没画——这就是"隐形护盾"；
    /// 截好的画面由 installCapturedScreen 装进来
    private static func makeSessionPanel(for screen: NSScreen) -> V2TextInputPanel {
        // ✅ 使用支持文本输入的 V2TextInputPanel
        let panel = V2TextInputPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .screenSaver  // ✨ 最高级别，确保在所有窗口（包括浮球）之上
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false  // ✨ 防止失去焦点时自动隐藏

        // 关键：确保面板在对应的屏幕上
        panel.setFrame(screen.frame, display: false)
        return panel
    }

    /// 窗口吸附用的窗口列表：去掉自家窗口和桌面 / 菜单栏 / Dock 等系统背景
    private static func interactiveWindows() -> [WindowInfo] {
        switch WindowInfoService.shared.fetchAllWindows() {
        case .success(let windows):
            // 过滤掉不需要的窗口：
            // 1. 当前应用自身的窗口
            // 2. 桌面/墙纸 (Wallpaper/Desktop) - 这些通常覆盖全屏且由 Finder 或 Window Server 拥有
            // 3. 菜单栏/Dock 栏等系统 UI
            let list = windows.filter { window in
                let name = window.ownerName
                let isSelf = name == "Quite Note" || name == "QuiteNote"
                let isSystemBackground = name == "Window Server" || name == "Dock" || (name == "Finder" && window.windowName == nil)

                // 只有不是自身且不是系统背景的窗口才显示交互矩形
                return !isSelf && !isSystemBackground
            }
            v2Logger.info("Fetched \(list.count) real windows (filtered system backgrounds)")
            return list
        case .failure(let error):
            v2Logger.error("Failed to fetch real windows: \(error.localizedDescription)")
            return []
        }
    }

    /// 鼠标所在屏的会话面板（鼠标不在任何屏上时退回第一块）
    private static func panelForMouseLocation() -> NSPanel? {
        let mouse = NSEvent.mouseLocation
        let index = screenIndex(containing: mouse, frames: NSScreen.screens.map(\.frame))
        let screen = index.map { NSScreen.screens[$0] }
        return screen.flatMap { screenPanelMap[$0] } ?? debugPanels.first
    }

    /// 点落在哪块屏（纯函数，可单测）；都不包含返回 nil
    static func screenIndex(containing point: CGPoint, frames: [CGRect]) -> Int? {
        frames.firstIndex(where: { $0.contains(point) })
    }

    /// 由截得的位图生成界面用的 NSImage（逻辑尺寸 = 屏幕点尺寸，像素 = 实际像素）。
    /// cgImage 为 nil（截屏失败）时退回纯色底图，界面仍可用
    static func snapshotImage(from cgImage: CGImage?, logicalSize: CGSize) -> NSImage {
        guard let cgImage = cgImage else {
            let img = NSImage(size: logicalSize)
            img.lockFocus()
            NSColor(calibratedWhite: 0.2, alpha: 1.0).set()
            NSRect(origin: .zero, size: logicalSize).fill()
            img.unlockFocus()
            return img
        }

        // ⚠️ 修复 Retina 模糊问题：确保图片尺寸与像素一致
        let image = NSImage(cgImage: cgImage, size: logicalSize) // 逻辑尺寸

        // 显式设置像素尺寸，避免缩放模糊
        image.size = logicalSize
        return image
    }

    private static func secondsSince(_ start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
    }

    /// ✨ 内部清理逻辑，不重置 isShowing 锁
    private static func cleanup() {
        // 移除监听
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        // 停止焦点看门狗
        focusWatchdogTimer?.invalidate()
        focusWatchdogTimer = nil

        // 移除失焦监听器（关键：不移除会在截图结束后触发"幽灵面板"重新弹出）
        if let observer = resignActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            resignActiveObserver = nil
        }

        for panel in debugPanels {
            panel.close()
        }
        debugPanels.removeAll()
        screenPanelMap.removeAll()
        captureProgress = CaptureProgress(total: 0)
        lastWatchdogActivation = nil
        // 会话结束：卡死判定阈值调回默认（截图会话期间是 1 秒）；释放 App Nap 断言
        DiagnosticCenter.setHangThreshold(DiagnosticCenter.stallMajorThreshold)
        if let activity = sessionActivity {
            ProcessInfo.processInfo.endActivity(activity)
            sessionActivity = nil
        }

        // ⚠️ 关闭调试模式时也重置全局状态
        V2PrimaryScreenStateManager.shared.reset()
    }

    static func close() {
        DiagnosticCenter.info("Screenshot", "截图会话结束（元素 \(V2PrimaryScreenStateManager.shared.elements.count) 个）")
        // 先执行清理
        cleanup()
        // 最后重置状态锁
        isShowing = false
        // ✨ 清除会话ID
        currentSessionID = nil
    }

    private static func setupKeyboardMonitor() {
        // 先重置状态
        V2PrimaryScreenStateManager.shared.reset()

        // ✨ 使用 Local Monitor（不需要辅助功能权限）
        // 同时配合 Panel 的 resignsKey 处理，确保失去焦点后重新激活
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 只有在显示截图界面时才拦截
            guard !debugPanels.isEmpty else { return event }

            // 处理 ESC (53)
            if event.keyCode == 53 {
                handleGlobalExitCommand()
                return nil  // 阻止事件传递
            }

            // 处理 Command+C/S/O/R
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command {
                if event.charactersIgnoringModifiers == "s" {
                    NotificationCenter.default.post(name: NSNotification.Name("SaveScreenshot"), object: nil)
                    return nil  // 阻止事件传递
                } else if event.charactersIgnoringModifiers == "c" {
                    NotificationCenter.default.post(name: NSNotification.Name("CopyScreenshot"), object: nil)
                    return nil  // 阻止事件传递
                } else if event.charactersIgnoringModifiers == "o" {
                    NotificationCenter.default.post(name: NSNotification.Name("OCRScreenshot"), object: nil)
                    return nil  // 阻止事件传递
                } else if event.charactersIgnoringModifiers == "r" {
                    NotificationCenter.default.post(name: NSNotification.Name("RecordScreenshot"), object: nil)
                    return nil  // 阻止事件传递
                }
            }

            return event
        }

        // ✨ 新增：监听应用失去焦点事件，自动重新激活 Panel
        // ⚠️ 修复：用实时的 debugPanels 判断（不能用闭包捕获的旧数组），
        // 并在 cleanup 时移除监听，否则截图结束后的任何一次失焦都会把已关闭的面板重新拉出来
        resignActiveObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.async {
                V2ScreenshotController.refocusScreenshotSession()
            }
        }

        // ✨ 新增（2026-08-18）：焦点看门狗
        // 根因：show() 的 NSApp.activate 与前台应用抢焦点可能输掉（Electron 类应用会立刻夺回），
        // App 不活跃时 localMonitor 收不到任何键盘事件 → ESC 失效 → 用户被困在全屏遮罩里（实锤：日志里
        // 出现过 3 分钟 / 12 分钟才结束的截图会话）。失焦监听救不了"从未激活"的情况，必须轮询兜底。
        focusWatchdogTimer?.invalidate()
        let watchdog = Timer(timeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                V2ScreenshotController.refocusScreenshotSession()
            }
        }
        RunLoop.main.add(watchdog, forMode: .common)
        focusWatchdogTimer = watchdog
    }

    /// 会话存续期间强制保持 App 活跃与面板置顶。
    /// - 应用不活跃：夺回来（激活限频 + 计时——系统拒绝激活时 activate 会同步阻塞，
    ///   每秒盲敲等于每秒堵一次主线程）。
    /// - 已有会话面板是 key：key 不动。此前每秒对所有面板挨个 becomeKey()：双屏下 key 每秒在
    ///   两块屏之间对调，文字工具正在输入的那块屏会被抢走键盘。
    /// - 没有面板是 key（被别的应用抢走 / 从未拿到）：给鼠标所在屏补 key。
    private static func refocusScreenshotSession() {
        guard !debugPanels.isEmpty else {
            focusWatchdogTimer?.invalidate()
            focusWatchdogTimer = nil
            return
        }

        let stepStart = DispatchTime.now()
        if !NSApp.isActive, shouldRetryActivation(now: stepStart, last: lastWatchdogActivation) {
            lastWatchdogActivation = stepStart
            NSApp.activate(ignoringOtherApps: true)
        }

        for panel in debugPanels {
            panel.orderFrontRegardless()
        }

        guard !sessionPanelIsKey(NSApp.keyWindow, in: debugPanels) else {
            logSlowStep("看门狗保持活跃", since: stepStart)
            return
        }
        (panelForMouseLocation() ?? debugPanels[0]).makeKey()
        logSlowStep("看门狗补 key", since: stepStart)
    }

    /// 看门狗这一拍要不要再试一次激活（纯函数，可单测）：距上次尝试满了间隔才试
    static func shouldRetryActivation(now: DispatchTime, last: DispatchTime?,
                                       interval: Double = watchdogActivationInterval) -> Bool {
        guard let last = last else { return true }
        return Double(now.uptimeNanoseconds - last.uptimeNanoseconds) / 1_000_000_000 >= interval
    }

    /// 已有本会话的面板是 key（纯函数，可单测）
    static func sessionPanelIsKey(_ keyWindow: NSWindow?, in panels: [NSWindow]) -> Bool {
        guard let keyWindow = keyWindow else { return false }
        return panels.contains { $0 === keyWindow }
    }
    
    /// ESC 后退的阶段性决策（纯函数，可单测）
    /// - 有标注：双击 ESC（2 秒窗口）防误触
    /// - 无标注有选区：先清选区（阶段后退）
    /// - 其余：立即退出
    enum V2EscDecision: Equatable {
        case requireDoublePress
        case clearSelection
        case exitNow
    }

    static func escDecision(hasElements: Bool, lastEscPress: Date?, now: Date, hasSelection: Bool) -> V2EscDecision {
        if hasElements {
            if let last = lastEscPress, now.timeIntervalSince(last) < 2.0 {
                return .exitNow
            }
            return .requireDoublePress
        }
        if hasSelection {
            return .clearSelection
        }
        return .exitNow
    }

    private static func handleGlobalExitCommand() {
        let manager = V2PrimaryScreenStateManager.shared

        switch escDecision(hasElements: !manager.elements.isEmpty,
                           lastEscPress: manager.lastEscKeyPressTime,
                           now: Date(),
                           hasSelection: manager.selectedArea != nil) {
        case .requireDoublePress:
            let now = Date()
            manager.lastEscKeyPressTime = now
            manager.postToast("再按一次退出 (已保留标注内容)", type: "info")

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if manager.lastEscKeyPressTime == now {
                    manager.lastEscKeyPressTime = nil
                }
            }
        case .clearSelection:
            manager.updateSelection(nil, on: nil)
            manager.updateHover(nil, label: nil, on: nil)
            // 重置工具和模式
            manager.updateTool(.cursor)
            manager.selectedElementId = nil
        case .exitNow:
            close()
        }
    }

    /// 支持文本输入的 NSPanel 子类
    /// 关键：覆盖 canBecomeKey 和 canBecomeMain，使 .borderless 样式下仍能接收键盘输入
    class V2TextInputPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
        
        // 允许第一响应者
        override var acceptsFirstResponder: Bool { true }
        
        // 覆盖 cancelOperation (处理 ESC)
        override func cancelOperation(_ sender: Any?) {
            V2ScreenshotController.handleGlobalExitCommand()
        }
    }
}
