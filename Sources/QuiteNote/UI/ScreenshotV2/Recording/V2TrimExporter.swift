import Foundation
import AVFoundation
import CoreMedia

/// 成片导出器：AVMutableComposition（分段/音轨/配音的合成结果）→ mp4
///
/// - 纯剪辑（无字幕、音量全 100%）：passthrough 直通（不转码，秒级）
/// - 带音量/字幕烧录：HighestQuality 重编码 + audioMix + videoComposition
enum V2TrimExporter {

    enum TrimError: LocalizedError {
        case exportFailed(String)
        var errorDescription: String? {
            switch self {
            case .exportFailed(let reason): return "导出失败：\(reason)"
            }
        }
    }

    /// - Parameters:
    ///   - audioMix: 各音轨音量（nil = 不调节，可走直通）
    ///   - videoComposition: 字幕烧录层（nil = 不烧录，可走直通）
    static func export(composition: AVMutableComposition,
                        audioMix: AVAudioMix? = nil,
                        videoComposition: AVVideoComposition? = nil) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuiteNote-Trim-\(UUID().uuidString).mp4")

        // 1. 直通（不转码）：仅纯剪辑可用
        if audioMix == nil && videoComposition == nil {
            if let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) {
                if let out = try? await run(session: session, outputURL: tempURL) {
                    return out
                }
                try? FileManager.default.removeItem(at: tempURL)
            }
        }

        // 2. 重编码：支持音量调节与字幕烧录（耗时与时长成正比）
        if let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) {
            session.audioMix = audioMix
            session.videoComposition = videoComposition
            if let out = try? await run(session: session, outputURL: tempURL) {
                return out
            }
            try? FileManager.default.removeItem(at: tempURL)
        }

        throw TrimError.exportFailed("导出失败（轨道不兼容或文件被占用）")
    }

    private static func run(session: AVAssetExportSession, outputURL: URL) async throws -> URL {
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        // exportAsynchronously 在 macOS 15 标记废弃（新 async API 为 15+）；
        // 项目最低 13，沿用旧 API（仅告警）
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                continuation.resume()
            }
        }

        guard session.status == .completed else {
            throw TrimError.exportFailed(session.error?.localizedDescription ?? "未知错误")
        }
        return outputURL
    }
}
