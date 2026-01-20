import Foundation
import Yams

// MARK: - Symbol Configuration Data Models

/// 符号配置元数据
struct SymbolMetadata: Codable, Equatable {
    var name: String
    let icon: String
    var priority: Int
    let enabled: Bool

    var iconDisplay: String {
        enabled ? icon : "🚫"
    }
}

/// 全局配置
struct SymbolGlobalConfig: Codable, Equatable {
    let triggerPrefix: String
    let autoHide: Bool
    let autoClean: Bool
    let panelPosition: String
    let panelWidth: String

    static let `default` = SymbolGlobalConfig(
        triggerPrefix: ":/",
        autoHide: true,
        autoClean: true,
        panelPosition: "cursor_bottom",
        panelWidth: "auto"
    )
}

/// 单个符号项
struct SymbolItem: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    let triggers: [String]
    let content: String
    let desc: String

    init(triggers: [String], content: String, desc: String) {
        self.id = UUID()
        self.triggers = triggers
        self.content = content
        self.desc = desc
    }

    /// 检查是否匹配触发词（模糊匹配）
    func matches(_ trigger: String) -> Bool {
        let normalizedTrigger = trigger.lowercased().trimmingCharacters(in: .whitespaces)
        return triggers.contains { $0.lowercased() == normalizedTrigger }
    }

    /// 获取主要触发词（第一个）
    var primaryTrigger: String {
        triggers.first ?? ""
    }
}

/// 符号菜单分类
struct SymbolMenu: Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let sort: Int
    let icon: String?
    let symbols: [SymbolItem]

    init(title: String, sort: Int, icon: String? = nil, symbols: [SymbolItem]) {
        self.id = UUID()
        self.title = title
        self.sort = sort
        self.icon = icon
        self.symbols = symbols
    }

    /// 获取所有触发词（用于快速索引）
    var allTriggers: [String: SymbolItem] {
        var result: [String: SymbolItem] = [:]
        for symbol in symbols {
            for trigger in symbol.triggers {
                result[trigger.lowercased()] = symbol
            }
        }
        return result
    }
}

/// 完整的符号配置
struct SymbolConfig: Codable, Equatable, Identifiable {
    let id: UUID
    let metadata: SymbolMetadata
    let global: SymbolGlobalConfig
    let menus: [SymbolMenu]

    init(
        id: UUID = UUID(),
        metadata: SymbolMetadata,
        global: SymbolGlobalConfig = .default,
        menus: [SymbolMenu]
    ) {
        self.id = id
        self.metadata = metadata
        self.global = global
        self.menus = menus
    }

    /// 获取所有触发词到符号的映射
    var triggerMap: [String: SymbolItem] {
        var map: [String: SymbolItem] = [:]
        for menu in menus {
            for (trigger, symbol) in menu.allTriggers {
                map[trigger] = symbol
            }
        }
        return map
    }

    /// 搜索匹配的符号
    func search(query: String) -> [SymbolItem] {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !normalizedQuery.isEmpty else { return [] }

        var results: Set<SymbolItem> = []

        for menu in menus {
            for symbol in menu.symbols {
                // 匹配触发词
                if symbol.triggers.contains(where: { $0.lowercased().contains(normalizedQuery) }) {
                    results.insert(symbol)
                }
                // 匹配描述
                if symbol.desc.lowercased().contains(normalizedQuery) {
                    results.insert(symbol)
                }
                // 匹配内容
                if symbol.content.lowercased().contains(normalizedQuery) {
                    results.insert(symbol)
                }
            }
        }

        return Array(results)
    }

    /// 检查触发词是否冲突
    func hasConflicts() -> [String: [SymbolItem]] {
        var conflicts: [String: [SymbolItem]] = [:]
        var triggerUsage: [String: [SymbolItem]] = [:]

        for menu in menus {
            for symbol in menu.symbols {
                for trigger in symbol.triggers {
                    let normalized = trigger.lowercased()
                    if triggerUsage[normalized] == nil {
                        triggerUsage[normalized] = []
                    }
                    triggerUsage[normalized]?.append(symbol)
                }
            }
        }

        for (trigger, symbols) in triggerUsage where symbols.count > 1 {
            conflicts[trigger] = symbols
        }

        return conflicts
    }

