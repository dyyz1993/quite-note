import Foundation
import os.log

/// 统一的大模型提炼接口：返回标题、总结与置信度
protocol AIServiceProtocol {
    /// 执行提炼任务：输入限制与原文；completion 返回结构化结果或错误
    func summarize(contextId: String?, titleLimit: Int, summaryLimit: Int, content: String, existingTags: [String], completion: @escaping (Result<SummaryResult, Error>) -> Void)
    
    /// 使用自定义提示词执行提炼任务
    func summarize(contextId: String?, titleLimit: Int, summaryLimit: Int, content: String, existingTags: [String], systemPrompt: String?, userPrompt: String?, completion: @escaping (Result<SummaryResult, Error>) -> Void)
    
    /// 为单个记录生成总结
    func summarizeSingle(contextId: String?, _ content: String, existingTags: [String], completion: @escaping (Result<SummaryResult, Error>) -> Void)
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
    private var activeRequestIds: Set<String> = [] // 记录正在处理的 contextId
    private let maxConcurrentRequests = 3
    private var activeRequests = 0
    private let queueLock = NSLock()
    
    /// 请求结构
    private struct AIRequest {
        let id = UUID()
        let contextId: String? // 用于去重的上下文 ID（如记录 ID）
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
        activeRequestIds.removeAll()
        queueLock.unlock()
    }
    
    /// 为单个记录生成总结
    func summarizeSingle(contextId: String?, _ content: String, existingTags: [String], completion: @escaping (Result<SummaryResult, Error>) -> Void) {
        // 使用默认限制值调用 summarize 方法
        summarize(contextId: contextId, titleLimit: 30, summaryLimit: 100, content: content, existingTags: existingTags, completion: completion)
    }
    
    /// 执行提炼任务，失败或超时时降级为前 15 字标题与空总结
    func summarize(contextId: String?, titleLimit: Int, summaryLimit: Int, content: String, existingTags: [String], completion: @escaping (Result<SummaryResult, Error>) -> Void) {
        summarize(contextId: contextId, titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, existingTags: existingTags, systemPrompt: nil, userPrompt: nil, completion: completion)
    }
    
