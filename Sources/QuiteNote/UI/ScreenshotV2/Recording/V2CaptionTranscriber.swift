import Foundation
import AppKit
import AVFAudio
import AVFoundation
import CoreMedia
import CoreVideo
import CoreText
import Speech

/// 字幕识别：macOS 26 的设备端 SpeechAnalyzer/SpeechTranscriber（本地、带时间戳）
/// 旧系统不可用，UI 侧按 available 隐藏入口。
enum V2CaptionTranscriber {

    struct Chunk {
        let start: Double
        let end: Double
        let text: String
    }

    static var available: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    /// 识别一个音频文件；offset 用于把文件内时间平移到全片时间轴（配音分段用）
    static func transcribe(fileURL: URL, offset: Double = 0) async throws -> [Chunk] {
        guard #available(macOS 26.0, *) else {
            throw NSError(domain: "QuiteNote.Caption", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "自动字幕需要 macOS 26 或更高版本"])
        }

        let audioFile = try AVAudioFile(forReading: fileURL)
        let transcriber = SpeechTranscriber(locale: Locale(identifier: "zh-CN"),
                                            preset: .transcription)
        let analyzer = try await SpeechAnalyzer(inputAudioFile: audioFile,
                                                modules: [transcriber],
                                                finishAfterFile: true)
        // 先跑完整个文件（finishAfterFile 自动收尾），再消费缓冲好的结果序列
        try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)

        var chunks: [Chunk] = []
        for try await result in transcriber.results {
            let range = result.range
            let text = String(result.text.characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard CMTIME_IS_NUMERIC(range.start), range.duration.seconds > 0.05,
                  !text.isEmpty else { continue }
            chunks.append(Chunk(start: offset + range.start.seconds,
                                end: offset + range.start.seconds + range.duration.seconds,
                                text: text))
        }
        return chunks
    }
}

// MARK: - 字幕烧录合成器（AVCoreAnimationTool 已从 macOS 26 SDK 移除，改用官方推荐的自定义合成器）

/// 逐帧：拷贝源画面 → 命中字幕时间窗则用 CoreText 在底部画字幕
/// 数据经静态属性装载（应用单窗口单导出，isExporting 已互斥）
final class V2CaptionCompositor: NSObject, AVVideoCompositing {

    /// [(时间窗（成片时间轴）, 文本)]，导出前装载、完成后清空
    static var activeCaptions: [(CMTimeRange, String)] = []

    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]

    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            guard let trackNumber = request.sourceTrackIDs.first,
                  let trackID = CMPersistentTrackID(exactly: trackNumber),
                  let source = request.sourceFrame(byTrackID: trackID),
                  let dest = request.renderContext.newPixelBuffer() else {
                request.finish(with: NSError(domain: "QuiteNote.Caption", code: 10,
                                             userInfo: [NSLocalizedDescriptionKey: "合成帧获取失败"]))
                return
            }

            CVPixelBufferLockBaseAddress(source, .readOnly)
            CVPixelBufferLockBaseAddress(dest, [])
            defer {
                CVPixelBufferUnlockBaseAddress(dest, [])
                CVPixelBufferUnlockBaseAddress(source, .readOnly)
            }

            // 拷贝源帧到输出
            guard let srcPtr = CVPixelBufferGetBaseAddress(source),
                  let dstPtr = CVPixelBufferGetBaseAddress(dest) else {
                request.finish(withComposedVideoFrame: dest)
                return
            }
            let srcBPR = CVPixelBufferGetBytesPerRow(source)
            let dstBPR = CVPixelBufferGetBytesPerRow(dest)
            let height = min(CVPixelBufferGetHeight(source), CVPixelBufferGetHeight(dest))
            let width = min(CVPixelBufferGetWidth(source), CVPixelBufferGetWidth(dest))
            if srcBPR == dstBPR {
                memcpy(dstPtr, srcPtr, srcBPR * height)
            } else {
                for y in 0..<height {
                    memcpy(dstPtr + y * dstBPR, srcPtr + y * srcBPR, min(srcBPR, dstBPR))
                }
            }

            // 命中字幕时间窗 → CoreText 绘制（底部居中，带阴影）
            let time = request.compositionTime
            if let hit = Self.activeCaptions.first(where: { CMTimeRangeContainsTime($0.0, time: time) }) {
                let ctx = CGContext(
                    data: dstPtr, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: dstBPR,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
                if let ctx {
                    let fontSize = max(18, CGFloat(height) * 0.055)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.boldSystemFont(ofSize: fontSize),
                        .foregroundColor: NSColor.white,
                    ]
                    let attributed = NSAttributedString(string: hit.1, attributes: attrs)
                    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
                    let box = CGRect(x: CGFloat(width) * 0.07,
                                     y: CGFloat(height) * 0.07,
                                     width: CGFloat(width) * 0.86,
                                     height: CGFloat(height) * 0.18)
                    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0),
                                                         CGPath(rect: box, transform: nil), nil)
                    ctx.setAllowsAntialiasing(true)
                    ctx.setShouldAntialias(true)
                    ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 3,
                                  color: CGColor(gray: 0, alpha: 0.8))
                    CTFrameDraw(frame, ctx)
                }
            }

            request.finish(withComposedVideoFrame: dest)
        }
    }
}
