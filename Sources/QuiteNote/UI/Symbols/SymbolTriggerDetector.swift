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

/// 符号触发检测器 - 监听文本输入，检测触发词
class SymbolTriggerDetector: ObservableObject {
    @Published var detectedTrigger: String?
    @Published var suggestions: [MatchedSymbolItem] = []
    @Published var triggerPosition: NSRange?

    private let configManager = SymbolConfigManager.shared
    private var debounceTimer: Timer?
    private let debounceDelay: TimeInterval = 0.01 // 进一步减少防抖延迟

    // 日志文件路径
    private let logPath = "/tmp/quitenote-symbol-debug.log"

    // 触发前缀
    var triggerPrefix: String {
        configManager.enabledConfigs.first?.global.triggerPrefix ?? ":/"
    }

    // 写日志到文件
    private func log(_ message: String) {
        print(message)
        if let fileHandle = FileHandle(forWritingAtPath: logPath) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(message.data(using: .utf8)!)
            fileHandle.closeFile()
        } else {
            try? message.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }

    /// 检测文本中的触发词
    func detectTrigger(in text: String, cursorPosition: Int) {
        // 立即执行检测，不使用防抖
        // 防抖会导致输入 / 时不立即触发
        performDetection(in: text, cursorPosition: cursorPosition)
    }

    /// 执行检测逻辑
    private func performDetection(in text: String, cursorPosition: Int) {
        log("[SymbolTriggerDetector] ========== 执行检测 ==========")
        log("[SymbolTriggerDetector] 文本长度: \(text.count), 光标位置: \(cursorPosition)")
        log("[SymbolTriggerDetector] 完整文本: '\(text)'")

        guard cursorPosition > 0 else {
            log("[SymbolTriggerDetector] 光标位置无效，清除检测")
            clearDetection()
            return
        }

        // ⭐ 关键修复：使用 NSString 进行索引操作，确保与 NSTextView 坐标系一致
        let nsString = text as NSString
        let nsLength = nsString.length

        // 使用 NSString.length 而不是 String.count（emoji等字符在两者中长度不同）
        guard cursorPosition > 0 && cursorPosition <= nsLength else {
            log("[SymbolTriggerDetector] 光标位置无效: cursorPosition=\(cursorPosition), nsLength=\(nsLength)")
            clearDetection()
            return
        }

        // 获取光标前的文本（使用 NSString）
        let textBeforeCursor = nsString.substring(with: NSRange(location: 0, length: cursorPosition))
        let nsBeforeCursor = textBeforeCursor as NSString

        log("[SymbolTriggerDetector] 光标前文本: '\(textBeforeCursor)' (NSString长度: \(nsBeforeCursor.length))")

        // ⭐ 关键修复：使用 NSString 从后往前查找触发前缀，限制搜索范围为最后50个字符
        // 这样可以避免找到文本中很靠前的 :/，而是找到最近输入的 :/
        let searchRange = NSRange(location: max(0, nsBeforeCursor.length - 50), length: min(50, nsBeforeCursor.length))
        let recentText = nsBeforeCursor.substring(with: searchRange)
        let nsRecentText = recentText as NSString

        // 在最近50个字符中查找触发前缀（使用 NSString.range）
        let relativePrefixRange = nsRecentText.range(of: triggerPrefix, options: .backwards)

        guard relativePrefixRange.location != NSNotFound else {
            log("[SymbolTriggerDetector] 未找到触发前缀: '\(triggerPrefix)'")
            clearDetection()
            return
        }

        // 计算相对于 textBeforeCursor 的实际位置
        let actualPrefixLocation = searchRange.location + relativePrefixRange.location
        let actualPrefixLength = relativePrefixRange.length

        log("[SymbolTriggerDetector] 找到触发前缀 '\(triggerPrefix)' 位置: \(actualPrefixLocation), 长度: \(actualPrefixLength)")

        // 获取触发词部分（从触发前缀结束到光标）
        let triggerTextStart = actualPrefixLocation + actualPrefixLength
        let triggerTextLength = cursorPosition - triggerTextStart

        guard triggerTextLength >= 0 else {
            log("[SymbolTriggerDetector] 触发词长度无效，清除检测")
            clearDetection()
            return
        }

        let triggerText = nsString.substring(with: NSRange(location: triggerTextStart, length: triggerTextLength))

        log("[SymbolTriggerDetector] 触发词: '\(triggerText)' (NSString长度: \(triggerTextLength))")

        // 新交互逻辑：输入:/显示所有符号，输入更多字符进行过滤
        let matchedItems: [MatchedSymbolItem]
        if triggerText.isEmpty {
            // 输入:/显示所有符号，按使用频率排序
            let symbols = Array(getAllSymbolsSorted().prefix(5))
            matchedItems = symbols.map { MatchedSymbolItem(symbol: $0, matchedTrigger: "") }
            log("[SymbolTriggerDetector] ✅ 显示所有符号: \(matchedItems.count) 个")
        } else {
            // 输入具体字符进行过滤
            let matches = findMatches(for: triggerText)
            matchedItems = matches.map { MatchedSymbolItem(symbol: $0.0, matchedTrigger: $0.1) }
            log("[SymbolTriggerDetector] 过滤结果: \(matchedItems.count) 个")
        }

        if !matchedItems.isEmpty {
            detectedTrigger = triggerText
            suggestions = matchedItems

            // 获取触发词位置（使用 NSString 坐标系）
            let location = actualPrefixLocation
            let length = cursorPosition - actualPrefixLocation
            triggerPosition = NSRange(location: location, length: length)

            log("[SymbolTriggerDetector] ✅ 检测成功！触发词: '\(triggerText)', 建议: \(matchedItems.count) 个")
            log("[SymbolTriggerDetector] 触发词位置: location=\(location), length=\(length)")
        } else {
            log("[SymbolTriggerDetector] 没有匹配结果，清除检测")
            clearDetection()
        }
        log("[SymbolTriggerDetector] ========== 检测完成 ==========")
    }

