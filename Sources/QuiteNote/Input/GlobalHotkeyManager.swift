import AppKit
import Carbon

/// 全局热键管理器（使用 Carbon API 实现真正的全局拦截）
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()
    
    private var hotkeys: [UInt32: HotkeyInfo] = [:]
    private var eventHandler: EventHandlerRef?
    
    struct HotkeyInfo {
        let id: UInt32
        let key: String
        let modifiers: NSEvent.ModifierFlags
        let handler: () -> Void
        let carbonHotkey: EventHotKeyRef
    }
    
    private init() {
        setupEventHandler()
    }
    
    private func setupEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        let status = InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, event, userData) -> OSStatus in
            guard let event = event, let userData = userData else { return OSStatus(eventNotHandledErr) }
            
            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            
            var hotkeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                         EventParamName(kEventParamDirectObject),
                                         EventParamType(typeEventHotKeyID),
                                         nil,
                                         MemoryLayout<EventHotKeyID>.size,
                                         nil,
                                         &hotkeyID)
            
            if status == noErr {
                if let info = manager.hotkeys[hotkeyID.id] {
                    DispatchQueue.main.async {
                        manager.dispatchHotkey(info)
                    }
                    return OSStatus(noErr)
                }
            }
            
            return CallNextEventHandler(nextHandler, event)
        }, 1, &eventType, ptr, &eventHandler)
        
        if status != noErr {
            print("[DEBUG] Failed to install Carbon event handler: \(status)")
        }
    }
    
    /// 注册全局热键
    /// - Parameters:
    ///   - key: 按键字符 (如 "a", "s")
    ///   - modifiers: 修饰键 (NSEvent.ModifierFlags)
    ///   - id: 唯一标识符
    ///   - handler: 触发时的回调
    /// - Returns: 是否注册成功（false = 按键非法或与其他应用/系统热键冲突）
    @discardableResult
    func register(key: String, modifiers: NSEvent.ModifierFlags, id: UInt32, handler: @escaping () -> Void) -> Bool {
        // 先注销旧的
        unregister(id: id)

        guard let keyCode = keyCode(for: key) else {
            print("[DEBUG] Invalid key for hotkey: \(key)")
            return false
        }

        let carbonModifiers = self.carbonModifiers(from: modifiers)
        let hotkeyID = EventHotKeyID(signature: OSType(0x514E5445), id: id) // "QNTE"

        var carbonHotkey: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode),
                                        UInt32(carbonModifiers),
                                        hotkeyID,
                                        GetApplicationEventTarget(),
                                        0,
                                        &carbonHotkey)

        if status == noErr, let ref = carbonHotkey {
            hotkeys[id] = HotkeyInfo(id: id, key: key, modifiers: modifiers,
                                     handler: handler, carbonHotkey: ref)
            print("[DEBUG] Successfully registered global hotkey: \(key) (keyCode: \(keyCode)) with modifiers: \(modifiers), id: \(id)")
            return true
        } else {
            print("[DEBUG] FAILED to register global hotkey: \(key), status: \(status), id: \(id)")
            DiagnosticCenter.warning("Shortcut", "热键注册失败：key=[\(key)] id=\(id) status=\(status)\(status == -9868 ? "（被系统/其他应用占用）" : "")")
            return false
        }
    }
    
    func unregister(id: UInt32) {
        if let info = hotkeys.removeValue(forKey: id) {
            UnregisterEventHotKey(info.carbonHotkey)
            print("[DEBUG] Unregistered global hotkey ID: \(id)")
        }
    }

    // MARK: - 录制快捷键期间的热键路由（ShortcutRecorderView 用）
    //
    // 方案演进：曾用「录制期间注销全部热键」——但 ⌥空格 这类组合键在注销后轮到
    // 搜狗输入法消费（Carbon 注册期间则在 IME 之前被我们持有），录制器永远收不到
    // （实测 ⌥K 能录、⌥空格 不能）。现行方案：录制期间热键保持注册，触发时不再执行
    // 原动作，而是把 (key, modifiers) 路由给录制器——Carbon 在 IME 之前拦截，
    // 重录 ⌥空格 / ⇧⌘V 都成立；非热键组合（如 ⌥K）仍走 NSEvent localMonitor 常规路径。

    /// 非 nil = 录制态：已注册热键触发时路由给录制器而非执行原动作（主线程调用）
    var recorderCaptureHandler: ((String, NSEvent.ModifierFlags) -> Void)?

    /// 空格探针热键 id（录制期间临时注册，见 beginRecordingCapture）
    private var probeIDs: [UInt32] = []

    /// 进入录制捕获态：① 已注册热键触发时路由给录制器；② 额外注册「空格×全部
    /// 修饰键组合」探针热键——空格类组合键在**未注册**状态下会被输入法（⌥空格→搜狗）
    /// 或系统（⌃空格→输入源切换）在 app 之前消费，探针保证录制器始终能采到空格键。
    /// 被系统/其他应用占用的组合注册失败（-9868）静默跳过。结束须调 endRecordingCapture。
    func beginRecordingCapture(handler: @escaping (String, NSEvent.ModifierFlags) -> Void) {
        recorderCaptureHandler = handler
        guard probeIDs.isEmpty else { return }
        let singles: [NSEvent.ModifierFlags] = [.command, .shift, .control, .option]
        var id: UInt32 = 9000
        for mask in 1..<16 {
            var flags: NSEvent.ModifierFlags = []
            for (bit, single) in singles.enumerated() where mask & (1 << bit) != 0 {
                flags.insert(single)
            }
            if register(key: " ", modifiers: flags, id: id, handler: {}) {
                probeIDs.append(id)
            }
            id += 1
        }
        print("[DEBUG] 录制快捷键：空格探针已注册 \(probeIDs.count)/15")
    }

    /// 结束录制捕获态：清路由 + 注销探针
    func endRecordingCapture() {
        recorderCaptureHandler = nil
        probeIDs.forEach { unregister(id: $0) }
        probeIDs.removeAll()
    }

    /// 是否处于录制捕获态（供 refresh 守卫与单测）
    var isRecordingCaptureActive: Bool {
        recorderCaptureHandler != nil || !probeIDs.isEmpty
    }

    /// 单测辅助：当前探针数量
    var probeCountForTest: Int { probeIDs.count }

    /// 单测辅助：注册总数
    var registeredCount: Int { hotkeys.count }

    /// Carbon 事件入口的分发逻辑（供单测直接调用验证路由）
    func dispatchHotkey(_ info: HotkeyInfo) {
        if let capture = recorderCaptureHandler {
            capture(info.key, info.modifiers)
        } else {
            info.handler()
        }
    }

    /// 单测辅助：按 id 取注册信息
    func hotkeyInfo(forTestID id: UInt32) -> HotkeyInfo? {
        hotkeys[id]
    }
    
    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var carbonFlags = 0
        if flags.contains(.command) { carbonFlags |= cmdKey }
        if flags.contains(.option) { carbonFlags |= optionKey }
        if flags.contains(.control) { carbonFlags |= controlKey }
        if flags.contains(.shift) { carbonFlags |= shiftKey }
        return carbonFlags
    }
    
    private func keyCode(for key: String) -> CGKeyCode? {
        let char = key.lowercased()
        
        // 简单映射常见按键，更完善的方案可以使用 TISGetInputSourceProperty
        let keyMap: [String: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
            "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
            "9": 25, "7": 26, "8": 28, "0": 29,
            "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
            "n": 45, "m": 46, ".": 47, " ": 49,
            // 防御：按住 ⌥ 时部分键盘布局把空格报告为不换行空格（U+00A0），
            // 启动器默认 ⌥空格，键码表兜住这种存法
            "\u{00A0}": 49,
            // 面板打开期间的 ESC Carbon 拦截（搜狗在中文模式下吞裸 ESC，见面板控制器）
            "esc": 53
        ]
        
        return keyMap[char]
    }
}
