import Foundation

import SwiftUI

/// 记录类型
enum RecordType: String, Codable, CaseIterable {
    case text = "text"
    case url = "url"
    case file = "file"
    case folder = "folder"
    case image = "image"
    case video = "video"
    case screenshot = "screenshot"
    case note = "note"  // 便签类型

    var localizedName: String {
        switch self {
        case .text: return "纯文本"
        case .url: return "链接"
        case .file: return "文件"
        case .folder: return "文件夹"
        case .image: return "照片" // 修改为 "照片" 以保持一致
        case .video: return "视频"
        case .screenshot: return "截图"
        case .note: return "便签"
        }
    }

    /// 统一图标
    var icon: IconName {
        switch self {
        case .text: return .type
        case .url: return .link
        case .file: return .fileText
        case .folder: return .folder
        case .image: return .image
        case .video: return .video
        case .screenshot: return .camera
        case .note: return .clipboard
        }
    }

    /// 统一主题色
    var themeColor: Color {
        switch self {
        case .text: return .themeTextSecondary
        case .url: return .themeBlue400
        case .file: return .themePurple400
        case .folder: return .themeYellow500
        case .image: return .themeGreen500
        case .video: return .themeRed500
        case .screenshot: return .themeBlue400
        case .note: return .themeOrange400
        }
    }
}

/// 记录模型：标题、内容、创建时间与去重哈希
struct Record: Identifiable, Equatable {
    let id: UUID
    var title: String? = nil
    let content: String
    var createdAt: Date
    let hash: String
    var aiStatus: String? = nil
    var summary: String? = nil
    var summaryConfidence: Double? = nil
    var starred: Bool = false
    var copiedAt: Date? = nil
    var tags: [String] = []
    var keywords: [String] = []
    var sourceApp: String? = nil
    var sourceUrl: String? = nil
    var type: RecordType = .text
    var skipAI: Bool = false
    var fileCount: Int? = nil  // 文件夹包含的文件数量
    var size: Int64 = 0       // 文件大小 (bytes)
    var noteFrame: NSRect? = nil  // 便签窗口位置

    static func == (lhs: Record, rhs: Record) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.content == rhs.content &&
        lhs.createdAt == rhs.createdAt &&
        lhs.hash == rhs.hash &&
        lhs.aiStatus == rhs.aiStatus &&
        lhs.summary == rhs.summary &&
        lhs.summaryConfidence == rhs.summaryConfidence &&
        lhs.starred == rhs.starred &&
        lhs.copiedAt == rhs.copiedAt &&
        lhs.tags == rhs.tags &&
        lhs.keywords == rhs.keywords &&
        lhs.sourceApp == rhs.sourceApp &&
        lhs.sourceUrl == rhs.sourceUrl &&
        lhs.type == rhs.type &&
        lhs.skipAI == rhs.skipAI &&
        lhs.fileCount == rhs.fileCount &&
        lhs.size == rhs.size &&
        lhs.noteFrame == rhs.noteFrame
    }
}
