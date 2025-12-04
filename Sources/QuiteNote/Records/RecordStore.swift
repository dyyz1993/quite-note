import Foundation
import Combine
import CoreData

/// 管理记录的增删改查、搜索与轻提示分发
final class RecordStore: ObservableObject {
    @Published private(set) var records: [Record] = []
    @Published var lightHint: String? = nil
    @Published var toast: ToastMessage? = nil
    @Published var aiProvider: AIProvider = .local
    @Published var enableAI: Bool = true
    var ai: AIServiceProtocol? = nil
    var titleLimit: Int = 20
    var summaryTrigger: Int = 20
    var summaryLimit: Int = 100
    var dedupEnabled: Bool = true
    var maxRecords: Int = 100
    private let stack = CoreDataStack.shared
    private let prefs = PreferencesManager.shared

    init() {
        loadFromStore()
        loadPreferences()
        if records.isEmpty {
            addMockData()
        }
    }

    private func addMockData() {
        let mockTexts = [
            "const [count, setCount] = useState(0);",
            "https://www.google.com/search?q=react+hooks",
            "Rust 是一种系统级编程语言，专注于安全性，尤其是并发安全。它支持函数式和命令式以及泛型等编程范式的多范式语言。Rust 在语法上和 C++ 类似，但是设计者想要在保证性能的同时提供更好的内存安全。Rust 最初是由 Mozilla 研究院的 Graydon Hoare 设计创造，然后在 Dave Herman, Brendan Eich 以及众多社区成员的贡献下发展壮大。Rust 的设计目标之一是使设计大型的互联网客户端和服务器的任务变得更容易。",
            "TODO: Fix the header layout on mobile screens.",
            "Docker run -p 8080:80 nginx",
            "Meeting notes: 1. Review Q3 goals, 2. Team lunch",
            "rgb(255, 99, 71)",
            "这是一个非常棒的产品构思！结合了硬件交互。",
            "import { motion } from 'framer-motion';\n// 这是一个多行代码注释\n// 用于测试行数统计",
            "git commit -m 'feat: add bluetooth listener'",
            "Email: contact@example.com",
            "MacBook Pro M3 Max"
        ]
        
        let now = Date()
        for (index, text) in mockTexts.enumerated() {
            let cd = stack.newRecord()
            cd.id = UUID()
            cd.content = text
            // Spread out timestamps over the last few hours
            cd.createdAt = now.addingTimeInterval(Double(-index * 3600))
            cd.digest = ClipboardService.sha1(text)
            cd.starred = index == 0
            
            // Mock AI results for some items
            if text.contains("Rust") {
                cd.title = "Rust 语言深度介绍与应用"
                cd.summary = "Rust 是一种注重安全与性能的系统级编程语言，解决了 C++ 在内存安全和并发性上的痛点。其设计目标是简化大型互联网应用的开发。"
                cd.summaryConfidence = 0.95
                cd.aiStatus = "success"
            } else if text.contains("useState") {
                cd.title = "React Hook: useState 定义"
                cd.aiStatus = "success"
            } else if text.contains("http") {
                cd.title = "外部链接资源"
                cd.aiStatus = "success"
            } else if text.contains("Docker") {
                cd.title = "Docker 运行命令"
                cd.aiStatus = "success"
            } else if text.contains("MacBook") {
                cd.title = "MacBook Pro M3 Max 产品名"
                cd.aiStatus = "success"
            } else if text.count > 20 {
                cd.title = "关于 \"\(text.prefix(15))...\" 的内容提炼"
                cd.aiStatus = "success"
            }
            
            stack.save()
        }
        loadFromStore() // Reload to update UI
    }

