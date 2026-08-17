import SwiftUI
import AppKit
import AVFoundation
import Combine
import CoreMedia

// MARK: - 剪辑模型（纯值类型，原始时间轴秒域）

/// 一个保留段（成片 = 所有段按序拼接）
struct EditSegment: Identifiable, Equatable {
    let id = UUID()
    var start: Double
    var end: Double
    var length: Double { end - start }
}

/// 一段补录配音（独立 m4a 文件 + 在全片时间轴上的起止）
struct DubTake: Identifiable, Equatable {
    let id = UUID()
    var start: Double
    var end: Double
    var fileURL: URL
}

/// 一条字幕
struct CaptionChunk: Identifiable, Equatable {
    let id = UUID()
    var start: Double
    var end: Double
    var text: String
}

/// 音轨状态（音量 0...2，1 = 100%）
struct AudioLaneState: Equatable {
    var volume: Double = 1
    var muted: Bool = false
}

// MARK: - 窗口与控制器

final class V2RecordingPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) {
        V2RecordingPreviewController.shared.close()
    }
}

/// 录屏预览工作台（剪映式快剪）：
/// 拖动轨道浏览 + 播放头拖动定位 + 分段剪辑（掐头去尾/分割/删除）
/// + 轨头音量静音 + 补录配音 + 自动字幕（macOS 26+）+ 直通导出
@MainActor
final class V2RecordingPreviewController {
    static let shared = V2RecordingPreviewController()
    private var panel: NSPanel?
    private var player: AVPlayer?

    func show(fileURL: URL) {
        if panel == nil {
            let p = V2RecordingPreviewPanel(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            p.title = "快剪"
            p.level = .floating
            p.isFloatingPanel = true
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.appearance = NSAppearance(named: .darkAqua)
            p.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0)
            p.minSize = NSSize(width: 780, height: 580)
            panel = p
        }

        player?.pause()
        player = nil

        let player = AVPlayer(playerItem: AVPlayerItem(url: fileURL))
        self.player = player

        panel?.title = fileURL.deletingPathExtension().lastPathComponent
        panel?.contentView = NSHostingView(
            rootView: V2RecordingEditorView(fileURL: fileURL, player: player))
        panel?.center()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        player.play()

        DiagnosticCenter.info("Recording", "快剪窗口已打开：\(fileURL.lastPathComponent)")
    }

    func close() {
        player?.pause()
        player = nil
        panel?.orderOut(nil)
    }
}

// MARK: - 播放状态模型

final class V2PlaybackModel: ObservableObject {
    let player: AVPlayer
    @Published private(set) var isPlaying = false
    @Published fileprivate(set) var currentTime: Double = 0

    private var timeObserverToken: Any?
    private var statusObservation: NSKeyValueObservation?

    init(player: AVPlayer) {
        self.player = player
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { [weak self] time in
            self?.currentTime = max(0, time.seconds)
        }
        statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.isPlaying = (player.timeControlStatus == .playing)
            }
        }
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        statusObservation?.invalidate()
    }

    func toggle() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            if let itemDuration = player.currentItem?.duration,
               CMTIME_IS_NUMERIC(itemDuration),
               currentTime >= itemDuration.seconds - 0.05 {
                player.seek(to: .zero)
                currentTime = 0
            }
            player.play()
        }
    }

    func pause() {
        player.pause()
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }
}

// MARK: - 视频画面层

private final class PlayerLayerNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        wantsLayer = true
        layer = playerLayer
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

private struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerNSView {
        let view = PlayerLayerNSView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: PlayerLayerNSView, context: Context) {
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
        }
    }
}

// MARK: - 编辑器主视图

struct V2RecordingEditorView: View {
    let fileURL: URL
    let player: AVPlayer

    @StateObject private var playback: V2PlaybackModel
    @StateObject private var assetInfo = V2RecordingAssetInfo()

    // 分段剪辑
    @State private var segments: [EditSegment] = []
    @State private var selectedSegmentID: UUID?
    @State private var zoom: Double = 40          // px / 秒（打开时自动适配到整片可见）
    @State private var viewportWidth: CGFloat = 0
    @State private var zoomFitted = false
    @State private var t: Double = 0              // 播放头（原始时间轴）
    @State private var undoStack: [[EditSegment]] = []

    // 音轨（与 assetInfo.waveforms 一一对应）+ 配音轨
    @State private var laneStates: [AudioLaneState] = []
    @State private var dubState = AudioLaneState()
    @State private var dubTakes: [DubTake] = []

    // 字幕
    @State private var captions: [CaptionChunk] = []
    @State private var captionsOn = false
    @State private var captionBusy = false
    @State private var editingCaption: CaptionChunk?

    // 配音
    @State private var dubRecorder: V2DubRecorder?
    @State private var dubTake: DubTake?
    @State private var dubLevel: Float = 0

    // 杂项
    @State private var snapIndicator: Double?
    @State private var trimDragBase: [EditSegment]?
    @State private var panBaseOriginal: Double?
    @State private var volumePopoverLane: Int?
    @State private var playbackRate: Float = 1
    @State private var isExporting = false
    @State private var copied = false
    @State private var savedToNotes = false
    @State private var rebuildTask: Task<Void, Never>?

    private let dubColor = Color(red: 245/255, green: 158/255, blue: 11/255)
    private let capColor = Color(red: 34/255, green: 197/255, blue: 94/255)

    private var duration: Double { max(0.001, assetInfo.duration) }
    private var keepDuration: Double { segments.reduce(0) { $0 + $1.length } }
    private var dubbing: Bool { dubTake != nil }
    private var hasEdits: Bool { segments.count > 1 || (segments.first.map { $0.start > 0.01 || $0.end < duration - 0.01 } ?? false) }
    private var selectedIndex: Int? { segments.firstIndex(where: { $0.id == selectedSegmentID }) }

