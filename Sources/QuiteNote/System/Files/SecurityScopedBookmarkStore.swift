import Foundation

/// Persists security-scoped bookmarks for folders selected through NSOpenPanel.
final class SecurityScopedBookmarkStore {
    static let shared = SecurityScopedBookmarkStore()

    private let defaults = UserDefaults.standard
    private var activeURLs = Set<URL>()
    private let lock = NSLock()

    private init() {}

    @discardableResult
    func save(_ url: URL, forKey key: String) -> Bool {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(data, forKey: key)
            return true
        } catch {
            return false
        }
    }

    func hasBookmark(forKey key: String) -> Bool {
        defaults.data(forKey: key) != nil
    }

    /// Resolves a bookmark and keeps its scope active for the app lifetime.
    func resolve(forKey key: String) -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        lock.lock()
        if !activeURLs.contains(url) {
            guard url.startAccessingSecurityScopedResource() else {
                lock.unlock()
                return nil
            }
            activeURLs.insert(url)
        }
        lock.unlock()

        if isStale {
            _ = save(url, forKey: key)
        }
        return url
    }

    func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}