    /// 添加一条记录并触发 UI 刷新
    func addRecord(content: String, hash: String) {
        let now = Date()
        let cd = stack.newRecord()
        cd.id = UUID()
        cd.content = content
        cd.createdAt = now
        cd.digest = hash
        cd.starred = false
        stack.save()
        let record = Record(id: cd.id, title: nil, content: content, createdAt: now, hash: hash, aiStatus: nil, summary: nil, summaryConfidence: nil, starred: false, copiedAt: nil)
        records.insert(record, at: 0)
        if records.count > maxRecords { records = Array(records.prefix(maxRecords)) }
        guard enableAI, content.count >= summaryTrigger, let ai else { return }
        let index = 0
        records[index].aiStatus = "pending"
        ai.summarize(titleLimit: titleLimit, summaryLimit: summaryLimit, content: content) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let s):
                    self.records[index].title = s.title
                    self.records[index].summary = s.summary
                    self.records[index].summaryConfidence = s.confidence
                    self.records[index].aiStatus = "success"
                    self.updateCDRecord(id: cd.id, title: s.title, summary: s.summary, confidence: s.confidence, aiStatus: "success")
                case .failure:
                    self.records[index].aiStatus = "fail"
                    self.updateCDRecord(id: cd.id, title: nil, summary: nil, confidence: nil, aiStatus: "fail")
                }
            }
        }
    }

    /// 判断是否为近期重复记录
    func isRecentDuplicate(hash: String, withinMinutes: Int) -> Bool {
        let threshold = Date().addingTimeInterval(Double(-withinMinutes) * 60)
        return records.first(where: { $0.hash == hash && $0.createdAt >= threshold }) != nil
    }

    func updateTimestampForHash(_ hash: String) {
        let now = Date()
        if let idx = records.firstIndex(where: { $0.hash == hash }) {
            let id = records[idx].id
            records[idx].createdAt = now
            let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let obj = try? stack.context.fetch(req).first {
                obj.createdAt = now
                stack.save()
            }
        }
    }

    /// 删除指定记录
    func delete(_ record: Record) {
        records.removeAll { $0.id == record.id }
        deleteCDRecord(id: record.id)
    }
    
    /// 清空所有记录
    func clearAll() {
        records.removeAll()
        let req = NSFetchRequest<NSFetchRequestResult>(entityName: "CDRecord")
        let deleteReq = NSBatchDeleteRequest(fetchRequest: req)
        try? stack.context.execute(deleteReq)
        stack.save()
    }

    /// 搜索记录（标题、内容模糊匹配）
    func search(_ query: String) -> [Record] {
        guard !query.isEmpty else { return records }
        let q = query.lowercased()
        return records.filter { ($0.title ?? "").lowercased().contains(q) || $0.content.lowercased().contains(q) }
    }

    /// 发送轻量提示（悬浮窗右下角气泡）
    func postLightHint(_ text: String) {
        lightHint = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.lightHint = nil }
    }

    /// 顶部右侧 Toast 提示
    func postToast(_ text: String, type: String = "info") {
        toast = ToastMessage(text: text, type: type)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.toast = nil }
    }

    /// 连接 AI 提炼服务
    func attachAI(service: AIServiceProtocol) {
        self.ai = service
        if let s = ai as? AIService {
            s.provider = aiProvider
            s.openAIBaseURL = prefs.openAIBaseURL
            s.openAIModel = prefs.openAIModel
        }
    }

    /// 设置 AI 提供商（本地/OpenAI）
    func setAIProvider(_ provider: AIProvider) {
        self.aiProvider = provider
        if let s = ai as? AIService { s.provider = provider }
        prefs.setAIProvider(provider == .openai ? "openai" : "local")
    }

    /// 配置 OpenAI 连接参数并写入 Keychain（仅密钥）
    func configureOpenAI(apiKey: String, baseURL: String, model: String) {
        KeychainHelper.shared.write(service: "QuiteNote", account: "openai_api_key", value: apiKey)
        prefs.setOpenAIBaseURL(baseURL)
        prefs.setOpenAIModel(model)
        if let s = ai as? AIService {
            s.openAIBaseURL = baseURL
            s.openAIModel = model
        }
    }

    func loadPreferences() {
        enableAI = prefs.enableAI
        titleLimit = prefs.titleLimit
        summaryTrigger = prefs.summaryTrigger
        summaryLimit = prefs.summaryLimit
        dedupEnabled = prefs.dedupEnabled
        maxRecords = prefs.maxRecords
        aiProvider = prefs.aiProvider == "openai" ? .openai : .local
    }

    func savePreferences() {
        prefs.setEnableAI(enableAI)
        prefs.setTitleLimit(titleLimit)
        prefs.setSummaryTrigger(summaryTrigger)
        prefs.setSummaryLimit(summaryLimit)
        prefs.setDedupEnabled(dedupEnabled)
        prefs.setMaxRecords(maxRecords)
    }

    /// 导出全部记录为 Markdown（占位：返回生成的文本）
    func exportMarkdown() -> String {
        var md = "# QuiteNote 导出\n\n"
        for r in records.reversed() {
            if let t = r.title {
                md += "## \(t)\n\n"
            } else {
                md += "## 无标题\n\n"
            }
            md += "创建时间：\(r.createdAt)\n\n"
            md += "\(r.content)\n\n"
            if let s = r.summary { md += "> 总结：\(s)\n\n" }
        }
        return md
    }

    /// 批量对无标题记录触发重新提炼（每次最多处理 3 条）
    func bulkResummarize(batchSize: Int = 3) {
        guard enableAI, let ai else { return }
        let targets = records.enumerated().filter { $0.element.title == nil }.prefix(batchSize)
        for (index, r) in targets {
            records[index].aiStatus = "pending"
            ai.summarize(titleLimit: titleLimit, summaryLimit: summaryLimit, content: r.content) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success(let s):
                        self.records[index].title = s.title
                        self.records[index].summary = s.summary
                        self.records[index].summaryConfidence = s.confidence
                        self.records[index].aiStatus = "success"
                        self.updateCDRecord(id: self.records[index].id, title: s.title, summary: s.summary, confidence: s.confidence, aiStatus: "success")
                    case .failure:
                        self.records[index].aiStatus = "fail"
                        self.updateCDRecord(id: self.records[index].id, title: nil, summary: nil, confidence: nil, aiStatus: "fail")
                    }
                }
            }
        }
    }

    private func loadFromStore() {
        let cds = (try? stack.fetchRecords()) ?? []
        records = cds.map { r in
            Record(id: r.id, title: r.title, content: r.content, createdAt: r.createdAt, hash: r.digest, aiStatus: r.aiStatus, summary: r.summary, summaryConfidence: r.summaryConfidence, starred: r.starred, copiedAt: r.copiedAt)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private func updateCDRecord(id: UUID, title: String?, summary: String?, confidence: Double?, aiStatus: String?) {
        let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let obj = try? stack.context.fetch(req).first {
            obj.title = title
            obj.summary = summary
            obj.summaryConfidence = confidence ?? obj.summaryConfidence
            obj.aiStatus = aiStatus
            stack.save()
        }
    }

    private func deleteCDRecord(id: UUID) {
        let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let obj = try? stack.context.fetch(req).first {
            stack.context.delete(obj)
            stack.save()
        }
    }

    func toggleStar(_ record: Record) {
        if let idx = records.firstIndex(where: { $0.id == record.id }) {
            records[idx].starred.toggle()
            let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
            req.predicate = NSPredicate(format: "id == %@", record.id as CVarArg)
            if let obj = try? stack.context.fetch(req).first {
                obj.starred = records[idx].starred
                stack.save()
            }
        }
    }

    func resummarize(record: Record) {
        guard let ai, enableAI else { return }
        guard let idx = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[idx].aiStatus = "pending"
        ai.summarize(titleLimit: titleLimit, summaryLimit: summaryLimit, content: record.content) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let s):
                    self.records[idx].title = s.title
                    self.records[idx].summary = s.summary
                    self.records[idx].summaryConfidence = s.confidence
                    self.records[idx].aiStatus = "success"
                    self.updateCDRecord(id: record.id, title: s.title, summary: s.summary, confidence: s.confidence, aiStatus: "success")
                case .failure:
                    self.records[idx].aiStatus = "fail"
                    self.updateCDRecord(id: record.id, title: nil, summary: nil, confidence: nil, aiStatus: "fail")
                }
            }
        }
    }
}
