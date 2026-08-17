import SwiftUI
import AppKit
import AVFoundation
import Combine
import CoreMedia

// MARK: - 裁剪模型（纯值类型，秒域）

/// 一段被裁掉的时间区间
struct CutSegment: Identifiable, Equatable {
    let id = UUID()
    var start: Double
    var end: Double
    var length: Double { end - start }
}

enum CutTarget: Equatable {
    case video
    case track(Int)
}

struct TimelineSelection: Equatable {
    var target: CutTarget
    var startFrac: Double
    var endFrac: Double
}

/// 区间数学（排序/合并/求补集）
enum V2CutMath {
    /// 排序 + 合并重叠 + 去掉过短片段
    static func normalize(_ input: [CutSegment]) -> [CutSegment] {
        let sorted = input.sorted { $0.start < $1.start }
        var out: [CutSegment] = []
        for c in sorted {
            if let last = out.last, c.start <= last.end {
                out[out.count - 1].end = max(last.end, c.end)
            } else {
                out.append(c)
            }
        }
        return out.filter { $0.length > 0.01 }
    }

    /// [lo, hi] 减去 cuts 的补集（保留区间列表）
    static func keepRanges(lo: Double, hi: Double, minus cuts: [CutSegment]) -> [(Double, Double)] {
        var result: [(Double, Double)] = []
        var cursor = lo
        for c in normalize(cuts) {
            let s = max(c.start, lo), e = min(c.end, hi)
            if e <= cursor || s >= hi { continue }
            if s > cursor { result.append((cursor, s)) }
            cursor = max(cursor, e)
        }
        if cursor < hi { result.append((cursor, hi)) }
        return result
    }

    /// [lo, t] 与 cuts 的重叠总长（原始时间 → 成片时间的偏移量）
    static func removedBefore(_ t: Double, lo: Double, hi: Double, cuts: [CutSegment]) -> Double {
        var removed = 0.0
        for c in normalize(cuts) {
            let s = max(c.start, lo), e = min(c.end, hi)
            guard e > lo, s < hi else { continue }
            removed += max(0, min(e, t) - s)
        }
        return removed
    }
}

// MARK: - 窗口与控制器

/// 支持 ESC 关闭的预览窗口面板
final class V2RecordingPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) {
        V2RecordingPreviewController.shared.close()
    }
}

/// 录屏预览工作台：录完即进，自定义播放器 + 时间线（缩略图/音轨波形）
/// + 完整裁剪（掐头去尾/中间多段删除/音轨静音/音轨分段裁剪）
///
/// 交互定位（对应原型 ⑤⑥）：停止录制 → 文件已落盘 + 路径已复制 → 打开本窗口。
/// 播放的是「合成结果」——任何裁剪/静音实时反映在播放里（所见即所得）；
/// 导出与播放共用同一个 AVMutableComposition。
@MainActor
final class V2RecordingPreviewController {
    static let shared = V2RecordingPreviewController()
    private var panel: NSPanel?
    private var player: AVPlayer?

    func show(fileURL: URL) {
        if panel == nil {
            let p = V2RecordingPreviewPanel(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            p.title = "录屏预览"
            p.level = .floating
            p.isFloatingPanel = true
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.appearance = NSAppearance(named: .darkAqua)
            p.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0)
            p.minSize = NSSize(width: 760, height: 560)
            panel = p
        }

        player?.pause()
        player = nil

        let player = AVPlayer(playerItem: AVPlayerItem(url: fileURL))
        self.player = player

        panel?.title = fileURL.deletingPathExtension().lastPathComponent
        panel?.contentView = NSHostingView(
            rootView: V2RecordingPreviewView(fileURL: fileURL, player: player))
        panel?.center()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        player.play()

        DiagnosticCenter.info("Recording", "预览窗口已打开：\(fileURL.lastPathComponent)")
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
            player.play()
        }
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }
}

// MARK: - 视频画面层

private final class PlayerLayerNSView: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func makeBackingLayer() -> CALayer { AVPlayerLayer() }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
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

// MARK: - 预览主视图

struct V2RecordingPreviewView: View {
    let fileURL: URL
    let player: AVPlayer

    @StateObject private var playback: V2PlaybackModel
    @StateObject private var assetInfo = V2RecordingAssetInfo()

