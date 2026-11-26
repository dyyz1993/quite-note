import Foundation
import os.log

/// 记录的 Markdown 导出/导入编解码。纯类型，不依赖 RecordStore 与任何单例，
/// RecordStore 只负责调用与落库。解析逻辑从原实现逐字搬运——宽松之处
/// （总结行解析保留 "**总结**：" 前缀残留、内容里的裸 "---" 行会被丢掉）都是现状语义，不要顺手"修"
enum RecordMarkdownCodec {
    private static let logger = Logger(subsystem: "com.quitenote.app", category: "RecordMarkdownCodec")

    /// 解析出的一条记录（字段与导出格式一一对应）
    struct ParsedRecord {
        let title: String?
        let content: String
        let summary: String?
        let tags: [String]
        let keywords: [String]
        let createdAt: Date?
    }

    struct ParseResult {
        /// 去重后待落库的记录
        let imported: [ParsedRecord]
        /// 因内容哈希已存在而跳过的条数
        let skippedCount: Int
    }

    /// 内容哈希（导入去重用，与 ClipboardService / addImportedRecord 保持一致）
    static func contentHash(_ content: String) -> String {
        let data = Data(content.utf8)
        return data.reduce(into: "") { $0 += String(format: "%02x", $1) }
    }

    // MARK: - 导出

    static func export(_ records: [Record]) -> String {
        let dateFormatter = ISO8601DateFormatter()
        var md = "# QuiteNote 导出\n\n"
        for r in records.reversed() {
            // 标题
            if let t = r.title {
                md += "## \(t)\n\n"
            } else {
                md += "## 无标题\n\n"
            }

            // 元数据
            md += "**创建时间**：\(dateFormatter.string(from: r.createdAt))\n\n"

            // 标签
            if !r.tags.isEmpty {
                md += "**标签**：\(r.tags.joined(separator: "、"))\n\n"
            }

            // 关键词
            if !r.keywords.isEmpty {
                md += "**关键词**：\(r.keywords.joined(separator: "、"))\n\n"
            }

            // 来源信息
            if let source = r.sourceApp {
                md += "**来源**：\(source)"
                if let url = r.sourceUrl {
                    md += " ([\(url)](\(url)))"
                }
                md += "\n\n"
            }

            // 内容
            md += "\(r.content)\n\n"

            // 总结
            if let s = r.summary {
                md += "> **总结**：\(s)\n\n"
            }

            md += "---\n\n"
        }
        return md
    }

    // MARK: - 导入

    /// 解析 Markdown。existingHashes 用于内容哈希去重（已存在的条目计入 skippedCount）
    static func parse(_ markdown: String, skippingExistingHashes existingHashes: Set<String>) -> ParseResult {
        var imported: [ParsedRecord] = []
        var skippedCount = 0
        let sections = markdown.components(separatedBy: "\n## ")

        for section in sections {
            let trimmed = section.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            // 解析各个部分
            var title: String?
            var createdAt: Date?
            var tags: [String] = []
            var keywords: [String] = []
            var content: String = ""
            var summary: String?

            let lines = trimmed.components(separatedBy: "\n")
            var i = 0

            // 第一行是标题
            if i < lines.count {
                let firstLine = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if !firstLine.isEmpty && !firstLine.hasPrefix("---") {
                    title = firstLine == "无标题" ? nil : firstLine
                }
                i += 1
            }

            // 解析元数据
            while i < lines.count {
                let line = lines[i].trimmingCharacters(in: .whitespaces)

                // 空行跳过
                if line.isEmpty {
                    i += 1
                    continue
                }

                // 创建时间
                if line.hasPrefix("**创建时间**") || line.hasPrefix("创建时间：") {
                    let dateStr = line.replacingOccurrences(of: "**创建时间**：", with: "")
                                   .replacingOccurrences(of: "创建时间：", with: "")
                    // 尝试多种日期格式
                    let dateFormatter1 = ISO8601DateFormatter()
                    var date = dateFormatter1.date(from: dateStr)

                    if date == nil {
                        // 尝试其他格式
                        let dateFormatter2 = DateFormatter()
                        dateFormatter2.dateFormat = "yyyy-MM-dd HH:mm:ss"
                        date = dateFormatter2.date(from: dateStr)
                    }

                    if date == nil {
                        let dateFormatter3 = DateFormatter()
                        dateFormatter3.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                        date = dateFormatter3.date(from: dateStr)
                    }

                    createdAt = date ?? Date()
                    logger.info("导入记录日期解析: '\(dateStr)' -> \(createdAt ?? Date())")
                    i += 1
                    continue
                }

                // 标签
                if line.hasPrefix("**标签**") || line.hasPrefix("标签") {
                    let tagsStr = line.replacingOccurrences(of: "**标签**：", with: "")
                                  .replacingOccurrences(of: "标签：", with: "")
                    tags = tagsStr.components(separatedBy: "、").map { $0.trimmingCharacters(in: .whitespaces) }
                    i += 1
                    continue
                }

                // 关键词
                if line.hasPrefix("**关键词**") || line.hasPrefix("关键词") {
                    let keywordsStr = line.replacingOccurrences(of: "**关键词**：", with: "")
                                     .replacingOccurrences(of: "关键词：", with: "")
                    keywords = keywordsStr.components(separatedBy: "、").map { $0.trimmingCharacters(in: .whitespaces) }
                    i += 1
                    continue
                }

                // 来源
                if line.hasPrefix("**来源**") {
                    i += 1
                    continue
                }

                // 分隔符或内容开始
                if line == "---" {
                    i += 1
                    continue
                }

                // 总结
                if line.hasPrefix(">") {
                    summary = line.replacingOccurrences(of: "> ", with: "")
                               .replacingOccurrences(of: ">**总结**：", with: "")
                               .replacingOccurrences(of: "> 总结：", with: "")
                    i += 1
                    continue
                }

                // 内容开始
                break
            }

            // 收集剩余内容
            while i < lines.count {
                let line = lines[i]
                if line != "---" {
                    content += line + "\n"
                }
                i += 1
            }

            // 去重后待落库
            let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedContent.isEmpty {
                let hash = contentHash(trimmedContent)

                if existingHashes.contains(hash) {
                    skippedCount += 1
                } else {
                    imported.append(ParsedRecord(
                        title: title,
                        content: trimmedContent,
                        summary: summary,
                        tags: tags,
                        keywords: keywords,
                        createdAt: createdAt
                    ))
                }
            }
        }

        return ParseResult(imported: imported, skippedCount: skippedCount)
    }
}
