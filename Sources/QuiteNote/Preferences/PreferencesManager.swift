import Foundation

final class PreferencesManager {
    static let shared = PreferencesManager()
    private let d = UserDefaults.standard

    var enableAI: Bool { d.bool(forKey: "enableAI") }
    var titleLimit: Int { max(15, d.integer(forKey: "titleLimit")) }
    var summaryTrigger: Int { max(0, d.integer(forKey: "summaryTrigger")) }
    var summaryLimit: Int { max(50, d.integer(forKey: "summaryLimit")) }
    var dedupEnabled: Bool { d.object(forKey: "dedupEnabled") == nil ? true : d.bool(forKey: "dedupEnabled") }
    var maxRecords: Int { let v = d.integer(forKey: "maxRecords"); return v == 0 ? 100 : v }
    var debounceSeconds: Int { let v = d.integer(forKey: "debounceSeconds"); return v == 0 ? 1 : v }
    var windowLock: Bool { d.object(forKey: "windowLock") == nil ? false : d.bool(forKey: "windowLock") }
    var animationsEnabled: Bool { d.object(forKey: "animationsEnabled") == nil ? true : d.bool(forKey: "animationsEnabled") }
    var aiProvider: String { d.string(forKey: "aiProvider") ?? "local" }
    var openAIBaseURL: String { d.string(forKey: "openAIBaseURL") ?? "https://api.openai.com/v1" }
    var openAIModel: String { d.string(forKey: "openAIModel") ?? "gpt-4o-mini" }

    func setEnableAI(_ v: Bool) { d.set(v, forKey: "enableAI") }
    func setTitleLimit(_ v: Int) { d.set(v, forKey: "titleLimit") }
    func setSummaryTrigger(_ v: Int) { d.set(v, forKey: "summaryTrigger") }
    func setSummaryLimit(_ v: Int) { d.set(v, forKey: "summaryLimit") }
    func setDedupEnabled(_ v: Bool) { d.set(v, forKey: "dedupEnabled") }
    func setMaxRecords(_ v: Int) { d.set(v, forKey: "maxRecords") }
    func setDebounceSeconds(_ v: Int) { d.set(v, forKey: "debounceSeconds") }
    func setWindowLock(_ v: Bool) { d.set(v, forKey: "windowLock") }
    func setAnimationsEnabled(_ v: Bool) { d.set(v, forKey: "animationsEnabled") }
    func setAIProvider(_ v: String) { d.set(v, forKey: "aiProvider") }
    func setOpenAIBaseURL(_ v: String) { d.set(v, forKey: "openAIBaseURL") }
    func setOpenAIModel(_ v: String) { d.set(v, forKey: "openAIModel") }
    
    // 搜索历史相关方法
    func stringArray(forKey key: String) -> [String]? {
        return d.stringArray(forKey: key)
    }
    
    func set(_ value: [String], forKey key: String) {
        d.set(value, forKey: key)
    }
}