    init(fileURL: URL, player: AVPlayer) {
        self.fileURL = fileURL
        self.player = player
        _playback = StateObject(wrappedValue: V2PlaybackModel(player: player))
    }

    // MARK: 时间映射（原始 ↔ 成片）

    private func timelineTime(fromOriginal o: Double) -> Double {
        var acc: Double = 0
        for g in segments {
            if o <= g.start { return acc }
            if o >= g.end { acc += g.length } else { return acc + (o - g.start) }
        }
        return acc
    }

    private func originalTime(fromTimeline x: Double) -> Double {
        var remaining = max(0, x)
        for g in segments {
            if remaining <= g.length { return g.start + remaining }
            remaining -= g.length
        }
        return segments.last?.end ?? 0
    }

    /// 播放头显示用的原始时间
    private var displayOriginal: Double {
        min(duration, max(0, originalTime(fromTimeline: playback.currentTime)))
    }

    var body: some View {
        VStack(spacing: 0) {
            playerArea
            controlBar
            timelineSection
            footer
        }
        .onAppear {
            segments = [EditSegment(start: 0, end: duration > 0.001 ? duration : 1)]
            // 剪映默认选中当前片段：打开即有把手可掐头去尾
            selectedSegmentID = segments.first?.id
            assetInfo.load(fileURL: fileURL)
        }
        .onChange(of: assetInfo.duration) { newValue in
            if segments.count == 1, let first = segments.first, first.end <= 0.001 || first.end == 1 {
                segments = [EditSegment(start: 0, end: newValue)]
                selectedSegmentID = segments.first?.id
            }
            fitZoomIfNeeded(duration: newValue)
        }
        .onChange(of: assetInfo.waveforms.count) { count in
            laneStates = Array(repeating: AudioLaneState(), count: count)
        }
        // 注意：不做「自动选中播放头所在段」——会与手动点选打架（选不中其他段的元凶）；
        // 选中态只在 打开默认选中 / 分割 / 删除 / 撤销 时显式变更
        .onChange(of: segments) { _ in schedulePlaybackRebuild() }
        .onChange(of: laneStates) { _ in schedulePlaybackRebuild() }
        .onChange(of: dubState) { _ in schedulePlaybackRebuild() }
        .onChange(of: dubTakes) { _ in schedulePlaybackRebuild() }
        .onReceive(playback.$currentTime) { current in
            tick(current: current)
        }
    }

    /// 周期回调：配音生长 / 成片循环
    private func tick(current: Double) {
        let original = originalTime(fromTimeline: current)
        if dubbing {
            dubTake?.end = min(duration, original)
        } else if playback.isPlaying, current >= keepDuration - 0.05, keepDuration > 0.1 {
            playback.seek(to: 0)   // 成片循环
        }
    }

    // MARK: 播放区

