import AppKit

/// 键盘快捷键管理器，支持全局快捷键和应用内快捷键
final class KeyboardShortcutManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    
    // 回调函数
    var onTogglePanel: (() -> Void)?
    var onToggleAI: (() -> Void)?
    var onForceCenter: (() -> Void)?
    var onCaptureClipboard: (() -> Void)?
    var onBulkSummarize: (() -> Void)?
    var onExport: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?
    
    /// 启动全局快捷键监听
    func start() {
        // 全局快捷键监听（应用内外都有效）
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return }
            let flags = e.modifierFlags
            
            // ⌥⌘ 快捷键组合
            if flags.contains(.command) && flags.contains(.option) {
                switch e.characters?.lowercased() {
                case "r": self.onTogglePanel?()           // ⌥⌘R 显示/隐藏面板
                case "a": self.onToggleAI?()              // ⌥⌘A 切换AI
                case "c": self.onCaptureClipboard?()      // ⌥⌘C 采集剪贴板
                case "e": self.onExport?()                 // ⌥⌘E 导出记录
                case "d": self.onForceCenter?()           // ⌥⌘D 强制居中（调试）
                default: break
                }
            }
            
            // ⌥⌘⇧ 快捷键组合
            if flags.contains(.command) && flags.contains(.option) && flags.contains(.shift) {
                switch e.characters?.lowercased() {
                case "r": self.onForceCenter?()            // ⌥⌘⇧R 强制居中
                case "a": self.onBulkSummarize?()         // ⌥⌘⇧A 批量提炼
                default: break
                }
            }
        }
        
        // 应用内快捷键监听（仅在应用前台有效）
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            let flags = e.modifierFlags
            
            // Cmd+, 打开设置
            if flags.contains(.command) && e.characters == "," {
                self.onOpenSettings?()
                return nil // 消费事件
            }
            
            // Cmd+Q 退出应用
            if flags.contains(.command) && e.characters?.lowercased() == "q" {
                self.onQuit?()
                return nil // 消费事件
            }
            
            return e // 不消费事件，继续传递
        }
    }

    /// 停止快捷键监听
    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }
    
    deinit { 
        stop()
    }
}

