import Foundation

/// 统一的大模型提炼接口：返回标题、总结与置信度
protocol AIServiceProtocol {
    /// 执行提炼任务：输入限制与原文；completion 返回结构化结果或错误
    func summarize(titleLimit: Int, summaryLimit: Int, content: String, completion: @escaping (Result<SummaryResult, Error>) -> Void)
}

/// 提供商类型：本地或 OpenAI
enum AIProvider {
    case local
    case openai
}

/// AI 服务实现：支持提供商选择、超时降级与结构化输出
final class AIService: AIServiceProtocol {
    var provider: AIProvider = .local
    var openAIBaseURL: String = "https://api.openai.com/v1"
    var openAIModel: String = "gpt-4o-mini"
    var timeout: TimeInterval = 5

    /// 执行提炼任务，按提供商路由；失败或超时时降级为前 15 字标题与空总结
    func summarize(titleLimit: Int, summaryLimit: Int, content: String, completion: @escaping (Result<SummaryResult, Error>) -> Void) {
        switch provider {
        case .local:
            summarizeLocally(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, completion: completion)
        case .openai:
            summarizeWithOpenAI(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, completion: completion)
        }
    }

    /// 本地规则提炼：根据长度与类型生成标题与总结
    private func summarizeLocally(titleLimit: Int, summaryLimit: Int, content: String, completion: @escaping (Result<SummaryResult, Error>) -> Void) {
        let deadline = DispatchTime.now() + timeout
        DispatchQueue.global().asyncAfter(deadline: deadline) {
            let baseTitle = String(content.prefix( max(0, min(titleLimit, 15)) ))
            let result = SummaryResult(title: baseTitle, summary: "", confidence: 0.0)
            completion(.success(result))
        }
    }

    /// 使用 OpenAI Chat Completions 生成固定 JSON 输出
    private func summarizeWithOpenAI(titleLimit: Int, summaryLimit: Int, content: String, completion: @escaping (Result<SummaryResult, Error>) -> Void) {
        guard let apiKey = KeychainHelper.shared.read(service: "QuiteNote", account: "openai_api_key") else {
            summarizeLocally(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, completion: completion)
            return
        }
        let url = URL(string: "\(openAIBaseURL)/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let sys = "你是一个写作助手，严格输出以下 JSON 字段，不要包含多余文本：{\"title\":不超过\(titleLimit)字的标题,\"summary\":不超过\(summaryLimit)字的总结,\"confidence\":0-1 之间置信度，仅数字}";
        let user = "原文：\n\n\(content)\n\n只返回 JSON。"

        let body: [String: Any] = [
            "model": openAIModel,
            "messages": [
                ["role": "system", "content": sys],
                ["role": "user", "content": user]
            ]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: req) { data, _, error in
            if error != nil {
                self.summarizeLocally(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, completion: completion)
                return
            }
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let msg = first["message"] as? [String: Any],
                  let contentStr = msg["content"] as? String else {
                self.summarizeLocally(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, completion: completion)
                return
            }
            let parsed = Self.parseJSONText(contentStr)
            let title = parsed?.title ?? String(content.prefix(min(titleLimit, 15)))
            let summary = parsed?.summary ?? ""
            let conf = parsed?.confidence ?? 0.0
            completion(.success(SummaryResult(title: title, summary: summary, confidence: conf)))
        }
        task.resume()

        // 超时处理
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if task.state == .running {
                task.cancel()
                self.summarizeLocally(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, completion: completion)
            }
        }
    }

    /// 解析模型返回的字符串为 JSON 结构
    private static func parseJSONText(_ text: String) -> SummaryResult? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SummaryResult.self, from: data)
    }
}

/// 提炼结果模型
struct SummaryResult: Codable {
    let title: String
    let summary: String
    let confidence: Double
}
