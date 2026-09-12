import Foundation
import AppKit
import AVFoundation
import CoreMedia
import CoreVideo
import ScreenCaptureKit

/// 录制中的鼠标呈现方式
enum V2RecordingCursorMode: String, CaseIterable {
    case keep      // 保留鼠标（默认）
    case hide      // 隐藏鼠标（录教程去干扰）
    case highlight // 保留 + 点击高亮（macOS 14.2+，旧系统自动回退保留）

    var localizedName: String {
        switch self {
        case .keep: return "保留"
        case .hide: return "隐藏"
        case .highlight: return "点击高亮"
        }
    }
}

/// 录制引擎：SCStream 按选区采集（画面 + 可选系统声）→ AVAssetWriter 直写 .mp4（H.264 + AAC）
/// 麦克风由 V2MicrophoneRecorder 独立采集，经 ingestMicrophone 合流为第二条音轨。
///
/// 关键设计（对应调研结论，改动前先看 Tests 与 AGENTS.md）：
/// - 只接受 SCFrameStatus.complete 的帧，.idle/.blank/.suspended 全部丢弃
/// - startSession 以第一路到达的 buffer PTS 为基准（SCK 时间戳是 host clock 域）
/// - 停止时复制最后一帧、以「当前时刻 − 暂停时长」为新 PTS 补尾帧——
///   屏幕静止时 SCK 不产帧，不补会导致静止段成片只有几十毫秒
/// - 暂停用 PTS 前移法（V2RecordingTiming）：暂停期间丢弃全部三路输入，
///   恢复时累计暂停时长，后续帧有效 PTS = 原始 PTS − 暂停累计，成片无暂停痕迹
/// - 内容过滤器排除本应用全部窗口：录制 UI（红框/控制条/浮球）永不入画
/// - 必须实现 didStopWithError：权限被撤销/用户从菜单栏指示器停止时立即收尾
///
/// 线程模型：start/stop 由 MainActor 发起；帧回调在 frameQueue；麦克风在 mic queue；
/// writer 状态全部经 stateLock 保护（含 markAsFinished 与迟到帧互斥）。
final class V2ScreenRecorderEngine: NSObject, SCStreamOutput, SCStreamDelegate {

    struct Parameters {
        let display: SCDisplay
        /// 每屏局部坐标系（左上原点、points）的采集区域，已由 V2RecordingGeometry 钳制
        let sourceRect: CGRect
        let pixelWidth: Int
        let pixelHeight: Int
        let fps: Int
        let averageBitRate: Int
        /// 临时文件路径（收尾后由 V2RecordingFileFinalizer 移入用户目录）
        let outputURL: URL
        /// 排除出画面的本应用，找不到时传空数组
        let excludedApplications: [SCRunningApplication]
        /// 录系统声音（SCK loopback 免驱动）
        let captureSystemAudio: Bool
        /// 录麦克风（引擎只负责建轨与合流，采集由 V2MicrophoneRecorder 喂入）
        let captureMicrophone: Bool
        /// 鼠标呈现方式（保留/隐藏/点击高亮）
        let cursorMode: V2RecordingCursorMode
    }

    /// 被系统强制停止（权限撤销、菜单栏录屏指示器停止）时回调，主线程执行
    var onForcedStop: (() -> Void)?

    /// 系统声实时电平（0...1，frameQueue 上回调），控制条电平条用
    var onSystemAudioLevel: ((Float) -> Void)?

    private let frameQueue = DispatchQueue(label: "com.quitenote.recording.frames")
    private let stateLock = NSLock()

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var sessionStarted = false
    private var firstPTS = CMTime.invalid
    private var lastVideoPTS = CMTime.invalid
    private var lastSystemAudioPTS = CMTime.invalid
    private var lastMicPTS = CMTime.invalid
    /// 保留最近一帧用于停止时补尾帧；只持有一帧，surface 池（queueDepth 3–8）可承受
    private var lastVideoFrame: CMSampleBuffer?

    // 暂停状态（PTS 前移法）
    private var paused = false
    private var pauseStartedAt = CMTime.invalid
    private var pausedDuration = CMTime.zero

    private(set) var isRecording = false
    private(set) var isPaused = false

