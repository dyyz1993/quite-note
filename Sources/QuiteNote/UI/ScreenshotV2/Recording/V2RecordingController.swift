import SwiftUI
import AppKit
import AVFoundation
import ScreenCaptureKit

/// 区域录制控制器：红框 + 控制条两个轻量面板，驱动 V2ScreenRecorderEngine
///
/// 生命周期：start(selection:screen:)（截图会话已由调用方关闭）
///   → 用户停止 / 取消 / 系统强制终止
///   → stop()：引擎收尾 → 临时文件移入用户目录 → 路径进剪贴板 + 轻提示
///   → teardown()：撤面板
@MainActor
final class V2RecordingController: ObservableObject {
    static let shared = V2RecordingController()

    /// 控制条显示的已录时长（秒，不含暂停段）
    @Published private(set) var elapsed: TimeInterval = 0
    /// 停止后的收尾中（面板显示「正在保存…」，正常 < 1 秒）
    @Published private(set) var isFinalizing = false
    /// 暂停中（控制条切 ▶、计时冻结、红框变黄虚线）
    @Published private(set) var isPaused = false
    /// 麦克风实时电平（0...1，20Hz 刷新驱动控制条电平条）
    @Published private(set) var micLevel: Float = 0
    /// 系统声实时电平（0...1）
    @Published private(set) var systemAudioLevel: Float = 0
    /// 录制启动阶段可调整的音频来源。真正起流前会读取最新值。
    @Published private(set) var pendingSystemAudio: Bool = PreferencesManager.shared.recordingSystemAudio
    @Published private(set) var pendingMicrophone: Bool = PreferencesManager.shared.recordingMicrophone
    /// 已点击录制但采集流还在启动中；用于立即显示红框和底部控制条。
    @Published private(set) var isStarting = false
    /// 录制前倒计时剩余秒数；倒计时期间尚未启动采集
    @Published private(set) var countdownRemaining: Int?

    private let engine = V2ScreenRecorderEngine()
    private var borderPanel: NSPanel?
    private var controlPanel: NSPanel?
    private var countdownPanel: NSPanel?
    private var micRecorder: V2MicrophoneRecorder?
    private var ticker: Timer?
    private var levelTimer: Timer?
    /// 音频线程 → UI 的电平中转（跨线程读写加锁）
    private let levelBox = V2RecordingAudioLevelBox()
    private var startedAt: Date?
    /// 暂停累计（用于计时器扣除）
    private var pauseStartedAt: Date?
    private var pausedSeconds: TimeInterval = 0
    /// 引擎正在运行（含启动中）；active=false 且 isFinalizing=true 是收尾窗口期
    private var active = false
    private var startTask: Task<Void, Never>?

    private init() {
        engine.onForcedStop = { [weak self] in
            self?.handleForcedStop()
        }
    }

    var isRunning: Bool { active || isStarting || isFinalizing || countdownRemaining != nil }

    // MARK: - 启动

    /// 开始区域录制
    /// - Parameters:
    ///   - selection: 选区（所在屏幕局部坐标，左上原点 points——与截图会话口径一致）
    ///   - screen: 选区所在屏幕
    func start(selection localRect: CGRect, screen: NSScreen) {
        guard !isRunning else {
            DiagnosticCenter.warning("Recording", "已有录制在进行，忽略重复启动")
            return
        }

        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            ScreenshotService.shared.announceRecordingError("无法识别目标屏幕，录制未开始")
            return
        }

        let sourceRect = V2RecordingGeometry.clampedSourceRect(
            local: localRect, screenPointSize: screen.frame.size)
        guard sourceRect.width >= 16, sourceRect.height >= 16 else {
            ScreenshotService.shared.announceRecordingError("选区太小，无法录制（至少 16×16）")
            return
        }

        let pixels = V2RecordingGeometry.pixelSize(for: sourceRect.size, scale: screen.backingScaleFactor)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuiteNote-Recording-\(UUID().uuidString).mp4")

        PreferencesManager.shared.setLastRecordingSelection(localRect, on: screen)

        // 音频两路独立开关（设置页/工具栏 ▾ 快选共用同一存储）
        pendingSystemAudio = PreferencesManager.shared.recordingSystemAudio
        pendingMicrophone = PreferencesManager.shared.recordingMicrophone

        DiagnosticCenter.info("Recording", String(format: "开始区域录屏：%.0f×%.0fpt @ %@ → %d×%dpx，系统声 %@ 麦克风 %@",
                                                  sourceRect.width, sourceRect.height,
                                                  screen.localizedName,
                                                  Int(pixels.width), Int(pixels.height),
                                                  pendingSystemAudio ? "开" : "关",
                                                  pendingMicrophone ? "开" : "关"))

