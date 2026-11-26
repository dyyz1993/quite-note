import XCTest
@testable import QuiteNote

/// RecordMarkdownCodec：导出 → 导入往返、三种日期格式、畸形输入不崩。
/// 解析逻辑是从 RecordStore 原实现逐字搬运的现状语义，这里把行为钉住
final class RecordMarkdownCodecTests: XCTestCase {

    // MARK: - 往返恒等

    func testExportImportRoundTripsCoreFields() {
        let record = QuiteNote.Record(
            id: UUID(),
            title: "会议笔记",
            content: "第一行\n第二行",
            createdAt: Date(timeIntervalSince1970: 1_742_000_000),
            hash: "rt-1",
            tags: ["工作", "会议"],
            keywords: ["关键词A", "关键词B"],
            sourceApp: "QuiteNote",
            sourceUrl: "https://example.com",
            type: .text
        )

        let markdown = RecordMarkdownCodec.export([record])
        let result = RecordMarkdownCodec.parse(markdown, skippingExistingHashes: [])

        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(result.imported.count, 1)
        let parsed = result.imported[0]
        XCTAssertEqual(parsed.title, "会议笔记")
        XCTAssertEqual(parsed.content, "第一行\n第二行")
        XCTAssertEqual(parsed.tags, ["工作", "会议"])
        XCTAssertEqual(parsed.keywords, ["关键词A", "关键词B"])
        XCTAssertEqual(parsed.createdAt, record.createdAt, "ISO8601 日期要精确往返")
    }

    /// 现状语义（搬运钉死）：导出把"总结"写在正文之后，而解析器的元数据循环
    /// 在第一行正文就 break——导出的总结回不到 summary 字段，会并进正文
    func testExportedSummaryLandsInsideContentOnImport() {
        let record = QuiteNote.Record(
            id: UUID(),
            content: "正文",
            createdAt: Date(timeIntervalSince1970: 1_742_000_000),
            hash: "rt-summary",
            summary: "要点总结"
        )

        let markdown = RecordMarkdownCodec.export([record])
        let result = RecordMarkdownCodec.parse(markdown, skippingExistingHashes: [])

        XCTAssertEqual(result.imported.count, 1)
        XCTAssertNil(result.imported[0].summary, "导出的总结不会解析回 summary 字段（现状如此）")
        XCTAssertTrue(result.imported[0].content.contains("> **总结**：要点总结"), "总结行并进正文")

        // 只有总结写在元数据区（正文之前）的手写文件才解析得出 summary，
        // 且 "> **总结**：" 前缀处理有残留——同样是现状
        let handwritten = "手写记录\n> **总结**：手写总结\n\n正文在此"
        let parsedHandwritten = RecordMarkdownCodec.parse(handwritten, skippingExistingHashes: [])
        XCTAssertEqual(parsedHandwritten.imported[0].summary, "**总结**：手写总结")
    }

    /// 导出逆序（旧记录在前），导入保持文件顺序；无标题记录往返为 nil 标题
    func testRoundTripOrderAndUntitledRecords() {
        let older = QuiteNote.Record(id: UUID(), content: "旧内容", createdAt: Date(timeIntervalSince1970: 1_000), hash: "rt-old")
        let newer = QuiteNote.Record(id: UUID(), title: nil, content: "新内容", createdAt: Date(timeIntervalSince1970: 2_000), hash: "rt-new")

        let markdown = RecordMarkdownCodec.export([older, newer])
        XCTAssertTrue(markdown.contains("## 无标题"), "无标题记录导出为「无标题」占位")

        let result = RecordMarkdownCodec.parse(markdown, skippingExistingHashes: [])
        XCTAssertEqual(result.imported.map(\.content), ["新内容", "旧内容"], "导出逆序、导入保持文件顺序")
        XCTAssertNil(result.imported[0].title, "「无标题」解析回 nil")
    }

    func testParseSkipsRecordsAlreadyPresentByContentHash() {
        let record = QuiteNote.Record(id: UUID(), content: "已存在的正文", createdAt: Date(), hash: "dup")
        let markdown = RecordMarkdownCodec.export([record])

        let result = RecordMarkdownCodec.parse(markdown, skippingExistingHashes: [RecordMarkdownCodec.contentHash("已存在的正文")])
        XCTAssertTrue(result.imported.isEmpty)
        XCTAssertEqual(result.skippedCount, 1)
    }

    // MARK: - 三种日期格式
    // 注意：解析器的第一行固定当标题，日期行必须跟在标题之后

    /// 导出格式（ISO8601）
    func testParsesISO8601Date() {
        let expected = ISO8601DateFormatter().date(from: "2026-01-02T03:04:05Z")
        let parsed = RecordMarkdownCodec.parse("标题\n**创建时间**：2026-01-02T03:04:05Z\n\n正文", skippingExistingHashes: [])
        XCTAssertEqual(parsed.imported.count, 1)
        XCTAssertEqual(parsed.imported[0].createdAt, expected)
    }

    /// 手写/历史文件的空格分隔格式
    func testParsesSpaceSeparatedDate() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let expected = formatter.date(from: "2025-06-07 08:09:10")
        XCTAssertNotNil(expected)

        let parsed = RecordMarkdownCodec.parse("标题\n**创建时间**：2025-06-07 08:09:10\n\n正文", skippingExistingHashes: [])
        XCTAssertEqual(parsed.imported.count, 1)
        XCTAssertEqual(parsed.imported[0].createdAt, expected)
    }

    /// 带数字时区偏移的格式（ISO8601DateFormatter 不认，落到第三种格式）
    func testParsesNumericTimezoneOffsetDate() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        let expected = formatter.date(from: "2025-06-07T08:09:10+0800")
        XCTAssertNotNil(expected)

        let parsed = RecordMarkdownCodec.parse("标题\n**创建时间**：2025-06-07T08:09:10+0800\n\n正文", skippingExistingHashes: [])
        XCTAssertEqual(parsed.imported.count, 1)
        XCTAssertEqual(parsed.imported[0].createdAt, expected)
    }

    /// 完全不可解析的日期回退到当前时间（不崩、不丢记录）
    func testUnparseableDateFallsBackToNow() {
        let before = Date()
        let parsed = RecordMarkdownCodec.parse("标题\n**创建时间**：不是日期的字符串\n\n正文", skippingExistingHashes: [])
        let after = Date()
        XCTAssertEqual(parsed.imported.count, 1)
        if let createdAt = parsed.imported[0].createdAt {
            XCTAssertTrue((before...after).contains(createdAt), "解析失败应回退到当前时间")
        } else {
            XCTFail("回退后 createdAt 不应为 nil")
        }
    }

    // MARK: - 畸形输入

    func testMalformedInputsDoNotCrashAndImportNothing() {
        for markdown in ["", "   \n  ", "---", "---\n\n---", "# QuiteNote 导出"] {
            let result = RecordMarkdownCodec.parse(markdown, skippingExistingHashes: [])
            XCTAssertTrue(result.imported.isEmpty, "'\(markdown)' 不应产出记录")
        }
    }

    /// 无元数据的纯文本段落：首行当标题，其余当正文
    func testPlainSectionBecomesTitleAndContent() {
        let parsed = RecordMarkdownCodec.parse("随手记\n没有元数据的正文", skippingExistingHashes: [])
        XCTAssertEqual(parsed.imported.count, 1)
        XCTAssertEqual(parsed.imported[0].title, "随手记")
        XCTAssertEqual(parsed.imported[0].content, "没有元数据的正文")
        XCTAssertNil(parsed.imported[0].createdAt)
    }
}
