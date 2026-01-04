import AppKit
import OSLog

/// 键盘快捷键管理器，支持全局快捷键和应用内快捷键
final class KeyboardShortcutManager {
    private let logger = Logger(subsystem: "com.quitenote.app.dev", category: "KeyboardShortcutManager")
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pasteMonitor: Any?

    // ⚠️ 防抖相关：防止快捷键重复触发
    private var lastScreenshotTriggerTime: Date?
    private let screenshotDebounceInterval: TimeInterval = 0.3  // 300ms防抖间隔

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

    /// ⚠️ 防抖触发截图回调
    /// 防止全局监听和应用内监听同时触发导致的重复调用
    private func triggerScreenshot() {
        let now = Date()

        // 检查是否在防抖间隔内
        if let lastTime = lastScreenshotTriggerTime,
           now.timeIntervalSince(lastTime) < screenshotDebounceInterval {
            logger.info("截图快捷键触发被防抖逻辑拦截（距离上次触发仅 \(now.timeIntervalSince(lastTime))s）")
            return
        }

        // 更新最后触发时间
        lastScreenshotTriggerTime = now
        logger.info("截图快捷键触发成功")

        // 调用回调
        onScreenshot?()
    }

    /// 启动键盘快捷键监听
    func start() {
        logger.info("启动键盘快捷键监听")
        
        // 检查辅助功能权限
        checkAccessibilityPermissions()
        
        // 缓存当前的快捷键配置并注册全局热键
        updateCachedShortcuts()
        
        // 全局粘贴事件监听（当应用没有焦点时）
        // ⚠️ 粘贴仍然使用监视器，因为我们不需要拦截它，只是感知
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
        
        // ⚠️ 移除旧的全局监视器，因为它对截图快捷键不够可靠
        // globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
        //     guard let self = self else { return }
        //     _ = self.handleKeyEvent(e, isGlobal: true)
        // }
        
        // 应用内快捷键监听（应用在前台时有效）
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self = self else { return e }
            if self.handleKeyEvent(e, isGlobal: false) {
                return nil // 消费事件
            }
            return e // 不消费事件，继续传递
        }
    }

    /// 检查并提示辅助功能权限
    private func checkAccessibilityPermissions() {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !accessEnabled {
            logger.warning("未授予辅助功能权限，全局快捷键可能无法生效。")
        } else {
            logger.info("已确认辅助功能权限。")
        }
    }

    /// 更新快捷键缓存
    func refresh() {
        updateCachedShortcuts()
    }

    private var cachedShortcut: String = ""
    private var cachedFlags: NSEvent.ModifierFlags = []

    private func updateCachedShortcuts() {
        cachedShortcut = PreferencesManager.shared.screenshotShortcut.lowercased()
        let rawFlags = UInt(PreferencesManager.shared.screenshotShortcutFlags)
        cachedFlags = NSEvent.ModifierFlags(rawValue: rawFlags).intersection([.command, .option, .shift, .control])
        
        logger.info("已更新快捷键缓存: \(self.cachedShortcut), flags: \(self.cachedFlags.rawValue)")
        
        // 注册全局热键 (Carbon API)
        if !cachedShortcut.isEmpty {
            GlobalHotkeyManager.shared.register(
                key: cachedShortcut,
                modifiers: cachedFlags,
                id: 1001
            ) { [weak self] in
                self?.logger.info("Carbon 全局热键触发: 截图")
                self?.triggerScreenshot()
            }
        } else {
            GlobalHotkeyManager.shared.unregister(id: 1001)
        }
        
        // 注册其他全局功能热键
        registerOtherGlobalHotkeys()
    }
    
    private func registerOtherGlobalHotkeys() {
        let manager = GlobalHotkeyManager.shared
        let cmdOpt: NSEvent.ModifierFlags = [.command, .option]
        let cmdOptShift: NSEvent.ModifierFlags = [.command, .option, .shift]
        
        // ⌥⌘ R: Toggle Panel
        manager.register(key: "r", modifiers: cmdOpt, id: 2001) { [weak self] in self?.onTogglePanel?() }
        // ⌥⌘ A: Toggle AI
        manager.register(key: "a", modifiers: cmdOpt, id: 2002) { [weak self] in self?.onToggleAI?() }
        // ⌥⌘ C: Capture Clipboard
        manager.register(key: "c", modifiers: cmdOpt, id: 2003) { [weak self] in self?.onCaptureClipboard?() }
        // ⌥⌘ E: Export
        manager.register(key: "e", modifiers: cmdOpt, id: 2004) { [weak self] in self?.onExport?() }
        // ⌥⌘ D: Force Center
        manager.register(key: "d", modifiers: cmdOpt, id: 2005) { [weak self] in self?.onForceCenter?() }
        
        // ⌥⌘⇧ R: Force Center (Backup)
        manager.register(key: "r", modifiers: cmdOptShift, id: 3001) { [weak self] in self?.onForceCenter?() }
        // ⌥⌘⇧ A: Bulk Summarize
        manager.register(key: "a", modifiers: cmdOptShift, id: 3002) { [weak self] in self?.onBulkSummarize?() }
    }

    /// 统一处理按键事件
    /// - Returns: 是否消费了该事件
    private func handleKeyEvent(_ e: NSEvent, isGlobal: Bool) -> Bool {
        // 获取修饰键，排除掉不相关的 flag
        let flags = e.modifierFlags.intersection([.command, .option, .shift, .control])
        
        // 获取按键字符
        let char = e.charactersIgnoringModifiers?.lowercased() ?? ""
        
        if char.isEmpty { return false }

        // 1. 检查截图快捷键
        if flags == cachedFlags && char == cachedShortcut {
            triggerScreenshot()
            return true
        }

        // 2. ⌥⌘ 快捷键组合
        if flags.contains(.command) && flags.contains(.option) {
            switch char {
            case "r": self.onTogglePanel?(); return true
            case "a": self.onToggleAI?(); return true
            case "c": self.onCaptureClipboard?(); return true
            case "e": self.onExport?(); return true
            case "d": self.onForceCenter?(); return true
            default: break
            }
        }
        
        // 3. ⌥⌘⇧ 快捷键组合
        if flags.contains(.command) && flags.contains(.option) && flags.contains(.shift) {
            switch char {
            case "r": self.onForceCenter?(); return true
            case "a": self.onBulkSummarize?(); return true
            default: break
            }
        }

        // 4. 仅限应用内处理的快捷键
        if !isGlobal {
            // Cmd+V 粘贴快捷键（应用内无输入框聚焦时）
            if flags == .command && char == "v" {
                if let focusedView = NSApp.keyWindow?.firstResponder,
                   focusedView is NSTextView || focusedView is NSTextField {
                    return false
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.onGlobalPaste?()
                    }
                    return true
                }
            }
            
            // Cmd+, 打开设置
            if flags == .command && char == "," {
                self.onOpenSettings?()
                return true
            }
            
            // Cmd+Q 退出应用
            if flags == .command && char == "q" {
                self.onQuit?()
                return true
            }
        }

        return false
    }

    /// 停止快捷键监听
    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        if let m = pasteMonitor { NSEvent.removeMonitor(m) }
        
        // 注销所有全局热键
        GlobalHotkeyManager.shared.unregister(id: 1001)
        GlobalHotkeyManager.shared.unregister(id: 2001)
        GlobalHotkeyManager.shared.unregister(id: 2002)
        GlobalHotkeyManager.shared.unregister(id: 2003)
        GlobalHotkeyManager.shared.unregister(id: 2004)
        GlobalHotkeyManager.shared.unregister(id: 2005)
        GlobalHotkeyManager.shared.unregister(id: 3001)
        GlobalHotkeyManager.shared.unregister(id: 3002)
    }
    
    deinit { 
        stop()
    }
}

