import Foundation

/// AI 降级处理器 - 负责在失败时提供降级结果
final class AIFallbackHandler {

    /// 生成降级结果（从内容前缀提取标题）
    static func createFallbackResult(content: String, titleLimit: Int) -> SummaryResult {
        let baseTitle = String(content.prefix(max(0, min(titleLimit, AIConstants.fallbackTitleLength))))
        return SummaryResult(
            title: baseTitle.isEmpty ? "无标题" : baseTitle,
            summary: "",
            confidence: 0.0,
            tags: [],
            keywords: []
        )
    }

    /// 创建部分降级结果（使用原始文本作为总结）
    static func createPartialFallbackResult(content: String, titleLimit: Int, rawSummary: String) -> SummaryResult {
        let baseTitle = String(content.prefix(max(0, min(titleLimit, AIConstants.fallbackTitleLength))))
        return SummaryResult(
            title: baseTitle.isEmpty ? "无标题" : baseTitle,
            summary: rawSummary,
            confidence: 0.5,
            tags: [],
            keywords: []
        )
    }

    /// 从错误创建降级结果
    static func createResultFromError(_ error: Error, content: String, titleLimit: Int) -> SummaryResult {
        let baseTitle = String(content.prefix(max(0, min(titleLimit, AIConstants.fallbackTitleLength))))

        // 根据错误类型设置不同的置信度
        let confidence: Double
        if let aiError = error as? AIError {
            switch aiError {
            case .noInternet, .timeout:
                confidence = 0.0
            case .httpError(let code) where code >= 500:
                confidence = 0.0
            default:
                confidence = 0.0
            }
        } else {
            confidence = 0.0
        }

        return SummaryResult(
            title: baseTitle.isEmpty ? "无标题" : baseTitle,
            summary: "",
            confidence: confidence,
            tags: [],
            keywords: []
        )
    }
}
