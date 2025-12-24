import Foundation
import os.log

/// OpenAI 响应解析器 - 负责解析 API 响应
final class OpenAIResponseParser {
    private static let logger = Logger(subsystem: "com.quitenote.app", category: "OpenAIResponseParser")

    /// 解析聊天完成响应为 SummaryResult
    static func parseSummaryResult(from jsonString: String) -> Result<SummaryResult, Error> {
        var trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        // 处理可能包含的 markdown 代码块
        trimmed = stripMarkdownCodeBlocks(from: trimmed)

        guard let jsonData = trimmed.data(using: .utf8) else {
            return .failure(ParseError.encodingFailed)
        }

        do {
            let result = try JSONDecoder().decode(SummaryResult.self, from: jsonData)
            return .success(result)
        } catch {
            Self.logger.error("JSON 解析失败: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    /// 从 JSON 字符串中移除 markdown 代码块标记
    static func stripMarkdownCodeBlocks(from text: String) -> String {
        var result = text

        // 处理 ```json...```
        if result.hasPrefix("```json") {
            result = result.replacingOccurrences(of: "```json", with: "")
            if result.hasSuffix("```") {
                result = String(result.prefix(result.count - 3))
            }
        }
        // 处理 ```...```
        else if result.hasPrefix("```") {
            result = result.replacingOccurrences(of: "```", with: "", options: .anchored)
            if result.hasSuffix("```") {
                result = String(result.prefix(result.count - 3))
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 构建系统提示词（包含标签逻辑）
    static func buildSystemPrompt(base: String,
                                  titleLimit: Int,
                                  summaryLimit: Int,
                                  existingTags: [String]) -> String {
        var result = base

        // 注入标签提示（如果是默认提示词）
        if result.contains("识别内容的分类。") {
            let tagsPrompt = buildTagsPrompt(existingTags: existingTags)
            result = result.replacingOccurrences(of: "识别内容的分类。", with: "识别内容的分类。\(tagsPrompt)")
        }

        // 替换占位符
        result = result.replacingOccurrences(of: "{titleLimit}", with: "\(titleLimit)")
        result = result.replacingOccurrences(of: "{summaryLimit}", with: "\(summaryLimit)")

        return result
    }

    /// 构建用户提示词
    static func buildUserPrompt(base: String, content: String) -> String {
        return base.replacingOccurrences(of: "{content}", with: content)
    }

    /// 构建标签提示词
    private static func buildTagsPrompt(existingTags: [String]) -> String {
        guard !existingTags.isEmpty else { return "" }

        return """
        当前系统已有标签库: [\(existingTags.joined(separator: ", "))]。
        请遵循以下增强规则：
        1. **优先复用**: 检查内容是否属于已有标签的维度，如果是，必须优先使用已有标签。
        2. **多维度分类**: 即使复用了旧标签，也请尝试从内容属性、技术工具、业务场景等维度补齐缺失的分类。
        3. **新增策略**: 仅在已有标签完全无法覆盖该内容的某个重要维度时，才创建新标签。
        4. **简洁规范**: 标签通常为 2-4 字，避免句子形式。
        """
    }
}

// MARK: - Parse Error

enum ParseError: LocalizedError {
    case encodingFailed
    case invalidJSON
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "字符串编码失败"
        case .invalidJSON:
            return "无效的 JSON 格式"
        case .missingField(let field):
            return "缺少字段: \(field)"
        }
    }
}
