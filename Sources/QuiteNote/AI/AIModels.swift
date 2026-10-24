import Foundation
import AppKit

/// AI 总结结果结构：标题、总结、置信度、标签与关键词
struct SummaryResult: Codable {
    let title: String
    let summary: String
    let confidence: Double
    let tags: [String]?
    let keywords: [String]?
}

/// AI 请求配置
struct AIRequestConfig {
    let contextId: String?
    let titleLimit: Int
    let summaryLimit: Int
    let content: String
    let existingTags: [String]
    let systemPrompt: String?
    let userPrompt: String?
    let timestamp: Date

    init(contextId: String? = nil,
         titleLimit: Int = 30,
         summaryLimit: Int = 100,
         content: String,
         existingTags: [String] = [],
         systemPrompt: String? = nil,
         userPrompt: String? = nil) {
        self.contextId = contextId
        self.titleLimit = titleLimit
        self.summaryLimit = summaryLimit
        self.content = content
        self.existingTags = existingTags
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.timestamp = Date()
    }
}

/// AI 队列中的请求项
struct AIRequestItem {
    let id = UUID()
    let config: AIRequestConfig
    let completion: (Result<SummaryResult, Error>) -> Void
}

/// 原始图片在 Chat Completions 请求中的最小载体。
struct AIImageData: Equatable {
    let mimeType: String
    let base64: String
}

/// 记录图片 → 请求图片的纯加载逻辑。
enum AIImagePayloadLoader {
    /// OpenAI data URL 支持的图片类型；JPEG/PNG 已覆盖本地截图和剪贴板图片的稳定编码路径。
    private static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg"]

    static func canLoad(path: String) -> Bool {
        // Non-PNG/JPEG images cannot be sent directly by this payload yet.
        guard let url = FileCoordinator.shared.resolveVirtualPath(path),
              FileManager.default.fileExists(atPath: url.path) else { return false }
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func load(path: String, maxPixel: CGFloat = 2048) -> AIImageData? {
        guard let url = FileCoordinator.shared.resolveVirtualPath(path),
              let source = NSImage(contentsOf: url) else { return nil }

        let shouldDownscale = maxPixel > 0 &&
            (source.size.width > maxPixel || source.size.height > maxPixel)
        let image = shouldDownscale ? downscale(source, maxPixel: maxPixel) : source

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }

        if url.pathExtension.lowercased() == "png" {
            guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
            return AIImageData(mimeType: "image/png", base64: data.base64EncodedString())
        }

        // JPEG 对照片类图片更小；不支持透明通道，所以铺白色背景。
        let opaque = opaqueImage(image)
        guard let opaqueTIFF = opaque.tiffRepresentation,
              let opaqueRep = NSBitmapImageRep(data: opaqueTIFF),
              let data = opaqueRep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            return nil
        }
        return AIImageData(mimeType: "image/jpeg", base64: data.base64EncodedString())
    }

    private static func downscale(_ image: NSImage, maxPixel: CGFloat) -> NSImage {
        let ratio = min(maxPixel / image.size.width, maxPixel / image.size.height, 1)
        let newSize = NSSize(width: floor(image.size.width * ratio), height: floor(image.size.height * ratio))
        let result = NSImage(size: newSize)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize))
        result.unlockFocus()
        return result
    }

    private static func opaqueImage(_ image: NSImage) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: image.size)).fill()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        result.unlockFocus()
        return result
    }
}

/// AI 服务常量
enum AIConstants {
    static let defaultTitleLimit = 30
    static let defaultSummaryLimit = 100
    static let defaultMaxTokens = 5000
    static let defaultTemperature = 0.3
    static let defaultTimeout: TimeInterval = 60
    static let maxConcurrentRequests = 3
    static let fallbackTitleLength = 15
}