    private var playerArea: some View {
        ZStack {
            PlayerLayerView(player: player)
                .background(Color.black)

            if !playback.isPlaying && !dubbing {
                Button(action: { playback.toggle() }) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 68, height: 68)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                        .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .shadow(radius: 12)
            }

            VStack {
                HStack {
                    Text("\(timeLabel(displayOriginal)) / \(timeLabel(keepDuration))")
                        .font(.themeCaption)
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.4)))
                    Spacer()
                    if dubbing {
                        HStack(spacing: 6) {
                            Circle().fill(Color.themeRed500).frame(width: 8, height: 8)
                                .opacity(dubLevel > 0.25 ? 1 : 0.3)
                            Text("配音中 · 跟着画面说话")
                                .font(.themeCaption)
                                .foregroundColor(.white)
                            AudioLevelBars(level: dubLevel, color: dubColor)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(dubColor.opacity(0.92)))
                    }
                }
                .padding(12)
                Spacer()
            }

            // 字幕叠加（烧录效果的预览）
            if captionsOn, let cap = currentCaption {
                Text(cap.text)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.35)))
                    .padding(.bottom, 20)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 230)
        .contentShape(Rectangle())
        .onTapGesture { if !dubbing { playback.toggle() } }
    }

    private var currentCaption: CaptionChunk? {
        let original = displayOriginal
        return captions.first { original >= $0.start && original <= $0.end }
    }

    // MARK: 控制条

    private var controlBar: some View {
        HStack(spacing: ThemeSpacing.px2.rawValue) {
            Button(action: { if !dubbing { playback.toggle() } }) {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.themeGray900)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)

            Text(timeLabel(displayOriginal))
                .font(.themeBody.weight(.semibold))
                .monospacedDigit()
                .fixedSize()
            Text("/ \(timeLabel(keepDuration))")
                .font(.themeCaption)
                .monospacedDigit()
                .fixedSize()
                .foregroundColor(.themeTextTertiary)

            Spacer()

            // 倍速播放（音调补偿，重建播放后保持）
            Menu {
                ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { rate in
                    Button(String(format: "%.1fx", rate)) { setPlaybackRate(Float(rate)) }
                }
            } label: {
                Text(String(format: "%.1fx", playbackRate))
                    .font(.themeCaption)
                    .fixedSize()
                    .monospacedDigit()
                    .foregroundColor(.themeTextPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.themeGray700))
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("播放速度（仅预览，不影响导出成片速度）")

            // 缩放
            HStack(spacing: 3) {
                Button(action: { zoom = max(10, zoom / 1.35) }) { Image(systemName: "minus") }
                    .frame(width: 24, height: 24)
                Text("\(Int(zoom))px/s").frame(minWidth: 40)
                Button(action: { zoom = min(400, zoom * 1.35) }) { Image(systemName: "plus") }
                    .frame(width: 24, height: 24)
            }
            .font(.themeCaption)
            .foregroundColor(.themeTextSecondary)
            .buttonStyle(.plain)

            toolButton("✂ 分割", disabled: !canSplit) { splitAtPlayhead() }
            toolButton("🗑 删除此段", disabled: segments.count < 2 || selectedIndex == nil) { deleteSelected() }
            toolButton(dubbing ? "⏹ 结束配音" : "🎙 补录配音",
                       prominent: dubbing) { toggleDub() }
            if V2CaptionTranscriber.available {
                toolButton(captionBusy ? "识别中…" : (captions.isEmpty ? "💬 自动字幕" : (captionsOn ? "💬 字幕 ✓" : "💬 字幕 关")),
                           disabled: captionBusy || (captions.isEmpty && !canTranscribe)) { toggleCaptions() }
            }
            toolButton("↩ 撤销", disabled: undoStack.isEmpty) { undo() }
            toolButton(isExporting ? "导出中…" : "导出成片", prominent: true, disabled: isExporting || dubbing) { exportFinal() }
        }
        .padding(.horizontal, ThemeSpacing.px4.rawValue)
        .padding(.vertical, ThemeSpacing.px2.rawValue)
        .background(Color.themeGray800.opacity(0.6))
    }

    private func toolButton(_ text: String, prominent: Bool = false,
                            disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.themeCaption)
                .fixedSize()
                .foregroundColor(prominent ? .white : .themeTextPrimary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(prominent ? Color.themeRed500 : Color.themeGray700)
                )
                .opacity(disabled ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: 时间线

    private var timelineSection: some View {
        HStack(spacing: 0) {
            gutter
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                ZStack(alignment: .topLeading) {
                    // 半透明底（被删区域由 gap 覆盖层表达）
                    Color.themeGray900.opacity(0.25)
                    // 轨道内容（随播放头平移）
                    TrackContent(
                        segments: segments,
                        selectedID: selectedSegmentID,
                        thumbnails: assetInfo.thumbnails,
                        waveforms: assetInfo.waveforms,
                        laneStates: laneStates,
                        dubTakes: dubTakes,
                        dubGrowingEnd: dubTake?.end,
                        captions: captions,
                        duration: duration,
                        zoom: zoom,
                        playheadFraction: displayOriginal / duration,
                        snapFraction: snapIndicator,
                        onSegmentTap: { id in selectedSegmentID = id },
                        onHandleDrag: { index, isStart, g in handleTrim(index: index, isStart: isStart, g: g) },
                        onHandleEnd: {
                            trimDragBase = nil
                            snapIndicator = nil
                        },
                        onCaptionTap: { cap in editingCaption = cap })
                    .frame(width: duration * zoom, alignment: .topLeading)
                    .offset(x: centerX(width: width) - displayOriginal * zoom)
                    .gesture(panGesture(width: width))
                    .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                        if !dubbing {
                            let original = min(duration, max(0, displayOriginal + (tap.location.x - centerX(width: width)) / zoom))
                            t = original
                            playback.seek(to: timelineTime(fromOriginal: original))
                        }
                    })

                    // 播放头（中央固定，可拖动）
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 1.5)
                        .offset(x: centerX(width: width))
                        .allowsHitTesting(false)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                        .offset(x: centerX(width: width) - 3.5)
                        .allowsHitTesting(false)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 24, height: timelineHeight)
                        .contentShape(Rectangle())
                        .offset(x: centerX(width: width) - 12)
                        .gesture(playheadDrag(width: width))
                }
                .onAppear {
                    // 记录视口宽度并尝试自动适配缩放（时长通常此刻还在分析，onChange 会兜底）
                    viewportWidth = width
                    fitZoomIfNeeded(duration: duration)
                }
            }
            .frame(height: timelineHeight)
        }
        .background(Color(red: 14/255, green: 21/255, blue: 36/255))
        .overlay(
            captionEditor.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        )
    }

    private func centerX(width: CGFloat) -> CGFloat { width / 2 }

    /// 剪映式自动适配：打开时缩放到整片刚好可见（短视频放大、长视频缩小到下限）
    private func fitZoomIfNeeded(duration: Double) {
        guard !zoomFitted, duration > 0.2, viewportWidth > 100 else { return }
        zoom = min(400, max(10, Double(viewportWidth - 24) / duration))
        zoomFitted = true
    }

    /// 倍速播放：音调补偿（变速不变调），重建播放后经 defaultRate 保持
    private func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        player.defaultRate = rate
        player.currentItem?.audioTimePitchAlgorithm = .timeDomain
        if player.timeControlStatus == .playing {
            player.rate = rate
        }
    }

    /// 拖动（播放头/轨道）跨越任一切割点时给一次轻震动反馈
    private func crossedCutBoundary(from old: Double, to new: Double) -> Bool {
        let lo = min(old, new), hi = max(old, new)
        return segments.contains { seg in
            (seg.start > lo && seg.start < hi) || (seg.end > lo && seg.end < hi)
        }
    }

    /// 把手修剪：以拖拽起手时的分段快照为基准，吸附播放头，钳制相邻段
    private func handleTrim(index: Int, isStart: Bool, g: DragGesture.Value) {
        guard !dubbing, segments.indices.contains(index) else { return }
        if playback.isPlaying { playback.pause() }
        if trimDragBase == nil {
            trimDragBase = segments
            pushUndo()
        }
        guard var base = trimDragBase, base.indices.contains(index) else { return }
        var seg = base[index]
        let delta = Double(g.translation.width) / zoom
        var snapped = false
        if isStart {
            let prevEnd = index > 0 ? base[index - 1].end : 0
            var newStart = min(seg.end - 0.5, max(prevEnd, seg.start + delta))
            if abs(newStart - displayOriginal) < 0.35 {
                newStart = min(seg.end - 0.5, max(prevEnd, displayOriginal))
                snapped = true
            }
            seg.start = newStart
        } else {
            let nextStart = index < base.count - 1 ? base[index + 1].start : duration
            var newEnd = max(seg.start + 0.5, min(nextStart, seg.end + delta))
            if abs(newEnd - displayOriginal) < 0.35 {
                newEnd = max(seg.start + 0.5, min(nextStart, displayOriginal))
                snapped = true
            }
            seg.end = newEnd
        }
        base[index] = seg
        segments = base
        snapIndicator = snapped ? (isStart ? seg.start : seg.end) / duration : nil
    }

    private var timelineHeight: CGFloat {
        16 + 48 + CGFloat(laneStates.count) * 26
            + (dubTakes.isEmpty && !dubbing ? 0 : 26)
            + (captions.isEmpty ? 0 : 26)
            + 6
    }

    /// 左侧轨头（画面/各音轨/配音/字幕；音量弹层）
    private var gutter: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("画面").font(.themeCaptionSmall).foregroundColor(.themeTextSecondary)
                Spacer()
            }
            .frame(width: 84, height: 16 + 48)

            ForEach(assetInfo.waveforms.indices, id: \.self) { i in
                laneHeader(index: i, label: assetInfo.waveforms[i].label,
                           color: assetInfo.waveforms[i].color,
                           state: Binding(
                            get: { laneStates.indices.contains(i) ? laneStates[i] : AudioLaneState() },
                            set: { if laneStates.indices.contains(i) { laneStates[i] = $0 } }))
            }

            if !dubTakes.isEmpty || dubbing {
                laneHeader(index: -1, label: "配音", color: dubColor,
                           state: $dubState)
            }

            if !captions.isEmpty {
                HStack {
                    Text("字幕").font(.themeCaptionSmall).foregroundColor(capColor)
                    Spacer()
                }
                .frame(width: 84, height: 26)
            }
        }
        .background(Color.themeGray900.opacity(0.4))
    }

    private func laneHeader(index: Int, label: String, color: Color,
                            state: Binding<AudioLaneState>) -> some View {
        HStack(spacing: 4) {
            Button(action: { state.wrappedValue.muted.toggle() }) {
                Image(systemName: state.wrappedValue.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundColor(state.wrappedValue.muted ? Color.themeRed400 : color)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("静音/恢复")

            Button(action: { volumePopoverLane = volumePopoverLane == index ? nil : index }) {
                Text("\(label) \(Int(state.wrappedValue.volume * 100))%")
                    .font(.themeCaptionSmall)
                    .foregroundColor(color)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(
                get: { volumePopoverLane == index },
                set: { if !$0, volumePopoverLane == index { volumePopoverLane = nil } })) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(label) 音量：\(Int(state.wrappedValue.volume * 100))%")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextPrimary)
                    Slider(value: Binding(
                        get: { state.wrappedValue.volume },
                        set: { state.wrappedValue.volume = $0 }), in: 0...2, step: 0.1)
                        .frame(width: 180)
                    Text("导出时非 100% 音量将走重编码（稍慢）")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                }
                .padding(12)
            }
        }
        .padding(.horizontal, 6)
        .frame(width: 84, height: 26, alignment: .leading)
    }

    // MARK: 手势

    private func panGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { g in
                guard !dubbing else { return }
                if playback.isPlaying { playback.pause() }
                // 以起手时的原始时间为基准（t 会随移动更新，不能作基准）
                if panBaseOriginal == nil { panBaseOriginal = displayOriginal }
                guard let base = panBaseOriginal else { return }
                let original = min(duration, max(0, base - (g.location.x - g.startLocation.x) / zoom))
                if crossedCutBoundary(from: t, to: original) {
                    HapticFeedbackManager.shared.lightImpact()
                }
                t = original
                playback.seek(to: timelineTime(fromOriginal: original))
            }
            .onEnded { _ in panBaseOriginal = nil }
    }

    private func playheadDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                guard !dubbing else { return }
                if playback.isPlaying { playback.pause() }
                if panBaseOriginal == nil { panBaseOriginal = displayOriginal }
                guard let base = panBaseOriginal else { return }
                let original = min(duration, max(0, base + (g.location.x - g.startLocation.x) / zoom))
                if crossedCutBoundary(from: t, to: original) {
                    HapticFeedbackManager.shared.lightImpact()
                }
                t = original
                playback.seek(to: timelineTime(fromOriginal: original))
            }
            .onEnded { _ in panBaseOriginal = nil }
    }

    // MARK: 剪辑动作

    /// 播放头所在的段（分割自动作用于它，无需先手动点选）
    private var playheadSegmentIndex: Int? {
        segments.firstIndex { displayOriginal >= $0.start && displayOriginal <= $0.end }
    }

    private var canSplit: Bool {
        guard let idx = playheadSegmentIndex else { return false }
        let seg = segments[idx]
        return displayOriginal > seg.start + 0.3 && displayOriginal < seg.end - 0.3
    }

    private func splitAtPlayhead() {
        guard let idx = playheadSegmentIndex, canSplit else { return }
        pushUndo()
        selectedSegmentID = segments[idx].id
        let seg = segments[idx]
        segments.replaceSubrange(idx...idx, with: [
            EditSegment(start: seg.start, end: displayOriginal),
            EditSegment(start: displayOriginal, end: seg.end),
        ])
        selectedSegmentID = segments[idx].id
    }

    private func deleteSelected() {
        guard segments.count >= 2, let idx = selectedIndex else { return }
        pushUndo()
        segments.remove(at: idx)
        selectedSegmentID = segments[min(idx, segments.count - 1)].id
    }

    private func pushUndo() {
        undoStack.append(segments)
        if undoStack.count > 30 { undoStack.removeFirst() }
    }

    private func undo() {
        guard let prev = undoStack.popLast() else { return }
        let restoreIndex = selectedIndex ?? 0
        segments = prev
        // 优先保持同位置的段（而不是跳到最后一段）
        if let id = selectedSegmentID, segments.contains(where: { $0.id == id }) { return }
        selectedSegmentID = segments.indices.contains(restoreIndex)
            ? segments[restoreIndex].id
            : segments.last?.id
    }

    // MARK: 配音

    private func toggleDub() {
        if !dubbing {
            startDub()
        } else {
            stopDub()
        }
    }

    private func startDub() {
        // 麦克风授权（录制时未开麦的用户首次配音会走到这）
        Task {
            let granted = await Self.requestMicPermission()
            guard granted else {
                ScreenshotService.shared.announceRecordingError("麦克风权限未授予，无法配音")
                return
            }
            let recorder = V2DubRecorder()
            recorder.onLevel = { level in
                Task { @MainActor in dubLevel = level }
            }
            do {
                let url = try recorder.start()
                dubRecorder = recorder
                let take = DubTake(start: t, end: t, fileURL: url)
                dubTake = take
                dubTakes.append(take)
                playback.seek(to: timelineTime(fromOriginal: t))
                playback.toggleUnlessPlaying()
            } catch {
                ScreenshotService.shared.announceRecordingError("配音启动失败：\(error.localizedDescription)")
            }
        }
    }

    private func stopDub() {
        guard let recorder = dubRecorder, let take = dubTake else { return }
        playback.pause()
        dubTake = nil
        dubLevel = 0
        Task {
            if let url = await recorder.stop() {
                if take.end - take.start < 0.4 {
                    try? FileManager.default.removeItem(at: url)
                    dubTakes.removeAll { $0.id == take.id }
                    ScreenshotService.shared.announceRecordingError("配音太短，已丢弃")
                } else {
                    if let idx = dubTakes.firstIndex(where: { $0.id == take.id }) {
                        dubTakes[idx].fileURL = url
                        dubTakes[idx].end = take.end
                    }
                    DiagnosticCenter.info("Recording", String(format: "配音完成：%.1fs → %@", take.end - take.start, url.lastPathComponent))
                }
            } else {
                dubTakes.removeAll { $0.id == take.id }
            }
            dubRecorder = nil
            schedulePlaybackRebuild()
        }
    }

    private static func requestMicPermission() async -> Bool {
        if #available(macOS 14.0, *) {
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        return true
    }

    // MARK: 字幕

    private var canTranscribe: Bool {
        !dubTakes.isEmpty || assetInfo.waveforms.contains { $0.label == "麦克风" }
    }

    private func toggleCaptions() {
        if captions.isEmpty {
            generateCaptions()
        } else {
            captionsOn.toggle()
        }
    }

    private func generateCaptions() {
        captionBusy = true
        Task {
            do {
                var chunks: [CaptionChunk] = []
                if !dubTakes.isEmpty {
                    for take in dubTakes {
                        let raw = try await V2CaptionTranscriber.transcribe(fileURL: take.fileURL, offset: take.start)
                        chunks += raw.map { CaptionChunk(start: $0.start, end: $0.end, text: $0.text) }
                    }
                } else {
                    // 无配音：把原片的麦克风轨导出成临时 m4a 再识别
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("QuiteNote-Cap-\(UUID().uuidString).m4a")
                    let asset = AVURLAsset(url: fileURL)
                    if let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) {
                        session.outputURL = tempURL
                        session.outputFileType = .m4a
                        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                            session.exportAsynchronously { cont.resume() }
                        }
                        if session.status == .completed {
                            let raw = try await V2CaptionTranscriber.transcribe(fileURL: tempURL, offset: 0)
                            chunks = raw.map { CaptionChunk(start: $0.start, end: $0.end, text: $0.text) }
                        }
                        try? FileManager.default.removeItem(at: tempURL)
                    }
                    if chunks.isEmpty {
                        throw NSError(domain: "QuiteNote.Caption", code: 3,
                                      userInfo: [NSLocalizedDescriptionKey: "没有可识别的音频（录屏时未开麦克风、也没有配音）"])
                    }
                }
                captions = chunks.sorted { $0.start < $1.start }
                captionsOn = true
                DiagnosticCenter.info("Recording", "字幕生成完成：\(captions.count) 条")
            } catch {
                ScreenshotService.shared.announceRecordingError(error.localizedDescription)
            }
            captionBusy = false
        }
    }

    /// 字幕编辑弹层
    @ViewBuilder
    private var captionEditor: some View {
        if let cap = editingCaption {
            VStack(spacing: 10) {
                Text("编辑字幕（\(timeLabel(cap.start)) – \(timeLabel(cap.end))）")
                    .font(.themeCaption)
                    .foregroundColor(.themeTextSecondary)
                TextField("字幕内容", text: Binding(
                    get: { editingCaption?.text ?? cap.text },
                    set: { newValue in
                        if let idx = captions.firstIndex(where: { $0.id == cap.id }) {
                            captions[idx].text = newValue
                        }
                    }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)
                HStack {
                    Button("删除这条") {
                        captions.removeAll { $0.id == cap.id }
                        editingCaption = nil
                    }
                    .foregroundColor(.themeRed400)
                    Spacer()
                    Button("完成") { editingCaption = nil }
                        .keyboardShortcut(.defaultAction)
                }
                .buttonStyle(.borderless)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.themeGray900))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.themeBorderSubtle))
            .padding(20)
        }
    }

    // MARK: 合成与导出

    private func schedulePlaybackRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, !isExporting, !dubbing else { return }
            await rebuildPlayback()
        }
    }

    private func rebuildPlayback() async {
        let wasPlaying = playback.isPlaying
        let originalNow = originalTime(fromTimeline: playback.currentTime)

        if hasEdits || !dubTakes.isEmpty || laneStates.contains(where: { $0.muted || abs($0.volume - 1) > 0.01 }),
           let built = try? await buildComposition() {
            let item = AVPlayerItem(asset: built.composition)
            item.audioMix = built.mix
            player.replaceCurrentItem(with: item)
        } else {
            player.replaceCurrentItem(with: AVPlayerItem(asset: AVURLAsset(url: fileURL)))
        }

        playback.seek(to: timelineTime(fromOriginal: originalNow))
        if wasPlaying {
            player.play()
            if playbackRate != 1 {
                player.rate = playbackRate
            }
        }
    }

    /// 合成 = 分段视频 + 各音轨（静音/音量）+ 配音轨（映射到成片时间轴）
    private func buildComposition() async throws -> (composition: AVMutableComposition, mix: AVAudioMix?)? {
        let asset = AVURLAsset(url: fileURL)
        guard let videoSource = (try? await asset.loadTracks(withMediaType: .video))?.first,
              !segments.isEmpty else { return nil }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }

        for seg in segments {
            let range = CMTimeRange(start: CMTime(seconds: seg.start, preferredTimescale: 600),
                                    end: CMTime(seconds: seg.end, preferredTimescale: 600))
            try? videoTrack.insertTimeRanges([NSValue(timeRange: range)], of: [videoSource], at: .zero)
        }

        var mixParams: [AVMutableAudioMixInputParameters] = []
        let totalTimeline = keepDuration

        func registerVolume(_ volume: Double, track: AVCompositionTrack) {
            guard abs(volume - 1) > 0.01 else { return }
            let p = AVMutableAudioMixInputParameters(track: track)
            let full = CMTimeRange(start: .zero, duration: CMTime(seconds: totalTimeline, preferredTimescale: 600))
            p.setVolumeRamp(fromStartVolume: Float(volume), toEndVolume: Float(volume), timeRange: full)
            mixParams.append(p)
        }

        // 源音轨
        for (i, source) in assetInfo.audioTracks.enumerated() {
            let state = laneStates.indices.contains(i) ? laneStates[i] : AudioLaneState()
            guard !state.muted else { continue }
            guard let audioTrack = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            for seg in segments {
                let range = CMTimeRange(start: CMTime(seconds: seg.start, preferredTimescale: 600),
                                        end: CMTime(seconds: seg.end, preferredTimescale: 600))
                try? audioTrack.insertTimeRanges([NSValue(timeRange: range)], of: [source], at: .zero)
            }
            registerVolume(state.volume, track: audioTrack)
        }

        // 配音：每段 take 与各保留段求交，按映射位置插入（对齐成片时间轴）
        if !dubState.muted {
            for take in dubTakes {
                let dubAsset = AVURLAsset(url: take.fileURL)
                guard let dubSource = (try? await dubAsset.loadTracks(withMediaType: .audio))?.first,
                      let audioTrack = composition.addMutableTrack(
                        withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                for seg in segments {
                    let s = max(seg.start, take.start)
                    let e = min(seg.end, take.end)
                    guard e - s > 0.05 else { continue }
                    let srcRange = CMTimeRange(start: CMTime(seconds: s - take.start, preferredTimescale: 600),
                                               duration: CMTime(seconds: e - s, preferredTimescale: 600))
                    let at = CMTime(seconds: timelineTime(fromOriginal: s), preferredTimescale: 600)
                    try? audioTrack.insertTimeRanges([NSValue(timeRange: srcRange)], of: [dubSource], at: at)
                }
                registerVolume(dubState.volume, track: audioTrack)
            }
        }

        let mix = mixParams.isEmpty ? nil : {
            let m = AVMutableAudioMix()
            m.inputParameters = mixParams
            return m
        }()
        return (composition, mix)
    }

    /// 字幕烧录：装载字幕到自定义合成器（AVCoreAnimationTool 已从 macOS 26 SDK 移除）
    private func captionVideoComposition(for composition: AVMutableComposition) async -> AVVideoComposition? {
        guard captionsOn, !captions.isEmpty,
              let videoTrack = composition.tracks(withMediaType: .video).first,
              let size = try? await videoTrack.load(.naturalSize),
              size.width > 0 else { return nil }

        var loaded: [(CMTimeRange, String)] = []
        for cap in captions {
            let start = timelineTime(fromOriginal: cap.start)
            let end = timelineTime(fromOriginal: cap.end)
            guard end - start > 0.1 else { continue }
            loaded.append((CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                        duration: CMTime(seconds: end - start, preferredTimescale: 600)),
                           cap.text))
        }
        guard !loaded.isEmpty else { return nil }
        V2CaptionCompositor.activeCaptions = loaded

        let vc = AVMutableVideoComposition()
        vc.renderSize = size
        vc.frameDuration = CMTime(value: 1, timescale: 30)
        vc.customVideoCompositorClass = V2CaptionCompositor.self
        return vc
    }

    private func exportFinal() {
        guard !isExporting, !dubbing else { return }
        isExporting = true

        Task {
            do {
                guard let built = try await buildComposition() else {
                    throw V2TrimExporter.TrimError.exportFailed("内容为空")
                }
                let burn = await captionVideoComposition(for: built.composition)
                let trimmedURL = try await V2TrimExporter.export(
                    composition: built.composition,
                    audioMix: built.mix,
                    videoComposition: burn)

                try? FileManager.default.removeItem(at: fileURL)
                try? FileManager.default.moveItem(at: trimmedURL, to: fileURL)
                DiagnosticCenter.info("Recording", "成片导出完成：\(fileURL.lastPathComponent)")
                V2RecordingPreviewController.shared.show(fileURL: fileURL)
            } catch {
                ScreenshotService.shared.announceRecordingError(error.localizedDescription)
            }
            isExporting = false
        }
    }

    // MARK: 底栏

    private var footer: some View {
        HStack(spacing: ThemeSpacing.px3.rawValue) {
            let removed = duration - keepDuration
            let dubSec = dubTakes.reduce(0.0) { $0 + $1.end - $1.start }
            Text("成片 \(timeLabel(keepDuration)) · \(segments.count) 段"
                 + (removed > 0.05 ? " · 已删 \(String(format: "%.1f", removed))s" : "")
                 + (dubSec > 0.05 ? " · 配音 \(Int(dubSec))s" : "")
                 + (captions.isEmpty ? "" : " · 字幕 \(captions.count) 条"))
                .font(.themeCaptionSmall)
                .monospacedDigit()
                .foregroundColor(hasEdits || !captions.isEmpty ? .themeYellow500 : .themeTextTertiary)

            Spacer()

            Button(action: copyPath) {
                Text(copied ? "已复制" : "复制路径")
                    .font(.themeCaptionSmall).fixedSize()
                    .foregroundColor(copied ? .themeStatusSuccess : .themeTextSecondary)
            }.buttonStyle(.plain)
            Button(action: { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }) {
                Text("Finder").font(.themeCaptionSmall).fixedSize()
                    .foregroundColor(.themeTextSecondary)
            }.buttonStyle(.plain)
            Button(action: saveToNotes) {
                Text(savedToNotes ? "已存闪记 ✓" : "存入闪记").font(.themeCaptionSmall).fixedSize()
                    .foregroundColor(savedToNotes ? .themeStatusSuccess : .themeTextSecondary)
            }.buttonStyle(.plain).disabled(savedToNotes)
            Button(action: { V2RecordingPreviewController.shared.close() }) {
                Text("关闭").font(.themeCaptionSmall).fixedSize()
                    .foregroundColor(.themeTextSecondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, ThemeSpacing.px4.rawValue)
        .padding(.vertical, ThemeSpacing.px2.rawValue)
        .background(Color.themeGray800.opacity(0.5))
    }

    private func copyPath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fileURL.path, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }

    private func saveToNotes() {
        guard !savedToNotes else { return }
        savedToNotes = true
        ScreenshotService.shared.saveRecordingToFlashNotes(fileURL: fileURL, duration: keepDuration)
    }

    private func timeLabel(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - 播放辅助

private extension V2PlaybackModel {
    func toggleUnlessPlaying() {
        if !isPlaying {
            playFromZeroIfNeededAndPlay()
        }
    }

    func playFromZeroIfNeededAndPlay() {
        if let itemDuration = player.currentItem?.duration,
           CMTIME_IS_NUMERIC(itemDuration),
           currentTime >= itemDuration.seconds - 0.05 {
            player.seek(to: .zero)
            currentTime = 0
        }
        player.play()
    }
}

// MARK: - 轨道内容（track 坐标系，宽 = duration × zoom）

private struct TrackContent: View {
    let segments: [EditSegment]
    let selectedID: UUID?
    let thumbnails: [NSImage]
    let waveforms: [V2RecordingAssetInfo.WaveformTrack]
    let laneStates: [AudioLaneState]
    let dubTakes: [DubTake]
    let dubGrowingEnd: Double?
    let captions: [CaptionChunk]
    let duration: Double
    let zoom: Double
    let playheadFraction: Double
    let snapFraction: Double?
    var onSegmentTap: ((UUID) -> Void)?
    var onHandleDrag: ((Int, Bool, DragGesture.Value) -> Void)?
    var onHandleEnd: (() -> Void)?
    var onCaptionTap: ((CaptionChunk) -> Void)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ruler
            thumbs
            waveLanes
            dubLane
            captionLane
            gapOverlays
            segmentFrames
            snapLine
        }
    }

    // MARK: 刻度尺（自适应）

    private var ruler: some View {
        Canvas { context, size in
            let labelStep: Double = zoom >= 60 ? 1 : zoom >= 25 ? 5 : 10
            let minorStep = labelStep / 5
            var sec: Double = 0
            while sec <= duration + 0.001 {
                let x = sec * zoom
                let major = abs(sec.truncatingRemainder(dividingBy: labelStep)) < 0.001
                let h: CGFloat = major ? 9 : 4
                let path = Path(CGRect(x: x, y: 16 - h, width: 1, height: h))
                context.fill(path, with: .color(major ? Color(red: 107/255, green: 121/255, blue: 148/255) : Color(red: 61/255, green: 74/255, blue: 104/255)))
                if major {
                    let label = "\(Int(sec / 60)):\(String(format: "%02d", Int(sec.truncatingRemainder(dividingBy: 60))))"
                    context.draw(Text(label).font(.system(size: 9.5)).foregroundColor(Color(red: 139/255, green: 149/255, blue: 171/255)),
                                 at: CGPoint(x: x, y: 6))
                }
                sec += minorStep
            }
        }
        .frame(height: 16)
    }

    private var thumbs: some View {
        // 剪映式平铺：格子宽度 ≈ 画面自然比例（44pt 高 ≈ 78pt 宽），数量按轨道长度算，
        // 从 24 张采样图里就近取样——不再是均分细条
        let naturalWidth: CGFloat = 44 * 16 / 9
        let trackWidth = duration * zoom
        let count = max(1, Int((trackWidth / naturalWidth).rounded()))
        let cellWidth = trackWidth / CGFloat(count)
        return HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                let sampleIndex = min(thumbnails.count - 1,
                                       i * max(1, thumbnails.count) / max(1, count))
                if thumbnails.indices.contains(sampleIndex) {
                    Image(nsImage: thumbnails[sampleIndex])
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cellWidth, height: 44)
                        .clipped()
                } else {
                    Color.themeGray700.frame(width: cellWidth, height: 44)
                }
            }
        }
        .frame(width: trackWidth, height: 48, alignment: .topLeading)
        .clipped()
        .padding(.top, 16)
    }

    // MARK: 波形轨

    @ViewBuilder
    private var waveLanes: some View {
        ForEach(waveforms.indices, id: \.self) { i in
            let state = laneStates.indices.contains(i) ? laneStates[i] : AudioLaneState()
            LaneWave(values: waveforms[i].values,
                     color: waveforms[i].color,
                     opacity: state.muted ? 0.15 : 0.35 + 0.65 * min(1, state.volume))
                .frame(width: duration * zoom, height: 24)
                .offset(y: 16 + 48 + CGFloat(i) * 26 + 1)
        }
    }

    @ViewBuilder
    private var dubLane: some View {
        if !dubTakes.isEmpty {
            ForEach(dubTakes) { take in
                let end = (take.id == dubTakes.last?.id && dubGrowingEnd != nil) ? dubGrowingEnd! : take.end
                RoundedRectangle(cornerRadius: 5)
                    .fill(dubColor.opacity(0.35))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(dubColor, lineWidth: 1.5))
                    .frame(width: max(6, (end - take.start) * zoom), height: 24)
                    .offset(x: take.start * zoom,
                            y: 16 + 48 + CGFloat(waveforms.count) * 26 + 1)
            }
        }
    }

    @ViewBuilder
    private var captionLane: some View {
        if !captions.isEmpty {
            ForEach(captions) { cap in
                Text(cap.text)
                    .font(.system(size: 9.5))
                    .foregroundColor(Color(red: 169/255, green: 232/255, blue: 191/255))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 5)
                    .frame(width: max(30, (cap.end - cap.start) * zoom), height: 22, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 4).fill(capColor.opacity(0.15)))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(capColor.opacity(0.55), lineWidth: 1))
                    .offset(x: cap.start * zoom,
                            y: 16 + 48 + CGFloat(waveforms.count) * 26 + (dubTakes.isEmpty ? 0 : 26) + 2)
                    .onTapGesture { onCaptionTap?(cap) }
            }
        }
    }

    // MARK: 被删空隙

    @ViewBuilder
    private var gapOverlays: some View {
        let topY: CGFloat = 16
        let bottomY: CGFloat = 16 + 48 + CGFloat(waveforms.count) * 26
            + (dubTakes.isEmpty ? 0 : 26) + 6
        let gaps = complement(of: segments, in: 0...duration)
        ForEach(gaps.indices, id: \.self) { i in
            let gap = gaps[i]
            Color.black.opacity(0.66)
                .frame(width: (gap.upperBound - gap.lowerBound) * zoom)
                .offset(x: gap.lowerBound * zoom, y: topY)
                .frame(width: duration * zoom, height: bottomY - topY, alignment: .topLeading)
        }
    }

    /// [0, d] 减去 segments 的补集
    private func complement(of segments: [EditSegment], in range: ClosedRange<Double>) -> [ClosedRange<Double>] {
        var result: [ClosedRange<Double>] = []
        var cursor = range.lowerBound
        for seg in segments.sorted(by: { $0.start < $1.start }) {
            if seg.start > cursor { result.append(cursor...min(seg.start, range.upperBound)) }
            cursor = max(cursor, seg.end)
        }
        if cursor < range.upperBound { result.append(cursor...range.upperBound) }
        return result.filter { $0.upperBound - $0.lowerBound > 0.02 }
    }

    // MARK: 段白框与把手

    @ViewBuilder
    private var segmentFrames: some View {
        ForEach(segments.indices, id: \.self) { i in
            let seg = segments[i]
            let isSelected = seg.id == selectedID
            // 白框主体：填充整段矩形作为点击热区（描边本身只有 2.5px，点不中）
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(isSelected ? 0.02 : 0.001))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.white : Color.white.opacity(0.4),
                                lineWidth: isSelected ? 2.5 : 1.5)
                )
                .frame(width: seg.length * zoom, height: 48 + CGFloat(waveforms.count) * 26
                       + (dubTakes.isEmpty ? 0 : 26) - 2)
                .offset(x: seg.start * zoom, y: 18)
                .contentShape(Rectangle())
                .onTapGesture { onSegmentTap?(seg.id) }

            if isSelected {
                TrimHandleView()
                    .offset(x: seg.start * zoom - 7, y: 18 + 12)
                    .gesture(handleDrag(index: i, isStart: true))
                TrimHandleView()
                    .offset(x: seg.end * zoom - 7, y: 18 + 12)
                    .gesture(handleDrag(index: i, isStart: false))
            }
        }
    }

    private func handleDrag(index: Int, isStart: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in onHandleDrag?(index, isStart, g) }
            .onEnded { _ in onHandleEnd?() }
    }

    @ViewBuilder
    private var snapLine: some View {
        if let snap = snapFraction {
            Rectangle()
                .fill(Color.themeBlue500.opacity(0.8))
                .frame(width: 1.5)
                .offset(x: snap * duration * zoom)
        }
    }

    private var dubColor: Color { Color(red: 245/255, green: 158/255, blue: 11/255) }
    private var capColor: Color { Color(red: 34/255, green: 197/255, blue: 94/255) }
}

private struct TrimHandleView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white)
            .frame(width: 14, height: 46)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 2)
            .contentShape(Rectangle())
    }
}

private struct LaneWave: View {
    let values: [Float]
    let color: Color
    var opacity: Double = 1

    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty else { return }
            let barWidth = size.width / CGFloat(values.count)
            for (i, v) in values.enumerated() {
                let h = max(1.5, CGFloat(v) * size.height)
                let rect = CGRect(x: CGFloat(i) * barWidth,
                                  y: (size.height - h) / 2,
                                  width: max(0.8, barWidth - 0.6),
                                  height: h)
                context.fill(Path(roundedRect: rect, cornerRadius: 0.8), with: .color(color.opacity(opacity)))
            }
        }
    }
}

private struct AudioLevelBars: View {
    let level: Float
    let color: Color

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2.5, height: barHeight(i))
            }
        }
        .frame(height: 14, alignment: .bottom)
        .animation(.linear(duration: 0.08), value: level)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let thresholds: [Float] = [0.04, 0.22, 0.5]
        let spans: [Float] = [0.28, 0.4, 0.5]
        let value = max(0, min(1, (level - thresholds[index]) / spans[index]))
        return 3 + CGFloat(value) * 11
    }
}