    /// 查找匹配的符号
    private func findMatches(for trigger: String) -> [(SymbolItem, String)] {
        let normalizedTrigger = trigger.lowercased().trimmingCharacters(in: .whitespaces)
        log("[SymbolTriggerDetector] 查找匹配，规范化触发词: '\(normalizedTrigger)'")

        var scoredMatches: [(SymbolItem, String, SearchScore)] = []

        let enabledCount = configManager.enabledConfigs.count
        log("[SymbolTriggerDetector] 已启用的配置数量: \(enabledCount)")

        for config in configManager.enabledConfigs {
            log("[SymbolTriggerDetector] 检查配置: \(config.metadata.name), 触发词映射数: \(config.triggerMap.count)")
            for (triggerKey, symbol) in config.triggerMap {
                // ⭐ 关键修复：检查符号的每个 trigger，找出最匹配的那个
                var bestScore: SearchScore? = nil
                var bestMatchedTrigger: String? = nil

                for symbolTrigger in symbol.triggers {
                    if let score = FuzzySearch.matchTrigger(triggers: [symbolTrigger], query: normalizedTrigger) {
                        log("[SymbolTriggerDetector] 模糊匹配检查: '\(symbolTrigger)' -> '\(symbol.content)' (level=\(score.level), chars=\(score.matchedCharCount))")
                        // 保留评分最高的（分数越低越好）
                        if bestScore == nil || score < bestScore! {
                            bestScore = score
                            bestMatchedTrigger = symbolTrigger
                        }
                    }
                }

                if let matchedTrigger = bestMatchedTrigger, let score = bestScore {
                    log("[SymbolTriggerDetector] ✅ 最佳匹配: '\(matchedTrigger)' -> '\(symbol.content)' (level=\(score.level), chars=\(score.matchedCharCount))")
                    scoredMatches.append((symbol, matchedTrigger, score))
                }
            }
        }

        log("[SymbolTriggerDetector] 匹配结果: \(scoredMatches.count) 个")

        // 去重：每个符号只保留评分最高的一个 trigger
        var bestMatchForSymbol: [SymbolItem: (String, SearchScore)] = [:]
        for (symbol, matchedTrigger, score) in scoredMatches {
            if let existing = bestMatchForSymbol[symbol] {
                if score < existing.1 {
                    bestMatchForSymbol[symbol] = (matchedTrigger, score)
                }
            } else {
                bestMatchForSymbol[symbol] = (matchedTrigger, score)
            }
        }

        // 转换为数组并按搜索评分排序
        let results = bestMatchForSymbol.map { (symbol, triggerInfo) -> (SymbolItem, String, SearchScore) in
            (symbol, triggerInfo.0, triggerInfo.1)
        }

        // 按模糊搜索评分排序（越低越好）
        let sorted = results.sorted { $0.2 < $1.2 }

        // 只返回 (SymbolItem, String)，其中 String 是匹配到的 trigger
        return Array(sorted.prefix(5).map { ($0.0, $0.1) })
    }

