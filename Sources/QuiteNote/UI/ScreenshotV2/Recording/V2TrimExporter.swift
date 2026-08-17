import Foundation
import AVFoundation
import CoreMedia

/// 成片导出器：AVMutableComposition（多段删除/音轨静音/分段裁剪的合成结果）
/// → AVAssetExportSession 直通（不转码，秒级）优先，失败回退重编码
///
/// 直通只拷贝轨道样本，耗时≈复制文件；已知边界：切点向前对齐最近关键帧
/// （屏录 GOP 约 1 秒）。直通对轨道组合不兼容时直接 failed，回退
/// HighestQuality 重编码（慢但帧精确）。
enum V2TrimExporter {

    enum TrimError: LocalizedError {
        case exportFailed(String)
        var errorDescription: String? {
            switch self {
            case .exportFailed(let reason): return "导出失败：\(reason)"
            }
        }
    }

    /// 导出合成结果（视频 + 未静音音轨，各自按保留区间拼接）
    /// - Returns: 导出产物（临时 mp4），调用方负责替换原文件
    static func exportComposition(_ composition: AVMutableComposition) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuiteNote-Trim-\(UUID().uuidString).mp4")

        // 1. 直通（不转码）
        if let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) {
            if let out = try? await run(session: session, outputURL: tempURL) {
                return out
            }
            try? FileManager.default.removeItem(at: tempURL)
        }

        // 2. 回退：重编码（帧精确，耗时与时长成正比）
        if let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) {
            if let out = try? await run(session: session, outputURL: tempURL) {
                return out
            }
            try? FileManager.default.removeItem(at: tempURL)
        }

        throw TrimError.exportFailed("直通与重编码均失败（轨道不兼容或文件被占用）")
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
