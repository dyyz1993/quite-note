import Foundation
import AppKit
import AVFoundation
import CoreMedia
import SwiftUI

/// 录屏资产分析器：缩略图条 + 每条音轨的 RMS 波形（快剪时间线的数据源）
///
/// 性能口径（调研结论）：1 分钟 720p 缩略图 12 张 + 波形包络，秒级完成；
/// 缩略图用宽松容差（直接取关键帧，跳过完整解码）。全部在后台线程跑，
/// @Published 结果回主线程。
final class V2RecordingAssetInfo: ObservableObject {
    struct WaveformTrack {
        let label: String
        let values: [Float]
        let color: Color
    }

    @Published var thumbnails: [NSImage] = []
    @Published var waveforms: [WaveformTrack] = []
    /// 与 waveforms 一一对应的源音轨（合成导出用）
    @Published var audioTracks: [AVAssetTrack] = []
    /// 智能卡点：场景切换时刻（秒，画面突变=切应用/翻页）
    @Published var sceneCuts: [Double] = []
    /// 智能卡点：每条音轨的音频高潮时刻（秒，与 waveforms 一一对应）
    @Published var audioPeaks: [[Double]] = []
    @Published var duration: Double = 0
    @Published var pixelText: String = ""
    @Published var fileSizeText: String = ""

    private var loadTask: Task<Void, Never>?

