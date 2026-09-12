import Foundation
import AVFoundation
import CoreMedia

/// 配音录制器：复用 V2MicrophoneRecorder 采集 → AAC .m4a 文件（每段配音一个文件）
///
/// 为什么落成文件而不是实时合流：合成导出（AVMutableComposition）需要独立的
/// 音频资产按时间插入；AAC/m4a 与 mp4 直通导出兼容（PCM 不行），且文件天然
/// 带时间戳供字幕识别直接使用。
final class V2DubRecorder {

    private let mic = V2MicrophoneRecorder()
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private(set) var fileURL: URL?
    private var sessionStarted = false
    private let lock = NSLock()

    /// 实时电平（驱动 UI）
    var onLevel: ((Float) -> Void)?

    private(set) var isRecording = false

    /// 开始一段配音，返回本次配音的临时文件 URL
    func start() throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        guard !isRecording else { throw NSError(domain: "QuiteNote.Dub", code: 1,
                                                userInfo: [NSLocalizedDescriptionKey: "已在配音中"]) }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuiteNote-Dub-\(UUID().uuidString).m4a")
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
        ])
        audioInput.expectsMediaDataInRealTime = true
        writer.add(audioInput)

        self.writer = writer
        self.input = audioInput
        self.fileURL = url
        self.sessionStarted = false

        mic.onBuffer = { [weak self] sample in
            guard let self else { return }
            self.ingest(sample)
        }
        mic.onLevel = { [weak self] level in
            self?.onLevel?(level)
        }
        try mic.start()
        isRecording = true
        return url
    }

    /// 停止并收尾；- Returns: 已完成文件的 URL（时长过短由调用方判断丢弃）
    func stop() async -> URL? {
        guard let stopState = prepareToStop() else { return nil }

        mic.stop()
        guard stopState.hadSession, let writer = stopState.writer, let url = stopState.url else {
            if let url = stopState.url {
                try? FileManager.default.removeItem(at: url)
            }
            return nil
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    /// NSLock 的获取必须留在同步上下文；Swift 6 禁止在 async 函数里直接 lock/unlock。
    private func prepareToStop() -> (writer: AVAssetWriter?, url: URL?, hadSession: Bool)? {
        lock.lock()
        defer { lock.unlock() }
        guard isRecording else {
            return nil
        }
        isRecording = false
        let writerRef = writer
        let urlRef = fileURL
        let hadSession = sessionStarted
        if hadSession {
            input?.markAsFinished()
        }
        writer = nil
        input = nil
        return (writerRef, urlRef, hadSession)
    }

    /// 取消（丢弃本段）
    func cancel() async {
        _ = await stop()
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        fileURL = nil
    }

    private func ingest(_ sample: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard isRecording, let writer = writer, let input = input else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        if !sessionStarted {
            writer.startWriting()
            writer.startSession(atSourceTime: pts)
            sessionStarted = true
        }
        if input.isReadyForMoreMediaData {
            input.append(sample)
        }
    }
}