    // 掐头去尾（0...1 全片比例）
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 1
    // 中间多段删除（视频级：画面+全部声音都剪掉）
    @State private var videoCuts: [CutSegment] = []
    // 每条音轨自己的裁剪（只静音该轨该段，画面与另一轨不受影响）
    @State private var trackCuts: [[CutSegment]] = []
    // 整轨静音（导出时不写入）
    @State private var mutedTracks: Set<Int> = []
    // 时间线拖选（待确认的删除区间）
    @State private var selection: TimelineSelection?

    @State private var isExporting = false
    @State private var copied = false
    @State private var exportError: String?
    @State private var rebuildTask: Task<Void, Never>?
    @State private var savedToNotes = false
    /// 磁吸命中时的吸附位置（全片比例），用于绘制吸附指示线
    @State private var snapIndicator: Double?

    init(fileURL: URL, player: AVPlayer) {
        self.fileURL = fileURL
        self.player = player
        _playback = StateObject(wrappedValue: V2PlaybackModel(player: player))
    }

    private var duration: Double { max(0.001, assetInfo.duration) }
    private var trimStartDur: Double { trimStart * duration }
    private var trimEndDur: Double { trimEnd * duration }

    private var normalizedCuts: [CutSegment] {
        V2CutMath.normalize(videoCuts)
    }

    /// 成片时长（掐头去尾 + 中间删除后）
    private var keepDuration: Double {
        (trimEndDur - trimStartDur)
            - V2CutMath.removedBefore(trimEndDur, lo: trimStartDur, hi: trimEndDur, cuts: videoCuts)
    }

    private var hasEdits: Bool {
        isTrimmed || !videoCuts.isEmpty
            || trackCuts.contains(where: { !$0.isEmpty })
            || !mutedTracks.isEmpty
    }

    private var isTrimmed: Bool { trimStart > 0.001 || trimEnd < 0.999 }

    // MARK: 时间映射（原始时间轴 ↔ 成片时间轴；无裁剪时恒等）

    private func timelineTime(fromOriginal t: Double) -> Double {
        t - trimStartDur
            - V2CutMath.removedBefore(min(max(t, trimStartDur), trimEndDur),
                                      lo: trimStartDur, hi: trimEndDur, cuts: videoCuts)
    }

    private func originalTime(fromTimeline x: Double) -> Double {
        var cursor = trimStartDur
        var remaining = max(0, x)
        for c in normalizedCuts {
            let s = max(c.start, trimStartDur), e = min(c.end, trimEndDur)
            guard e > cursor, s < trimEndDur else { continue }
            if remaining < s - cursor { return cursor + remaining }
            remaining -= s - cursor
            cursor = e
        }
        return cursor + remaining
    }

    /// 播放头显示用的原始时间
    private var displayOriginalTime: Double {
        originalTime(fromTimeline: playback.currentTime)
    }

    var body: some View {
        VStack(spacing: 0) {
            playerArea
            timelineSection
            segmentBar
            infoStrip
            actionBar
        }
        .onAppear { assetInfo.load(fileURL: fileURL) }
        .onChange(of: assetInfo.waveforms.count) { _ in
            trackCuts = Array(repeating: [], count: assetInfo.waveforms.count)
        }
        .onChange(of: videoCuts) { _ in schedulePlaybackRebuild() }
        .onChange(of: trackCuts) { _ in schedulePlaybackRebuild() }
        .onChange(of: mutedTracks) { _ in schedulePlaybackRebuild() }
        .onChange(of: trimStart) { _ in schedulePlaybackRebuild() }
        .onChange(of: trimEnd) { _ in schedulePlaybackRebuild() }
    }

    // MARK: 播放区

    private var playerArea: some View {
        ZStack {
            PlayerLayerView(player: player)
                .background(Color.black)

            if !playback.isPlaying {
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
                Spacer()
                customControls
                    .padding(.horizontal, ThemeSpacing.px4.rawValue)
                    .padding(.bottom, ThemeSpacing.px2.rawValue + 4)
                    .background(
                        LinearGradient(colors: [.clear, .black.opacity(0.65)],
                                       startPoint: .top, endPoint: .bottom)
                    )
            }
        }
        .frame(minHeight: 240)
        .contentShape(Rectangle())
        .onTapGesture { playback.toggle() }
    }

