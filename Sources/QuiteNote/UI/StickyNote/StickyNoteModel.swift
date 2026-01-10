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
}
