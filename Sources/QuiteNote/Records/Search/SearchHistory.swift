import Foundation
import Combine

/// 搜索历史管理器
final class SearchHistory {
    private let preferences: PreferencesManager
    private(set) var history: [String] = []

    // 当历史记录更新时发送通知
    let didUpdate = PassthroughSubject<Void, Never>()

    init(preferences: PreferencesManager = .shared) {
        self.preferences = preferences
        load()
    }

    /// 添加搜索词到历史记录
    func add(_ query: String) {
        // 避免频繁更新，如果查询已在历史记录顶部，则不更新
        if let first = history.first, first == query {
            return
        }

        // 移除重复项
        history.removeAll { $0 == query }
        // 添加到开头
        history.insert(query, at: 0)
        // 限制历史记录数量
        if history.count > 20 {
            history = Array(history.prefix(20))
        }

        // 异步保存到偏好设置，避免阻塞UI
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.save()
        }

        // 发送更新通知
        didUpdate.send()
    }

    /// 清空搜索历史
    func clear() {
        history.removeAll()
        save()
        didUpdate.send()
    }

    /// 从偏好设置加载搜索历史
    private func load() {
        history = preferences.stringArray(forKey: "searchHistory") ?? []
    }

    /// 保存搜索历史到偏好设置
    private func save() {
        preferences.set(history, forKey: "searchHistory")
    }
}
