import Foundation
import os.log

/// 记录的 Markdown 导出/导入编解码。纯类型，不依赖 RecordStore 与任何单例，
/// RecordStore 只负责调用与落库。解析逻辑从 RecordStore 原实现搬出（2026-11-26），
/// 导出格式没变；搬运时顺带修了三处让"导出再导入"不保真的地方——总结并进正文、
/// 正文里的 "---" 被丢、以"标签 / 关键词"开头的正文首行被当成元数据（见 parse 的注释）。
/// 仍然不保真的地方：正文里以 "## " 开头的行会被当成下一条记录的标题（格式的固有歧义）
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

                // 标签（前缀必须带到冒号：正文以"标签"两个字开头的记录，首行不是元数据）
                if line.hasPrefix("**标签**：") || line.hasPrefix("标签：") {
                    let tagsStr = line.replacingOccurrences(of: "**标签**：", with: "")
                                  .replacingOccurrences(of: "标签：", with: "")
                    tags = tagsStr.components(separatedBy: "、").map { $0.trimmingCharacters(in: .whitespaces) }
                    i += 1
                    continue
                }

                // 关键词（同上，前缀必须带到冒号）
                if line.hasPrefix("**关键词**：") || line.hasPrefix("关键词：") {
                    let keywordsStr = line.replacingOccurrences(of: "**关键词**：", with: "")
                                     .replacingOccurrences(of: "关键词：", with: "")
                    keywords = keywordsStr.components(separatedBy: "、").map { $0.trimmingCharacters(in: .whitespaces) }
                    i += 1
                    continue
                }

                // 来源
                if line.hasPrefix("**来源**：") {
                    i += 1
                    continue
                }

                // 分隔符或内容开始
                if line == "---" {
                    i += 1
                    continue
                }

                // 总结（写在正文之前的手写文件）。只剥行首的引用符和"总结："标记——
                // 标记后面才是总结正文，别把标记留在内容里
                if line.hasPrefix(">") {
                    var text = line.drop(while: { $0 == ">" || $0 == " " })
                    if text.hasPrefix("**总结**：") {
                        text = text.dropFirst("**总结**：".count)
                    } else if text.hasPrefix("总结：") {
                        text = text.dropFirst("总结：".count)
                    }
                    summary = String(text)
                    i += 1
                    continue
                }

                // 内容开始
                break
            }

            // 收集正文。导出格式是「正文 … 空行 … > **总结**：… 空行 … ---」：
            // 只剥掉节末那一条分隔线（正文里的 "---" 是内容，要留着）；正文开始后，
            // 前面隔了一个空行的 "> **总结**：" 行起到节末都是总结。旧实现把所有 "---"
            // 都丢掉、也认不出正文之后的总结行——自己导出的文件再导入，正文被改写、
            // 哈希对不上还会重复入库
            var bodyLines = i < lines.count ? Array(lines[i...]) : []
            if let lastText = bodyLines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
               bodyLines[lastText].trimmingCharacters(in: .whitespaces) == "---" {
                bodyLines.removeSubrange(lastText...)
            }
            if summary == nil,
               let marker = bodyLines.firstIndex(where: { $0.hasPrefix("> **总结**：") }),
               marker > 0, bodyLines[marker - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                var summaryLines = Array(bodyLines[marker...])
                summaryLines[0] = String(summaryLines[0].dropFirst("> **总结**：".count))
                summary = summaryLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                bodyLines.removeSubrange(marker...)
            }
            content = bodyLines.joined(separator: "\n")

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
