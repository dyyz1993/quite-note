import Foundation
import AppKit

/// 启动器网页搜索预设（P1 三件套之一）
///
/// 关键词设计（IME 教训应用）：**中文词**（搜索/百度/知乎）在中文输入法下直接
/// 上屏，随时可用；英文词（gh/so/npm）需英文模式或回车上屏原始字母。
/// 用法："搜索 swift 泛型" / "百度 快捷键" → 首行出现"在 Google 搜索「…」"→ ↵ 打开浏览器
enum LauncherWebSearch {

    struct Preset {
        let keywords: [String]   // 触发词（小写比较）
        let name: String
        let makeURL: (String) -> URL
    }

    struct Query: Equatable {
        let presetName: String
        let term: String
        var url: URL
    }

    static let presets: [Preset] = [
        Preset(keywords: ["搜索", "google", "g"], name: "Google") {
            URL(string: "https://www.google.com/search?q=" + urlEncode($0))!
        },
        Preset(keywords: ["百度", "baidu", "bd"], name: "百度") {
            URL(string: "https://www.baidu.com/s?wd=" + urlEncode($0))!
        },
        Preset(keywords: ["gh", "github"], name: "GitHub") {
            URL(string: "https://github.com/search?q=" + urlEncode($0))!
        },
        Preset(keywords: ["so", "stackoverflow"], name: "StackOverflow") {
            URL(string: "https://stackoverflow.com/search?q=" + urlEncode($0))!
        },
        Preset(keywords: ["npm"], name: "npm") {
            URL(string: "https://www.npmjs.com/search?q=" + urlEncode($0))!
        },
        Preset(keywords: ["知乎", "zh", "zhihu"], name: "知乎") {
            URL(string: "https://www.zhihu.com/search?q=" + urlEncode($0))!
        },
    ]

    static func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    /// 解析："关键词 + 空格 + 词" → 查询；无空格或无词返回 nil（走普通应用搜索）
    static func parse(_ text: String) -> Query? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()
        for preset in presets {
            for keyword in preset.keywords {
                guard lowered.hasPrefix(keyword.lowercased() + " ") else { continue }
                let term = String(trimmed.dropFirst(keyword.count + 1))
                    .trimmingCharacters(in: .whitespaces)
                guard !term.isEmpty else { return nil }
                return Query(presetName: preset.name, term: term, url: preset.makeURL(term))
            }
        }
        return nil
    }
}

/// 退出运行中的应用（P1 三件套之二）："退出 微信" / "退出chrome"
@MainActor
enum LauncherQuitService {

    struct Target: Identifiable, Equatable {
        let appName: String
        let bundleID: String
        var id: String { bundleID }

        @discardableResult
        func terminate() -> Bool {
            let app = NSWorkspace.shared.runningApplications.first {
                $0.bundleIdentifier == bundleID
            }
            return app?.terminate() ?? false
        }
    }

    static let triggerKeywords = ["退出", "quit", "q"]

    /// 解析："退出 微信" → 匹配的运行中应用列表（按名称包含，封顶 5 个）
    static func parse(_ text: String) -> [Target]? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()
        var term: String?
        for keyword in triggerKeywords {
            if lowered.hasPrefix(keyword.lowercased() + " ") {
                term = String(trimmed.dropFirst(keyword.count + 1))
                    .trimmingCharacters(in: .whitespaces)
                break
            }
            if lowered == keyword.lowercased() { term = "" ; break }   // 只输"退出" → 列出全部
        }
        guard var term else { return nil }

        // 排除自己/系统后台进程；仅用户可见的常规应用
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }
        if term.isEmpty {
            return running.prefix(5).map { Target(appName: $0.localizedName ?? "?", bundleID: $0.bundleIdentifier ?? "?") }
        }
        let loweredTerm = term.lowercased()
        term = loweredTerm
        let hits = running.filter {
            ($0.localizedName ?? "").lowercased().contains(loweredTerm)
                || ($0.bundleIdentifier ?? "").lowercased().contains(loweredTerm)
        }
        return hits.prefix(5).map { Target(appName: $0.localizedName ?? "?", bundleID: $0.bundleIdentifier ?? "?") }
    }
}
