import Foundation
import os.log

/// AI 总结结果结构：标题、总结、置信度、标签与关键词
struct SummaryResult: Codable {
    let title: String
    let summary: String
    let confidence: Double
    let tags: [String]?
    let keywords: [String]?
}

/// 统一的大模型提炼接口：返回标题、总结与置信度
protocol AIServiceProtocol {
    /// 执行提炼任务：输入限制与原文；completion 返回结构化结果或错误
    func summarize(titleLimit: Int, summaryLimit: Int, content: String, existingTags: [String], completion: @escaping (Result<SummaryResult, Error>) -> Void)
    
    /// 使用自定义提示词执行提炼任务
    func summarize(titleLimit: Int, summaryLimit: Int, content: String, existingTags: [String], systemPrompt: String?, userPrompt: String?, completion: @escaping (Result<SummaryResult, Error>) -> Void)
    
    /// 为单个记录生成总结
    func summarizeSingle(_ content: String, existingTags: [String], completion: @escaping (Result<SummaryResult, Error>) -> Void)
}

/// AI 服务实现：仅支持 OpenAI
final class AIService: AIServiceProtocol {
    private static let logger = Logger(subsystem: "com.quitenote.app", category: "AIService")
    var openAIBaseURL: String = "https://api.openai.com/v1"
    var openAIModel: String = "gpt-4o-mini"
    var timeout: TimeInterval = 60

    // 延迟加载：避免重复访问 Keychain
    private var hasCheckedAPIKey = false
    private var cachedAPIKey: String? = nil
    
    // 请求队列管理
    private var requestQueue: [AIRequest] = []
    private var isProcessingRequest = false
    private let maxConcurrentRequests = 3
    private var activeRequests = 0
    private let queueLock = NSLock()
    
    /// 请求结构
    private struct AIRequest {
        let id = UUID()
        let titleLimit: Int
        let summaryLimit: Int
        let content: String
        let existingTags: [String]
        let systemPrompt: String?
        let userPrompt: String?
        let completion: (Result<SummaryResult, Error>) -> Void
        let timestamp = Date()
    }
    
    /// 析构函数，确保清理资源
    deinit {
        queueLock.lock()
        requestQueue.removeAll()
        queueLock.unlock()
    }
    
    /// 为单个记录生成总结
    func summarizeSingle(_ content: String, existingTags: [String], completion: @escaping (Result<SummaryResult, Error>) -> Void) {
        // 使用默认限制值调用 summarize 方法
        summarize(titleLimit: 30, summaryLimit: 100, content: content, existingTags: existingTags, completion: completion)
    }
    
    /// 执行提炼任务，失败或超时时降级为前 15 字标题与空总结
    func summarize(titleLimit: Int, summaryLimit: Int, content: String, existingTags: [String], completion: @escaping (Result<SummaryResult, Error>) -> Void) {
        summarize(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, existingTags: existingTags, systemPrompt: nil, userPrompt: nil, completion: completion)
    }
    
    /// 使用自定义提示词执行提炼任务
    func summarize(titleLimit: Int, summaryLimit: Int, content: String, existingTags: [String], systemPrompt: String?, userPrompt: String?, completion: @escaping (Result<SummaryResult, Error>) -> Void) {
        // 创建请求并加入队列
        let request = AIRequest(
            titleLimit: titleLimit,
            summaryLimit: summaryLimit,
            content: content,
            existingTags: existingTags,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            completion: completion
        )
        
        queueLock.lock()
        requestQueue.append(request)
        queueLock.unlock()
        
        // 尝试处理队列
        processQueue()
    }
    
    /// 处理请求队列
    private func processQueue() {
        queueLock.lock()
        
        // 如果正在处理请求数量已达上限，则等待
        guard activeRequests < maxConcurrentRequests else {
            queueLock.unlock()
            return
        }
        
        // 如果队列为空，则无需处理
        guard !requestQueue.isEmpty else {
            queueLock.unlock()
            return
        }
        
        // 取出下一个请求
        let request = requestQueue.removeFirst()
        activeRequests += 1
        
        queueLock.unlock()
        
        // 处理请求 - 仅使用OpenAI
        summarizeWithOpenAI(
            titleLimit: request.titleLimit, 
            summaryLimit: request.summaryLimit, 
            content: request.content,
            existingTags: request.existingTags,
            systemPrompt: request.systemPrompt,
            userPrompt: request.userPrompt
        ) { [weak self] result in
            request.completion(result)
            self?.requestCompleted()
        }
    }
    
