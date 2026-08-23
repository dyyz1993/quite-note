import Foundation
import AppKit

/// 链接条目的 favicon 服务：按域名拉取 /favicon.ico，磁盘缓存（Cache/Favicons）
///
/// 隐私说明：仅向「用户复制的那条链接所属域名」发起请求（不上传内容本身）；
/// 请求失败或离线时回退到通用链接图标。
final class ClipboardFaviconService {
    static let shared = ClipboardFaviconService()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let session: URLSession
    private var inFlight: [String: [(NSImage?) -> Void]] = [:]
    private let lock = NSLock()

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh)"]
        session = URLSession(configuration: config)
    }

    private var cacheDirectory: URL {
        let dir = FileCoordinator.shared.getDirectoryURL(for: .thumbnail)
            .deletingLastPathComponent()
            .appendingPathComponent("Favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 同步读缓存（列表复用时快速命中）
    func cachedFavicon(for domain: String) -> NSImage? {
        let key = normalize(domain)
        guard !key.isEmpty else { return nil }
        if let hit = memoryCache.object(forKey: key as NSString) { return hit }
        guard let image = NSImage(contentsOf: cacheDirectory.appendingPathComponent("\(key).ico")) else { return nil }
        memoryCache.setObject(image, forKey: key as NSString)
        return image
    }

    /// 异步取 favicon（缓存 → 下载 → 落盘），主线程回调；失败回调 nil
    func loadFavicon(for domain: String, completion: @escaping (NSImage?) -> Void) {
        let key = normalize(domain)
        guard !key.isEmpty, let base = URL(string: "https://\(key)/favicon.ico") else {
            completion(nil)
            return
        }
        if let hit = cachedFavicon(for: domain) {
            completion(hit)
            return
        }

        // 合并在途请求
        lock.lock()
        var listeners = inFlight[key] ?? []
        listeners.append(completion)
        inFlight[key] = listeners
        let shouldStart = listeners.count == 1
        lock.unlock()
        guard shouldStart else { return }

        session.dataTask(with: base) { [weak self] data, response, _ in
            let image: NSImage? = {
                guard let data,
                      (response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true,
                      let img = NSImage(data: data) else { return nil }
                return img
            }()

            if let image, let self {
                self.memoryCache.setObject(image, forKey: key as NSString)
                try? data?.write(to: self.cacheDirectory.appendingPathComponent("\(key).ico"))
            }

            let callbacks: [(NSImage?) -> Void]
            self?.lock.lock()
            callbacks = self?.inFlight.removeValue(forKey: key) ?? []
            self?.lock.unlock()

            DispatchQueue.main.async {
                callbacks.forEach { $0(image) }
            }
        }.resume()
    }

    private func normalize(_ domain: String) -> String {
        domain.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
            .replacingOccurrences(of: "/", with: "_")
    }
}