    func load(fileURL: URL) {
        loadTask?.cancel()
        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            let asset = AVURLAsset(url: fileURL)
            guard !Task.isCancelled else { return }

            // 时长 / 分辨率 / 文件大小
            var duration = 0.0
            var pixelText = ""
            if let d = try? await asset.load(.duration), CMTIME_IS_NUMERIC(d) {
                duration = d.seconds
            }
            if let videoTrack = (try? await asset.loadTracks(withMediaType: .video))?.first,
               let size = try? await videoTrack.load(.naturalSize) {
                pixelText = "\(Int(size.width))×\(Int(size.height))"
            }
            var sizeText = ""
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let bytes = attrs[.size] as? Int64 {
                sizeText = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            }
            guard !Task.isCancelled else { return }

            // 缩略图：宽松容差 → 直接取最近关键帧，避免完整解码
            var thumbs: [NSImage] = []
            let thumbCount = 12
            if duration > 0 {
                let gen = AVAssetImageGenerator(asset: asset)
                gen.maximumSize = CGSize(width: 240, height: 140)
                gen.requestedTimeToleranceBefore = CMTime(seconds: 0.6, preferredTimescale: 600)
                gen.requestedTimeToleranceAfter = CMTime(seconds: 0.6, preferredTimescale: 600)
                for i in 0..<thumbCount {
                    if Task.isCancelled { break }
                    let t = duration * (Double(i) + 0.5) / Double(thumbCount)
                    if let cg = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) {
                        thumbs.append(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
                    }
                }
            }
            guard !Task.isCancelled else { return }

            // 每条音轨一条波形：单声道→麦克风、双声道→系统声音（与录制写入顺序一致）
            var waves: [WaveformTrack] = []
            var sources: [AVAssetTrack] = []
            if let audioTracks = try? await asset.loadTracks(withMediaType: .audio) {
                for track in audioTracks {
                    if Task.isCancelled { break }
                    let channels = Self.channelCount(of: track)
                    let label: String
                    if audioTracks.count > 1 {
                        label = channels == 1 ? "麦克风" : "系统声音"
                    } else {
                        label = channels == 1 ? "麦克风" : "音频"
                    }
                    let color = channels == 1 ? Color.themePurple400 : Color.themeBlue400
                    let values = Self.rmsEnvelope(asset: asset, track: track,
                                                  duration: track.timeRange.duration.seconds, buckets: 240)
                    if !values.isEmpty {
                        waves.append(WaveformTrack(label: label, values: values, color: color))
                        sources.append(track)
                    }
                }
            }

            // 智能卡点：音频高潮（包络峰值）+ 场景切换（帧差）
            var peaks: [[Double]] = []
            for wave in waves {
                peaks.append(Self.peaks(from: wave.values, duration: duration, buckets: 240))
            }
            var cuts: [Double] = []
            if duration > 0, let videoTrack = (try? await asset.loadTracks(withMediaType: .video))?.first {
                cuts = Self.detectSceneCuts(asset: asset, track: videoTrack)
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.duration = duration
                self.pixelText = pixelText
                self.fileSizeText = sizeText
                self.thumbnails = thumbs
                self.waveforms = waves
                self.audioTracks = sources
                self.sceneCuts = cuts
                self.audioPeaks = peaks
            }
        }
    }

    /// 从 format description 读声道数（区分麦克风/系统声的依据）
    private static func channelCount(of track: AVAssetTrack) -> Int {
        guard let descs = try? track.formatDescriptions,
              let anyDesc = descs.first else { return 0 }
        // CoreFoundation 桥接转换恒成功，编译器不允许 as? 形式
        let desc = anyDesc as! CMFormatDescription
        guard let ext = desc.extensions as? [String: Any] else { return 0 }
        return ext["Channels"] as? Int ?? 0
    }

    /// 音频高潮：归一化包络上的局部峰值（> 0.75，彼此至少隔 2 秒）
    private static func peaks(from values: [Float], duration: Double, buckets: Int) -> [Double] {
        guard values.count > 4, duration > 0 else { return [] }
        var result: [Double] = []
        var lastTime = -10.0
        for i in 1..<(values.count - 1) {
            let v = values[i]
            guard v > 0.75, v >= values[i - 1], v >= values[i + 1] else { continue }
            let t = duration * Double(i) / Double(buckets)
            if t - lastTime > 2.0 {
                result.append(t)
                lastTime = t
            }
        }
        return Array(result.prefix(20))
    }

    /// 场景切换：降采样（64×36）逐帧差分，均差超阈值且距上一刀 > 1 秒记一处
    /// 解码是主要成本（约与时长线性，1 分钟 720p 数秒），在后台任务中调用
    private static func detectSceneCuts(asset: AVURLAsset, track: AVAssetTrack) -> [Double] {
        guard let reader = try? AVAssetReader(asset: asset) else { return [] }
        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 36,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { return [] }

        var previous: [UInt8]?
        var cuts: [Double] = []
        var lastCut = -10.0
        var frameIndex = 0

        while let sample = output.copyNextSampleBuffer() {
            frameIndex += 1
            guard frameIndex % 3 == 0,              // 每 3 帧比一次，屏录场景足够
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }

            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { continue }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            var current = [UInt8](repeating: 0, count: height * bytesPerRow)
            current.withUnsafeMutableBytes { raw in
                _ = raw.baseAddress.map { memcpy($0, base, height * bytesPerRow) }
            }

            if let prev = previous {
                var difference = 0
                var channels = 0
                for y in 0..<height {
                    let row = y * bytesPerRow
                    for x in 0..<width {
                        let offset = row + x * 4
                        difference += abs(Int(current[offset]) - Int(prev[offset]))
                        difference += abs(Int(current[offset + 1]) - Int(prev[offset + 1]))
                        difference += abs(Int(current[offset + 2]) - Int(prev[offset + 2]))
                        channels += 3
                    }
                }
                let normalized = Double(difference) / Double(max(1, channels)) / 255.0
                let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                if normalized > 0.14, time - lastCut > 1.0 {
                    cuts.append(time)
                    lastCut = time
                }
            }
            previous = current
        }
        return Array(cuts.prefix(30))
    }

    /// PCM 能量包络：AVAssetReader 顺序读取 → 分桶 RMS → 归一化
    private static func rmsEnvelope(asset: AVAsset, track: AVAssetTrack, duration: Double, buckets: Int) -> [Float] {
        guard duration > 0, buckets > 0,
              let reader = try? AVAssetReader(asset: asset) else { return [] }

        let pcm: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVNumberOfChannelsKey: 1, // 混为单声道，包络只需能量
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: pcm)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { return [] }

        var sums = [Double](repeating: 0, count: buckets)
        var counts = [Int](repeating: 0, count: buckets)

        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length > 0 else { continue }
            var data = Data(count: length)
            let copied = data.withUnsafeMutableBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else { return kCMBlockBufferStructureAllocationFailedErr }
                return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
            }
            guard copied == kCMBlockBufferNoErr else { continue }

            let startSeconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            // 录制链路两轨均为 48kHz（引擎写死），无需从 ASBD 读取
            let sampleRate = 48000.0
            let frames = length / MemoryLayout<Int16>.size

            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let ints = raw.bindMemory(to: Int16.self)
                // 每 4 帧采 1 个即可（包络不需要逐样本）
                var i = 0
                while i < frames {
                    let t = startSeconds + Double(i) / sampleRate
                    let bucket = min(buckets - 1, max(0, Int(t / duration * Double(buckets))))
                    let v = Double(abs(Int(ints[i]))) / 32768.0
                    sums[bucket] += v * v
                    counts[bucket] += 1
                    i += 4
                }
            }
        }

        var rms: [Float] = []
        rms.reserveCapacity(buckets)
        var peak: Double = 0.0001
        var raw: [Double] = []
        for i in 0..<buckets {
            let r = counts[i] == 0 ? 0 : sqrt(sums[i] / Double(counts[i]))
            raw.append(r)
            peak = max(peak, r)
        }
        for r in raw {
            rms.append(Float(min(1, r / peak)))
        }
        return rms
    }
}
