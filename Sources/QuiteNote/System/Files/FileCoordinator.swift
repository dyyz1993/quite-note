import Foundation
import os.log
import AppKit

/// 资源类型
enum ResourceType: String {
    case image = "Images"
    case screenshot = "Screenshots"
    case syncedFolder = "SyncedFolders"
    case file = "Files"
    case thumbnail = "Cache/Thumbnails"
}

/// 负责结构化文件管理、路径生成与重名校验
final class FileCoordinator {
    static let shared = FileCoordinator()
    private static let logger = Logger(subsystem: "com.quitenote.app", category: "FileCoordinator")
    
    private let fileManager = FileManager.default
    
    /// 应用数据根目录
    private let rootURL: URL
    
    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // 数据隔离红线：测试进程可用 QN_TEST_STORAGE_ROOT 重定向全部存储到临时目录；
        // 开发变体（com.quitenote.app.dev）按 Bundle ID 使用独立目录，与生产数据互不干扰
        if let testRoot = ProcessInfo.processInfo.environment["QN_TEST_STORAGE_ROOT"] {
            rootURL = URL(fileURLWithPath: testRoot, isDirectory: true)
        } else {
            let dirName = Bundle.main.bundleIdentifier ?? "com.quitenote.app"
            rootURL = appSupport.appendingPathComponent(dirName, isDirectory: true)
        }
        setupDirectoryStructure()
    }
    
    /// 初始化目录结构
    private func setupDirectoryStructure() {
        let directories: [ResourceType] = [.image, .screenshot, .syncedFolder, .file, .thumbnail]
        
        for dir in directories {
            let url = getDirectoryURL(for: dir)
            if !fileManager.fileExists(atPath: url.path) {
                do {
                    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                } catch {
                    Self.logger.error("创建目录失败 \(dir.rawValue): \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// 获取指定类型的目录路径
    func getDirectoryURL(for type: ResourceType) -> URL {
        if type == .thumbnail {
            return rootURL.appendingPathComponent("Cache/Thumbnails", isDirectory: true)
        }
        return rootURL.appendingPathComponent("Attachments/\(type.rawValue)", isDirectory: true)
    }
    
    /// 生成唯一的子目录名
    /// 格式: yyyyMMdd_HHmmss_[ShortHash]
    private func generateUniqueDirectoryName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateStr = formatter.string(from: Date())
        let randomHash = String(UUID().uuidString.prefix(4)).lowercased()
        return "\(dateStr)_\(randomHash)"
    }
    
    /// 安全地保存文件到指定类型目录
    func storeFile(at sourceURL: URL, type: ResourceType) throws -> URL {
        let uniqueDir = generateUniqueDirectoryName()
        let destinationDir = getDirectoryURL(for: type).appendingPathComponent(uniqueDir, isDirectory: true)
        
        // 创建唯一子目录
        try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        
        let fileName = sanitizeFileName(sourceURL.lastPathComponent)
        let destinationURL = destinationDir.appendingPathComponent(fileName)
        
        // 如果是文件夹同步，使用不同的拷贝逻辑
        if type == .syncedFolder {
            try copyDirectory(from: sourceURL, to: destinationURL)
        } else {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
        
        return destinationURL
    }
    
    /// 将 NSImage 保存到指定类型目录
    func storeImage(_ image: NSImage, type: ResourceType, originalName: String? = nil) throws -> URL {
        let uniqueDir = generateUniqueDirectoryName()
        let destinationDir = getDirectoryURL(for: type).appendingPathComponent(uniqueDir, isDirectory: true)
        
        // 创建唯一子目录
        try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        
        let baseName = originalName ?? "image.png"
        let fileName = sanitizeFileName(baseName)
        let destinationURL = destinationDir.appendingPathComponent(fileName)
        
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "FileCoordinator", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法转换图片数据"])
        }
        
        try pngData.write(to: destinationURL)
        return destinationURL
    }
    
    /// 获取相对于根目录的虚拟路径 (用于数据库存储)
    /// 格式: app://attachments/Images/filename
    func convertToVirtualPath(from url: URL) -> String? {
        let path = url.path
        let rootPath = rootURL.path
        
        if path.hasPrefix(rootPath) {
            let relativePath = String(path.dropFirst(rootPath.count))
            // 移除开头的斜杠并替换为虚拟协议
            let cleanPath = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "app://\(cleanPath)"
        }
        return nil
    }
    
    /// 将虚拟路径还原为真实本地 URL
    func resolveVirtualPath(_ virtualPath: String) -> URL? {
        guard virtualPath.hasPrefix("app://") else {
            // 如果不是虚拟路径，尝试作为绝对路径处理
            let url = URL(fileURLWithPath: virtualPath)
            return fileManager.fileExists(atPath: url.path) ? url : nil
        }
        
        let relativePath = String(virtualPath.dropFirst(6)) // 移除 "app://"
        return rootURL.appendingPathComponent(relativePath)
    }
    
    // MARK: - Private Helpers
    
    private func sanitizeFileName(_ name: String) -> String {
        // 移除不允许的字符
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>")
        return name.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
    
    private func copyDirectory(from source: URL, to destination: URL) throws {
        // 对于文件夹，我们需要先创建目标目录
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        
        let contents = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        
        for item in contents {
            let destItem = destination.appendingPathComponent(item.lastPathComponent)
            try fileManager.copyItem(at: item, to: destItem)
        }
    }
}
