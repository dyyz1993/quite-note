import Foundation
import os.log

/// OpenAI API 客户端 - 负责与 OpenAI API 的通信
final class OpenAIClient {
    private static let logger = Logger(subsystem: "com.quitenote.app", category: "OpenAIClient")

    private var baseURL: String
    private var model: String
    private var timeout: TimeInterval
    private let keychain: KeychainHelper

    // 延迟加载 API Key
    private var hasCheckedAPIKey = false
    private var cachedAPIKey: String?

    init(baseURL: String = "https://api.openai.com/v1",
         model: String = "gpt-4o-mini",
         timeout: TimeInterval = AIConstants.defaultTimeout,
         keychain: KeychainHelper = .shared) {
        self.baseURL = baseURL
        self.model = model
        self.timeout = timeout
        self.keychain = keychain
    }

    // MARK: - Public Methods

    /// 测试 API 连接
    func testConnection(completion: @escaping (Result<Void, Error>) -> Void) {
        Self.logger.info("测试 OpenAI 连接")

        guard let apiKey = getAPIKey() else {
            completion(.failure(AIError.apiKeyMissing))
            return
        }

        guard let testURL = URL(string: "\(baseURL)/models") else {
            completion(.failure(AIError.invalidURL(baseURL)))
            return
        }

        var request = URLRequest(url: testURL)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout

        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(self.mapError(error)))
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    Self.logger.info("OpenAI 连接测试成功")
                    completion(.success(()))
                } else {
                    completion(.failure(AIError.httpError(httpResponse.statusCode)))
                }
            } else {
                completion(.failure(AIError.invalidResponse))
            }
        }

        task.resume()
    }

    /// 发送聊天完成请求
    func chatCompletion(systemPrompt: String,
                        userPrompt: String,
                        temperature: Double = AIConstants.defaultTemperature,
                        maxTokens: Int = AIConstants.defaultMaxTokens,
                        completion: @escaping (Result<String, Error>) -> Void) {

        guard let apiKey = getAPIKey() else {
            completion(.failure(AIError.apiKeyMissing))
            return
        }

        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            completion(.failure(AIError.invalidURL(baseURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": temperature,
            "max_tokens": maxTokens,
            "response_format": ["type": "json_object"]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: .prettyPrinted)
        } catch {
            completion(.failure(error))
            return
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                completion(.failure(self.mapError(error)))
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    completion(.failure(AIError.httpError(httpResponse.statusCode)))
                    return
                }
            }

            guard let data = data else {
                completion(.failure(AIError.noData))
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let message = first["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    completion(.success(content))
                } else {
                    completion(.failure(AIError.invalidResponse))
                }
            } catch {
                completion(.failure(error))
            }
        }

        task.resume()
    }

    // MARK: - Private Methods

    private func getAPIKey() -> String? {
        if !hasCheckedAPIKey {
            cachedAPIKey = keychain.read(service: "QuiteNote", account: "openai_api_key")
            hasCheckedAPIKey = true
            Self.logger.info("API 密钥获取结果: \(self.cachedAPIKey != nil ? "成功" : "失败")")
        }
        return cachedAPIKey
    }

    private func mapError(_ error: Error) -> Error {
        let nsError = error as NSError

        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            return AIError.noInternet
        case NSURLErrorTimedOut:
            return AIError.timeout
        case 401:
            return AIError.invalidAPIKey
        default:
            return AIError.networkError(error.localizedDescription)
        }
    }
}

// MARK: - AI Error Types

enum AIError: LocalizedError {
    case apiKeyMissing
    case invalidAPIKey
    case invalidURL(String)
    case noInternet
    case timeout
    case httpError(Int)
    case noData
    case invalidResponse
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "未设置 API 密钥"
        case .invalidAPIKey:
            return "API 密钥无效"
        case .invalidURL(let url):
            return "无效的 API URL: \(url)"
        case .noInternet:
            return "无网络连接"
        case .timeout:
            return "连接超时"
        case .httpError(let code):
            return "HTTP 错误 \(code)"
        case .noData:
            return "无响应数据"
        case .invalidResponse:
            return "无效的响应"
        case .networkError(let msg):
            return "网络错误: \(msg)"
        }
    }
}
