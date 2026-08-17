import Foundation
import AVFoundation
import CoreMedia
import CoreAudio

/// 麦克风采集：AVAudioEngine tap → 48kHz Float32 单声道 → CMSampleBuffer
///
/// 为什么不用 SCK：captureMicrophone 是 macOS 15+ 的 API，本项目最低支持 13，
/// 麦克风必须走 AVAudioEngine 独立采集、由引擎合流成第二条音轨（QuickRecorder 同款方案）。
///
/// 线程：tap 回调在音频实时线程上，只做字节拷贝 + 转封装，然后抛给 queue；
/// PTS 用 CMClock hostTimeClock 在回调时刻取样——与 SCK 视频帧同一时间域，
/// 引擎侧可与系统声/视频统一做暂停前移。
final class V2MicrophoneRecorder {

    /// 采集回调（在内部串行队列上回调，非音频线程）；失败时 error 为 nil 之外的情况
    var onBuffer: ((CMSampleBuffer) -> Void)?
    /// 启动/停止失败等异常上报（主线程）
    var onError: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "com.quitenote.recording.mic")

    private(set) var isRunning = false

    func start() throws {
        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0 else {
            throw NSError(domain: "QuiteNote.Recording", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "找不到可用麦克风设备"])
        }

        // 目标格式固定 48k 单声道，引擎自动完成硬件格式转换
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false) else {
            throw NSError(domain: "QuiteNote.Recording", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "无法创建麦克风目标格式"])
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: targetFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.queue.async {
                guard let onBuffer = self.onBuffer else { return }
                if let sample = Self.makeSampleBuffer(buffer) {
                    onBuffer(sample)
                }
            }
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        onBuffer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    // MARK: - AVAudioPCMBuffer → CMSampleBuffer

    /// PCM → CMSampleBuffer：字节拷贝进自有 CMBlockBuffer（tap 的缓冲会被引擎复用，不能直接引用）
    private static func makeSampleBuffer(_ pcm: AVAudioPCMBuffer) -> CMSampleBuffer? {
        guard let channelData = pcm.floatChannelData?[0] else { return nil }
        let formatDescription = pcm.format.formatDescription
        let frameCount = Int(pcm.frameLength)
        guard frameCount > 0 else { return nil }
        let byteCount = frameCount * MemoryLayout<Float>.size

        var blockBuffer: CMBlockBuffer?
        // 分配自有内存并立即拷贝（AssureMemoryNow），与 tap 缓冲生命周期解耦
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer)
        guard status == kCMBlockBufferNoErr, let block = blockBuffer else { return nil }

        status = CMBlockBufferReplaceDataBytes(
            with: channelData,
            blockBuffer: block,
            offsetIntoDestination: 0,
            dataLength: byteCount)
        guard status == kCMBlockBufferNoErr else { return nil }

        // PTS 与 SCK 视频同域（host clock），由引擎统一做暂停前移
        let pts = CMClockGetTime(CMClock.hostTimeClock)
        let duration = CMTime(value: CMTimeValue(frameCount), timescale: CMTimeScale(pcm.format.sampleRate))
        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid)

        var sampleBuffer: CMSampleBuffer?
        let created = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer)
        return created == noErr ? sampleBuffer : nil
    }
}