    /// 把锁的获取限制在同步函数内；Swift 6 不允许 async 函数直接调用 lock/unlock。
    private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try body()
    }

    // MARK: - 生命周期

    func start(parameters: Parameters) async throws {
        let alreadyRunning = withStateLock { isRecording }
        guard !alreadyRunning else { return }

        let filter = SCContentFilter(
            display: parameters.display,
            excludingApplications: parameters.excludedApplications,
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        config.sourceRect = parameters.sourceRect
        config.width = parameters.pixelWidth
        config.height = parameters.pixelHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(parameters.fps))
        config.queueDepth = 5
        config.showsCursor = (parameters.cursorMode != .hide)
        if parameters.cursorMode == .highlight, #available(macOS 15.0, *) {
            config.showMouseClicks = true
        }
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        if parameters.captureSystemAudio {
            config.capturesAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
            // 不录自己 app 的声音（提示音等）
            config.excludesCurrentProcessAudio = true
        }

        let writer = try AVAssetWriter(outputURL: parameters.outputURL, fileType: .mp4)

        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: parameters.pixelWidth,
            AVVideoHeightKey: parameters.pixelHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: parameters.averageBitRate,
            ],
        ])
        video.expectsMediaDataInRealTime = true
        writer.add(video)

        var systemAudio: AVAssetWriterInput?
        if parameters.captureSystemAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
            ])
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            systemAudio = input
        }

        var mic: AVAssetWriterInput?
        if parameters.captureMicrophone {
            // 麦克风轨：48k 单声道（与 V2MicrophoneRecorder 的目标格式一致）
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
            ])
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            mic = input
        }

        withStateLock {
            self.writer = writer
            self.videoInput = video
            self.systemAudioInput = systemAudio
            self.micInput = mic
            self.outputURL = parameters.outputURL
            self.sessionStarted = false
            self.firstPTS = .invalid
            self.lastVideoPTS = .invalid
            self.lastSystemAudioPTS = .invalid
            self.lastMicPTS = .invalid
            self.lastVideoFrame = nil
            self.paused = false
            self.isPaused = false
            self.pauseStartedAt = .invalid
            self.pausedDuration = .zero
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)
            if parameters.captureSystemAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: frameQueue)
            }
            try await stream.startCapture()
        } catch {
            withStateLock {
                self.writer = nil
                self.videoInput = nil
                self.systemAudioInput = nil
                self.micInput = nil
                self.outputURL = nil
            }
            throw error
        }

        withStateLock {
            self.stream = stream
            self.isRecording = true
        }
    }

    // MARK: - 暂停 / 恢复（PTS 前移法，见 V2RecordingTiming）

    func pause() {
        stateLock.lock()
        guard isRecording, !paused else {
            stateLock.unlock()
            return
        }
        paused = true
        isPaused = true
        pauseStartedAt = CMClockGetTime(CMClock.hostTimeClock)
        stateLock.unlock()
    }

    func resume() {
        stateLock.lock()
        guard paused else {
            stateLock.unlock()
            return
        }
        let now = CMClockGetTime(CMClock.hostTimeClock)
        pausedDuration = V2RecordingTiming.accumulatedPause(
            previous: pausedDuration, pauseStartedAt: pauseStartedAt, resumedAt: now)
        paused = false
        isPaused = false
        pauseStartedAt = .invalid
        stateLock.unlock()
    }

    // MARK: - 麦克风合流入口（V2MicrophoneRecorder 的 queue 上调用）

    func ingestMicrophone(_ sample: CMSampleBuffer) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let effective = V2RecordingTiming.effectivePTS(rawPTS: pts, pausedDuration: pausedDurationSafe())

        stateLock.lock()
        defer { stateLock.unlock() }

        guard isRecording, !paused, let input = micInput else { return }
        ensureSessionStarted(effectivePTS: effective)
        appendAudio(sample, effectivePTS: effective, lastPTS: &lastMicPTS, into: input)
    }

    /// 暂停读取也要加锁（ingest 在 mic queue 上，与 pause/resume 并发）
    private func pausedDurationSafe() -> CMTime {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pausedDuration
    }

    // MARK: - 停止 / 取消

    /// 停止并收尾：补静止尾帧 → 结束会话 → finishWriting
    /// - Returns: 已完成文件的 URL；一帧都没录到（立即停止）返回 nil
    func stop() async throws -> URL? {
        guard let preparation = prepareToStop() else { return nil }

        if let s = preparation.stream {
            try? await s.stopCapture()
        }

        guard preparation.hadSession, let writer = preparation.writer, let url = preparation.url else {
            // 一帧都没录到：清掉 writer 建立的空文件
            if let url = preparation.url {
                try? FileManager.default.removeItem(at: url)
            }
            DiagnosticCenter.info("Recording", "录制过短，未产生任何帧，已丢弃")
            return nil
        }

        await writer.finishWriting()

        guard writer.status == .completed else {
            let error = writer.error
            try? FileManager.default.removeItem(at: url)
            DiagnosticCenter.error("Recording", "写盘失败（磁盘满/编码错误）：\(String(describing: error))")
            throw error ?? NSError(domain: "QuiteNote.Recording", code: 2,
                                   userInfo: [NSLocalizedDescriptionKey: "录屏文件写入失败"])
        }

        DiagnosticCenter.info("Recording", String(format: "录制收尾完成：%.1f 秒 → %@", preparation.recordedSeconds, url.lastPathComponent))
        return url
    }

    private struct StopPreparation {
        let stream: SCStream?
        let writer: AVAssetWriter?
        let url: URL?
        let hadSession: Bool
        let recordedSeconds: Double
    }

    /// 在同步锁域内结算暂停、补尾帧、结束输入，并摘走异步收尾所需对象。
    private func prepareToStop() -> StopPreparation? {
        withStateLock {
            guard isRecording else { return nil }
            isRecording = false
            let targetStream = stream
            let writerRef = writer
            let urlRef = outputURL
            let hadSession = sessionStarted
            var recordedSeconds = 0.0

            if paused, pauseStartedAt.isValid {
                let now = CMClockGetTime(CMClock.hostTimeClock)
                pausedDuration = V2RecordingTiming.accumulatedPause(
                    previous: pausedDuration, pauseStartedAt: pauseStartedAt, resumedAt: now)
                paused = false
            }

            if hadSession, let writer = writerRef {
                let pad = V2RecordingTiming.padPTS(
                    now: CMClockGetTime(CMClock.hostTimeClock), pausedDuration: pausedDuration)
                var sessionEnd = CMTime.invalid
                if let last = lastVideoFrame, pad > lastVideoPTS,
                   let input = videoInput,
                   let padded = Self.retimedCopy(of: last, presentationTimeStamp: pad),
                   input.isReadyForMoreMediaData {
                    input.append(padded)
                    sessionEnd = pad
                } else if lastVideoPTS.isValid {
                    sessionEnd = lastVideoPTS
                }
                if sessionEnd.isValid {
                    writer.endSession(atSourceTime: sessionEnd)
                }
                videoInput?.markAsFinished()
                systemAudioInput?.markAsFinished()
                micInput?.markAsFinished()

                if firstPTS.isValid, sessionEnd.isValid {
                    recordedSeconds = sessionEnd.seconds - firstPTS.seconds
                }
            }

            // 此后迟到的帧回调会在锁内看到 isRecording=false 直接返回。
            stream = nil
            writer = nil
            videoInput = nil
            systemAudioInput = nil
            micInput = nil
            lastVideoFrame = nil

            return StopPreparation(
                stream: targetStream,
                writer: writerRef,
                url: urlRef,
                hadSession: hadSession,
                recordedSeconds: recordedSeconds
            )
        }
    }

    /// 取消：丢弃临时文件，不产生任何产物
    func cancel() async {
        guard let preparation = prepareToCancel() else { return }

        if let s = preparation.stream {
            try? await s.stopCapture()
        }
        if let w = preparation.writer {
            await w.finishWriting()
        }
        if let url = preparation.url {
            try? FileManager.default.removeItem(at: url)
        }
        DiagnosticCenter.info("Recording", "录制已取消，临时文件已删除")
    }

    private func prepareToCancel() -> (stream: SCStream?, writer: AVAssetWriter?, url: URL?)? {
        withStateLock {
            guard isRecording else { return nil }
            isRecording = false
            let targetStream = stream
            let writerRef = writer
            let urlRef = outputURL
            if sessionStarted {
                videoInput?.markAsFinished()
                systemAudioInput?.markAsFinished()
                micInput?.markAsFinished()
            }
            stream = nil
            writer = nil
            videoInput = nil
            systemAudioInput = nil
            micInput = nil
            lastVideoFrame = nil
            return (targetStream, writerRef, urlRef)
        }
    }

    // MARK: - SCStreamOutput（frameQueue 上调用）

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            ingestVideo(sampleBuffer)
        case .audio:
            ingestSystemAudio(sampleBuffer)
        case .microphone:
            // 麦克风由 V2MicrophoneRecorder/AVAudioEngine 独立采集，避免重复写入。
            break
        @unknown default:
            break
        }
    }

    private func ingestVideo(_ sampleBuffer: CMSampleBuffer) {
        // 只接受完整帧；屏幕静止时的 .idle 等状态不携带新内容
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete else {
            return
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        stateLock.lock()
        defer { stateLock.unlock() }

        guard isRecording, !paused, let input = videoInput else { return }

        let effective = V2RecordingTiming.effectivePTS(rawPTS: pts, pausedDuration: pausedDuration)
        ensureSessionStarted(effectivePTS: effective)

        // 乱序/重复帧保护（暂停前移后天然单调，无需特殊处理）
        guard !lastVideoPTS.isValid || effective > lastVideoPTS else { return }
        guard input.isReadyForMoreMediaData else { return }

        if pausedDuration.seconds > 0 {
            // 有暂停空洞时必须用重定时副本；无暂停时可直接 append 原始帧省一次拷贝
            if let retimed = Self.retimedCopy(of: sampleBuffer, presentationTimeStamp: effective) {
                input.append(retimed)
                lastVideoPTS = effective
                lastVideoFrame = retimed
            }
        } else {
            input.append(sampleBuffer)
            lastVideoPTS = effective
            lastVideoFrame = sampleBuffer
        }
    }

    private func ingestSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        // 实时电平：录到多响就显示多响（暂停期间不产帧，电平自然归零）
        onSystemAudioLevel?(Self.rmsLevel(of: sampleBuffer))

        stateLock.lock()
        defer { stateLock.unlock() }

        guard isRecording, !paused, let input = systemAudioInput else { return }

        let effective = V2RecordingTiming.effectivePTS(rawPTS: pts, pausedDuration: pausedDuration)
        ensureSessionStarted(effectivePTS: effective)
        appendAudio(sampleBuffer, effectivePTS: effective, lastPTS: &lastSystemAudioPTS, into: input)
    }

    /// CMSampleBuffer（Float32 PCM）→ 归一化 RMS 电平
    private static func rmsLevel(of sample: CMSampleBuffer) -> Float {
        var needed = 0
        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sample,
            bufferListSizeNeededOut: &needed,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer) == noErr else { return 0 }

        let buffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        var sum: Float = 0
        var count = 0
        for buffer in buffers {
            guard let data = buffer.mData, buffer.mDataByteSize >= 4 else { continue }
            let floats = data.bindMemory(to: Float.self, capacity: Int(buffer.mDataByteSize) / 4)
            let n = Int(buffer.mDataByteSize) / 4
            var i = 0
            while i < n {
                let v = floats[i]
                sum += v * v
                count += 1
                i += 8 // 采样步进，电平不需要逐样本
            }
        }
        guard count > 0 else { return 0 }
        let rms = sqrt(sum / Float(count))
        return min(1, rms * 3) // 展示尺度放大：语音 RMS 常在 0.05~0.3
    }

    /// 音频公共追加路径：重定时 + 单调保护 + append（实时录制不阻塞，来不及就丢这包）
    private func appendAudio(_ sample: CMSampleBuffer, effectivePTS: CMTime,
                             lastPTS: inout CMTime, into input: AVAssetWriterInput) {
        guard !lastPTS.isValid || effectivePTS > lastPTS else { return }
        guard input.isReadyForMoreMediaData else { return }
        guard let retimed = Self.retimedCopy(of: sample, presentationTimeStamp: effectivePTS) else { return }
        input.append(retimed)
        lastPTS = effectivePTS
    }

    /// 会话起点 = 第一路到达 buffer 的有效 PTS（host clock 域，非零基）
    private func ensureSessionStarted(effectivePTS: CMTime) {
        guard !sessionStarted else { return }
        writer?.startWriting()
        writer?.startSession(atSourceTime: effectivePTS)
        sessionStarted = true
        firstPTS = effectivePTS
    }

    // MARK: - SCStreamDelegate

    /// 流被系统终止：权限撤销 / 用户从菜单栏录屏指示器停止
    /// 必须立即收尾 writer，否则已录内容全部丢失
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DiagnosticCenter.error("Recording", "采集流被系统终止：\(error.localizedDescription)")
        DispatchQueue.main.async { [weak self] in
            self?.onForcedStop?()
        }
    }

    // MARK: - 私有

    /// 复制一帧并替换 PTS（补尾帧/暂停前移用；不解码、共享像素缓冲）
    private static func retimedCopy(of sample: CMSampleBuffer, presentationTimeStamp: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: sample.duration,
            presentationTimeStamp: presentationTimeStamp,
            decodeTimeStamp: .invalid
        )
        var out: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sample,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &out
        )
        return status == noErr ? out : nil
    }
}
