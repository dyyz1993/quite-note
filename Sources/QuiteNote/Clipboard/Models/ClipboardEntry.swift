import Foundation

/// 剪贴板条目内容类型（PRD 3.1：文本 / 链接 / 图片 / 文件，视频按文件处理）
enum ClipboardEntryType: String, Codable, CaseIterable {
    case text
    case link
    case image
    case file

    var localizedName: String {
        switch self {
        case .text: return "文本"
        case .link: return "链接"
        case .image: return "图片"
        case .file: return "文件"
        }
    }
}

/// 图片 OCR 状态（PRD 3.2：等待、处理中、成功、失败、关闭）
enum ClipboardOCRStatus: String, Codable {
    case waiting
    case processing
    case success
    case failed
    case disabled

    var localizedName: String {
        switch self {
        case .waiting: return "等待识别"
        case .processing: return "识别中"
        case .success: return "已识别"
        case .failed: return "识别失败"
        case .disabled: return "已关闭"
        }
    }
}

/// 剪贴板历史条目（PRD 5.3 字段）
/// 与正式 Record 完全独立：自动捕获的临时记录，可过期，加入闪记后通过 savedRecordID 关联
struct ClipboardEntry: Identifiable, Equatable {
    let id: UUID
    var type: ClipboardEntryType
    var createdAt: Date
    var lastUsedAt: Date
    /// 文本内容 / 链接原文 / 文件路径（图片条目为空，OCR 文本在 ocrText）
    var plainText: String?
    /// 链接条目的完整 URL（域名为搜索时现算）
    var sourceURL: String?
    var sourceApp: String?
    var sourceBundleID: String?
    var contentHash: String
    /// 图片原图的虚拟路径（app://attachments/Clipboard/...）
    var assetPath: String?
    var ocrText: String?
    var ocrStatus: ClipboardOCRStatus?
    var byteSize: Int64
    var pasteCount: Int
    var isPinned: Bool
    /// 加入闪记后对应正式 Record 的 id；取消关联置 nil（不删正式记录）
    var savedRecordID: UUID?

    init(
        id: UUID = UUID(),
        type: ClipboardEntryType,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date(),
        plainText: String? = nil,
        sourceURL: String? = nil,
        sourceApp: String? = nil,
        sourceBundleID: String? = nil,
        contentHash: String,
        assetPath: String? = nil,
        ocrText: String? = nil,
        ocrStatus: ClipboardOCRStatus? = nil,
        byteSize: Int64 = 0,
        pasteCount: Int = 0,
        isPinned: Bool = false,
        savedRecordID: UUID? = nil
    ) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.plainText = plainText
        self.sourceURL = sourceURL
        self.sourceApp = sourceApp
        self.sourceBundleID = sourceBundleID
        self.contentHash = contentHash
        self.assetPath = assetPath
        self.ocrText = ocrText
        self.ocrStatus = ocrStatus
        self.byteSize = byteSize
        self.pasteCount = pasteCount
        self.isPinned = isPinned
        self.savedRecordID = savedRecordID
    }
}

/// 剪贴板内容类型识别（纯函数，可单测）
enum ClipboardTypeDetector {

    /// 判断文本是否为完整 URL（PRD：链接 = 完整匹配 URL 的文本）
    static func isPureURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else { return false }
        // 完整匹配：不允许夹带其他内容
        return URL(string: trimmed)?.scheme != nil && !trimmed.contains_whitespace
    }

    /// 从 URL 文本提取域名（搜索范围包含域名，PRD 9.1）
    static func domain(ofURL text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host else { return nil }
        return host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }

    /// 按内容特征归类：文件引用 > 图片 > 链接 > 文本
    /// - Parameters:
    ///   - hasFileURL: 剪贴板包含文件引用（.fileURL 类型）
    ///   - hasImage: 剪贴板包含图片数据（.png/.tiff 等）
    ///   - text: 文本内容（可能为空）
    static func detect(hasFileURL: Bool, hasImage: Bool, text: String?) -> ClipboardEntryType {
        if hasFileURL { return .file }
        if hasImage { return .image }
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return isPureURL(text) ? .link : .text
        }
        return .text
    }
}

private extension String {
    var contains_whitespace: Bool {
        unicodeScalars.contains { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
    }
}