        let countdownSeconds = PreferencesManager.shared.recordingCountdownSeconds
        isStarting = true
        // 先把反馈 UI 放出来，再做 SCK 内容枚举、音频权限和起流。
        // 这样点击录制后马上能看到选区边界，也能在真正起流前切换音频来源。
        showOverlay(selection: localRect, screen: screen)
        if countdownSeconds > 0 {
            countdownRemaining = countdownSeconds
            showCountdown(selection: localRect, screen: screen)
        }

        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                if countdownSeconds > 0 {
                    for remaining in stride(from: countdownSeconds, through: 1, by: -1) {
                        guard !Task.isCancelled else {
                            self.hideCountdown()
                            return
                        }
                        self.countdownRemaining = remaining
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                    self.hideCountdown()
                }

                // 起录稳定延迟：截图遮罩刚关闭时画面合成器可能还有残影，
                // 等 250ms 让底层画面完全就位再起流（否则首帧可能录到遮罩残影/层级错乱）
                try await Task.sleep(nanoseconds: 250_000_000)

                // 麦克风需要独立 TCC 授权：先请求，拒绝则本次降级为不开麦（不阻断录制）
                let wantsSystemAudio = self.pendingSystemAudio
                var wantsMicrophone = self.pendingMicrophone
                if wantsMicrophone {
                    let granted = await Self.requestMicrophonePermission()
                    if !granted {
                        wantsMicrophone = false
                        self.pendingMicrophone = false
                        DiagnosticCenter.warning("Recording", "麦克风权限未授予，本次录制不含麦克风")
                        ScreenshotService.shared.announceRecordingError("麦克风权限未授予，本次录制不含麦克风")
                    }
                }

                // 枚举显示器内容需要屏幕录制权限——能进入截图会话即已授权
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    throw NSError(domain: "QuiteNote.Recording", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "SCShareableContent 中找不到目标显示器"])
                }
                // 从 SCK 的应用列表里找本应用，排除后红框/控制条/浮球永不入画
                let selfApp = content.applications.first {
                    $0.bundleIdentifier == Bundle.main.bundleIdentifier
                }
                if selfApp == nil {
                    // 排除失败时自己的 UI 可能入画（含遮罩残影），落日志便于排查
                    DiagnosticCenter.warning("Recording", "未能在 SCShareableContent 中定位本应用（bundleID=\(Bundle.main.bundleIdentifier ?? "nil")），窗口排除未生效")
                }

                try await engine.start(parameters: .init(
                    display: display,
                    sourceRect: sourceRect,
                    pixelWidth: Int(pixels.width),
                    pixelHeight: Int(pixels.height),
                    fps: 30,
                    averageBitRate: V2RecordingGeometry.recommendedBitRate(
                        pixelWidth: Int(pixels.width), pixelHeight: Int(pixels.height), fps: 30),
                    outputURL: tempURL,
                    excludedApplications: selfApp.map { [$0] } ?? [],
                    captureSystemAudio: wantsSystemAudio,
                    captureMicrophone: wantsMicrophone,
                    cursorMode: V2RecordingCursorMode(rawValue: PreferencesManager.shared.recordingCursorMode) ?? .keep
                ))

                // 麦克风采集器在引擎就绪后再启动（拿到 TCC 授权的时机也更自然）
                if wantsMicrophone {
                    let mic = V2MicrophoneRecorder()
                    mic.onBuffer = { [weak self] sample in
                        self?.engine.ingestMicrophone(sample)
                    }
                    mic.onLevel = { [levelBox] level in
                        levelBox.mic = level
                    }
                    do {
                        try mic.start()
                        micRecorder = mic
                    } catch {
                        DiagnosticCenter.warning("Recording", "麦克风启动失败（无设备/被占用）：\(error.localizedDescription)")
                        ScreenshotService.shared.announceRecordingError("麦克风启动失败，本次录制不含麦克风")
                    }
                }
                // 系统声实时电平
                engine.onSystemAudioLevel = { [levelBox] level in
                    levelBox.system = level
                }

                self.active = true
                self.startedAt = Date()
                self.elapsed = 0
                self.pausedSeconds = 0
                self.isPaused = false
                self.pendingSystemAudio = wantsSystemAudio
                self.pendingMicrophone = micRecorder != nil
                self.isStarting = false
                self.startTicker()
                self.startLevelTicker()
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                self.hideCountdown()
                DiagnosticCenter.error("Recording", "录屏启动失败：\(error.localizedDescription)")
                ScreenshotService.shared.announceRecordingError("录屏启动失败：\(error.localizedDescription)")
                self.teardown()
            }
        }
    }

    /// 麦克风 TCC 授权（macOS 14+ 显式请求；13 上启动采集时系统自动弹窗，默认放行）
    private static func requestMicrophonePermission() async -> Bool {
        if #available(macOS 14.0, *) {
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        return true
    }

    // MARK: - 停止 / 取消 / 暂停

    /// 暂停⇄恢复：暂停期间画面冻结、三路输入全部丢弃；恢复后成片时间轴无缝（PTS 前移法）
    func togglePause() {
        guard active, !isFinalizing else { return }
        if isPaused {
            engine.resume()
            isPaused = false
            if let started = pauseStartedAt {
                pausedSeconds += Date().timeIntervalSince(started)
            }
            pauseStartedAt = nil
        } else {
            engine.pause()
            isPaused = true
            pauseStartedAt = Date()
        }
    }

    func stop() {
        guard active else { return }
        active = false
        stopTicker()
        stopMicrophone()
        // 控制条观察 isFinalizing 自动切换为「正在保存…」状态
        isFinalizing = true

        Task {
            do {
                if let tempURL = try await engine.stop() {
                    // 停止即落盘（文件安全），随后直接进入预览工作台
                    let finalURL = try V2RecordingFileFinalizer.finalize(
                        tempURL: tempURL,
                        directory: V2RecordingFileFinalizer.defaultDirectory())
                    ScreenshotService.shared.announceRecordingSaved(path: finalURL.path)
                    V2RecordingPreviewController.shared.show(fileURL: finalURL)
                } else {
                    ScreenshotService.shared.announceRecordingError("录制时间太短，未生成文件")
                }
            } catch {
                ScreenshotService.shared.announceRecordingError("录屏保存失败：\(error.localizedDescription)")
            }
            teardown()
        }
    }

    func cancel() {
        guard active || isStarting else { return }
        if isStarting && !active {
            startTask?.cancel()
            teardown()
            return
        }
        active = false
        stopTicker()
        stopMicrophone()
        isFinalizing = true

        Task {
            await engine.cancel()
            ScreenshotService.shared.announceRecordingCancelled()
            teardown()
        }
    }

    private func stopMicrophone() {
        micRecorder?.stop()
        micRecorder = nil
    }

    /// 权限被撤销 / 系统停止：按「停止」收尾，抢救已录内容
    private func handleForcedStop() {
        guard active else { return }
        DiagnosticCenter.warning("Recording", "系统终止录制，正在抢救已录内容")
        stop()
    }

    // MARK: - 面板

    private func showOverlay(selection localRect: CGRect, screen: NSScreen) {
        let globalRect = V2RecordingGeometry.appKitGlobalRect(local: localRect, screenFrame: screen.frame)

        // 红框：画在选区外侧 2pt，不会被录进视频（且内容过滤已排除本应用窗口，双保险）
        let borderFrame = globalRect.insetBy(dx: -2, dy: -2)
        let border = NSPanel(
            contentRect: borderFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        configureFloatingPanel(border, ignoresMouse: true)
        border.setFrame(borderFrame, display: true)
        border.contentView = NSHostingView(rootView: V2RecordingBorderView(controller: self))
        border.orderFrontRegardless()
        borderPanel = border

        // 控制条：先量内容实际尺寸再定面板大小（写死宽度会把文字压成 "…"），
        // 三级动态定位（与截图工具栏同策略），visibleFrame 避开 Dock 与菜单栏
        let barView = V2RecordingControlBarView(controller: self)
        let barHosting = NSHostingView(rootView: barView)
        let fitting = barHosting.fittingSize
        let barSize = CGSize(width: max(340, ceil(fitting.width) + 4),
                             height: max(44, ceil(fitting.height)))
        let control = NSPanel(
            contentRect: NSRect(origin: .zero, size: barSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        configureFloatingPanel(control, ignoresMouse: false)
        control.contentView = barHosting
        positionControlPanel(control, selection: globalRect, barSize: barSize, screen: screen)
        control.orderFrontRegardless()
        controlPanel = control
    }

    private func showCountdown(selection localRect: CGRect, screen: NSScreen) {
        let globalRect = V2RecordingGeometry.appKitGlobalRect(local: localRect, screenFrame: screen.frame)
        let size = CGSize(width: 184, height: 132)
        let visible = screen.visibleFrame
        let x = max(visible.minX + 8, min(globalRect.midX - size.width / 2, visible.maxX - size.width - 8))
        let y = max(visible.minY + 8, min(globalRect.midY - size.height / 2, visible.maxY - size.height - 8))

        let panel = NSPanel(
            contentRect: NSRect(origin: CGPoint(x: x, y: y), size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        configureFloatingPanel(panel, ignoresMouse: true)
        panel.contentView = NSHostingView(rootView: V2RecordingCountdownView(controller: self))
        panel.orderFrontRegardless()
        countdownPanel = panel
    }

    private func hideCountdown() {
        countdownPanel?.close()
        countdownPanel = nil
        countdownRemaining = nil
    }

    private func configureFloatingPanel(_ panel: NSPanel, ignoresMouse: Bool) {
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = ignoresMouse
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
    }

    /// 三级动态定位（复用截图工具栏 V2FloatingToolbar 的策略，换算到 AppKit 全局坐标）：
    /// ① 选区下方 → ② 选区上方 → ③ 选区内部底部（全屏选区兜底）；
    /// X 方向钳制在可见区内，保证控制条任何情况下都完整可见、不压 Dock
    private func positionControlPanel(_ panel: NSPanel, selection globalRect: CGRect,
                                      barSize: CGSize, screen: NSScreen) {
        let visible = screen.visibleFrame
        let spacing: CGFloat = 12

        var x = globalRect.midX - barSize.width / 2
        x = max(visible.minX + 8, min(x, visible.maxX - barSize.width - 8))

        var y: CGFloat
        let below = globalRect.minY - spacing - barSize.height
        let above = globalRect.maxY + spacing
        if below >= visible.minY {
            y = below
        } else if above + barSize.height <= visible.maxY {
            y = above
        } else {
            // 全屏/贴边选区：放进选区内部底部；选区本身贴可见区底部时抬到中部
            y = globalRect.minY + spacing
            if y < visible.minY {
                y = globalRect.midY - barSize.height / 2
            }
        }

        panel.setFrame(NSRect(origin: CGPoint(x: x, y: y), size: barSize), display: true)
    }

    private func teardown() {
        stopTicker()
        startTask = nil
        hideCountdown()
        borderPanel?.close()
        borderPanel = nil
        controlPanel?.close()
        controlPanel = nil
        isFinalizing = false
        isStarting = false
        isPaused = false
        elapsed = 0
        startedAt = nil
        pauseStartedAt = nil
        pausedSeconds = 0
    }

    /// 录制真正起流前切换音频来源。录制开始后音轨结构已锁定，按钮会自动变为只读。
    func setPendingSystemAudio(_ enabled: Bool) {
        guard isStarting else { return }
        pendingSystemAudio = enabled
        PreferencesManager.shared.setRecordingSystemAudio(enabled)
    }

    func setPendingMicrophone(_ enabled: Bool) {
        guard isStarting else { return }
        pendingMicrophone = enabled
        PreferencesManager.shared.setRecordingMicrophone(enabled)
    }

    // MARK: - 计时（扣除暂停段）

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let startedAt = self.startedAt else { return }
                var paused = self.pausedSeconds
                if self.isPaused, let pauseStart = self.pauseStartedAt {
                    paused += Date().timeIntervalSince(pauseStart)
                }
                self.elapsed = max(0, Date().timeIntervalSince(startedAt) - paused)
            }
        }
    }

    /// 20Hz 电平刷新：从跨线程中转盒取最新值驱动 UI（暂停时归零）
    private func startLevelTicker() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isPaused || !self.active {
                    self.micLevel = 0
                    self.systemAudioLevel = 0
                } else {
                    self.micLevel = self.levelBox.mic
                    self.systemAudioLevel = self.levelBox.system
                }
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        levelTimer?.invalidate()
        levelTimer = nil
    }
}

/// 音频线程 → 主线程的电平中转盒（音频回调频率高，UI 定时器按 20Hz 取值）
final class V2RecordingAudioLevelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _mic: Float = 0
    private var _system: Float = 0

    var mic: Float {
        get { lock.lock(); defer { lock.unlock() }; return _mic }
        set { lock.lock(); defer { lock.unlock() }; _mic = newValue }
    }

    var system: Float {
        get { lock.lock(); defer { lock.unlock() }; return _system }
        set { lock.lock(); defer { lock.unlock() }; _system = newValue }
    }
}