    private var customControls: some View {
        HStack(spacing: ThemeSpacing.px3.rawValue) {
            Button(action: { playback.toggle() }) {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(timeLabel(displayOriginalTime))
                .font(.themeCaption)
                .monospacedDigit()
                .fixedSize()
                .foregroundColor(.white)

            GeometryReader { geo in
                let progress = min(1, max(0, displayOriginalTime / duration))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25)).frame(height: 4)
                    Capsule().fill(Color.white)
                        .frame(width: max(4, geo.size.width * progress), height: 4)
                    Circle().fill(Color.white)
                        .frame(width: 11, height: 11)
                        .offset(x: geo.size.width * progress - 5.5)
                        .shadow(radius: 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { g in
                        let fraction = min(1, max(0, g.location.x / max(1, geo.size.width)))
                        let original = duration * fraction
                        playback.seek(to: timelineTime(fromOriginal: original))
                    }
                )
            }
            .frame(height: 14)

            Text(hasEdits ? "成片 \(timeLabel(keepDuration))" : timeLabel(duration))
                .font(.themeCaption)
                .monospacedDigit()
                .fixedSize()
                .foregroundColor(hasEdits ? .themeYellow500 : .white.opacity(0.8))
        }
    }

    // MARK: 时间线（缩略图 + 音轨波形 + 播放头 + 手柄 + 拖选）

    private var timelineSection: some View {
        VStack(spacing: ThemeSpacing.px1.rawValue + 4) {
            if assetInfo.thumbnails.isEmpty && assetInfo.waveforms.isEmpty {
                HStack(spacing: ThemeSpacing.px2.rawValue) {
                    ProgressView().controlSize(.small)
                    Text("正在分析画面与音轨…")
                        .font(.themeCaption)
                        .foregroundColor(.themeTextTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                HStack(alignment: .top, spacing: ThemeSpacing.px2.rawValue) {
                    // 左侧标签列（与时间线行高对齐）
                    VStack(alignment: .leading, spacing: 3) {
                        Text("画面")
                            .font(.themeCaptionSmall)
                            .foregroundColor(.themeTextTertiary)
                            .frame(height: 44, alignment: .center)
                        ForEach(assetInfo.waveforms.indices, id: \.self) { i in
                            HStack(spacing: 4) {
                                Text(assetInfo.waveforms[i].label)
                                    .font(.themeCaptionSmall)
                                    .foregroundColor(assetInfo.waveforms[i].color)
                                    .fixedSize()
                                Button(action: { toggleMute(i) }) {
                                    Image(systemName: mutedTracks.contains(i) ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(mutedTracks.contains(i) ? Color.themeRed400 : assetInfo.waveforms[i].color)
                                        .frame(width: 16, height: 16)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(mutedTracks.contains(i) ? "此轨已静音（点击恢复）" : "静音此轨（导出不含）")
                            }
                            .frame(height: 26, alignment: .leading)
                        }
                    }
                    .frame(width: 84, alignment: .leading)

                    // 时间线主体（所有元素共享同一坐标系）
                    GeometryReader { geo in
                        let width = max(1, geo.size.width)
                        ZStack(alignment: .topLeading) {
                            filmstripView
                                .frame(height: 44, alignment: .top)

                            waveformRows(width: width)
                                .padding(.top, 48)

                            // 掐头去尾遮罩（左右压暗 + 黄线）
                            trimShadow(width: width)

                            // 拖选（视频级）：缩略图条上的红色选区
                            if let sel = selection, case .video = sel.target {
                                selectionOverlay(start: sel.startFrac, end: sel.endFrac)
                                    .frame(height: 44)
                            }

                            // 智能卡点：◆ 场景切换（点卡点跳转播放）
                            sceneMarkers(width: width)

                            // 磁吸指示线（手柄吸附到卡点时显示）
                            if let snap = snapIndicator {
                                Rectangle()
                                    .fill(Color.themeYellow500.opacity(0.8))
                                    .frame(width: 1.5)
                                    .offset(x: width * snap)
                                    .allowsHitTesting(false)
                            }

                            // 播放头
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 1.5)
                                .offset(x: width * min(1, max(0, displayOriginalTime / duration)))
                                .shadow(color: .black.opacity(0.6), radius: 1)
                                .allowsHitTesting(false)

                            // 黄色手柄（掐头去尾）
                            TrimHandle()
                                .offset(x: width * trimStart - 5)
                                .gesture(handleDrag(width: width, isStart: true))
                            TrimHandle()
                                .offset(x: width * trimEnd - 5)
                                .gesture(handleDrag(width: width, isStart: false))

                            // 缩略图条自身的拖选手势（视频级删除）
                            Color.clear
                                .frame(height: 44)
                                .contentShape(Rectangle())
                                .gesture(rowDragGesture(target: .video, width: width))
                        }
                        // 点击定位（点手柄/波形行以外区域）
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture().onEnded { tap in
                                let fraction = min(1, max(0, tap.location.x / width))
                                playback.seek(to: timelineTime(fromOriginal: duration * fraction))
                            }
                        )
                    }
                    .frame(height: timelineHeight)
                }
            }

            // 修剪信息行 + 选区操作
            trimInfoRow
        }
        .padding(.horizontal, ThemeSpacing.px4.rawValue)
        .padding(.top, ThemeSpacing.px2.rawValue + 2)
        .padding(.bottom, ThemeSpacing.px1.rawValue + 2)
        .background(Color.themeGray900)
    }

    /// 缩略图条
    private var filmstripView: some View {
        HStack(spacing: 2) {
            ForEach(assetInfo.thumbnails.indices, id: \.self) { i in
                Image(nsImage: assetInfo.thumbnails[i])
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: 44)
                    .clipped()
                    .cornerRadius(2)
            }
        }
    }

    /// ◆ 场景切换卡点（缩略图条上方一排，点击跳转）
    private func sceneMarkers(width: CGFloat) -> some View {
        ForEach(assetInfo.sceneCuts, id: \.self) { time in
            Text("◆")
                .font(.system(size: 9))
                .foregroundColor(.themeYellow500)
                .frame(width: 12, height: 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    playback.seek(to: timelineTime(fromOriginal: time))
                }
                .help("场景切换 \(timeLabel(time)) · 点击跳转")
                .offset(x: width * time / duration - 6, y: -10)
        }
    }

    /// 音轨波形行（含该轨裁剪红区、该轨拖选、拖选手势）
    private func waveformRows(width: CGFloat) -> some View {
        VStack(spacing: 3) {
            ForEach(assetInfo.waveforms.indices, id: \.self) { i in
                waveRow(i: i, width: width)
            }
        }
    }

    private func waveRow(i: Int, width: CGFloat) -> some View {
        let waveform = assetInfo.waveforms[i]
        let cuts = trackCuts.indices.contains(i) ? trackCuts[i] : []
        let rowPeaks = assetInfo.audioPeaks.indices.contains(i) ? assetInfo.audioPeaks[i] : []
        let rowSelection: TimelineSelection? = {
            guard let sel = selection, case .track(let ti) = sel.target, ti == i else { return nil }
            return sel
        }()

        return ZStack {
            WaveformBars(values: waveform.values, color: waveform.color,
                         dimmed: mutedTracks.contains(i))
                .frame(height: 26)

            ForEach(cuts) { cut in
                redZone(startFrac: cut.start / duration,
                        lengthFrac: cut.length / duration)
                    .frame(height: 26)
            }

            // ▲ 音频高潮卡点（该轨波形底部，点击跳转）
            ForEach(rowPeaks, id: \.self) { time in
                Text("▲")
                    .font(.system(size: 9))
                    .foregroundColor(waveform.color)
                    .frame(width: 12, height: 10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playback.seek(to: timelineTime(fromOriginal: time))
                    }
                    .help("音频高潮 \(timeLabel(time)) · 点击跳转")
                    .offset(x: width * time / duration - 6, y: 14)
            }

            if let sel = rowSelection {
                selectionOverlay(start: sel.startFrac, end: sel.endFrac)
                    .frame(height: 26)
            }
        }
        .frame(height: 26)
        .contentShape(Rectangle())
        .gesture(rowDragGesture(target: .track(i), width: width))
    }

    // MARK: 卡点磁吸

    /// 全部吸附目标（全片比例）：场景切换 + 各轨音频高潮
    private var snapFractions: [Double] {
        var fractions = assetInfo.sceneCuts.map { $0 / duration }
        for peaks in assetInfo.audioPeaks {
            fractions += peaks.map { $0 / duration }
        }
        return fractions
    }

    /// 距最近卡点 < 0.8% 宽度时吸附；命中时记录指示线位置
    private func snap(_ fraction: Double) -> Double {
        let tolerance = 0.008
        var best = fraction
        var bestDistance = tolerance
        for candidate in snapFractions {
            let distance = abs(candidate - fraction)
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        if best != fraction {
            snapIndicator = best
        } else {
            snapIndicator = nil
        }
        return best
    }

    private var timelineHeight: CGFloat {
        48 + CGFloat(assetInfo.waveforms.count) * 29 + 6
    }

    private func handleDrag(width: CGFloat, isStart: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let raw = min(1, max(0, g.location.x / width))
                let fraction = snap(raw) // 卡点磁吸（◆场景切换/▲音频高潮）
                if isStart {
                    trimStart = min(trimEnd - 0.01, fraction)
                } else {
                    trimEnd = max(trimStart + 0.01, fraction)
                }
            }
            .onEnded { _ in snapIndicator = nil }
    }

    private func rowDragGesture(target: CutTarget, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { g in
                let f1 = min(1, max(0, g.startLocation.x / width))
                let f2 = snap(min(1, max(0, g.location.x / width))) // 选区终点磁吸卡点
                selection = TimelineSelection(target: target,
                                               startFrac: min(f1, f2),
                                               endFrac: max(f1, f2))
            }
            .onEnded { g in
                snapIndicator = nil
                // 误触保护：太短的选择视为点击（交给 tap 定位），清空选区
                if abs(g.location.x - g.startLocation.x) < 12 {
                    selection = nil
                }
            }
    }

    private var selectionZone: some View { EmptyView() }

    /// 待删除选区的红色覆盖（需要外部提供起止比例）
    private func selectionOverlay(start: Double, end: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.red.opacity(0.28)
                    .frame(width: geo.size.width * max(0.005, end - start))
                    .frame(width: geo.size.width, alignment: .leading)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.themeRed500).frame(width: 1.5)
                    }
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Color.themeRed500).frame(width: 1.5)
                    }
                    .offset(x: geo.size.width * start)
            }
            .allowsHitTesting(false)
        }
    }

    private func redZone(startFrac: Double, lengthFrac: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.red.opacity(0.32)
                    .frame(width: geo.size.width * max(0.004, lengthFrac))
                    .frame(width: geo.size.width, alignment: .leading)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.themeRed400, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            .frame(width: geo.size.width * max(0.004, lengthFrac))
                            .frame(width: geo.size.width, alignment: .leading)
                    )
                    .offset(x: geo.size.width * startFrac)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func trimShadow(width: CGFloat) -> some View {
        Color.black.opacity(0.55)
            .frame(width: max(0, width * trimStart), height: timelineHeight - 44)
            .frame(width: width, height: timelineHeight - 44, alignment: .leading)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color.themeYellow500.opacity(0.9)).frame(width: 2)
            }
        Color.black.opacity(0.55)
            .frame(width: max(0, width * (1 - trimEnd)), height: timelineHeight - 44)
            .frame(width: width, height: timelineHeight - 44, alignment: .trailing)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.themeYellow500.opacity(0.9)).frame(width: 2)
            }
    }

    private var trimInfoRow: some View {
        HStack(spacing: ThemeSpacing.px2.rawValue) {
            if let sel = selection {
                Text("已选 \(timeLabel(duration * sel.startFrac))–\(timeLabel(duration * sel.endFrac))（\(selectionLabel(for: sel.target))）")
                    .font(.themeCaptionSmall)
                    .foregroundColor(.themeRed400)
                    .fixedSize()
                miniButton("✂ 删除此段", prominent: true) { commitSelection(sel) }
                miniButton("取消", prominent: false) { selection = nil }
            } else {
                Text("保留 \(timeLabel(trimStartDur)) – \(timeLabel(trimEndDur))"
                     + (videoCuts.isEmpty ? "" : " · 已删 \(videoCuts.count) 段")
                     + " · 成片 \(timeLabel(keepDuration))")
                    .font(.themeCaptionSmall)
                    .foregroundColor(hasEdits ? .themeYellow500 : .themeTextTertiary)
                    .monospacedDigit()
            }

            Spacer()

            if !videoCuts.isEmpty || trackCuts.contains(where: { !$0.isEmpty }) {
                miniButton("撤销一刀", prominent: false, action: undoLastCut)
            }
            if hasEdits {
                miniButton("清空裁剪", prominent: false, action: resetEdits)
            }
        }
        .frame(height: 22)
    }

    // MARK: 段条（成片结构预览）

    @ViewBuilder
    private var segmentBar: some View {
        if videoCuts.isEmpty && !isTrimmed {
            EmptyView()
        } else {
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                HStack(spacing: 2) {
                    // 头部裁掉
                    if trimStart > 0.001 {
                        segment(color: .themeRed500, dashed: true, label: "✂",
                                width: width * trimStart) { resetTrimEnds() }
                    }
                    // 保留段与删除段交替
                    let keeps = V2CutMath.keepRanges(lo: trimStartDur, hi: trimEndDur, minus: videoCuts)
                    ForEach(keeps.indices, id: \.self) { i in
                        let (ks, ke) = keeps[i]
                        segment(color: .themeGreen500, dashed: false,
                                label: i == 0 ? "保留" : "",
                                width: width * (ke - ks) / duration) {}
                        if i < keeps.count - 1, videoCuts.indices.contains(i) {
                            let cut = videoCuts[i]
                            segment(color: .themeRed500, dashed: true, label: "✂",
                                    width: width * cut.length / duration) {
                                removeCut(cut.id)
                            }
                        }
                    }
                    // 尾部裁掉
                    if trimEnd < 0.999 {
                        segment(color: .themeRed500, dashed: true, label: "✂",
                                width: width * (1 - trimEnd)) { resetTrimEnds() }
                    }
                }
                .frame(width: width, alignment: .leading)
            }
            .frame(height: 16)
            .padding(.horizontal, ThemeSpacing.px4.rawValue)
            .background(Color.themeGray900)
        }
    }

    private func segment(color: Color, dashed: Bool, label: String,
                         width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(color == .themeRed500 ? Color.themeRed400 : Color.themeGreen500)
                .frame(width: max(6, width), height: 14)
                .background(
                    Rectangle()
                        .fill(color.opacity(0.22))
                        .overlay(
                            Rectangle()
                                .stroke(color.opacity(0.6),
                                        style: dashed ? StrokeStyle(lineWidth: 1, dash: [3, 2]) : StrokeStyle(lineWidth: 1))
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(label != "✂")
        .help(label == "✂" ? "点击撤销这一刀" : "")
    }

    // MARK: 信息条 & 操作栏

    private var infoStrip: some View {
        HStack(spacing: ThemeSpacing.px3.rawValue) {
            if assetInfo.duration > 0 {
                Text(String(format: "⏱ %.1f 秒", assetInfo.duration))
            }
            if !assetInfo.pixelText.isEmpty {
                Text(assetInfo.pixelText)
            }
            if assetInfo.waveforms.isEmpty {
                Text("🔇 无声")
            } else if !mutedTracks.isEmpty {
                Text("🔊 \(assetInfo.waveforms.count - mutedTracks.count)/\(assetInfo.waveforms.count) 路音轨")
                    .foregroundColor(.themeYellow500)
            } else {
                Text("🔊 \(assetInfo.waveforms.count) 路音轨")
            }
            if !assetInfo.fileSizeText.isEmpty {
                Text(assetInfo.fileSizeText)
            }
        }
        .font(.themeCaption)
        .foregroundColor(.themeTextSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(1)
        .padding(.horizontal, ThemeSpacing.px4.rawValue)
        .padding(.vertical, ThemeSpacing.px1.rawValue + 2)
        .background(Color.themeGray800.opacity(0.5))
    }

    private var actionBar: some View {
        HStack(spacing: ThemeSpacing.px2.rawValue + 2) {
            Button(action: copyPath) {
                actionLabel(icon: "doc.on.doc", text: copied ? "已复制" : "复制路径",
                            color: copied ? .themeStatusSuccess : .themeTextPrimary)
            }
            .buttonStyle(.plain)

            Button(action: { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }) {
                actionLabel(icon: "folder", text: "Finder 中显示", color: .themeTextPrimary)
            }
            .buttonStyle(.plain)

            Button(action: saveToNotes) {
                actionLabel(icon: savedToNotes ? "checkmark" : "tray.and.arrow.down",
                            text: savedToNotes ? "已存入闪记" : "存入闪记",
                            color: savedToNotes ? .themeStatusSuccess : .themeTextPrimary)
            }
            .buttonStyle(.plain)
            .disabled(savedToNotes)
            .help("创建闪记记录（首帧缩略图 + 路径引用，不拷贝视频本体）")

            Spacer()

            if let error = exportError {
                Text(error)
                    .font(.themeCaptionSmall)
                    .foregroundColor(.themeStatusError)
                    .lineLimit(1)
                    .help(error)
            }

            if hasEdits {
                Button(action: exportFinal) {
                    HStack(spacing: ThemeSpacing.px1.rawValue + 2) {
                        if isExporting {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "scissors")
                                .font(.system(size: 12))
                        }
                        Text(isExporting ? "导出中…" : "导出成片")
                            .font(.themeBody)
                            .fixedSize()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, ThemeSpacing.px3.rawValue)
                    .padding(.vertical, ThemeSpacing.px1.rawValue + 3)
                    .background(
                        RoundedRectangle(cornerRadius: ThemeRadius.md.rawValue)
                            .fill(isExporting ? AnyShapeStyle(Color.themeGray600) : AnyShapeStyle(Color.themeRed500))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isExporting)
                .help("按当前裁剪/静音导出（直通不转码，秒级）")
            }

            Button(action: { V2RecordingPreviewController.shared.close() }) {
                Text("关闭")
                    .font(.themeBody)
                    .fixedSize()
                    .foregroundColor(.white)
                    .padding(.horizontal, ThemeSpacing.px4.rawValue)
                    .padding(.vertical, ThemeSpacing.px1.rawValue + 3)
                    .background(
                        RoundedRectangle(cornerRadius: ThemeRadius.md.rawValue)
                            .fill(Color.themePurple500)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, ThemeSpacing.px4.rawValue)
        .padding(.vertical, ThemeSpacing.px2.rawValue + 2)
        .background(Color.themeGray900)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.themeBorderSubtle), alignment: .top)
    }

    // MARK: 剪辑动作

    private func toggleMute(_ i: Int) {
        if mutedTracks.contains(i) {
            mutedTracks.remove(i)
        } else {
            mutedTracks.insert(i)
        }
    }

    private func commitSelection(_ sel: TimelineSelection) {
        defer { selection = nil }
        guard sel.endFrac - sel.startFrac > 0.005 else { return }
        let cut = CutSegment(start: duration * sel.startFrac, end: duration * sel.endFrac)
        switch sel.target {
        case .video:
            videoCuts = V2CutMath.normalize(videoCuts + [cut])
        case .track(let i):
            guard trackCuts.indices.contains(i) else { return }
            trackCuts[i] = V2CutMath.normalize(trackCuts[i] + [cut])
        }
    }

    private func removeCut(_ id: UUID) {
        videoCuts.removeAll { $0.id == id }
    }

    private func undoLastCut() {
        if !videoCuts.isEmpty {
            videoCuts.removeLast()
            return
        }
        for i in stride(from: trackCuts.count - 1, through: 0, by: -1) where !trackCuts[i].isEmpty {
            trackCuts[i].removeLast()
            return
        }
    }

    private func resetTrimEnds() {
        withAnimation(.easeInOut(duration: 0.15)) {
            trimStart = 0
            trimEnd = 1
        }
    }

    private func resetEdits() {
        withAnimation(.easeInOut(duration: 0.15)) {
            trimStart = 0
            trimEnd = 1
        }
        videoCuts = []
        for i in trackCuts.indices { trackCuts[i] = [] }
        mutedTracks = []
        selection = nil
    }

    // MARK: 播放重建（合成实时预览）

    private func schedulePlaybackRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 防抖：拖手柄时不要反复重建
            guard !Task.isCancelled, !isExporting else { return }
            await rebuildPlayback()
        }
    }

    private func rebuildPlayback() async {
        let wasPlaying = playback.isPlaying
        let originalNow = originalTime(fromTimeline: playback.currentTime)

        if hasEdits, let composition = try? await buildComposition() {
            player.replaceCurrentItem(with: AVPlayerItem(asset: composition))
        } else {
            player.replaceCurrentItem(with: AVPlayerItem(asset: AVURLAsset(url: fileURL)))
        }

        playback.seek(to: timelineTime(fromOriginal: originalNow))
        if wasPlaying {
            player.play()
        }
    }

    /// 合成 = 视频按保留区间拼接 + 未静音音轨按各自保留区间拼接
    private func buildComposition() async throws -> AVMutableComposition? {
        let asset = AVURLAsset(url: fileURL)
        guard let videoSource = (try? await asset.loadTracks(withMediaType: .video))?.first else { return nil }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }

        let videoKeeps = V2CutMath.keepRanges(lo: trimStartDur, hi: trimEndDur, minus: videoCuts)
        guard !videoKeeps.isEmpty else { return nil }

        var insertedAny = false
        for (ks, ke) in videoKeeps {
            let range = CMTimeRange(start: CMTime(seconds: ks, preferredTimescale: 600),
                                    end: CMTime(seconds: ke, preferredTimescale: 600))
            try? videoTrack.insertTimeRanges([NSValue(timeRange: range)], of: [videoSource], at: .zero)
            insertedAny = true
        }
        guard insertedAny else { return nil }

        for (i, source) in assetInfo.audioTracks.enumerated() where !mutedTracks.contains(i) {
            let extra = trackCuts.indices.contains(i) ? trackCuts[i] : []
            let keeps = V2CutMath.keepRanges(lo: trimStartDur, hi: trimEndDur, minus: videoCuts + extra)
            guard !keeps.isEmpty,
                  let audioTrack = composition.addMutableTrack(
                    withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            for (ks, ke) in keeps {
                let range = CMTimeRange(start: CMTime(seconds: ks, preferredTimescale: 600),
                                        end: CMTime(seconds: ke, preferredTimescale: 600))
                try? audioTrack.insertTimeRanges([NSValue(timeRange: range)], of: [source], at: .zero)
            }
        }
        return composition
    }

    // MARK: 导出

    private func exportFinal() {
        guard hasEdits, !isExporting else { return }
        isExporting = true
        exportError = nil

        Task {
            do {
                guard let composition = try await buildComposition() else {
                    throw V2TrimExporter.TrimError.exportFailed("内容被裁空")
                }
                let trimmedURL = try await V2TrimExporter.exportComposition(composition)
                // 原地替换：文件名/已复制的路径保持有效
                try? FileManager.default.removeItem(at: fileURL)
                try? FileManager.default.moveItem(at: trimmedURL, to: fileURL)
                DiagnosticCenter.info("Recording", "裁剪导出完成：\(fileURL.lastPathComponent)")
                V2RecordingPreviewController.shared.show(fileURL: fileURL)
            } catch {
                exportError = error.localizedDescription
                DiagnosticCenter.error("Recording", "裁剪导出失败：\(error.localizedDescription)")
            }
            isExporting = false
        }
    }

    // MARK: 小部件

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
        ScreenshotService.shared.saveRecordingToFlashNotes(fileURL: fileURL,
                                                           duration: assetInfo.duration)
    }

    private func selectionLabel(for target: CutTarget) -> String {
        switch target {
        case .video: return "画面段"
        case .track(let i):
            return assetInfo.waveforms.indices.contains(i) ? assetInfo.waveforms[i].label : "音轨"
        }
    }

    private func miniButton(_ text: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.themeCaptionSmall)
                .fixedSize()
                .foregroundColor(prominent ? .white : .themeTextSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(prominent ? Color.themeRed500 : Color.themeGray700)
                )
        }
        .buttonStyle(.plain)
    }

    private func actionLabel(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: ThemeSpacing.px1.rawValue + 2) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(text)
                .font(.themeBody)
                .fixedSize()
        }
        .foregroundColor(color)
        .padding(.horizontal, ThemeSpacing.px3.rawValue)
        .padding(.vertical, ThemeSpacing.px1.rawValue + 3)
        .background(
            RoundedRectangle(cornerRadius: ThemeRadius.md.rawValue)
                .fill(Color.themeGray700)
        )
    }

    private func timeLabel(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - 时间线子组件

private struct TrimHandle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.themeYellow500)
            .frame(width: 10, height: 40)
            .shadow(color: .black.opacity(0.5), radius: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
            .contentShape(Rectangle())
    }
}

private struct WaveformBars: View {
    let values: [Float]
    let color: Color
    var dimmed: Bool = false

    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty else { return }
            let barColor = dimmed ? color.opacity(0.25) : color
            let barWidth = size.width / CGFloat(values.count)
            for (i, v) in values.enumerated() {
                let h = max(1.5, CGFloat(v) * size.height)
                let rect = CGRect(x: CGFloat(i) * barWidth,
                                  y: (size.height - h) / 2,
                                  width: max(0.8, barWidth - 0.6),
                                  height: h)
                context.fill(Path(roundedRect: rect, cornerRadius: 0.8), with: .color(barColor))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: dimmed)
    }
}
