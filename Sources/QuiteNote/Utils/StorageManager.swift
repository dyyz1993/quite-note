import Foundation

/// 存储统计信息模型
struct StorageStats {
    let totalSize: Int64
    let fileCount: Int64
    let typeDistribution: [String: Int64]
    
    static let empty = StorageStats(totalSize: 0, fileCount: 0, typeDistribution: [:])
    
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

/// 存储管理器：负责计算目录体积与类型分布
final class StorageManager {
    static let shared = StorageManager()
    private init() {}
    
    /// 计算指定目录的存储统计信息
    /// - Parameter directory: 目标目录 URL
    /// - Returns: 统计结果
    func calculateStats(for directory: URL) -> StorageStats {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        var fileCount: Int64 = 0
        var typeDistribution: [String: Int64] = [:]
        
        guard let enumerator = fileManager.enumerator(at: directory, 
                                                    includingPropertiesForKeys: [URLResourceKey.fileSizeKey, URLResourceKey.isDirectoryKey],
                                                    options: [.skipsHiddenFiles]) else {
            return .empty
        }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [URLResourceKey.fileSizeKey, URLResourceKey.isDirectoryKey])
                
                // 跳过目录
                if let isDirectory = resourceValues.isDirectory, isDirectory {
                    continue
                }
                
                if let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                    fileCount += 1
                    
                    let ext = fileURL.pathExtension.lowercased()
                    let key = ext.isEmpty ? "other" : ext
                    typeDistribution[key, default: 0] += Int64(fileSize)
                }
            } catch {
                print("[DEBUG] StorageManager error: \(error.localizedDescription)")
            }
        }
        
        return StorageStats(totalSize: totalSize, fileCount: fileCount, typeDistribution: typeDistribution)
    }
}
