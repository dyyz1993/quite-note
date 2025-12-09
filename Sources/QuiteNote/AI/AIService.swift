import Foundation

/// 统一的大模型提炼接口：返回标题、总结与置信度
protocol AIServiceProtocol {
    /// 执行提炼任务：输入限制与原文；completion 返回结构化结果或错误
    func summarize(titleLimit: Int, summaryLimit: Int, content: String, completion: @escaping (Result<SummaryResult, Error>) -> Void)
    
    /// 为单个记录生成总结
    func summarizeSingle(_ content: String, completion: @escaping (Result<SummaryResult, Error>) -> Void)
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
    func summarizeSingle(_ content: String, completion: @escaping (Result<SummaryResult, Error>) -> Void) {
        // 使用默认限制值调用 summarize 方法
        summarize(titleLimit: 30, summaryLimit: 100, content: content, completion: completion)
    }

    /// 执行提炼任务，按提供商路由；失败或超时时降级为前 15 字标题与空总结
    func summarize(titleLimit: Int, summaryLimit: Int, content: String, completion: @escaping (Result<SummaryResult, Error>) -> Void) {
        // 创建请求并加入队列
        let request = AIRequest(
            titleLimit: titleLimit,
            summaryLimit: summaryLimit,
            content: content,
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
        
        // 处理请求
        processRequest(request)
    }
    
    /// 处理单个请求
    private func processRequest(_ request: AIRequest) {
        switch provider {
        case .local:
            summarizeLocally(titleLimit: request.titleLimit, summaryLimit: request.summaryLimit, content: request.content) { [weak self] result in
                request.completion(result)
                self?.requestCompleted()
            }
        case .openai:
            summarizeWithOpenAI(titleLimit: request.titleLimit, summaryLimit: request.summaryLimit, content: request.content) { [weak self] result in
                request.completion(result)
                self?.requestCompleted()
            }
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
        }
        return cachedAPIKey
    }

    /// 本地规则提炼：根据长度与类型生成标题与总结，或使用配置的自定义API
    private func summarizeLocally(titleLimit: Int, summaryLimit: Int, content: String, completion: @escaping (Result<SummaryResult, Error>) -> Void) {
        print("[AI] 使用本地总结，内容长度: \(content.count)")
        
        // 检查是否配置了自定义API端点
        if let apiKey = getOpenAIAPIKey(), !openAIBaseURL.contains("api.openai.com") {
            print("[AI] 检测到自定义API端点，使用配置的API: \(openAIBaseURL)")
            summarizeWithCustomAPI(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, apiKey: apiKey, completion: completion)
            return
        }
        
        // 原有的本地总结逻辑
        let deadline = DispatchTime.now() + timeout
        DispatchQueue.global().asyncAfter(deadline: deadline) {
            let baseTitle = String(content.prefix( max(0, min(titleLimit, 15)) ))
            let result = SummaryResult(title: baseTitle, summary: "", confidence: 0.0)
            print("[AI] 本地总结完成 - 标题: \(baseTitle), 总结: 空, 置信度: 0.0")
            completion(.success(result))
        }
    }

    /// 使用 OpenAI Chat Completions 生成固定 JSON 输出
    private func summarizeWithOpenAI(titleLimit: Int, summaryLimit: Int, content: String, completion: @escaping (Result<SummaryResult, Error>) -> Void) {
        print("[AI] 开始处理总结请求，内容长度: \(content.count)")
        
        // 防止多次回调的标志
        var hasCompleted = false
        let safeCompletion: (Result<SummaryResult, Error>) -> Void = { result in
            if !hasCompleted {
                hasCompleted = true
                completion(result)
            }
        }
        
        guard let apiKey = getOpenAIAPIKey() else {
            print("[AI] 未找到API密钥，使用本地总结")
            summarizeLocally(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, completion: safeCompletion)
            return
        }
        print("[AI] 使用OpenAI API处理请求")
        let url = URL(string: "\(openAIBaseURL)/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let sys = "你是一个专业的问题分析助手。请仔细分析以下文本，提炼出其中的核心问题或关键点。严格输出以下 JSON 字段，不要包含多余文本：{\"title\":不超过\(titleLimit)字的问题标题,\"summary\":不超过\(summaryLimit)字的问题总结,\"confidence\":0-1 之间置信度，仅数字}";
        let user = "请分析以下文本，提炼出其中的问题或关键点：\n\n\(content)\n\n只返回 JSON，确保标题和总结都聚焦于问题本身。"

        let body: [String: Any] = [
            "model": openAIModel,
            "messages": [
                ["role": "system", "content": sys],
                ["role": "user", "content": user]
            ]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: req) { [weak self] data, response, error in
            if error != nil {
                print("[AI] API请求错误: \(error?.localizedDescription ?? "未知错误")")
                self?.summarizeLocally(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, completion: safeCompletion)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("[AI] API响应状态码: \(httpResponse.statusCode)")
            }
            
            guard let data else {
                print("[AI] API响应数据为空")
                self?.summarizeLocally(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, completion: safeCompletion)
                return
            }
            
            // 打印原始响应（仅前500字符）
            if let responseString = String(data: data, encoding: .utf8) {
                let preview = String(responseString.prefix(500))
                print("[AI] API响应预览: \(preview)")
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let msg = first["message"] as? [String: Any],
                  let contentStr = msg["content"] as? String else {
                print("[AI] 无法解析API响应JSON")
                self?.summarizeLocally(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, completion: safeCompletion)
                return
            }
            
            print("[AI] 解析的内容: \(contentStr)")
            
            let parsed = Self.parseJSONText(contentStr)
            let title = parsed?.title ?? String(content.prefix(min(titleLimit, 15)))
            let summary = parsed?.summary ?? ""
            let conf = parsed?.confidence ?? 0.0
            
            print("[AI] 解析结果 - 标题: \(title), 总结: \(summary), 置信度: \(conf)")
            
            safeCompletion(.success(SummaryResult(title: title, summary: summary, confidence: conf)))
        }
        task.resume()

        // 超时处理
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
            if task.state == URLSessionTask.State.running {
                task.cancel()
                self?.summarizeLocally(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, completion: safeCompletion)
            }
        }
    }
    
    /// 使用自定义API（如智谱AI）生成总结
    private func summarizeWithCustomAPI(titleLimit: Int, summaryLimit: Int, content: String, apiKey: String, completion: @escaping (Result<SummaryResult, Error>) -> Void) {
        print("[AI] 使用自定义API处理请求: \(openAIBaseURL)")
        
        // 防止多次回调的标志
        var hasCompleted = false
        let safeCompletion: (Result<SummaryResult, Error>) -> Void = { result in
            if !hasCompleted {
                hasCompleted = true
                completion(result)
            }
        }
        
        // 构建请求URL，智谱AI的API端点处理
        var urlString = openAIBaseURL
        // 智谱AI的API端点通常已经包含完整路径
        if !openAIBaseURL.hasSuffix("/chat/completions") && !openAIBaseURL.contains("/paas/v4/") {
            urlString = "\(openAIBaseURL)/chat/completions"
        }
        
        guard let url = URL(string: urlString) else {
            print("[AI] 无效的API URL: \(urlString)")
            summarizeLocally(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, completion: safeCompletion)
            return
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // 设置超时时间
        req.timeoutInterval = timeout

        // 限制内容长度以避免内存问题
        let maxLength = 8000
        let truncatedContent = content.count > maxLength ? String(content.prefix(maxLength)) + "..." : content
        
        let sys = "你是一个专业的问题分析助手。请仔细分析以下文本，提炼出其中的核心问题或关键点。严格输出以下 JSON 字段，不要包含多余文本：{\"title\":不超过\(titleLimit)字的问题标题,\"summary\":不超过\(summaryLimit)字的问题总结,\"confidence\":0-1 之间置信度，仅数字}";
        let user = "请分析以下文本，提炼出其中的问题或关键点：\n\n\(truncatedContent)\n\n只返回 JSON，确保标题和总结都聚焦于问题本身。"

        let body: [String: Any] = [
            "model": openAIModel,
            "messages": [
                ["role": "system", "content": sys],
                ["role": "user", "content": user]
            ]
        ]
        
        // 安全的JSON序列化
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            print("[AI] JSON序列化错误: \(error.localizedDescription)")
            summarizeLocally(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, completion: safeCompletion)
            return
        }

        // 使用优化的URLSession配置
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        
        let task = session.dataTask(with: req) { [weak self] data, response, error in
            if error != nil {
                print("[AI] 自定义API请求错误: \(error?.localizedDescription ?? "未知错误")")
                self?.summarizeLocally(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, completion: safeCompletion)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("[AI] 自定义API响应状态码: \(httpResponse.statusCode)")
            }
            
            guard let data else {
                print("[AI] 自定义API响应数据为空")
                self?.summarizeLocally(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, completion: safeCompletion)
                return
            }
            
            // 打印原始响应（仅前500字符）
            if let responseString = String(data: data, encoding: .utf8) {
                let preview = String(responseString.prefix(500))
                print("[AI] 自定义API响应预览: \(preview)")
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let msg = first["message"] as? [String: Any],
                  let contentStr = msg["content"] as? String else {
                print("[AI] 无法解析自定义API响应JSON")
                self?.summarizeLocally(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, completion: safeCompletion)
                return
            }
            
            print("[AI] 自定义API解析的内容: \(contentStr)")
            
            let parsed = Self.parseJSONText(contentStr)
            let title = parsed?.title ?? String(content.prefix(min(titleLimit, 15)))
            let summary = parsed?.summary ?? ""
            let conf = parsed?.confidence ?? 0.0
            
            print("[AI] 自定义API解析结果 - 标题: \(title), 总结: \(summary), 置信度: \(conf)")
            
            safeCompletion(.success(SummaryResult(title: title, summary: summary, confidence: conf)))
        }
        task.resume()

        // 超时处理
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
            if task.state == URLSessionTask.State.running {
                task.cancel()
                self?.summarizeLocally(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content, completion: safeCompletion)
            }
        }
    }

    /// 测试API连接
    func testConnection(completion: @escaping (Result<Bool, Error>) -> Void) {
        guard provider == .openai else {
            // 本地提供商总是可用的
            completion(.success(true))
            return
        }
        
        guard let apiKey = getOpenAIAPIKey() else {
            completion(.failure(NSError(domain: "AIService", code: 401, userInfo: [NSLocalizedDescriptionKey: "未设置API密钥"])))
            return
        }
        
        let url = URL(string: "\(openAIBaseURL)/models")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: req) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "AIService", code: 0, userInfo: [NSLocalizedDescriptionKey: "无效的响应"])))
                return
            }
            
            if httpResponse.statusCode == 200 {
                completion(.success(true))
            } else {
                completion(.failure(NSError(domain: "AIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP错误: \(httpResponse.statusCode)"])))
            }
        }
        
        task.resume()
        
        // 超时处理
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if task.state == .running {
                task.cancel()
                completion(.failure(NSError(domain: "AIService", code: 408, userInfo: [NSLocalizedDescriptionKey: "请求超时"])))
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
