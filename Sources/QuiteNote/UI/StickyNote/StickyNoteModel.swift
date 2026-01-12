import Foundation
import AppKit
import SwiftUI

/// 贴纸页面数据模型
struct StickyNotePage: Codable, Identifiable {
    var id = UUID()
    var content: String = ""
}

/// 贴纸数据模型
struct StickyNoteModel: Codable, Identifiable {
    var id = UUID()
    var pages: [StickyNotePage] = [StickyNotePage(), StickyNotePage(), StickyNotePage()]
    var currentPageIndex: Int = 0
    var frame: NSRect = NSRect(x: 100, y: 100, width: 300, height: 200)
    var opacity: Double = 0.95 // 默认透明度
    var syncRecordId: UUID? = nil  // 关联的记录 ID（用于双向同步）

    var currentContent: String {
        get {
            guard currentPageIndex < pages.count else { return "" }
            return pages[currentPageIndex].content
        }
        set {
            if currentPageIndex < pages.count {
                pages[currentPageIndex].content = newValue
            }
        }
    }

    /// 从第一页第一行提取项目信息（名称和颜色）
    func extractProjectInfo() -> (name: String, color: Color?) {
        guard !pages.isEmpty else { return ("", nil) }

        let firstPageContent = pages[0].content
        let lines = firstPageContent.components(separatedBy: .newlines)
        guard let firstLine = lines.first else { return ("", nil) }

        // 解析第一行，提取颜色和文本
        let colorPattern = "\\[c:(#?[0-9a-fA-F]{3,8})\\]"
        var cleanedLine = firstLine
        var firstColor: Color? = nil

        // 查找第一个颜色标记
        if let colorRegex = try? NSRegularExpression(pattern: colorPattern, options: []),
           let colorMatch = colorRegex.firstMatch(in: firstLine, options: [], range: NSRange(location: 0, length: firstLine.utf16.count)),
           let hexRange = Range(colorMatch.range(at: 1), in: firstLine) {
            let hex = String(firstLine[hexRange])
            // 移除 # 前缀
            let sanitizedHex = hex.replacingOccurrences(of: "#", with: "")
            // 使用 Color+Theme.swift 中已有的 NSColor(hex:) 扩展
            if let nsColor = NSColor(hex: sanitizedHex) {
                firstColor = Color(nsColor)
            }
            // 移除颜色标记
            cleanedLine = colorRegex.stringByReplacingMatches(in: firstLine, options: [], range: NSRange(location: 0, length: firstLine.utf16.count), withTemplate: "")
        }

        // 移除其他 Markdown 标记
        cleanedLine = cleanedLine
            .replacingOccurrences(of: "\\*\\*(.*?)\\*\\*", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "~~(.*?)~~", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "^\\s*-\\s*\\[\\s*\\]\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^\\s*-\\s*\\[x\\]\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^[☐☑]\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 限制项目名长度（最多10个字符）
        let projectName = String(cleanedLine.prefix(10))

        return (projectName, firstColor)
    }

    /// 从第一页第一行提取便签标题（用于保存到记录）
    func extractNoteTitle() -> String {
        guard !pages.isEmpty else { return "便签" }
        let lines = pages[0].content.components(separatedBy: .newlines)

        // 跳过空行和页面分隔符，找到真正的第一行内容
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // 检查是否是页面分隔符
            let separatorPattern = "^-------- Page \\d+ --------$"
            if let regex = try? NSRegularExpression(pattern: separatorPattern),
               regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)) != nil {
                continue // 跳过分隔符
            }
            // 跳过空行
            if trimmed.isEmpty {
                continue
            }
            // 找到真正的第一行内容
            return cleanTitle(trimmed)
        }

        return "便签"
    }

    private func cleanTitle(_ line: String) -> String {
        var cleaned = line

        // 移除页面分隔符 -------- Page X --------
        cleaned = cleaned.replacingOccurrences(
            of: "^-------- Page \\d+ --------\\s*",
            with: "",
            options: .regularExpression
        )

        // 移除所有颜色标记 [c:hex]text[/c] 和 [/c]
        cleaned = cleaned.replacingOccurrences(
            of: "\\[c:[^\\]]+\\]",
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: "\\[/c\\]",
            with: "",
            options: .regularExpression
        )

        // 移除 Markdown 加粗 **text**
        cleaned = cleaned.replacingOccurrences(
            of: "\\*\\*(.*?)\\*\\*",
            with: "$1",
            options: .regularExpression
        )

        // 移除 Markdown 删除线 ~~text~~
        cleaned = cleaned.replacingOccurrences(
            of: "~~(.*?)~~",
            with: "$1",
            options: .regularExpression
        )

        // 移除下划线标记 <u>text</u>
        cleaned = cleaned.replacingOccurrences(
            of: "<u>(.*?)</u>",
            with: "$1",
            options: .regularExpression
        )

        // 移除待办标记 ☐, ☑, - [ ], - [x]
        cleaned = cleaned.replacingOccurrences(
            of: "^\\s*[-\\*]?\\s*\\[\\s*[xX]?\\]\\s*",
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: "^[☐☑]\\s*",
            with: "",
            options: .regularExpression
        )

        let result = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "便签" : String(result.prefix(50))
    }
}