    /// 清除检测结果
    func clearDetection() {
        detectedTrigger = nil
        suggestions = []
        triggerPosition = nil
    }

    /// 获取所有符号并排序（按使用频率/默认顺序）
    private func getAllSymbolsSorted() -> [SymbolItem] {
        var allSymbols: [SymbolItem] = []

        // 收集所有启用的配置中的符号
        for config in configManager.enabledConfigs {
            for menu in config.menus.sorted(by: { $0.sort < $1.sort }) {
                allSymbols.append(contentsOf: menu.symbols)
            }
        }

        // 按优先级排序：核心高频 > 其他
        let sorted = allSymbols.sorted { a, b in
            // 核心高频符号优先
            let aIsCore = a.desc.contains("核心") || a.desc.contains("高频")
            let bIsCore = b.desc.contains("核心") || b.desc.contains("高频")

            if aIsCore && !bIsCore { return true }
            if !aIsCore && bIsCore { return false }

            // 然后按描述长度排序
            return a.desc.count < b.desc.count
        }

        return sorted
    }

    /// 获取要替换的完整文本范围（包括触发前缀）
    /// 重新计算范围而不是使用缓存的 triggerPosition，确保准确性
    /// 注意：NSTextView 使用 NSString 坐标系（UTF-16），必须全程使用 NSString 操作
    func getReplacementRange(in text: String, cursorPosition: Int) -> NSRange? {
        // ⭐ 关键修复：全程使用 NSString，确保与 NSTextView 坐标系一致
        let nsString = text as NSString
        let nsLength = nsString.length

        log("[SymbolTriggerDetector] getReplacementRange - NSString长度: \(nsLength), 光标位置: \(cursorPosition)")

        // ⭐ 使用 NSString.length 而不是 String.count（emoji等字符在两者中长度不同）
        guard cursorPosition > 0 && cursorPosition <= nsLength else {
            log("[SymbolTriggerDetector] 光标位置无效: cursorPosition=\(cursorPosition), nsLength=\(nsLength)")
            return nil
        }

        // 获取光标前的文本（使用 NSString）
        let textBeforeCursor = nsString.substring(with: NSRange(location: 0, length: cursorPosition))
        let nsBeforeCursor = textBeforeCursor as NSString

        log("[SymbolTriggerDetector] 光标前文本: '\(textBeforeCursor)' (NSString长度: \(nsBeforeCursor.length))")

        // 使用 NSString 的 range 方法从后往前查找触发前缀
        let prefixRange = nsBeforeCursor.range(of: triggerPrefix, options: .backwards)

        // 检查是否找到（location != NSNotFound）
        guard prefixRange.location != NSNotFound else {
            log("[SymbolTriggerDetector] 未找到触发前缀: '\(triggerPrefix)'")
            return nil
        }

        log("[SymbolTriggerDetector] 找到触发前缀 NSRange: location=\(prefixRange.location), length=\(prefixRange.length)")

        // 计算完整的替换范围（从触发前缀开始到光标位置）
        // location: 触发前缀在整个文本中的位置
        // length: 从触发前缀到光标的长度
        let result = NSRange(location: prefixRange.location, length: cursorPosition - prefixRange.location)

        log("[SymbolTriggerDetector] 计算的替换范围: location=\(result.location), length=\(result.length)")
        log("[SymbolTriggerDetector] 将要替换的文本: '\(nsString.substring(with: result))'")

        return result
    }

