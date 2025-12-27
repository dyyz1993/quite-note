import AppKit
import OSLog

/// 键盘快捷键管理器，支持全局快捷键和应用内快捷键
final class KeyboardShortcutManager {
    private let logger = Logger(subsystem: "com.quitenote.app.dev", category: "KeyboardShortcutManager")
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pasteMonitor: Any?
    
    // 回调函数
    var onTogglePanel: (() -> Void)?
    var onToggleAI: (() -> Void)?
    var onForceCenter: (() -> Void)?
    var onCaptureClipboard: (() -> Void)?
    var onBulkSummarize: (() -> Void)?
    var onExport: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?
    var onGlobalPaste: (() -> Void)?
    var onScreenshot: (() -> Void)?
    
    /// 启动全局快捷键监听
    func start() {
        logger.info("启动键盘快捷键监听")
        
        // 全局粘贴事件监听（当应用没有焦点时）
        pasteMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self = self else { return }
            
            // 检测 Cmd+V 粘贴快捷键
            if e.modifierFlags.contains(.command) && e.characters?.lowercased() == "v" {
                // 延迟一小段时间，确保粘贴内容已经更新到剪贴板
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.onGlobalPaste?()
                }
            }
        }
        
        // 全局快捷键监听（应用内外都有效）
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return }
            let flags = e.modifierFlags
            let char = e.charactersIgnoringModifiers?.lowercased()
            
            // ⌥⌘ 快捷键组合
            if flags.contains(.command) && flags.contains(.option) {
                switch char {
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
                switch char {
                case "r": self.onForceCenter?()            // ⌥⌘⇧R 强制居中
                case "a": self.onBulkSummarize?()         // ⌥⌘⇧A 批量提炼
                default: break
                }
            }

            // 截图快捷键 (从 PreferencesManager 读取)
            let prefShortcut = PreferencesManager.shared.screenshotShortcut.lowercased()
            let prefFlagsRaw = UInt(PreferencesManager.shared.screenshotShortcutFlags)
            let prefFlags = NSEvent.ModifierFlags(rawValue: prefFlagsRaw)
            
            // 只保留关键修饰键进行比较 (cmd, opt, shift, ctrl)
            let relevantFlags: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
            let currentFlags = flags.intersection(relevantFlags)
            let targetFlags = prefFlags.intersection(relevantFlags)
            
            if currentFlags == targetFlags && char == prefShortcut {
                self.logger.info("全局快捷键触发: 截图")
                self.onScreenshot?()
            }
        }
        
        // 应用内快捷键监听（仅在应用前台有效）
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            let flags = e.modifierFlags
            let char = e.charactersIgnoringModifiers?.lowercased()
            
            // 截图快捷键 (应用内也支持)
            let prefShortcut = PreferencesManager.shared.screenshotShortcut.lowercased()
            let prefFlagsRaw = UInt(PreferencesManager.shared.screenshotShortcutFlags)
            let prefFlags = NSEvent.ModifierFlags(rawValue: prefFlagsRaw)
            let relevantFlags: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
            let currentFlags = flags.intersection(relevantFlags)
            let targetFlags = prefFlags.intersection(relevantFlags)

            if currentFlags == targetFlags && char == prefShortcut {
                self.logger.info("应用内快捷键触发: 截图")
                self.onScreenshot?()
                return nil // 消费事件
            }
            
            // Cmd+V 粘贴快捷键（应用内无输入框聚焦时）
            if flags.contains(.command) && char == "v" {
                // 检查当前焦点是否在文本输入框中
                if let focusedView = NSApp.keyWindow?.firstResponder,
                   focusedView is NSTextView || focusedView is NSTextField {
                    // 如果焦点在文本输入框中，不处理，让系统默认粘贴行为生效
                    return e
                } else {
                    // 如果焦点不在文本输入框中，处理粘贴事件
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.onGlobalPaste?()
                    }
                    return nil // 消费事件，防止系统默认粘贴行为
                }
            }
            
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
        if let m = pasteMonitor { NSEvent.removeMonitor(m) }
    }
    
    deinit { 
        stop()
    }
}