    /// 统计信息
    var stats: ConfigStats {
        let totalMenus = menus.count
        let totalSymbols = menus.reduce(0) { $0 + $1.symbols.count }
        let totalTriggers = menus.reduce(0) { $0 + $1.symbols.reduce(0) { $0 + $1.triggers.count } }

        return ConfigStats(
            menuCount: totalMenus,
            symbolCount: totalSymbols,
            triggerCount: totalTriggers,
            conflictCount: hasConflicts().count
        )
    }
}

/// 配置统计信息
struct ConfigStats {
    let menuCount: Int
    let symbolCount: Int
    let triggerCount: Int
    let conflictCount: Int
}

// MARK: - YAML Encoding/Decoding Helpers

extension SymbolConfig {
    /// 从 YAML 字符串解析配置
    static func from(yaml: String) throws -> SymbolConfig {
        guard let data = yaml.data(using: .utf8) else {
            throw SymbolConfigError.invalidEncoding
        }
        return try from(yamlData: data)
    }

    /// 从 YAML 数据解析配置
    static func from(yamlData: Data) throws -> SymbolConfig {
        guard let yamlString = String(data: yamlData, encoding: .utf8) else {
            print("[SymbolConfig.from] ❌ 无法将数据转换为 UTF-8 字符串")
            throw SymbolConfigError.invalidEncoding
        }

        print("[SymbolConfig.from] 开始解析 YAML，长度: \(yamlString.count)")

        // 使用 Yams 库解析 YAML
        guard let yamlDict = try Yams.load(yaml: yamlString) as? [String: Any] else {
            print("[SymbolConfig.from] ❌ Yams 解析失败")
            throw SymbolConfigError.invalidFormat
        }

        print("[SymbolConfig.from] ✅ Yams 解析成功，keys: \(yamlDict.keys)")

        return try parse(from: yamlDict)
    }

    /// 解析配置字典
    internal static func parse(from dict: [String: Any]) throws -> SymbolConfig {
        print("[SymbolConfig.parse] Starting to parse config dict")

        guard let metadataDict = dict["metadata"] as? [String: Any] else {
            print("[SymbolConfig.parse] ❌ Missing metadata")
            throw SymbolConfigError.missingMetadata
        }

        print("[SymbolConfig.parse] ✅ Found metadata")
        let metadata = SymbolMetadata(
            name: (metadataDict["name"] as? String) ?? "未命名配置",
            icon: (metadataDict["icon"] as? String) ?? "🔣",
            priority: (metadataDict["priority"] as? Int) ?? 1,
            enabled: (metadataDict["enabled"] as? Bool) ?? true
        )
        print("[SymbolConfig.parse] Metadata: \(metadata.name), enabled: \(metadata.enabled)")

        var globalConfig = SymbolGlobalConfig.default
        if let globalDict = dict["global"] as? [String: Any] {
            globalConfig = SymbolGlobalConfig(
                triggerPrefix: (globalDict["trigger_prefix"] as? String) ?? ":/",
                autoHide: (globalDict["auto_hide"] as? Bool) ?? true,
                autoClean: (globalDict["auto_clean"] as? Bool) ?? true,
                panelPosition: (globalDict["panel_position"] as? String) ?? "cursor_bottom",
                panelWidth: (globalDict["panel_width"] as? String) ?? "auto"
            )
        }
        print("[SymbolConfig.parse] ✅ Global config parsed")

        guard let menusArray = dict["symbol_menus"] as? [[String: Any]] else {
            print("[SymbolConfig.parse] ❌ Missing or invalid symbol_menus")
            print("[SymbolConfig.parse]   symbol_menus type: \(type(of: dict["symbol_menus"] ?? "nil"))")
            throw SymbolConfigError.missingMenus
        }

        print("[SymbolConfig.parse] ✅ Found \(menusArray.count) menus")

        let menus = try menusArray.map { menuDict -> SymbolMenu in
            guard let title = menuDict["title"] as? String else {
                print("[SymbolConfig.parse] ❌ Menu missing title")
                throw SymbolConfigError.invalidMenuFormat
            }

            let sort = (menuDict["sort"] as? Int) ?? 0
            let icon = menuDict["icon"] as? String

            print("[SymbolConfig.parse]   Parsing menu: \(title), icon: \(icon ?? "nil"), sort: \(sort)")

            guard let symbolsArray = menuDict["symbols"] as? [[String: Any]] else {
                print("[SymbolConfig.parse] ❌ Menu \(title) missing symbols array")
                throw SymbolConfigError.invalidMenuFormat
            }

            print("[SymbolConfig.parse]     Found \(symbolsArray.count) symbols")

            let symbols = try symbolsArray.map { symbolDict -> SymbolItem in
                print("[SymbolConfig.parse]       Symbol trigger type: \(type(of: symbolDict["trigger"] ?? "nil"))")

                // Try to cast trigger to [String]
                guard let triggers = symbolDict["trigger"] as? [String] else {
                    // If that fails, try to handle Yams specific types
                    if let anySequence = symbolDict["trigger"] {
                        print("[SymbolConfig.parse]       Trigger is not [String], trying to convert...")
                        print("[SymbolConfig.parse]       Actual type: \(type(of: anySequence))")
                    }
                    throw SymbolConfigError.invalidSymbolFormat
                }

                guard let content = symbolDict["content"] as? String,
                      let desc = symbolDict["desc"] as? String else {
                    throw SymbolConfigError.invalidSymbolFormat
                }
                return SymbolItem(triggers: triggers, content: content, desc: desc)
            }

            return SymbolMenu(title: title, sort: sort, icon: icon, symbols: symbols)
        }

        print("[SymbolConfig.parse] ✅ Successfully parsed \(menus.count) menus")

        // 详细输出每个菜单的信息
        for (index, menu) in menus.enumerated() {
            print("[SymbolConfig.parse]   Menu[\(index)]: \(menu.title) | icon: \(menu.icon ?? "nil") | \(menu.symbols.count) symbols")
        }

        return SymbolConfig(metadata: metadata, global: globalConfig, menus: menus)
    }

