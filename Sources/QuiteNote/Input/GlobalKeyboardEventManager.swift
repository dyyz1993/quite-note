import AppKit

/// 全局键盘事件管理器
///
/// 统一管理所有面板的键盘事件，通过优先级避免冲突
class GlobalKeyboardEventManager {
    static let shared = GlobalKeyboardEventManager()

    /// 键盘事件处理器
    struct Handler {
        let id: String
        let priority: Int
        let canHandle: () -> Bool
        let handle: (NSEvent) -> Bool
    }

    private var handlers: [String: Handler] = [:]
    private let lock = NSLock()
    private var monitor: Any?

    private init() {
        setupMonitor()
    }

    /// 注册键盘事件处理器
    ///
    /// - Parameters:
    ///   - id: 处理器唯一标识
    ///   - priority: 优先级（数值越大优先级越高）
    ///   - canHandle: 检查是否应该处理此事件的闭包
    ///   - handle: 处理事件的闭包，返回 true 表示事件已消费
    func register(id: String, priority: Int, canHandle: @escaping () -> Bool, handle: @escaping (NSEvent) -> Bool) {
        lock.lock()
        defer { lock.unlock() }

        let handler = Handler(id: id, priority: priority, canHandle: canHandle, handle: handle)
        handlers[id] = handler

        print("[GlobalKeyboardEventManager] Registered handler: \(id) with priority: \(priority)")
    }

    /// 注销键盘事件处理器
    ///
    /// - Parameter id: 处理器唯一标识
    func unregister(id: String) {
        lock.lock()
        defer { lock.unlock() }

        handlers.removeValue(forKey: id)

        print("[GlobalKeyboardEventManager] Unregistered handler: \(id)")
    }

    /// 设置键盘事件监听
    private func setupMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            return self.handleEvent(event)
        }

        print("[GlobalKeyboardEventManager] Keyboard event monitor set up")
    }

    /// 处理键盘事件
    ///
    /// - Parameter event: 键盘事件
    /// - Returns: nil 表示事件已消费，event 表示继续传递
    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        lock.lock()
        let sortedHandlers = handlers.values.sorted { $0.priority > $1.priority }
        lock.unlock()

        for handler in sortedHandlers {
            if handler.canHandle() {
                let consumed = handler.handle(event)
                if consumed {
                    print("[GlobalKeyboardEventManager] Event consumed by: \(handler.id), keyCode: \(event.keyCode)")
                    return nil // 消费事件
                }
            }
        }

        return event // 继续传递
    }
}

/// 键盘事件优先级常量
enum KeyboardEventPriority {
    /// 符号浏览器面板（最高优先级）
    static let symbolBrowser = 100

    /// 符号联想面板
    static let symbolSuggestion = 90

    /// 截图标注面板
    static let screenshotAnnotation = 80

    /// 主悬浮面板
    static let floatingPanel = 50

    /// 全局快捷键（最低优先级）
    static let globalShortcuts = 10
}
