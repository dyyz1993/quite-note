import Foundation
import AppKit
import Vision

/// 截图 OCR 服务：基于苹果原生 Vision 框架，完全本地、免费、离线
///
/// 使用链路：截图工具栏「文字识别」按钮 → V2ScreenshotView 组装选区最终图
/// → recognizeText → V2OCRResultPanel 展示可编辑结果
@MainActor
final class V2OCRService {
    static let shared = V2OCRService()
    private init() {}

    /// 一行文字片段（归一化坐标，原点左下、y 向上，与 Vision boundingBox 一致）
    struct OCRLineFragment {
        let rect: CGRect
        let text: String
    }

    /// 对图片执行 OCR（中文简体 + 英文），结果在主线程回调；无文字时回调空字符串
    func recognizeText(in image: NSImage, completion: @escaping (String?) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(nil)
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            if error != nil {
                DiagnosticCenter.error("OCR", "Vision 请求失败: \(error!.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            let fragments = observations.compactMap { obs -> OCRLineFragment? in
                guard let candidate = obs.topCandidates(1).first else { return nil }
                return OCRLineFragment(rect: obs.boundingBox, text: candidate.string)
            }
            let text = Self.assembleText(fragments)
            DispatchQueue.main.async { completion(text) }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                DiagnosticCenter.error("OCR", "执行识别失败: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    /// 把散落的文字片段按版面拼成可读文本（纯函数，可单测）：
    /// 按基线从上到下分行；同一行内（minY 差 ≤ 行高的 60%）按从左到右排序后拼接
    nonisolated static func assembleText(_ fragments: [OCRLineFragment]) -> String {
        guard !fragments.isEmpty else { return "" }

        // 归一化坐标 y 向上：minY 大的在版面上方
        let sorted = fragments.sorted { $0.rect.minY > $1.rect.minY }

        var lineTexts: [String] = []
        var currentLineParts: [(x: CGFloat, text: String)] = []
        var currentLineAnchorY: CGFloat?

        for fragment in sorted {
            let y = fragment.rect.minY
            let height = fragment.rect.height

            if let anchor = currentLineAnchorY,
               abs(y - anchor) <= max(0.005, height * 0.6) {
                currentLineParts.append((fragment.rect.minX, fragment.text))
            } else {
                if !currentLineParts.isEmpty {
                    lineTexts.append(joinLine(currentLineParts))
                }
                currentLineParts = [(fragment.rect.minX, fragment.text)]
                currentLineAnchorY = y
            }
        }
        if !currentLineParts.isEmpty {
            lineTexts.append(joinLine(currentLineParts))
        }

        return lineTexts.joined(separator: "\n")
    }

    /// 同一行内的片段按从左到右排序拼接
    private nonisolated static func joinLine(_ parts: [(x: CGFloat, text: String)]) -> String {
        parts.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ")
    }
}
