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

    // RecordStore 引用，用于撤销/重做功能
    weak var recordStore: RecordStore?

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
    var onStopRecording: (() -> Void)?
    var onOpenClipboardHistory: (() -> Void)?
    var onOpenAppLauncher: (() -> Void)?

    /// 剪贴板历史快捷键注册失败（与系统/其他应用冲突），设置页据此提示（PRD 6）
    static var clipboardShortcutConflict = false
    /// 应用启动器快捷键注册失败（默认 ⌥空格，常与 Alfred/Raycast 冲突），设置页据此提示
    static var launcherShortcutConflict = false
    private var cachedClipboardShortcut: String = ""
    private var cachedClipboardFlags: NSEvent.ModifierFlags = []

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
        
        // 缓存当前的快捷键配置并注册全局热键
        updateCachedShortcuts()
        Self.clipboardShortcutConflict = !registerClipboardHotkey()
        Self.launcherShortcutConflict = !registerLauncherHotkey()
        
        // 全局粘贴事件监听（当应用没有焦点时）
        // ⚠️ 粘贴仍然使用监视器，因为我们不需要拦截它，只是感知
        // App Store 沙盒版剔除：全局 keyDown 监控需要 Input Monitoring 授权，
        // 沙盒内静默失效且 App Review 会质询（沙盒审计 2026-09-15）
        #if !APP_STORE
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
        #endif
        
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

    /// 更新快捷键缓存
    func refresh() {
        // 录制快捷键期间跳过：refresh 会注销+重注册热键，录制期间的按键可能落进
        // 这个空窗（2s 冲突轮询曾踩雷）。捕获路径的 setter 随后触发正常 refresh
        guard !GlobalHotkeyManager.shared.isRecordingCaptureActive else {
            logger.info("录制快捷键进行中，跳过 refresh")
            return
        }
        updateCachedShortcuts()
        Self.clipboardShortcutConflict = !registerClipboardHotkey()
        Self.launcherShortcutConflict = !registerLauncherHotkey()
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

    /// 剪贴板历史面板热键（PRD 6：默认 ⇧⌘V，可配置；冲突时记录并暴露给设置页）
    private func registerClipboardHotkey() -> Bool {
        let key = PreferencesManager.shared.clipboardOpenShortcut.lowercased()
        let flags = NSEvent.ModifierFlags(rawValue: UInt(PreferencesManager.shared.clipboardOpenShortcutFlags))
            .intersection([.command, .option, .shift, .control])
        cachedClipboardShortcut = key
        cachedClipboardFlags = flags

        guard !key.isEmpty else {
            GlobalHotkeyManager.shared.unregister(id: 2007)
            return true
        }
        return GlobalHotkeyManager.shared.register(key: key, modifiers: flags, id: 2007) { [weak self] in
            self?.onOpenClipboardHistory?()
        }
    }

    /// 应用启动器热键（默认 ⌥空格，可配置；空字符串 = 禁用）
    /// 失败自动重试一次：录制探针注销后立即重注册同一组合，窗口服务器热键表
    /// 可能短暂未同步（实测捕获 ⌥空格 后紧接的注册失败、热键失活）
    private func registerLauncherHotkey(retry: Bool = true) -> Bool {
        let key = PreferencesManager.shared.launcherOpenShortcut.lowercased()
        let flags = NSEvent.ModifierFlags(rawValue: UInt(PreferencesManager.shared.launcherOpenShortcutFlags))
            .intersection([.command, .option, .shift, .control])

        guard !key.isEmpty else {
            GlobalHotkeyManager.shared.unregister(id: 4001)
            return true
        }
        let ok = GlobalHotkeyManager.shared.register(key: key, modifiers: flags, id: 4001) { [weak self] in
            self?.onOpenAppLauncher?()
        }
        if !ok && retry {
            logger.info("启动器热键注册失败，1.5s 后重试")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                if self?.registerLauncherHotkey(retry: false) == true {
                    Self.launcherShortcutConflict = false
                }
            }
        }
        return ok
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
        // ⌥⌘ .: Stop active screen recording
        manager.register(key: ".", modifiers: cmdOpt, id: 2006) { [weak self] in self?.onStopRecording?() }
        
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
            case ".": self.onStopRecording?(); return true
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
                let responder = NSApp.keyWindow?.firstResponder
                // 反馈表单可见时：焦点在文本框 → 放行贴文字；否则 → 直接通知表单粘贴截图附件。
                // （不能只 return false：主菜单"编辑→粘贴"(disabled) 会在 keyEquivalent 阶段吞掉 ⌘V，
                //  SwiftUI onCommand 收不到，所以必须用通知直连）
                if FeedbackSettingsTab.isFeedbackFormVisible {
                    if responder is NSTextView || responder is NSTextField {
                        return false
                    }
                    NotificationCenter.default.post(name: .feedbackPasteShortcut, object: nil)
                    return true
                }
                DiagnosticCenter.info("Shortcut", "⌘V 事件到达（反馈表单可见: false，焦点: \( responder.map { String(describing: type(of: $0)) } ?? "nil" )）")
                if let focusedView = responder,
                   focusedView is NSTextView || focusedView is NSTextField {
                    return false
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.onGlobalPaste?()
                    }
                    return true
                }
            }

            // P4.1: Cmd+Z 撤销
            if flags == .command && char == "z" {
                // 检查是否有文本编辑器聚焦
                if let focusedView = NSApp.keyWindow?.firstResponder,
                   let textView = focusedView as? NSTextView, textView.isEditable {
                    return false // 让文本编辑器处理撤销
                }
                // 应用级别撤销
                if let store = self.recordStore, HistoryManager.shared.canUndo {
                    HistoryManager.shared.undo(recordStore: store)
                    store.postToast("已撤销", type: "info")
                    return true
                }
            }

            // P4.1: Cmd+Shift+Z 重做
            if flags == [.command, .shift] && char == "z" {
                // 检查是否有文本编辑器聚焦
                if let focusedView = NSApp.keyWindow?.firstResponder,
                   let textView = focusedView as? NSTextView, textView.isEditable {
                    return false // 让文本编辑器处理重做
                }
                // 应用级别重做
                if let store = self.recordStore, HistoryManager.shared.canRedo {
                    HistoryManager.shared.redo(recordStore: store)
                    store.postToast("已重做", type: "info")
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
        GlobalHotkeyManager.shared.unregister(id: 2006)
        GlobalHotkeyManager.shared.unregister(id: 3001)
        GlobalHotkeyManager.shared.unregister(id: 3002)
        GlobalHotkeyManager.shared.unregister(id: 2007)
        GlobalHotkeyManager.shared.unregister(id: 4001)
    }
    
    deinit { 
        stop()
    }
}