    /// 转换为 YAML 字符串
    func toYaml() -> String {
        var lines: [String] = []

        // Metadata
        lines.append("metadata:")
        lines.append("  name: \"\(metadata.name)\"")
        lines.append("  icon: \"\(metadata.icon)\"")
        lines.append("  priority: \(metadata.priority)")
        lines.append("  enabled: \(metadata.enabled)")
        lines.append("")

        // Global config
        lines.append("global:")
        lines.append("  trigger_prefix: \"\(global.triggerPrefix)\"")
        lines.append("  auto_hide: \(global.autoHide)")
        lines.append("  auto_clean: \(global.autoClean)")
        lines.append("  panel_position: \"\(global.panelPosition)\"")
        lines.append("  panel_width: \"\(global.panelWidth)\"")
        lines.append("")

        // Symbol menus
        lines.append("symbol_menus:")
        for menu in menus.sorted(by: { $0.sort < $1.sort }) {
            lines.append("  - title: \"\(menu.title)\"")
            lines.append("    sort: \(menu.sort)")
            if let icon = menu.icon {
                lines.append("    icon: \"\(icon)\"")
            }
            lines.append("    symbols:")
            for symbol in menu.symbols {
                let triggers = symbol.triggers.map { "\"\($0)\"" }.joined(separator: ", ")
                lines.append("      - trigger: [\(triggers)]")
                lines.append("        content: \"\(symbol.content)\"")
                lines.append("        desc: \"\(symbol.desc)\"")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// 转换为字典格式（用于 plist 保存）
    func toDict() -> [String: Any] {
        let metadataDict: [String: Any] = [
            "name": metadata.name,
            "icon": metadata.icon,
            "priority": metadata.priority,
            "enabled": metadata.enabled
        ]

        let globalDict: [String: Any] = [
            "trigger_prefix": global.triggerPrefix,
            "auto_hide": global.autoHide,
            "auto_clean": global.autoClean,
            "panel_position": global.panelPosition,
            "panel_width": global.panelWidth
        ]

        let menusArray = menus.sorted(by: { $0.sort < $1.sort }).map { menu -> [String: Any] in
            var dict: [String: Any] = [
                "title": menu.title,
                "sort": menu.sort
            ]

            if let icon = menu.icon {
                dict["icon"] = icon
            }

            let symbolsArray = menu.symbols.map { symbol -> [String: Any] in
                return [
                    "trigger": symbol.triggers,
                    "content": symbol.content,
                    "desc": symbol.desc
                ]
            }

            dict["symbols"] = symbolsArray
            return dict
        }

        return [
            "metadata": metadataDict,
            "global": globalDict,
            "symbol_menus": menusArray
        ]
    }
}

// MARK: - Errors

enum SymbolConfigError: LocalizedError {
    case invalidEncoding
    case invalidFormat
    case missingMetadata
    case missingMenus
    case invalidMenuFormat
    case invalidSymbolFormat

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "配置编码无效"
        case .invalidFormat:
            return "配置格式无效"
        case .missingMetadata:
            return "缺少元数据"
        case .missingMenus:
            return "缺少符号菜单"
        case .invalidMenuFormat:
            return "菜单格式无效"
        case .invalidSymbolFormat:
            return "符号格式无效"
        }
    }
}

// MARK: - Default Configurations

extension SymbolConfig {
    /// 默认配置示例（中文触发词）
    static let defaultConfig = SymbolConfig(
        metadata: SymbolMetadata(
            name: "默认符号库",
            icon: "🔣",
            priority: 1,
            enabled: true
        ),
        global: .default,
        menus: [
            SymbolMenu(
                title: "核心高频",
                sort: 1,
                icon: "⭐",
                symbols: [
                    SymbolItem(triggers: ["bug", "err", "错误"], content: "🐛", desc: "BUG/程序错误/异常"),
                    SymbolItem(triggers: ["gj", "gaijin", "改进", "fix"], content: "🔧", desc: "改进/修复/逻辑调整"),
                    SymbolItem(triggers: ["yh", "youhua", "优化", "opt"], content: "⚡", desc: "性能优化/效率提升"),
                    SymbolItem(triggers: ["yq", "yuqi", "预期", "goal"], content: "🎯", desc: "预期目标/指标达成"),
                    SymbolItem(triggers: ["ok", "完成", "通过", "yes"], content: "✅", desc: "完成/测试通过/验收"),
                    SymbolItem(triggers: ["warn", "risk", "风险", "警告"], content: "⚠️", desc: "风险提示/边界条件")
                ]
            ),
            SymbolMenu(
                title: "开发技术",
                sort: 2,
                icon: "👨‍💻",
                symbols: [
                    SymbolItem(triggers: ["dev", "开发", "code"], content: "👨‍💻", desc: "开发/编码/全栈实现"),
                    SymbolItem(triggers: ["test", "测试"], content: "🧪", desc: "测试验证/单元测试"),
                    SymbolItem(triggers: ["deploy", "上线"], content: "🚀", desc: "部署上线/发布"),
                    SymbolItem(triggers: ["api", "接口"], content: "🔌", desc: "接口集成/第三方API"),
                    SymbolItem(triggers: ["log", "日志"], content: "📜", desc: "日志记录/审计"),
                    SymbolItem(triggers: ["arrow", "箭头", "→"], content: "→", desc: "流程推进/逻辑指向")
                ]
            ),
            SymbolMenu(
                title: "产品规划",
                sort: 3,
                icon: "📋",
                symbols: [
                    SymbolItem(triggers: ["req", "需求"], content: "📋", desc: "需求清单/需求文档"),
                    SymbolItem(triggers: ["proto", "原型"], content: "📱", desc: "产品原型/交互设计"),
                    SymbolItem(triggers: ["data", "指标"], content: "📊", desc: "产品指标/数据报表"),
                    SymbolItem(triggers: ["flow", "流程"], content: "🔗", desc: "业务流程/用户旅程")
                ]
            )
        ]
    )