    /// 执行提炼任务
    func summarize(contextId: String?, titleLimit: Int, summaryLimit: Int, content: String, existingTags: [String], systemPrompt: String?, userPrompt: String?, completion: @escaping (Result<SummaryResult, Error>) -> Void) {
        // 创建请求并加入队列
        let request = AIRequest(
            contextId: contextId,
            titleLimit: titleLimit,
            summaryLimit: summaryLimit,
            content: content,
            existingTags: existingTags,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            completion: completion
        )
        
        queueLock.lock()
        
        // 去重逻辑：如果队列中已存在相同 contextId 的请求，则移除旧的
        if let cid = contextId {
            if let index = requestQueue.firstIndex(where: { $0.contextId == cid }) {
                print("[AI] 队列中已存在相同 ID (\(cid)) 的请求，移除旧请求")
                requestQueue.remove(at: index)
            }
            
            // 如果该 ID 正在处理中，我们也允许新请求入队，但处理时会再次检查
        }
        
        requestQueue.append(request)
        queueLock.unlock()
        
        // 异步触发队列处理，尝试填满并发槽位
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.triggerQueueProcessing()
        }
    }
    
    /// 触发队列处理，直到达到最大并发数
    private func triggerQueueProcessing() {
        while true {
            queueLock.lock()
            
            // 如果正在处理请求数量已达上限，或者队列为空，则退出循环
            guard activeRequests < maxConcurrentRequests && !requestQueue.isEmpty else {
                queueLock.unlock()
                break
            }
            
            // 取出下一个请求
            let request = requestQueue.removeFirst()
            
            // 进一步检查 contextId：如果该 ID 正在处理中，则跳过此请求（避免同一记录并发执行）
            if let cid = request.contextId, activeRequestIds.contains(cid) {
                print("[AI] ID (\(cid)) 正在处理中，跳过此队列请求")
                queueLock.unlock()
                continue
            }
            
            if let cid = request.contextId {
                activeRequestIds.insert(cid)
            }
            
            activeRequests += 1
            queueLock.unlock()
            
            // 处理单个请求
            processRequest(request)
        }
    }
    
    /// 处理单个请求
    private func processRequest(_ request: AIRequest) {
        summarizeWithOpenAI(
            titleLimit: request.titleLimit, 
            summaryLimit: request.summaryLimit, 
            content: request.content,
            existingTags: request.existingTags,
            systemPrompt: request.systemPrompt,
            userPrompt: request.userPrompt
        ) { [weak self] result in
            request.completion(result)
            self?.requestCompleted(contextId: request.contextId)
        }
    }
    
    /// 请求完成回调
    private func requestCompleted(contextId: String?) {
        queueLock.lock()
        activeRequests -= 1
        if let cid = contextId {
            activeRequestIds.remove(cid)
        }
        queueLock.unlock()
        
        // 继续处理队列
        triggerQueueProcessing()
    }

    /// 获取 OpenAI API 密钥（延迟加载，避免重复访问 Keychain）
    private func getOpenAIAPIKey() -> String? {
        queueLock.lock()
        defer { queueLock.unlock() }

        if !hasCheckedAPIKey {
            cachedAPIKey = KeychainHelper.shared.read(service: "QuiteNote", account: "openai_api_key")
            hasCheckedAPIKey = true
            print("[AI] API密钥获取结果: \(cachedAPIKey != nil ? "成功" : "失败")")
        }
        return cachedAPIKey
    }

    // MARK: - 纯文本改写（OCR AI 整理等场景）

    /// 是否已配置 AI 密钥（UI 按钮可用性/引导判断用）
    func hasAPIKey() -> Bool {
        getOpenAIAPIKey() != nil
    }

    /// 纯文本改写：复用现有密钥/模型/BaseURL 配置，不要求 JSON 响应
    /// 与 summarize 的区别：输入输出都是自然语言文本，适合 OCR 整理等场景
    /// 带自动重试（最多 4 次尝试，1s/2s/4s 指数退避）——
    /// 实测中转型端点会在 200/401/超时之间随机波动，重试显著提升成功率
    func rewrite(system: String, user: String, completion: @escaping (Result<String, Error>) -> Void) {
        attemptRewrite(system: system, user: user, remainingRetries: 3, completion: completion)
    }

    private func attemptRewrite(system: String, user: String, remainingRetries: Int, completion: @escaping (Result<String, Error>) -> Void) {
        var hasCompleted = false
        let safeCompletion: (Result<String, Error>) -> Void = { result in
            if !hasCompleted { hasCompleted = true; completion(result) }
        }

        guard let apiKey = getOpenAIAPIKey() else {
            safeCompletion(.failure(AIRewriteError.notConfigured)); return
        }
        guard let url = URL(string: "\(openAIBaseURL)/chat/completions") else {
            safeCompletion(.failure(AIRewriteError.badURL)); return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // 诊断：密钥指纹（前4位+长度）与目标 URL——排查"App 读到的密钥与命令行读到的不一致"类问题
        DiagnosticCenter.info("OCR", "AI 请求 → \(url.absoluteString) | key=\(apiKey.prefix(4))…(len=\(apiKey.count))")

        let body: [String: Any] = [
            "model": openAIModel,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.2,
            "max_tokens": 8000
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        URLSession(configuration: config).dataTask(with: req) { data, response, error in
            // 可重试的错误：网络错误 / 401 / 5xx（中转端点会在这些状态间随机波动）
            func scheduleRetry(reason: String) {
                let delay = pow(2.0, Double(3 - remainingRetries))  // 1s → 2s → 4s
                DiagnosticCenter.warning("OCR", "AI 请求\(reason)，\(Int(delay)) 秒后自动重试（剩 \(remainingRetries) 次）")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.attemptRewrite(system: system, user: user, remainingRetries: remainingRetries - 1, completion: completion)
                }
            }

            if let error {
                if remainingRetries > 0 { scheduleRetry(reason: "网络错误: \(error.localizedDescription)"); return }
                safeCompletion(.failure(error)); return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                // 诊断：失败响应体落日志——401 是代理拒的还是上游拒的，一看便知
                if let data, let body = String(data: data, encoding: .utf8) {
                    DiagnosticCenter.error("OCR", "AI HTTP \(http.statusCode) 响应体: \(String(body.prefix(200)))")
                }
                if remainingRetries > 0 && (http.statusCode == 401 || http.statusCode >= 500) {
                    scheduleRetry(reason: " HTTP \(http.statusCode)"); return
                }
                safeCompletion(.failure(AIRewriteError.http(http.statusCode))); return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  var content = message["content"] as? String else {
                safeCompletion(.failure(AIRewriteError.emptyResponse)); return
            }
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            // 剥掉模型可能自行包裹的 markdown 代码块
            if content.hasPrefix("```") {
                content = content
                    .replacingOccurrences(of: "```text\n", with: "")
                    .replacingOccurrences(of: "```markdown\n", with: "")
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            DispatchQueue.main.async {
                safeCompletion(.success(content))
            }
        }.resume()
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
        
        guard let url = URL(string: "\(openAIBaseURL)/chat/completions") else {
            print("[AI] 错误: 无效的 OpenAI Base URL: \(openAIBaseURL)")
            let baseTitle = String(content.prefix(max(0, min(titleLimit, 15))))
            let result = SummaryResult(title: baseTitle, summary: "", confidence: 0.0, tags: [], keywords: [])
            completion(.success(result))
            return
        }
        
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
/// 纯文本改写（OCR AI 整理）的错误类型
enum AIRewriteError: LocalizedError {
    case notConfigured
    case badURL
    case http(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "未配置 AI 密钥（设置 → AI 中填写后即可使用）"
        case .badURL: return "无效的 AI Base URL"
        case .http(let code):
            if code == 401 {
                return "AI 服务端不稳定（已自动重试仍 401）——多为中转端点波动，稍后再试；若持续失败请检查 设置 → AI 的 Base URL"
            }
            return "AI 请求失败（HTTP \(code)）"
        case .emptyResponse: return "AI 返回内容为空"
        }
    }
}
