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
    /// 便利贴：新建便利贴（默认 ⌥⇧⌘N，可配置；MainApp 接到 StickyNoteManager.shared.createNewNote）
    var onNewStickyNote: (() -> Void)?
    /// 便利贴：切换「固定到所有 Space」（默认 ⌥⌘P，可配置；作用于当前聚焦的便利贴）
    var onToggleStickySpacePin: (() -> Void)?

    /// 剪贴板历史快捷键注册失败（与系统/其他应用冲突），设置页据此提示（PRD 6）
    static var clipboardShortcutConflict = false
    /// 应用启动器快捷键注册失败（默认 ⌥空格，常与 Alfred/Raycast 冲突），设置页据此提示
    static var launcherShortcutConflict = false
    /// 便利贴「新建」快捷键注册失败（与系统/其他应用冲突），设置页「便利贴」据此提示
    static var stickyNoteShortcutConflict = false
    /// 便利贴「固定到所有 Space」快捷键注册失败，设置页「便利贴」据此提示
    static var stickySpacePinShortcutConflict = false
    private var cachedClipboardShortcut: String = ""
    private var cachedClipboardFlags: NSEvent.ModifierFlags = []

    // MARK: - 便利贴热键的注册执行者（可注入）
    //
    // 便利贴两个热键原先由 StickyNoteManager.setupShortcuts() 硬编码注册（⌘⇧N / ⌥⌘P），
    // 不归这里管——设置里看不到、不能改、不能关，⌘⇧N 还抢走 Finder 的「新建文件夹」。
    // 现在与剪贴板、启动器一样收归这里：偏好可配、空键 = 禁用、注册失败有冲突标志供设置页提示。
    // Carbon 热键是全系统独占——测试进程里真实注册可能与正在运行的正式版撞车，
    // 所以「偏好 → 注册参数」是纯函数，「执行注册/注销/重试」走下面三个可注入闭包，单测不依赖真实注册成功。

    /// 便利贴热键的 Carbon id（沿用 StickyNoteManager 旧实现的 5001 / 5002）
    static let stickyNoteHotkeyID: UInt32 = 5001
    static let stickySpacePinHotkeyID: UInt32 = 5002

    typealias HotkeyRegister = (_ key: String, _ modifiers: NSEvent.ModifierFlags, _ id: UInt32, _ handler: @escaping () -> Void) -> Bool
    /// 真正执行 Carbon 注册（默认 GlobalHotkeyManager；单测注入假实现）
    var hotkeyRegister: HotkeyRegister = { key, modifiers, id, handler in
        GlobalHotkeyManager.shared.register(key: key, modifiers: modifiers, id: id, handler: handler)
    }
    /// 真正执行注销（同上）
    var hotkeyUnregister: (UInt32) -> Void = { GlobalHotkeyManager.shared.unregister(id: $0) }
    /// 注册失败后的延迟重试调度（默认 1.5s；单测注入为捕获块，按需手动触发）
    var scheduleHotkeyRetry: (@escaping () -> Void) -> Void = { block in
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: block)
    }
    /// 本实例登记过的便利贴热键 id（registerStickyHotkeys 时记下）。stop() 只注销这些：
    /// GlobalHotkeyManager 是进程级单例，一个从没登记过便利贴热键的临时实例（如单测里
    /// new 出来只为验证 refresh 守卫的）析构时，不得把别的 owner 注册的同 id 热键顺手清掉
    private var registeredStickyHotkeyIDs: Set<UInt32> = []

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
        registerStickyHotkeys()
        
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
        registerStickyHotkeys()
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

    // MARK: - 便利贴热键（新建便利贴 / 切换固定到所有 Space）

    /// 偏好 → 注册参数（纯函数）：key 统一小写（存量值可能是大写），flags 只保留 ⌘⌥⇧⌃
    ///（录制器写入的是 deviceIndependent 全量位，可能夹带 fn、小键盘等无关位）。
    /// flags 经 clamping 转 UInt：负数（只有外部手改 defaults 才会出现）不会让 UInt() 陷阱，
    /// 而是归零成「无修饰键」——随后被 isSafeToRegister 拒绝注册
    static func hotkeyRegistration(key: String, flags: Int) -> HotkeyRegistration {
        let modifierMask: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        return HotkeyRegistration(
            key: key.lowercased(),
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(clamping: flags)).intersection(modifierMask)
        )
    }

    /// 把一条注册参数应用到系统（注册的执行部分，register / unregister 可注入）。
    /// - 空键 = 禁用：注销旧注册并返回 true（禁用不是失败）
    /// - 非空键但不带修饰键 = 拒绝注册并返回 false（见 HotkeyRegistration.isSafeToRegister）
    /// - 其余按参数注册，返回是否注册成功
    @discardableResult
    static func applyHotkey(_ registration: HotkeyRegistration,
                            id: UInt32,
                            action: @escaping () -> Void,
                            register: HotkeyRegister,
                            unregister: (UInt32) -> Void) -> Bool {
        guard registration.isEnabled else {
            unregister(id)
            return true
        }
        guard registration.isSafeToRegister else {
            unregister(id)
            DiagnosticCenter.warning("Shortcut", "热键配置不安全，拒绝注册：key=[\(registration.key)] id=\(id)（非空键必须带修饰键）")
            return false
        }
        return register(registration.key, registration.modifiers, id, action)
    }

    /// 便利贴两个热键：按当前偏好注册并刷新冲突标志。start / refresh 都走这里；
    /// 单测注入 hotkeyRegister 等闭包后可直接调用（不触碰事件监听器与其他热键）。
    ///
    /// 注册失败会 1.5s 后重试一次（同启动器：录制探针注销后窗口服务器热键表可能短暂未同步，
    /// 实测 status=-9878 瞬态失败）；重试时重新读偏好，期间用户改键/禁用都以最新值为准。
    /// 配置本身不安全（裸键）不重试——重试也不会成功
    func registerStickyHotkeys() {
        Self.stickyNoteShortcutConflict = !registerStickyNoteHotkey()
        Self.stickySpacePinShortcutConflict = !registerStickySpacePinHotkey()
    }

    /// 新建便利贴热键（默认 ⌥⇧⌘N，可配置；空字符串 = 禁用）
    private func registerStickyNoteHotkey(retry: Bool = true) -> Bool {
        let registration = Self.hotkeyRegistration(key: PreferencesManager.shared.stickyNoteShortcut,
                                                   flags: PreferencesManager.shared.stickyNoteShortcutFlags)
        registeredStickyHotkeyIDs.insert(Self.stickyNoteHotkeyID)
        let ok = Self.applyHotkey(registration,
                                  id: Self.stickyNoteHotkeyID,
                                  action: { [weak self] in self?.onNewStickyNote?() },
                                  register: hotkeyRegister,
                                  unregister: hotkeyUnregister)
        if !ok && retry && registration.isSafeToRegister {
            logger.info("便利贴「新建」热键注册失败，1.5s 后重试")
            scheduleHotkeyRetry { [weak self] in
                if self?.registerStickyNoteHotkey(retry: false) == true {
                    Self.stickyNoteShortcutConflict = false
                }
            }
        }
        return ok
    }

    /// 切换「固定到所有 Space」热键（默认 ⌥⌘P，可配置；空字符串 = 禁用）
    private func registerStickySpacePinHotkey(retry: Bool = true) -> Bool {
        let registration = Self.hotkeyRegistration(key: PreferencesManager.shared.stickySpacePinShortcut,
                                                   flags: PreferencesManager.shared.stickySpacePinShortcutFlags)
        registeredStickyHotkeyIDs.insert(Self.stickySpacePinHotkeyID)
        let ok = Self.applyHotkey(registration,
                                  id: Self.stickySpacePinHotkeyID,
                                  action: { [weak self] in self?.onToggleStickySpacePin?() },
                                  register: hotkeyRegister,
                                  unregister: hotkeyUnregister)
        if !ok && retry && registration.isSafeToRegister {
            logger.info("便利贴「固定到所有 Space」热键注册失败，1.5s 后重试")
            scheduleHotkeyRetry { [weak self] in
                if self?.registerStickySpacePinHotkey(retry: false) == true {
                    Self.stickySpacePinShortcutConflict = false
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
        // 便利贴两个热键：只注销本实例登记过的（见 registeredStickyHotkeyIDs），
        // 且与注册同走可注入的注销闭包（单测注入假实现时 stop 也不碰真实 Carbon）
        for id in registeredStickyHotkeyIDs {
            hotkeyUnregister(id)
        }
        registeredStickyHotkeyIDs.removeAll()
    }
    
    deinit { 
        stop()
    }
}

/// 一条可配置全局热键的注册参数（偏好 → 参数的映射见
/// KeyboardShortcutManager.hotkeyRegistration(key:flags:)，纯函数、便于单测）
struct HotkeyRegistration: Equatable {
    /// 归一化后的按键字符（小写）；空串 = 禁用
    let key: String
    /// 只保留 ⌘⌥⇧⌃ 四个修饰键
    let modifiers: NSEvent.ModifierFlags

    /// 是否启用（空键 = 禁用）
    var isEnabled: Bool { !key.isEmpty }

    /// 是否可以安全注册。非空键必须带至少一个修饰键：裸字母 / 空格 / 回车做成 Carbon 全局热键，
    /// 会把系统里每一次该按键都截走（任何 App 里都打不出这个字）。录制器本就要求带修饰键
    ///（或功能键，而功能键不在 GlobalHotkeyManager 的键码表里、注册必失败），这里兜底的是
    /// 被写坏的偏好（外部手改 defaults 等）——偏好 flags 被破坏时宁可提示冲突也不注册
    var isSafeToRegister: Bool { isEnabled && !modifiers.isEmpty }

    /// 展示串，修饰键按系统惯例排序（⌃⌥⇧⌘，与状态栏菜单渲染一致）：⌃⌘N、⌥⌘P、⌥空格。
    /// 禁用时返回空串
    func displayString(spaceLabel: String = "空格") -> String {
        guard isEnabled else { return "" }
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + (key == " " ? spaceLabel : key.uppercased())
    }
}