    /// 插入选中的符号
    func insertSymbol(_ symbol: SymbolItem, into text: String, cursorPosition: Int) -> (newText: String, newCursorPos: Int)? {
        guard let range = getReplacementRange(in: text, cursorPosition: cursorPosition) else {
            return nil
        }

        let nsString = text as NSString

        // 确保范围有效
        guard range.location + range.length <= nsString.length else { return nil }

        // 获取配置（用于决定是否清除触发词）
        let config = configManager.enabledConfigs.first ?? .defaultConfig
        let shouldCleanTrigger = config.global.autoClean

        // ⭐ 重要：使用 NSString 长度而不是 Swift String count
        // emoji 等特殊字符在 Swift String 中算 1 个字符，但在 NSString 中可能占 2 个位置
        let symbolContentLength = (symbol.content as NSString).length
        log("[SymbolTriggerDetector] 符号内容: '\(symbol.content)', NSString长度: \(symbolContentLength), String长度: \(symbol.content.count)")

        if shouldCleanTrigger {
            // 替换整个触发词（包括前缀）
            let newText = nsString.replacingCharacters(in: range, with: symbol.content)
            let newCursorPos = range.location + symbolContentLength
            log("[SymbolTriggerDetector] 替换范围: (\(range.location), \(range.length)) -> 新光标: \(newCursorPos) = range.location(\(range.location)) + symbolLength(\(symbolContentLength))")
            log("[SymbolTriggerDetector] 新文本长度: \(newText.count) (原长度: \(nsString.length))")
            return (newText, newCursorPos)
        } else {
            // 只替换触发词部分，保留前缀
            let prefixLength = triggerPrefix.count
            let triggerRange = NSRange(location: range.location + prefixLength, length: range.length - prefixLength)
            let newText = nsString.replacingCharacters(in: triggerRange, with: symbol.content)
            let newCursorPos = triggerRange.location + symbolContentLength
            log("[SymbolTriggerDetector] 替换范围(不含前缀): (\(triggerRange.location), \(triggerRange.length)) -> 新光标: \(newCursorPos)")
            log("[SymbolTriggerDetector] 新文本长度: \(newText.count) (原长度: \(nsString.length))")
            return (newText, newCursorPos)
        }
    }

    /// 处理键盘导航（上下箭头选择）
    func moveSelection(by offset: Int) {
        guard !suggestions.isEmpty else { return }

        let currentIndex = suggestions.firstIndex { $0.content == suggestions.first?.content } ?? 0
        let newIndex = (currentIndex + offset + suggestions.count) % suggestions.count

        // 触发更新（不需要手动调用，SwiftUI会自动处理）
        // objectWillChange.send() is called automatically by @Published properties
    }
}

// MARK: - Trigger Match Result

struct TriggerMatch {
    let symbol: SymbolItem
    let matchedTrigger: String
    let matchType: MatchType

    enum MatchType {
        case exact          // 完全匹配
        case prefix         // 前缀匹配
        case fuzzy          // 模糊匹配
    }
}

// MARK: - Publisher Extensions

extension SymbolTriggerDetector {
    /// 创建触发检测的 Publisher
    func triggerPublisher(
        for textPublisher: Published<String>.Publisher,
        cursorPublisher: Published<Int>.Publisher
    ) -> AnyPublisher<Void, Never> {

        return textPublisher
            .combineLatest(cursorPublisher) { text, cursor in
                (text, cursor)
            }
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .map { [weak self] (text, cursor) in
                self?.detectTrigger(in: text, cursorPosition: cursor)
                return ()
            }
            .eraseToAnyPublisher()
    }
}
