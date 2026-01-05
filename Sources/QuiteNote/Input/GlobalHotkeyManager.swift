import AppKit
import Carbon

/// 全局热键管理器（使用 Carbon API 实现真正的全局拦截）
final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()
    
    private var hotkeys: [UInt32: HotkeyInfo] = [:]
    private var eventHandler: EventHandlerRef?
    
    struct HotkeyInfo {
        let id: UInt32
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
                        info.handler()
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
    func register(key: String, modifiers: NSEvent.ModifierFlags, id: UInt32, handler: @escaping () -> Void) {
        // 先注销旧的
        unregister(id: id)
        
        guard let keyCode = keyCode(for: key) else {
            print("[DEBUG] Invalid key for hotkey: \(key)")
            return
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
            hotkeys[id] = HotkeyInfo(id: id, handler: handler, carbonHotkey: ref)
            print("[DEBUG] Successfully registered global hotkey: \(key) (keyCode: \(keyCode)) with modifiers: \(modifiers), id: \(id)")
        } else {
            print("[DEBUG] FAILED to register global hotkey: \(key), status: \(status), id: \(id)")
            if status == -9868 { // eventHotKeyExistsErr
                print("[DEBUG] Error: Hotkey already exists or is reserved by system/another app")
            }
        }
    }
    
    func unregister(id: UInt32) {
        if let info = hotkeys.removeValue(forKey: id) {
            UnregisterEventHotKey(info.carbonHotkey)
            print("[DEBUG] Unregistered global hotkey ID: \(id)")
        }
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
            "n": 45, "m": 46, ".": 47, " ": 49
        ]
        
        return keyMap[char]
    }
}
