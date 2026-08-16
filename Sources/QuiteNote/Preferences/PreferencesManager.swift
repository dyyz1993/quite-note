import Foundation
import AppKit
import Combine

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

    var enableAI: Bool { d.object(forKey: "enableAI") == nil ? true : d.bool(forKey: "enableAI") }
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
    func setAttachmentsPath(_ v: String?) { d.set(v, forKey: "attachmentsPath") }
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

    // 截图文件保存目录（空字符串 = 使用桌面）
    var screenshotSaveDirectory: String { d.string(forKey: "screenshotSaveDirectory") ?? "" }
    func setScreenshotSaveDirectory(_ v: String) {
        objectWillChange.send()
        d.set(v, forKey: "screenshotSaveDirectory")
    }

    // 保存截图文件后自动复制绝对路径到剪贴板
    var screenshotCopyPathAfterSave: Bool { d.object(forKey: "screenshotCopyPathAfterSave") == nil ? true : d.bool(forKey: "screenshotCopyPathAfterSave") }
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
            "openAIBaseURL", "openAIModel", "aiSystemPrompt", "aiUserPrompt",
            "preferredEditor"
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

