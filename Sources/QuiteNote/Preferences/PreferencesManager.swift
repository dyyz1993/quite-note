import Foundation
import AppKit
import Combine
import ServiceManagement

struct LastRecordingSelection {
    let normalizedRect: CGRect
    let displayID: CGDirectDisplayID
}

final class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()
    private let d = UserDefaults.standard
    
    private init() {
        migratePromptsIfNeeded()
    }

    private func migratePromptsIfNeeded() {
        let oldSysDefault1 = "你是一个专业的问题分析助手。请仔细分析以下文本，提炼出其中的核心问题或关键点。严格输出以下 JSON 字段，不要包含多余文本：{\"title\":不超过{titleLimit}字的问题标题,\"summary\":不超过{summaryLimit}字的问题总结,\"confidence\":0-1 之间置信度，仅数字}"
        let oldSysDefault2 = """
        你是一个专业的内容分析助手，擅长对各种文本内容（包括但不限于 URL、API Key、密钥、代码片段、技术文档、日常随笔等）进行分类和总结。
        
        请按照以下格式返回 JSON 结果：
        1. **title**: 概括内容的核心，不超过 {titleLimit} 字。如果是 API Key 或密钥，标题应指明其用途或来源（如 "OpenAI API Key"）。
        2. **summary**: 提炼核心要点，不超过 {summaryLimit} 字。如果是代码，说明其功能；如果是密钥，提醒安全存储。
        3. **tags**: 识别内容的分类。
        4. **keywords**: 提取 3-10 个精细化的搜索关键词。
           - 必须以 # 开头（如 #APIKey, #SwiftUI, #Deployment）。
           - 关键词应包含具体的技术栈、工具名或业务场景。
           - 总数不得超过 10 个。
        5. **confidence**: 0-1 之间的分析置信度。

        严格输出 JSON 格式，字段如下：{"title": string, "summary": string, "confidence": number, "tags": [string], "keywords": [string]}
        """
        
        let _ = "请分析以下文本，提炼出其中的内容核心：\n\n{content}\n\n只返回 JSON，确保分析精准且聚焦。"
        
        let currentSys = d.string(forKey: "aiSystemPrompt")
        if currentSys == oldSysDefault1 || currentSys == oldSysDefault2 {
            d.removeObject(forKey: "aiSystemPrompt")
        }
        
        if d.string(forKey: "aiUserPrompt") == "请分析以下文本，提炼出其中的问题或关键点：\n\n{content}\n\n只返回 JSON，确保标题和总结都聚焦于问题本身。" {
            d.removeObject(forKey: "aiUserPrompt")
        }
    }

    // 新安装默认关闭，避免用户未明确同意时自动把剪贴板内容发送给第三方 AI。
    var enableAI: Bool { d.object(forKey: "enableAI") == nil ? false : d.bool(forKey: "enableAI") }
    var titleLimit: Int { max(15, d.integer(forKey: "titleLimit")) }
    var summaryTrigger: Int { max(0, d.integer(forKey: "summaryTrigger")) }
    var summaryLimit: Int { max(50, d.integer(forKey: "summaryLimit")) }
    var dedupEnabled: Bool { d.object(forKey: "dedupEnabled") == nil ? true : d.bool(forKey: "dedupEnabled") }
    var maxScreenshots: Int { let v = d.integer(forKey: "maxScreenshots"); return v == 0 ? 200 : v }
    var debounceSeconds: Int { let v = d.integer(forKey: "debounceSeconds"); return v == 0 ? 1 : v }
    var windowLock: Bool { d.object(forKey: "windowLock") == nil ? false : d.bool(forKey: "windowLock") }
    var animationsEnabled: Bool { d.object(forKey: "animationsEnabled") == nil ? true : d.bool(forKey: "animationsEnabled") }
    var rememberWindowPosition: Bool { d.object(forKey: "rememberWindowPosition") == nil ? true : d.bool(forKey: "rememberWindowPosition") }
    var attachmentsPath: String? { d.string(forKey: "attachmentsPath") }
    var preferredEditor: String { d.string(forKey: "preferredEditor") ?? "System Default" }

    // 截图设置
    var screenshotShortcut: String { d.string(forKey: "screenshotShortcut") ?? "s" }
    var screenshotShortcutFlags: Int { d.object(forKey: "screenshotShortcutFlags") == nil ? Int(NSEvent.ModifierFlags([.command, .shift]).rawValue) : d.integer(forKey: "screenshotShortcutFlags") }
    var screenshotSaveToClipboard: Bool { d.object(forKey: "screenshotSaveToClipboard") == nil ? true : d.bool(forKey: "screenshotSaveToClipboard") }

    var openAIBaseURL: String { d.string(forKey: "openAIBaseURL") ?? "https://api.openai.com/v1" }
    var openAIModel: String { d.string(forKey: "openAIModel") ?? "gpt-4o-mini" }
    
    // AI 提示词配置
    var aiSystemPrompt: String { 
        d.string(forKey: "aiSystemPrompt") ?? """
        你是一个专业的内容分析助手，擅长对各种文本内容（包括但不限于 URL、API Key、密钥、代码片段、技术文档、日常随笔等）进行多维度分类和总结。
        
        请按照以下格式返回 JSON 结果：
        1. **title**: 概括内容的核心，不超过 {titleLimit} 字。如果是 API Key 或密钥，标题应指明其用途或来源（如 "OpenAI API Key"）。
        2. **summary**: 提炼核心要点，不超过 {summaryLimit} 字。如果是代码，说明其功能；如果是密钥，提醒安全存储。
        3. **tags**: 识别内容的分类标签。请从以下维度进行考虑：
           - **内容属性**: 如 [代码, 文档, 密钥, 配置, 链接, 笔记]
           - **技术/工具**: 如 [Swift, Python, OpenAI, AWS, Git]
           - **业务/场景**: 如 [支付, 认证, 部署, 需求, 学习]
           识别规则：识别内容的分类，**严禁包含 # 符号**。
        4. **keywords**: 提取 3-10 个精细化的搜索关键词。
           - **必须以 # 开头**（如 #APIKey, #SwiftUI, #Deployment）。
           - 关键词应包含具体的技术栈、工具名或业务场景。
           - 总数不得超过 10 个。
        5. **confidence**: 0-1 之间的分析置信度。

        严格输出 JSON 格式，字段如下：{"title": string, "summary": string, "confidence": number, "tags": [string], "keywords": [string]}
        """ 
    }
    var aiUserPrompt: String { 
        d.string(forKey: "aiUserPrompt") ?? "请分析以下文本，提炼出其中的内容核心：\n\n{content}\n\n只返回 JSON，确保分析精准且聚焦。" 
    }

    func setEnableAI(_ v: Bool) { d.set(v, forKey: "enableAI") }
    func setTitleLimit(_ v: Int) { d.set(v, forKey: "titleLimit") }
    func setSummaryTrigger(_ v: Int) { d.set(v, forKey: "summaryTrigger") }
    func setSummaryLimit(_ v: Int) { d.set(v, forKey: "summaryLimit") }
    func setDedupEnabled(_ v: Bool) { d.set(v, forKey: "dedupEnabled") }
    func setMaxScreenshots(_ v: Int) { d.set(v, forKey: "maxScreenshots") }
    func setDebounceSeconds(_ v: Int) { d.set(v, forKey: "debounceSeconds") }
    func setWindowLock(_ v: Bool) { d.set(v, forKey: "windowLock") }
    func setAnimationsEnabled(_ v: Bool) { d.set(v, forKey: "animationsEnabled") }
    func setRememberWindowPosition(_ v: Bool) { d.set(v, forKey: "rememberWindowPosition") }

    // MARK: - 开机自启动（macOS 13+ SMAppService）
    // 状态以系统登录项注册表为准（不落 UserDefaults）：用户可能在「系统设置 → 通用 → 登录项」里手动增删，
    // 只存 UserDefaults 会与系统实际状态脱节。resetAll() 也不动它——系统级注册不属于应用内偏好。

    /// 登录项是否已注册
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    /// 系统要求用户到登录项列表里手动放行（注册被挂起）
    var loginItemNeedsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// 设置开机自启动；返回是否成功，失败时调用方应回读 `launchAtLogin` 回退 UI
    @discardableResult
    func setLaunchAtLogin(_ v: Bool) -> Bool {
        let service = SMAppService.mainApp
        guard v != (service.status == .enabled) else { return true }
        do {
            if v {
                try service.register()
            } else {
                try service.unregister()
            }
            DiagnosticCenter.info("App", v ? "开机自启动已开启" : "开机自启动已关闭")
            return true
        } catch {
            DiagnosticCenter.error("App", "开机自启动设置失败: \(error.localizedDescription)")
            return false
        }
    }
    func setAttachmentsPath(_ v: String?) { d.set(v, forKey: "attachmentsPath") }
    func setAttachmentsDirectory(_ url: URL?) {
        setAttachmentsPath(url?.path)
        if let url {
            _ = SecurityScopedBookmarkStore.shared.save(url, forKey: "attachmentsDirectoryBookmark")
        } else {
            SecurityScopedBookmarkStore.shared.remove(forKey: "attachmentsDirectoryBookmark")
        }
    }
    func setPreferredEditor(_ v: String) { d.set(v, forKey: "preferredEditor") }

    func setScreenshotShortcut(_ v: String) { 
        objectWillChange.send()
        d.set(v, forKey: "screenshotShortcut") 
    }
    func setScreenshotShortcutFlags(_ v: Int) { 
        objectWillChange.send()
        d.set(v, forKey: "screenshotShortcutFlags") 
    }
    func setScreenshotSaveToClipboard(_ v: Bool) { d.set(v, forKey: "screenshotSaveToClipboard") }

    // 截图文件保存目录（空字符串 = 使用下载目录）
    var screenshotSaveDirectory: String { d.string(forKey: "screenshotSaveDirectory") ?? "" }
    func setScreenshotSaveDirectory(_ v: String) {
        objectWillChange.send()
        d.set(v, forKey: "screenshotSaveDirectory")
        if v.isEmpty {
            SecurityScopedBookmarkStore.shared.remove(forKey: "screenshotSaveDirectoryBookmark")
        }
    }

    func setScreenshotSaveDirectory(_ url: URL?) {
        objectWillChange.send()
        d.set(url?.path ?? "", forKey: "screenshotSaveDirectory")
        if let url {
            _ = SecurityScopedBookmarkStore.shared.save(url, forKey: "screenshotSaveDirectoryBookmark")
        } else {
            SecurityScopedBookmarkStore.shared.remove(forKey: "screenshotSaveDirectoryBookmark")
        }
    }

    // 保存截图文件后自动复制绝对路径到剪贴板
    var screenshotCopyPathAfterSave: Bool { d.object(forKey: "screenshotCopyPathAfterSave") == nil ? true : d.bool(forKey: "screenshotCopyPathAfterSave") }

    // MARK: - 剪贴板历史（PRD：本地 Alfred 式剪贴板历史）

    /// 总开关（默认开，但首次引导未确认前不捕获——见 clipboardOnboarded）
    var clipboardHistoryEnabled: Bool { d.object(forKey: "clipboardHistoryEnabled") == nil ? true : d.bool(forKey: "clipboardHistoryEnabled") }
    /// 首次引导是否已确认（确认前监控不启动，PRD 4.1）
    var clipboardOnboarded: Bool { d.bool(forKey: "clipboardOnboarded") }
    /// 暂停截止时间（"暂停 1 小时/到明天"用；nil = 未暂停）
    var clipboardPausedUntil: Date? { d.object(forKey: "clipboardPausedUntil") as? Date }
    /// 是否处于暂停中
    var isClipboardPaused: Bool {
        if let until = clipboardPausedUntil { return Date() < until }
        return false
    }

    // 记录内容开关（PRD 8.2）
    var clipboardRecordText: Bool { d.object(forKey: "clipboardRecordText") == nil ? true : d.bool(forKey: "clipboardRecordText") }
    var clipboardRecordImage: Bool { d.object(forKey: "clipboardRecordImage") == nil ? true : d.bool(forKey: "clipboardRecordImage") }
    var clipboardRecordLink: Bool { d.object(forKey: "clipboardRecordLink") == nil ? true : d.bool(forKey: "clipboardRecordLink") }
    var clipboardRecordFile: Bool { d.object(forKey: "clipboardRecordFile") == nil ? true : d.bool(forKey: "clipboardRecordFile") }
    var clipboardRecordSourceApp: Bool { d.object(forKey: "clipboardRecordSourceApp") == nil ? true : d.bool(forKey: "clipboardRecordSourceApp") }

    // 图片 OCR（PRD 8.3）
    var clipboardEnableOCR: Bool { d.object(forKey: "clipboardEnableOCR") == nil ? true : d.bool(forKey: "clipboardEnableOCR") }
    var clipboardOCRChinese: Bool { d.object(forKey: "clipboardOCRChinese") == nil ? true : d.bool(forKey: "clipboardOCRChinese") }
    var clipboardOCREnglish: Bool { d.object(forKey: "clipboardOCREnglish") == nil ? true : d.bool(forKey: "clipboardOCREnglish") }
    var clipboardOCRAutoRetry: Bool { d.object(forKey: "clipboardOCRAutoRetry") == nil ? true : d.bool(forKey: "clipboardOCRAutoRetry") }

    // 打开历史面板快捷键（PRD 6：默认 ⇧⌘V，可配置）
    var clipboardOpenShortcut: String { d.string(forKey: "clipboardOpenShortcut") ?? "v" }
    var clipboardOpenShortcutFlags: Int { d.object(forKey: "clipboardOpenShortcutFlags") == nil ? Int(NSEvent.ModifierFlags([.command, .shift]).rawValue) : d.integer(forKey: "clipboardOpenShortcutFlags") }

    // 历史保留策略（PRD 4.3 / 8.5）
    var clipboardMaxEntries: Int { let v = d.integer(forKey: "clipboardMaxEntries"); return v == 0 ? 500 : v }
    /// 保留天数；0 = 永不过期
    var clipboardRetentionDays: Int { let v = d.integer(forKey: "clipboardRetentionDays"); return v == 0 ? 30 : v }

    /// 排除应用列表（bundleID 前缀匹配；默认覆盖常见密码管理器，PRD 8.6/15）
    var clipboardExcludedBundleIDs: [String] {
        d.stringArray(forKey: "clipboardExcludedBundleIDs") ?? [
            "com.agilebits.onepassword-osx",  // 1Password 7
            "com.1password.1password",        // 1Password 8+
            "com.bitwarden.desktop",          // Bitwarden
            "com.dashlane.Dashlane",          // Dashlane
            "com.apple.keychainaccess",       // 钥匙串访问
        ]
    }

    func setClipboardHistoryEnabled(_ v: Bool) {
        objectWillChange.send()
        d.set(v, forKey: "clipboardHistoryEnabled")
        ClipboardMonitor.shared.syncWithPreferences()
    }
    func setClipboardOnboarded(_ v: Bool) { d.set(v, forKey: "clipboardOnboarded") }
    func setClipboardPausedUntil(_ v: Date?) {
        objectWillChange.send()
        d.set(v, forKey: "clipboardPausedUntil")
        ClipboardMonitor.shared.syncWithPreferences()
    }
    func setClipboardRecordText(_ v: Bool) { d.set(v, forKey: "clipboardRecordText") }
    func setClipboardRecordImage(_ v: Bool) { d.set(v, forKey: "clipboardRecordImage") }
    func setClipboardRecordLink(_ v: Bool) { d.set(v, forKey: "clipboardRecordLink") }
    func setClipboardRecordFile(_ v: Bool) { d.set(v, forKey: "clipboardRecordFile") }
    func setClipboardRecordSourceApp(_ v: Bool) { d.set(v, forKey: "clipboardRecordSourceApp") }
    func setClipboardEnableOCR(_ v: Bool) { d.set(v, forKey: "clipboardEnableOCR") }
    func setClipboardOCRChinese(_ v: Bool) { d.set(v, forKey: "clipboardOCRChinese") }
    func setClipboardOCREnglish(_ v: Bool) { d.set(v, forKey: "clipboardOCREnglish") }
    func setClipboardOCRAutoRetry(_ v: Bool) { d.set(v, forKey: "clipboardOCRAutoRetry") }
    func setClipboardOpenShortcut(_ v: String) {
        objectWillChange.send()
        d.set(v, forKey: "clipboardOpenShortcut")
    }
    func setClipboardOpenShortcutFlags(_ v: Int) {
        objectWillChange.send()
        d.set(v, forKey: "clipboardOpenShortcutFlags")
    }
    func setClipboardMaxEntries(_ v: Int) { d.set(v, forKey: "clipboardMaxEntries") }
    func setClipboardRetentionDays(_ v: Int) { d.set(v, forKey: "clipboardRetentionDays") }
    func setClipboardExcludedBundleIDs(_ v: [String]) { d.set(v, forKey: "clipboardExcludedBundleIDs") }

    // 录屏设置：两路音频独立开关（都关 = 无声录制；都开 = 带解说的会议场景）
    var recordingSystemAudio: Bool { d.object(forKey: "recordingSystemAudio") == nil ? true : d.bool(forKey: "recordingSystemAudio") }
    var recordingMicrophone: Bool { d.object(forKey: "recordingMicrophone") == nil ? false : d.bool(forKey: "recordingMicrophone") }
    /// 鼠标呈现：keep 保留 / hide 隐藏 / highlight 点击高亮（14.2+，旧系统回退保留）
    var recordingCursorMode: String { d.string(forKey: "recordingCursorMode") ?? V2RecordingCursorMode.keep.rawValue }
    /// 录制前倒计时：0 = 关闭；建议教程/演示使用 3 秒
    var recordingCountdownSeconds: Int {
        let value = d.integer(forKey: "recordingCountdownSeconds")
        return [0, 3, 5].contains(value) ? value : 0
    }

    /// 上次录屏区域：按显示器保存归一化坐标，避免分辨率变化或多屏切换时直接复用绝对坐标
    var lastRecordingSelection: LastRecordingSelection? {
        guard let values = d.dictionary(forKey: "lastRecordingSelection"),
              let displayID = values["displayID"] as? NSNumber,
              let x = values["x"] as? NSNumber,
              let y = values["y"] as? NSNumber,
              let width = values["width"] as? NSNumber,
              let height = values["height"] as? NSNumber else {
            return nil
        }

        let rect = CGRect(x: x.doubleValue, y: y.doubleValue,
                          width: width.doubleValue, height: height.doubleValue)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return LastRecordingSelection(normalizedRect: rect,
                                      displayID: CGDirectDisplayID(displayID.uint32Value))
    }

    func setRecordingSystemAudio(_ v: Bool) {
        d.set(v, forKey: "recordingSystemAudio")
        objectWillChange.send()
    }

    func setRecordingMicrophone(_ v: Bool) {
        d.set(v, forKey: "recordingMicrophone")
        objectWillChange.send()
    }

    func setRecordingCursorMode(_ v: V2RecordingCursorMode) {
        d.set(v.rawValue, forKey: "recordingCursorMode")
        objectWillChange.send()
    }

    func setRecordingCountdownSeconds(_ v: Int) {
        d.set([0, 3, 5].contains(v) ? v : 0, forKey: "recordingCountdownSeconds")
        objectWillChange.send()
    }

    func setLastRecordingSelection(_ rect: CGRect, on screen: NSScreen) {
        guard rect.width > 0, rect.height > 0,
              screen.frame.width > 0, screen.frame.height > 0,
              let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return
        }

        let size = screen.frame.size
        let normalized = CGRect(x: rect.minX / size.width,
                                y: rect.minY / size.height,
                                width: rect.width / size.width,
                                height: rect.height / size.height)
        d.set([
            "displayID": displayNumber,
            "x": normalized.minX,
            "y": normalized.minY,
            "width": normalized.width,
            "height": normalized.height
        ], forKey: "lastRecordingSelection")
    }

    func resolvedLastRecordingSelection(on screen: NSScreen) -> CGRect? {
        guard let saved = lastRecordingSelection,
              let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              displayNumber.uint32Value == saved.displayID else {
            return nil
        }

        let size = screen.frame.size
        let rect = CGRect(x: saved.normalizedRect.minX * size.width,
                          y: saved.normalizedRect.minY * size.height,
                          width: saved.normalizedRect.width * size.width,
                          height: saved.normalizedRect.height * size.height)
        let screenBounds = CGRect(origin: .zero, size: size)
        let resolved = rect.intersection(screenBounds)
        return resolved.width >= 16 && resolved.height >= 16 ? resolved : nil
    }
    func setScreenshotCopyPathAfterSave(_ v: Bool) {
        objectWillChange.send()
        d.set(v, forKey: "screenshotCopyPathAfterSave")
    }

    func setOpenAIBaseURL(_ v: String) { d.set(v, forKey: "openAIBaseURL") }
    func setOpenAIModel(_ v: String) { d.set(v, forKey: "openAIModel") }
    func setAISystemPrompt(_ v: String) { 
        objectWillChange.send()
        d.set(v, forKey: "aiSystemPrompt") 
    }
    func setAIUserPrompt(_ v: String) { 
        objectWillChange.send()
        d.set(v, forKey: "aiUserPrompt") 
    }
    
    /// 重置系统提示词为默认值
    func resetAISystemPrompt() {
        objectWillChange.send()
        d.removeObject(forKey: "aiSystemPrompt")
    }
    
    /// 重置用户提示词为默认值
    func resetAIUserPrompt() {
        objectWillChange.send()
        d.removeObject(forKey: "aiUserPrompt")
    }
    
    /// 重置所有设置为默认值
    func resetAll() {
        objectWillChange.send()
        let keys = [
            "enableAI", "titleLimit", "summaryTrigger", "summaryLimit", 
            "dedupEnabled", "maxScreenshots", "debounceSeconds", "windowLock", 
            "animationsEnabled", "rememberWindowPosition", "attachmentsPath",
            "attachmentsDirectoryBookmark", "screenshotSaveDirectoryBookmark",
            "screenshotSaveDirectory", "openAIBaseURL", "openAIModel", "aiSystemPrompt", "aiUserPrompt",
            "preferredEditor", "recordingSystemAudio", "recordingMicrophone", "recordingCursorMode",
            "recordingCountdownSeconds", "lastRecordingSelection",
            "clipboardHistoryEnabled", "clipboardRecordText", "clipboardRecordImage", "clipboardRecordLink",
            "clipboardRecordFile", "clipboardRecordSourceApp", "clipboardEnableOCR", "clipboardOCRChinese",
            "clipboardOCREnglish", "clipboardOCRAutoRetry", "clipboardOpenShortcut", "clipboardOpenShortcutFlags",
            "clipboardMaxEntries", "clipboardRetentionDays", "clipboardExcludedBundleIDs", "clipboardPausedUntil"
        ]
        for key in keys {
            d.removeObject(forKey: key)
        }
    }
    
    // 搜索历史相关方法
    func stringArray(forKey key: String) -> [String]? {
        return d.stringArray(forKey: key)
    }
    
    func set(_ value: [String], forKey key: String) {
        d.set(value, forKey: key)
    }
    
    // 窗口位置相关方法
    func getWindowPosition() -> NSRect? {
        if let data = d.data(forKey: "windowPosition"),
           let rect = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSValue.self, from: data) {
            return rect.rectValue
        }
        return nil
    }
    
    func setWindowPosition(_ rect: NSRect) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: NSValue(rect: rect), requiringSecureCoding: false) {
            d.set(data, forKey: "windowPosition")
        }
    }
    
    // 获取窗口所属屏幕的ID
    func getWindowScreenId() -> String? {
        return d.string(forKey: "windowScreenId")
    }
    
    // 保存窗口所属屏幕的ID
    func setWindowScreenId(_ screenId: String) {
        d.set(screenId, forKey: "windowScreenId")
    }
    
    // 根据屏幕ID查找对应的屏幕
    func getScreenById(_ screenId: String) -> NSScreen? {
        // 首先尝试通过屏幕的本地名称查找
        for screen in NSScreen.screens {
            if screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber == NSNumber(value: Int(screenId) ?? 0) {
                return screen
            }
        }
        
        // 如果找不到，返回主屏幕
        return NSScreen.main
    }
}
