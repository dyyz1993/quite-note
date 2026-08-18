import Foundation
import Combine

/// 匹配的符号项 - 包含符号和匹配到的触发词
struct MatchedSymbolItem: Identifiable, Equatable {
    let id = UUID()
    let symbol: SymbolItem
    let matchedTrigger: String

    var content: String { symbol.content }
    var desc: String { symbol.desc }
    var triggers: [String] { symbol.triggers }
}

/// 触发上下文：定位到的触发前缀及其在文本中的范围（NSString / UTF-16 坐标系）
struct SymbolTriggerContext: Equatable {
    let prefix: String
    let range: NSRange
}

/// 符号触发检测器 - 监听文本输入，检测触发词
class SymbolTriggerDetector: ObservableObject {
    @Published var detectedTrigger: String?
    @Published var suggestions: [MatchedSymbolItem] = []
    @Published var triggerPosition: NSRange?

    private let configManager: SymbolConfigManager

    init(configManager: SymbolConfigManager = .shared) {
        self.configManager = configManager
    }

    /// 所有启用配置的触发前缀（去重 + 排序，保证遍历顺序稳定）
    var enabledPrefixes: [String] {
        Array(Set(configManager.enabledConfigs.map { $0.global.triggerPrefix })).sorted()
    }

    /// 兼容属性：第一个启用配置的前缀（仅用于展示，检测逻辑使用 enabledPrefixes）
    var triggerPrefix: String {
        configManager.enabledConfigs.first?.global.triggerPrefix ?? ":/"
    }

    /// 检测文本中的触发词
    func detectTrigger(in text: String, cursorPosition: Int) {
        performDetection(in: text, cursorPosition: cursorPosition)
    }

    private func performDetection(in text: String, cursorPosition: Int) {
        guard cursorPosition > 0 else {
            clearDetection()
            return
        }

        // NSTextView 使用 NSString 坐标系（UTF-16），emoji 等字符与 String.count 长度不同
        let nsString = text as NSString
        guard cursorPosition <= nsString.length else {
            clearDetection()
            return
        }

        guard let context = Self.locateTrigger(nsText: nsString, cursor: cursorPosition, prefixes: enabledPrefixes) else {
            clearDetection()
            return
        }

        let triggerStart = context.range.location + context.range.length
        let triggerText = nsString.substring(with: NSRange(location: triggerStart, length: cursorPosition - triggerStart))

        let matchedItems = Self.suggestions(
            forTrigger: triggerText,
            matchedPrefix: context.prefix,
            configs: configManager.enabledConfigs
        )

        guard !matchedItems.isEmpty else {
            clearDetection()
            return
        }

        detectedTrigger = triggerText
        suggestions = matchedItems
        triggerPosition = NSRange(location: context.range.location, length: cursorPosition - context.range.location)
    }

    // MARK: - 前缀定位（纯函数，可单测）

