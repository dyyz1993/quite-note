import Foundation

struct MagpieGatewayInfo: Equatable {
    let name: String
    let version: String?
}

enum MagpieCatalogError: LocalizedError, Equatable {
    case invalidURL
    case notMagpie
    case invalidResponse
    case emptyCatalog
    case http(Int)
    case unreachable(String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Magpie 地址无效"
        case .notMagpie:
            return "这个地址不是 Magpie 网关"
        case .invalidResponse:
            return "Magpie 返回了无法解析的数据"
        case .emptyCatalog:
            return "Magpie 没有开放可用模型"
        case .http(let code):
            return "Magpie 请求失败（HTTP \(code)）"
        case .unreachable:
            return "无法连接 Magpie。请确认已安装并启动 Magpie；如果已启动，请检查地址和端口。"
        }
    }
}

final class MagpieCatalogService {
    private let session: URLSession
    private let timeout: TimeInterval

    init(session: URLSession = .shared, timeout: TimeInterval = 3) {
        self.session = session
        self.timeout = timeout
    }

    func load(baseURL: String, completion: @escaping (Result<(MagpieGatewayInfo, [MagpieModel]), MagpieCatalogError>) -> Void) {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let root = URL(string: trimmedBaseURL),
              let scheme = root.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              root.host()?.isEmpty == false,
              root.fragment == nil else {
            completion(.failure(.invalidURL))
            return
        }
        // URL(string:relativeTo:) is too lenient for malformed user input.
        guard let rootURL = URL(string: root.absoluteString + "/") else {
            completion(.failure(.invalidURL))
            return
        }
        guard let helloURL = URL(string: "api/hello", relativeTo: rootURL),
              let modelsURL = URL(string: "v1/models", relativeTo: rootURL) else {
            completion(.failure(.invalidURL))
            return
        }

        loadGatewayInfo(from: helloURL) { infoResult in
            switch infoResult {
            case .failure(let error):
                completion(.failure(error))
            case .success(let info):
                self.loadModels(from: modelsURL) { modelsResult in
                    switch modelsResult {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let models):
                        completion(.success((info, models)))
                    }
                }
            }
        }
    }

    private func loadGatewayInfo(
        from url: URL,
        completion: @escaping (Result<MagpieGatewayInfo, MagpieCatalogError>) -> Void
    ) {
        request(url) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                struct Response: Decodable {
                    let name: String
                    let version: String?
                }
                guard let response = try? JSONDecoder().decode(Response.self, from: data),
                      response.name == "magpie" else {
                    completion(.failure(.notMagpie))
                    return
                }
                completion(.success(MagpieGatewayInfo(name: response.name, version: response.version)))
            }
        }
    }

    private func loadModels(
        from url: URL,
        completion: @escaping (Result<[MagpieModel], MagpieCatalogError>) -> Void
    ) {
        request(url) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                struct Response: Decodable {
                    struct Item: Decodable {
                        let id: String
                        let display_name: String?
                        let owned_by: String?
                        let modalities: Modalities?
                    }
                    struct Modalities: Decodable {
                        let input: [String]?
                    }
                    let data: [Item]
                }
                guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
                    completion(.failure(.invalidResponse))
                    return
                }
                let models = response.data
                    .filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .map {
                        MagpieModel(
                            id: $0.id,
                            displayName: $0.display_name ?? $0.id,
                            owner: $0.owned_by,
                            supportsImageInput: $0.modalities?.input?.contains("image") == true
                        )
                    }
                    .sorted {
                        $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                    }
                guard !models.isEmpty else {
                    completion(.failure(.emptyCatalog))
                    return
                }
                completion(.success(models))
            }
        }
    }

    private func request(
        _ url: URL,
        completion: @escaping (Result<Data, MagpieCatalogError>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(AIConnectionResolver.magpieToken)", forHTTPHeaderField: "Authorization")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = timeout
        session.dataTask(with: request) { data, response, error in
            if let error {
                let reason = (error as NSError).localizedFailureReason ?? error.localizedDescription
                completion(.failure(.unreachable(reason)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(.http(http.statusCode)))
                return
            }
            guard let data else {
                completion(.failure(.invalidResponse))
                return
            }
            completion(.success(data))
        }.resume()
    }
}

enum MagpieCatalogUIState {
    case idle
    case loading
    case loaded([MagpieModel])
    case failed(String)
}