    /// 请求完成回调
    private func requestCompleted() {
        queueLock.lock()
        activeRequests -= 1
        queueLock.unlock()
        
        // 继续处理队列中的下一个请求
        processQueue()
    }

    /// 获取 OpenAI API 密钥（延迟加载，避免重复访问 Keychain）
    private func getOpenAIAPIKey() -> String? {
        if !hasCheckedAPIKey {
            cachedAPIKey = KeychainHelper.shared.read(service: "QuiteNote", account: "openai_api_key")
            hasCheckedAPIKey = true
            print("[AI] API密钥获取结果: \(cachedAPIKey != nil ? "成功" : "失败")")
        }
        return cachedAPIKey
    }

    /// 使用 OpenAI Chat Completions 生成固定 JSON 输出
    private func summarizeWithOpenAI(titleLimit: Int, summaryLimit: Int, content: String, existingTags: [String], systemPrompt: String? = nil, userPrompt: String? = nil, completion: @escaping (Result<SummaryResult, Error>) -> Void) {
        
        // 防止多次回调的标志
        var hasCompleted = false
        let safeCompletion: (Result<SummaryResult, Error>) -> Void = { result in
            if !hasCompleted {
                hasCompleted = true
                completion(result)
            }
        }
        
        guard let apiKey = getOpenAIAPIKey() else {
            let baseTitle = String(content.prefix(max(0, min(titleLimit, 15))))
            let result = SummaryResult(title: baseTitle, summary: "", confidence: 0.0, tags: [], keywords: [])
            completion(.success(result))
            return
        }
        
        let url = URL(string: "\(openAIBaseURL)/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // 准备现有标签提示
        let tagsPrompt = existingTags.isEmpty ? "" : "\n当前系统已有标签库: [\(existingTags.joined(separator: ", "))]。\n请遵循以下增强规则：\n1. **优先复用**: 检查内容是否属于已有标签的维度，如果是，必须优先使用已有标签。\n2. **多维度分类**: 即使复用了旧标签，也请尝试从内容属性、技术工具、业务场景等维度补齐缺失的分类。\n3. **新增策略**: 仅在已有标签完全无法覆盖该内容的某个重要维度时，才创建新标签。\n4. **简洁规范**: 标签通常为 2-4 字，避免句子形式。"

        // 获取基础提示词
        let baseSys = systemPrompt ?? PreferencesManager.shared.aiSystemPrompt
        let baseUser = userPrompt ?? PreferencesManager.shared.aiUserPrompt
        
        // 注入标签提示（如果是系统默认提示词，则注入 tagsPrompt）
        var sys = baseSys
        if sys.contains("识别内容的分类。") {
            sys = sys.replacingOccurrences(of: "识别内容的分类。", with: "识别内容的分类。\(tagsPrompt)")
        }
        
        // 替换占位符
        sys = sys.replacingOccurrences(of: "{titleLimit}", with: "\(titleLimit)")
        sys = sys.replacingOccurrences(of: "{summaryLimit}", with: "\(summaryLimit)")
        
        let user = baseUser.replacingOccurrences(of: "{content}", with: content)
        
        let body: [String: Any] = [
            "model": openAIModel,
            "messages": [
                ["role": "system", "content": sys],
                ["role": "user", "content": user]
            ],
            "temperature": 0.3,
            "max_tokens": 5000,
            "response_format": ["type": "json_object"]
        ]

        do {
            let bodyData = try JSONSerialization.data(withJSONObject: body, options: .prettyPrinted)
            req.httpBody = bodyData
        } catch {
       
            let baseTitle = String(content.prefix(max(0, min(titleLimit, 15))))
            let result = SummaryResult(title: baseTitle, summary: "", confidence: 0.0, tags: [], keywords: [])
            completion(.success(result))
            return
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)

        let task = session.dataTask(with: req) { data, response, error in
            if error != nil {
                let baseTitle = String(content.prefix(max(0, min(titleLimit, 15))))
                let result = SummaryResult(title: baseTitle, summary: "", confidence: 0.0, tags: [], keywords: [])
                safeCompletion(.success(result))
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode != 200 {
                    let baseTitle = String(content.prefix(max(0, min(titleLimit, 15))))
                    let result = SummaryResult(title: baseTitle, summary: "", confidence: 0.0, tags: [], keywords: [])
                    safeCompletion(.success(result))
                    return
                }
            }

            guard let data = data else {
                let baseTitle = String(content.prefix(max(0, min(titleLimit, 15))))
                let result = SummaryResult(title: baseTitle, summary: "", confidence: 0.0, tags: [], keywords: [])
                safeCompletion(.success(result))
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let message = first["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    
                    var trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // 处理可能包含的 markdown 代码块
                    if trimmed.hasPrefix("```json") {
                        trimmed = trimmed.replacingOccurrences(of: "```json", with: "")
                        if trimmed.hasSuffix("```") {
                            trimmed = String(trimmed.prefix(trimmed.count - 3))
                        }
                    } else if trimmed.hasPrefix("```") {
                        trimmed = trimmed.replacingOccurrences(of: "```", with: "")
                        if trimmed.hasSuffix("```") {
                            trimmed = String(trimmed.prefix(trimmed.count - 3))
                        }
                    }
                    trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    
                    
                    if let jsonData = trimmed.data(using: .utf8) {
                        do {
                            let summary = try JSONDecoder().decode(SummaryResult.self, from: jsonData)
                            
                            safeCompletion(.success(summary))
                        } catch {
                            
                            // 尝试降级处理
                            let baseTitle = String(content.prefix(max(0, min(titleLimit, 15))))
                            let result = SummaryResult(title: baseTitle, summary: trimmed, confidence: 0.5, tags: [], keywords: [])
                            safeCompletion(.success(result))
                        }
                    } else {
                        
                        let baseTitle = String(content.prefix(max(0, min(titleLimit, 15))))
                        let result = SummaryResult(title: baseTitle, summary: "", confidence: 0.0, tags: [], keywords: [])
                        safeCompletion(.success(result))
                    }
                } else {
                    
                    let baseTitle = String(content.prefix(max(0, min(titleLimit, 15))))
                    let result = SummaryResult(title: baseTitle, summary: "", confidence: 0.0, tags: [], keywords: [])
                    safeCompletion(.success(result))
                }
            } catch {
                
                let baseTitle = String(content.prefix(max(0, min(titleLimit, 15))))
                let result = SummaryResult(title: baseTitle, summary: "", confidence: 0.0, tags: [], keywords: [])
                safeCompletion(.success(result))
            }
        }

        task.resume()
    }

    /// 测试连接 - 仅测试OpenAI
    func testConnection(completion: @escaping (Result<Bool, Error>) -> Void) {
        print("[AI] 测试OpenAI连接")
        
        guard let apiKey = getOpenAIAPIKey() else {
            completion(.failure(NSError(domain: "AIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "未设置API密钥"])))
            return
        }

        guard let testURL = URL(string: "\(openAIBaseURL)/models") else {
            completion(.failure(NSError(domain: "AIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的API URL: \(openAIBaseURL)"])))
            return
        }

        var req = URLRequest(url: testURL)
        req.httpMethod = "GET"
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = timeout

        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: req) { data, response, error in
            if let error = error {
                let nsError = error as NSError
                var errorMessage = "连接失败"
                
                if nsError.code == NSURLErrorNotConnectedToInternet {
                    errorMessage = "无网络连接"
                } else if nsError.code == NSURLErrorTimedOut {
                    errorMessage = "连接超时"
                } else if nsError.code == 401 {
                    errorMessage = "API密钥无效"
                } else {
                    errorMessage = error.localizedDescription
                }
                
                completion(.failure(NSError(domain: "AIService", code: nsError.code, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    print("[AI] OpenAI连接测试成功")
                    completion(.success(true))
                } else {
                    let errorMsg = "HTTP错误 \(httpResponse.statusCode)"
                    completion(.failure(NSError(domain: "AIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])))
                }
            } else {
                completion(.failure(NSError(domain: "AIService", code: 0, userInfo: [NSLocalizedDescriptionKey: "无效的响应"])))
            }
        }

        task.resume()
    }
}

/// 简化的总结结果结构（用于简单解析）
private struct SimpleSummaryResult: Codable {
    let title: String
    let summary: String
    let confidence: Double
}