import Foundation
import AppKit
import SwiftUI

/// 宽容取值：缺键、值为 null、类型不符都归为 nil。
/// decodeIfPresent 对"键存在但值为 null"会抛错，try? 把这种情况一并算作缺失
private func lenientValue<T: Decodable, K: CodingKey>(_ type: T.Type, _ key: K, in container: KeyedDecodingContainer<K>) -> T? {
    try? container.decodeIfPresent(type, forKey: key)
}

/// 贴纸页面数据模型
struct StickyNotePage: Codable, Identifiable, Equatable {
    var id = UUID()
    var content: String = ""

    init(id: UUID = UUID(), content: String = "") {
        self.id = id
        self.content = content
    }

    /// 容错解码。合成 Codable 对带默认值的非可选字段要求键必须存在，少一个键就
    /// 整份数据解码失败；这里缺键、为 null、类型不符都回落到默认值
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = lenientValue(UUID.self, .id, in: container) ?? UUID()
        content = lenientValue(String.self, .content, in: container) ?? ""
    }
}

/// 贴纸数据模型
struct StickyNoteModel: Codable, Identifiable, Equatable {
    static let defaultFrame = NSRect(x: 100, y: 100, width: 300, height: 200)

    var id = UUID()
    var pages: [StickyNotePage] = [StickyNotePage(), StickyNotePage(), StickyNotePage()]
    var currentPageIndex: Int = 0
    var frame: NSRect = StickyNoteModel.defaultFrame
    var opacity: Double = 0.95 // 默认透明度
    var syncRecordId: UUID? = nil  // 关联的记录 ID（用于双向同步）
    var pinnedToAllSpaces: Bool = false  // 是否在所有 Space 显示（四指滑动切换的虚拟桌面）
    var color: StickyNoteColor = .blue  // 便签底色

    init(frame: NSRect = StickyNoteModel.defaultFrame, pages: [StickyNotePage]? = nil, syncRecordId: UUID? = nil, color: StickyNoteColor = .blue) {
        self.frame = frame
        self.pages = pages ?? [StickyNotePage(), StickyNotePage(), StickyNotePage()]
        self.syncRecordId = syncRecordId
        self.color = color
    }

    /// 容错解码，理由同 StickyNotePage。便利贴数据整份存在一个键里，解码失败后
    /// notes 为空，下一次保存就会用空数组把原数据覆盖掉，所以字段务必宽容
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = lenientValue(UUID.self, .id, in: container) ?? UUID()
        pages = lenientValue([StickyNotePage].self, .pages, in: container) ?? []
        currentPageIndex = lenientValue(Int.self, .currentPageIndex, in: container) ?? 0
        frame = lenientValue(NSRect.self, .frame, in: container) ?? Self.defaultFrame
        opacity = lenientValue(Double.self, .opacity, in: container) ?? 0.95
        syncRecordId = lenientValue(UUID.self, .syncRecordId, in: container)
        pinnedToAllSpaces = lenientValue(Bool.self, .pinnedToAllSpaces, in: container) ?? false
        color = lenientValue(StickyNoteColor.self, .color, in: container) ?? .blue
        normalize()
    }

    /// 解码结果收敛到合法状态：空页表、越界的当前页、NaN 或零尺寸的 frame 都会
    /// 让窗口创建出问题
    private mutating func normalize() {
        if pages.isEmpty { pages = [StickyNotePage()] }
        if !pages.indices.contains(currentPageIndex) { currentPageIndex = 0 }
        if !frame.origin.x.isFinite || !frame.origin.y.isFinite
            || !frame.size.width.isFinite || !frame.size.height.isFinite
            || frame.width < 1 || frame.height < 1 {
            frame = Self.defaultFrame
        }
    }

    var currentContent: String {
        get {
            guard pages.indices.contains(currentPageIndex) else { return "" }
            return pages[currentPageIndex].content
        }
        set {
            if pages.indices.contains(currentPageIndex) {
                pages[currentPageIndex].content = newValue
            }
        }
    }

    /// 所有页都为空（保存到记录时据此跳过）
    var isBlank: Bool {
        pages.allSatisfy { $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// 从第一页第一行提取项目信息（名称和颜色）
    func extractProjectInfo() -> (name: String, color: Color?) {
        guard !pages.isEmpty else { return ("", nil) }

        let firstPageContent = pages[0].content
        let lines = firstPageContent.components(separatedBy: .newlines)
        guard let firstLine = lines.first else { return ("", nil) }

        // 颜色：沿用旧行为——首行第一个 [c:hex] 标记（不要求闭合）决定边框和项目名的颜色
        var firstColor: Color? = nil
        if let hex = StickyNoteMarkdown.strippingColorMarkers(firstLine).firstHex,
           let nsColor = StickyNoteMarkdown.color(fromHex: hex) {
            firstColor = Color(nsColor)
        }

        // 项目名：首行去掉标记后的文字。成对的标记（加粗/删除线/下划线/颜色）由 plainText 去掉；
        // 没闭合的颜色标记也一并去掉，包括落单的 [/c]——蒙层上不该露出标记
        let visible = StickyNoteMarkdown.plainText(firstLine)
        let name = StickyNoteMarkdown.strippingColorMarkers(visible).text

        // 去掉行首的待办前缀（图标，或没被渲染成图标的 "- [ ]" / "- [x]"）
        var rest = Substring(name.drop(while: { $0 == " " || $0 == "\t" }))
        if rest.first == "☐" || rest.first == "☑" {
            rest = rest.dropFirst()
        } else if rest.hasPrefix("- [ ]") || rest.hasPrefix("- [x]") || rest.hasPrefix("- [X]") {
            rest = rest.dropFirst(5)
        }

        // 限制项目名长度（最多10个字符）
        let projectName = String(rest.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10))

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
