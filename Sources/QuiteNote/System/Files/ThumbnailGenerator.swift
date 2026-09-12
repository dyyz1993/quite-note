import Foundation
import AppKit
import os.log
import CryptoKit

/// 负责后台缩略图生成与缓存
final class ThumbnailGenerator {
    static let shared = ThumbnailGenerator()
    private static let logger = Logger(subsystem: "com.quitenote.app", category: "ThumbnailGenerator")
    
    private let fileManager = FileManager.default
    private let thumbnailSize: CGFloat = 256.0 // 缩略图最大尺寸
    
    private init() {}
    
    /// 获取资源的缩略图 URL
    /// 如果缓存中不存在，则同步生成并返回
    func getThumbnailURL(for sourceURL: URL) -> URL? {
        let cacheDir = FileCoordinator.shared.getDirectoryURL(for: .thumbnail)
        
        // 缩略图文件名为路径的稳定哈希（Swift hashValue 每次启动随机化，
        // 用它做 key 等于缓存永远不命中——每次启动首滚都全量重新生成缩略图）
        let thumbnailURL = cacheDir.appendingPathComponent("\(Self.stableKey(for: sourceURL)).jpg")
        
        // 如果已存在且源文件没变，直接返回
        if fileManager.fileExists(atPath: thumbnailURL.path) {
            return thumbnailURL
        }
        
        // 否则生成缩略图
        return generateThumbnail(from: sourceURL, to: thumbnailURL)
    }
    
    /// 只查**已存在**的缩略图（不生成）——详情面板秒出首帧用；
    /// 返回 nil 表示该图还没有缩略图（捕获时未生成/外部文件）
    func existingThumbnailURL(for sourceURL: URL) -> URL? {
        let cacheDir = FileCoordinator.shared.getDirectoryURL(for: .thumbnail)
        let thumbnailURL = cacheDir.appendingPathComponent("\(Self.stableKey(for: sourceURL)).jpg")
        return fileManager.fileExists(atPath: thumbnailURL.path) ? thumbnailURL : nil
    }

    /// 异步获取缩略图
    func getThumbnailURLAsync(for sourceURL: URL, completion: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let url = self.getThumbnailURL(for: sourceURL)
            DispatchQueue.main.async {
                completion(url)
            }
        }
    }

    /// 删除指定资源的缩略图
    func removeThumbnail(for sourceURL: URL) {
        let cacheDir = FileCoordinator.shared.getDirectoryURL(for: .thumbnail)
        let thumbnailURL = cacheDir.appendingPathComponent("\(Self.stableKey(for: sourceURL)).jpg")
        try? fileManager.removeItem(at: thumbnailURL)
    }
    
    /// 路径 → 稳定缓存 key（SHA256 前 16 位，跨启动一致）
    static func stableKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.path.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private Helpers
    
    private func generateThumbnail(from source: URL, to destination: URL) -> URL? {
        // 检查是否是图片
        guard let image = NSImage(contentsOf: source) else {
            // 如果是文件夹，我们可以获取系统图标作为缩略图
            if isDirectory(at: source) {
                return generateFolderIcon(for: source, to: destination)
            }
            return nil
        }
        
        let targetSize = calculateThumbnailSize(originalSize: image.size)
        let thumbnail = NSImage(size: targetSize)
        
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                  from: NSRect(origin: .zero, size: image.size),
                  operation: .copy,
                  fraction: 1.0)
        thumbnail.unlockFocus()
        
        guard let tiffData = thumbnail.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }
        
        do {
            try jpegData.write(to: destination)
            return destination
        } catch {
            Self.logger.error("写入缩略图失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func calculateThumbnailSize(originalSize: NSSize) -> NSSize {
        let ratio = min(thumbnailSize / originalSize.width, thumbnailSize / originalSize.height)
        if ratio >= 1.0 { return originalSize }
        return NSSize(width: originalSize.width * ratio, height: originalSize.height * ratio)
    }
    
    private func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
    
    private func generateFolderIcon(for source: URL, to destination: URL) -> URL? {
        let icon = NSWorkspace.shared.icon(forFile: source.path)
        icon.size = NSSize(width: thumbnailSize, height: thumbnailSize)
        
        guard let tiffData = icon.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        do {
            try pngData.write(to: destination)
            return destination
        } catch {
            return nil
        }
    }
}
