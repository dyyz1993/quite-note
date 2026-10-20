import Foundation

enum AIConnectionKind: String {
    case magpie
    case customOpenAI
}

struct AIConnectionSnapshot: Equatable {
    let kind: AIConnectionKind
    let baseURL: String
    let model: String
    let bearerToken: String

    var isReady: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !bearerToken.isEmpty &&
        URL(string: normalizedBaseURL) != nil
    }

    var normalizedBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AIRequestError: LocalizedError {
    case notConfigured(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let message):
            return message
        }
    }
}

struct MagpieModel: Identifiable, Equatable {
    let id: String
    let displayName: String
    let owner: String?
    let supportsImageInput: Bool

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return id.localizedCaseInsensitiveContains(query) ||
            displayName.localizedCaseInsensitiveContains(query)
    }
}

enum AIConnectionResolver {
    static let magpieToken = "magpie-quite-note"

    static func snapshot(
        kind: AIConnectionKind,
        customBaseURL: String,
        customModel: String,
        customAPIKey: String?,
        magpieBaseURL: String,
        magpieModel: String = ""
    ) -> AIConnectionSnapshot {
        switch kind {
        case .magpie:
            return AIConnectionSnapshot(
                kind: .magpie,
                baseURL: magpieBaseURL,
                model: magpieModel,
                bearerToken: magpieToken
            )
        case .customOpenAI:
            return AIConnectionSnapshot(
                kind: .customOpenAI,
                baseURL: customBaseURL,
                model: customModel,
                bearerToken: customAPIKey ?? ""
            )
        }
    }

    static func snapshot(preferences: PreferencesManager) -> AIConnectionSnapshot {
        snapshot(
            kind: preferences.aiConnectionKind,
            customBaseURL: preferences.openAIBaseURL,
            customModel: preferences.openAIModel,
            customAPIKey: KeychainHelper.shared.read(
                service: "QuiteNote",
                account: "openai_api_key"
            ),
            magpieBaseURL: preferences.magpieBaseURL,
            magpieModel: preferences.magpieModelID ?? ""
        )
    }

    static func currentModelSnapshot(preferences: PreferencesManager) -> Result<AIConnectionSnapshot, AIRequestError> {
        let snapshot = snapshot(preferences: preferences)
        guard snapshot.isReady else {
            let message = snapshot.kind == .magpie
                ? "Magpie 连接配置不完整"
                : "请填写自定义 API 的 Base URL、模型和 API Key"
            return .failure(.notConfigured(message))
        }
        return .success(snapshot)
    }

    static func chatURLRequest(
        snapshot: AIConnectionSnapshot,
        systemPrompt: String,
        userPrompt: String,
        temperature: Double,
        maxTokens: Int,
        requiresJSON: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: "\(snapshot.normalizedBaseURL)/chat/completions") else {
            throw AIRequestError.notConfigured("无效的 AI Base URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(snapshot.bearerToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        var body: [String: Any] = [
            "model": snapshot.normalizedModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": temperature,
            "max_tokens": maxTokens
        ]
        if requiresJSON {
            body["response_format"] = ["type": "json_object"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// OpenAI Chat Completions 多模态消息：文本 + 若干 data URL 图片。
    /// 保留 JSON 输出约束；不支持该格式的服务端会返回 HTTP 错误，由调用方展示失败状态。
    static func multimodalChatURLRequest(
        snapshot: AIConnectionSnapshot,
        systemPrompt: String,
        userPrompt: String,
        images: [AIImageData],
        temperature: Double,
        maxTokens: Int,
        requiresJSON: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: "\(snapshot.normalizedBaseURL)/chat/completions") else {
            throw AIRequestError.notConfigured("无效的 AI Base URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(snapshot.bearerToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90

        var userContent: [[String: Any]] = [
            ["type": "text", "text": userPrompt]
        ]
        for image in images {
            userContent.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:\(image.mimeType);base64,\(image.base64)"
                ]
            ])
        }

        var body: [String: Any] = [
            "model": snapshot.normalizedModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "temperature": temperature,
            "max_tokens": maxTokens
        ]
        if requiresJSON {
            body["response_format"] = ["type": "json_object"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func resolvedKind(storedKind: AIConnectionKind?, hasLegacyAIConfig: Bool) -> AIConnectionKind {
        if let storedKind { return storedKind }
        return hasLegacyAIConfig ? .customOpenAI : .magpie
    }
}