    /// 英文触发词配置示例
    static let englishConfig = SymbolConfig(
        metadata: SymbolMetadata(
            name: "English Symbols",
            icon: "🌐",
            priority: 2,
            enabled: true
        ),
        global: .default,
        menus: [
            SymbolMenu(
                title: "Status",
                sort: 1,
                icon: "📌",
                symbols: [
                    SymbolItem(triggers: ["todo", "task"], content: "📝", desc: "To-do / Task"),
                    SymbolItem(triggers: ["done", "complete"], content: "✅", desc: "Done / Complete"),
                    SymbolItem(triggers: ["wip", "progress"], content: "🔄", desc: "Work in Progress"),
                    SymbolItem(triggers: ["block", "blocked"], content: "🚫", desc: "Blocked"),
                    SymbolItem(triggers: ["review", "pr"], content: "👀", desc: "Need Review"),
                    SymbolItem(triggers: ["approved"], content: "👍", desc: "Approved"),
                    SymbolItem(triggers: ["rejected"], content: "❌", desc: "Rejected"),
                    SymbolItem(triggers: ["skipped"], content: "⏭️", desc: "Skipped")
                ]
            ),
            SymbolMenu(
                title: "Priority",
                sort: 2,
                icon: "🚨",
                symbols: [
                    SymbolItem(triggers: ["critical", "urgent"], content: "🔴", desc: "Critical"),
                    SymbolItem(triggers: ["high", "important"], content: "🟠", desc: "High Priority"),
                    SymbolItem(triggers: ["medium", "normal"], content: "🟡", desc: "Medium Priority"),
                    SymbolItem(triggers: ["low"], content: "🟢", desc: "Low Priority"),
                    SymbolItem(triggers: ["info"], content: "🔵", desc: "Information")
                ]
            ),
            SymbolMenu(
                title: "Development",
                sort: 3,
                icon: "💻",
                symbols: [
                    SymbolItem(triggers: ["bug", "issue"], content: "🐛", desc: "Bug Report"),
                    SymbolItem(triggers: ["fix", "patch"], content: "🔧", desc: "Fix / Patch"),
                    SymbolItem(triggers: ["feat", "feature"], content: "✨", desc: "New Feature"),
                    SymbolItem(triggers: ["refactor"], content: "♻️", desc: "Refactor"),
                    SymbolItem(triggers: ["perf", "performance"], content: "⚡", desc: "Performance"),
                    SymbolItem(triggers: ["test"], content: "🧪", desc: "Tests"),
                    SymbolItem(triggers: ["docs", "doc"], content: "📚", desc: "Documentation"),
                    SymbolItem(triggers: ["style"], content: "💄", desc: "Style / UI"),
                    SymbolItem(triggers: ["chore"], content: "🔨", desc: "Chore"),
                    SymbolItem(triggers: ["ci", "build"], content: "🤖", desc: "CI / Build"),
                    SymbolItem(triggers: ["deploy", "release"], content: "🚀", desc: "Deploy / Release")
                ]
            ),
            SymbolMenu(
                title: "Communication",
                sort: 4,
                icon: "💬",
                symbols: [
                    SymbolItem(triggers: ["question", "help", "q"], content: "❓", desc: "Question"),
                    SymbolItem(triggers: ["idea", "suggest"], content: "💡", desc: "Idea / Suggestion"),
                    SymbolItem(triggers: ["thought", "thinking"], content: "🤔", desc: "Thinking / Consider"),
                    SymbolItem(triggers: ["note", "memo"], content: "📝", desc: "Note"),
                    SymbolItem(triggers: ["warning", "warn"], content: "⚠️", desc: "Warning"),
                    SymbolItem(triggers: ["error"], content: "❌", desc: "Error"),
                    SymbolItem(triggers: ["success"], content: "✅", desc: "Success"),
                    SymbolItem(triggers: ["tip", "hint"], content: "💡", desc: "Tip / Hint"),
                    SymbolItem(triggers: ["example"], content: "💬", desc: "Example"),
                    SymbolItem(triggers: ["quote"], content: "💭", desc: "Quote")
                ]
            ),
            SymbolMenu(
                title: "Arrows",
                sort: 5,
                icon: "➡️",
                symbols: [
                    SymbolItem(triggers: ["right", "->"], content: "→", desc: "Right Arrow"),
                    SymbolItem(triggers: ["left", "<-"], content: "←", desc: "Left Arrow"),
                    SymbolItem(triggers: ["up", "^"], content: "↑", desc: "Up Arrow"),
                    SymbolItem(triggers: ["down", "v"], content: "↓", desc: "Down Arrow"),
                    SymbolItem(triggers: ["double-right", "=>"], content: "⇒", desc: "Double Right"),
                    SymbolItem(triggers: ["double-left", "<="], content: "⇐", desc: "Double Left"),
                    SymbolItem(triggers: ["return"], content: "↩️", desc: "Return"),
                    SymbolItem(triggers: ["enter"], content: "⤵️", desc: "Enter")
                ]
            )
        ]
    )
}
