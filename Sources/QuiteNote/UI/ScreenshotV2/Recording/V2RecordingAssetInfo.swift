import Foundation
import AppKit
import AVFoundation
import CoreMedia
import SwiftUI

/// 录屏资产分析器：缩略图 + 每条音轨的 RMS 波形（快剪时间线的数据源）
///
/// 性能口径：1 分钟 720p 缩略图 24 张 + 波形包络，秒级完成；缩略图用宽松容差
/// （直接取关键帧，跳过完整解码）。全部在后台线程跑，@Published 结果回主线程。
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
            let thumbCount = 24
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

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.duration = duration
                self.pixelText = pixelText
                self.fileSizeText = sizeText
                self.thumbnails = thumbs
                self.waveforms = waves
                self.audioTracks = sources
                let trackDesc = waves.map { $0.label }.joined(separator: "+")
                DiagnosticCenter.info("Recording", "分析完成：缩略图 \(thumbs.count)，音轨 \(waves.count)（\(trackDesc.isEmpty ? "无声" : trackDesc)）")
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
                    let tt = startSeconds + Double(i) / sampleRate
                    let bucket = min(buckets - 1, max(0, Int(tt / duration * Double(buckets))))
                    let v = Double(abs(Int(ints[i]))) / 32768.0
                    sums[bucket] += v * v
                    counts[bucket] += 1
                    i += 4
                }
            }
        }

        var rms: [Float] = []
        rms.reserveCapacity(buckets)
        var peak = 0.0001
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