    /// 在光标前（限最近 50 个 UTF-16 单位）查找触发前缀
    ///
    /// 规则：
    /// 1. 支持多个前缀并行（默认库 ":/"、表情库 ":e" 等），取离光标最近的一个
    /// 2. 词边界约束：前缀的前一个字符不能是 ASCII 字母/数字——排除 "https:/" 等 URL 场景误触发；
    ///    中文等非 ASCII 字符后接前缀是合法输入
    /// 3. 同一位置命中多个前缀时取更长的（":e" 与 ":ex" 并存时 ":ex" 优先）
    /// 4. 某次出现被词边界拒绝时（如 URL 内），继续向前找该前缀更早的合法出现
    static func locateTrigger(nsText: NSString, cursor: Int, prefixes: [String]) -> SymbolTriggerContext? {
        guard cursor > 0, cursor <= nsText.length else { return nil }

        let windowLength = min(50, cursor)
        let windowStart = cursor - windowLength
        let window = nsText.substring(with: NSRange(location: windowStart, length: windowLength)) as NSString

        var best: SymbolTriggerContext?
        for prefix in prefixes where !prefix.isEmpty {
            guard let relativeLocation = lastValidLocation(of: prefix, in: window) else { continue }
            let candidate = SymbolTriggerContext(
                prefix: prefix,
                range: NSRange(location: windowStart + relativeLocation, length: (prefix as NSString).length)
            )
            if let current = best {
                let nearer = candidate.range.location > current.range.location
                let longerAtSameSpot = candidate.range.location == current.range.location && candidate.prefix.count > current.prefix.count
                if nearer || longerAtSameSpot {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }
        return best
    }

    /// 在窗口内从后往前找一个满足词边界的前缀位置
    private static func lastValidLocation(of prefix: String, in window: NSString) -> Int? {
        let prefixLength = (prefix as NSString).length
        guard prefixLength > 0, prefixLength <= window.length else { return nil }

        var searchEnd = window.length
        while searchEnd >= prefixLength {
            let range = window.range(of: prefix, options: .backwards, range: NSRange(location: 0, length: searchEnd))
            guard range.location != NSNotFound else { return nil }
            if range.location == 0 || !isASCIILetterOrDigit(window.character(at: range.location - 1)) {
                return range.location
            }
            // 该出现被词边界拒绝（如 URL 内），继续向前找
            searchEnd = range.location
        }
        return nil
    }

    private static func isASCIILetterOrDigit(_ ch: unichar) -> Bool {
        (ch >= 0x30 && ch <= 0x39) || (ch >= 0x41 && ch <= 0x5A) || (ch >= 0x61 && ch <= 0x7A)
    }

    // MARK: - 建议列表（纯函数，可单测）

    /// 生成建议列表
    /// - 裸前缀（触发词为空）：只展示该前缀所属配置的符号
    /// - 有触发词：跨所有启用配置模糊匹配，同内容符号去重，按匹配度排序
    static func suggestions(forTrigger trigger: String, matchedPrefix: String, configs: [SymbolConfig]) -> [MatchedSymbolItem] {
        if trigger.isEmpty {
            let ownerConfigs = configs.filter { $0.global.triggerPrefix == matchedPrefix }
            return sortedSymbols(from: ownerConfigs)
                .prefix(5)
                .map { MatchedSymbolItem(symbol: $0, matchedTrigger: "") }
        }
        return matchSymbols(trigger: trigger, configs: configs)
    }

    /// 符号排序：核心高频优先，其次按描述长度
    private static func sortedSymbols(from configs: [SymbolConfig]) -> [SymbolItem] {
        var allSymbols: [SymbolItem] = []
        for config in configs {
            for menu in config.menus.sorted(by: { $0.sort < $1.sort }) {
                allSymbols.append(contentsOf: menu.symbols)
            }
        }
        return allSymbols.sorted { a, b in
            let aIsCore = a.desc.contains("核心") || a.desc.contains("高频")
            let bIsCore = b.desc.contains("核心") || b.desc.contains("高频")
            if aIsCore != bIsCore { return aIsCore }
            return a.desc.count < b.desc.count
        }
    }

    private static func matchSymbols(trigger: String, configs: [SymbolConfig]) -> [MatchedSymbolItem] {
        let normalizedTrigger = trigger.lowercased().trimmingCharacters(in: .whitespaces)
        guard !normalizedTrigger.isEmpty else { return [] }

        // 按符号内容去重（不同配置可能定义同内容符号，如默认库/英文库都有 bug→🐛），保留评分最好的一条
        var bestMatchForContent: [String: (symbol: SymbolItem, trigger: String, score: SearchScore)] = [:]

        for config in configs {
            for (_, symbol) in config.triggerMap {
                var bestScore: SearchScore?
                var bestMatchedTrigger: String?
                for symbolTrigger in symbol.triggers {
                    if let score = FuzzySearch.matchTrigger(triggers: [symbolTrigger], query: normalizedTrigger),
                       bestScore == nil || score < bestScore! {
                        bestScore = score
                        bestMatchedTrigger = symbolTrigger
                    }
                }
                if let score = bestScore, let matchedTrigger = bestMatchedTrigger {
                    if let existing = bestMatchForContent[symbol.content] {
                        if score < existing.score {
                            bestMatchForContent[symbol.content] = (symbol, matchedTrigger, score)
                        }
                    } else {
                        bestMatchForContent[symbol.content] = (symbol, matchedTrigger, score)
                    }
                }
            }
        }

        return bestMatchForContent.values
            .sorted {
                if $0.score != $1.score { return $0.score < $1.score }
                return $0.symbol.content < $1.symbol.content // 评分相同按内容排序，保证顺序稳定
            }
            .prefix(5)
            .map { MatchedSymbolItem(symbol: $0.symbol, matchedTrigger: $0.trigger) }
    }

    /// 清除检测结果
    func clearDetection() {
        detectedTrigger = nil
        suggestions = []
        triggerPosition = nil
    }

    // MARK: - 替换与插入

    /// 定位替换目标（与检测使用同一套定位规则，保证范围一致）
    func replacementTarget(in text: String, cursorPosition: Int) -> SymbolTriggerContext? {
        let nsString = text as NSString
        return Self.locateTrigger(nsText: nsString, cursor: cursorPosition, prefixes: enabledPrefixes)
    }

    /// 获取要替换的完整文本范围（从触发前缀开始到光标位置）
    func getReplacementRange(in text: String, cursorPosition: Int) -> NSRange? {
        guard let context = replacementTarget(in: text, cursorPosition: cursorPosition) else { return nil }
        return NSRange(location: context.range.location, length: cursorPosition - context.range.location)
    }

    /// 插入选中的符号
    /// 返回值的光标位置为 NSString / UTF-16 坐标，与 NSTextView 一致
    func insertSymbol(_ symbol: SymbolItem, into text: String, cursorPosition: Int) -> (newText: String, newCursorPos: Int)? {
        let nsString = text as NSString
        guard let context = replacementTarget(in: text, cursorPosition: cursorPosition) else {
            return nil
        }

        let fullRange = NSRange(location: context.range.location, length: cursorPosition - context.range.location)
        guard fullRange.length >= 0, NSMaxRange(fullRange) <= nsString.length else { return nil }

        // 用实际匹配到的前缀所属配置决定 autoClean（多前缀下不能写死第一个配置）
        let config = configManager.enabledConfigs.first { $0.global.triggerPrefix == context.prefix } ?? .defaultConfig

        // emoji 等特殊字符在 NSString 中可能占多个 UTF-16 单位，光标必须按 NSString 长度计算
        let symbolContentLength = (symbol.content as NSString).length

        if config.global.autoClean {
            // 替换整个触发词（包括前缀）
            let newText = nsString.replacingCharacters(in: fullRange, with: symbol.content)
            return (newText, fullRange.location + symbolContentLength)
        } else {
            // 只替换触发词部分，保留前缀
            let prefixLength = (context.prefix as NSString).length
            let triggerRange = NSRange(location: fullRange.location + prefixLength, length: fullRange.length - prefixLength)
            let newText = nsString.replacingCharacters(in: triggerRange, with: symbol.content)
            return (newText, triggerRange.location + symbolContentLength)
        }
    }
}
