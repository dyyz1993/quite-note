import Foundation
import os.log

/// AI 请求队列管理器 - 负责队列管理、并发控制、去重
final class AIRequestQueue {
    private static let logger = Logger(subsystem: "com.quitenote.app", category: "AIRequestQueue")

    private var queue: [AIRequestItem] = []
    private var activeRequestIds: Set<String> = []
    private var activeRequests = 0
    private let maxConcurrent: Int
    private let lock = NSLock()

    /// 队列状态回调
    var onQueueProcessed: (() -> Void)?

    init(maxConcurrent: Int = AIConstants.maxConcurrentRequests) {
        self.maxConcurrent = maxConcurrent
    }

    /// 添加请求到队列
    func enqueue(_ request: AIRequestItem) {
        lock.lock()

        // 去重逻辑：如果队列中已存在相同 contextId 的请求，则移除旧的
        if let contextId = request.config.contextId {
            if let index = queue.firstIndex(where: { $0.config.contextId == contextId }) {
                Self.logger.info("队列中已存在相同 ID (\(contextId)) 的请求，移除旧请求")
                queue.remove(at: index)
            }
        }

        queue.append(request)
        lock.unlock()

        // 异步触发队列处理
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.process()
        }
    }

    /// 处理队列
    private func process() {
        while true {
            lock.lock()

            // 如果正在处理请求数量已达上限，或者队列为空，则退出循环
            guard activeRequests < maxConcurrent && !queue.isEmpty else {
                lock.unlock()
                break
            }

            // 取出下一个请求
            let request = queue.removeFirst()

            // 进一步检查 contextId：如果该 ID 正在处理中，则跳过此请求
            if let contextId = request.config.contextId,
               activeRequestIds.contains(contextId) {
                Self.logger.info("ID (\(contextId)) 正在处理中，跳过此队列请求")
                lock.unlock()
                continue
            }

            // 标记为正在处理
            if let contextId = request.config.contextId {
                activeRequestIds.insert(contextId)
            }
            activeRequests += 1
            lock.unlock()

            // 处理单个请求
            processRequest(request) { req in
                // 由外部 AIService 调用实际处理逻辑
                // 这里只是占位，实际处理在 AIService 中
            }
        }
    }

    /// 处理单个请求（由外部调用）
    func processRequest(_ request: AIRequestItem, handler: (AIRequestItem) -> Void) {
        handler(request)
    }

    /// 标记请求完成
    func markCompleted(contextId: String?) {
        lock.lock()
        activeRequests -= 1
        if let contextId = contextId {
            activeRequestIds.remove(contextId)
        }
        lock.unlock()

        // 继续处理队列
        process()

        // 触发回调
        onQueueProcessed?()
    }

    /// 清空队列
    func clear() {
        lock.lock()
        queue.removeAll()
        activeRequestIds.removeAll()
        lock.unlock()
    }

    /// 获取队列状态
    func getStatus() -> (queueCount: Int, activeCount: Int, activeIds: Set<String>) {
        lock.lock()
        let status = (queue.count, activeRequests, activeRequestIds)
        lock.unlock()
        return status
    }
}
