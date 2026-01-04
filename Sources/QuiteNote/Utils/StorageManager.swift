import Foundation

/// 存储统计信息模型
struct StorageStats {
    let totalSize: Int64
    let fileCount: Int64
    let typeDistribution: [String: Int64]
    let categoryStats: [RecordType: CategoryStat]
    
    struct CategoryStat {
        let count: Int
        let size: Int64
        
        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
    }
    
    static let empty = StorageStats(totalSize: 0, fileCount: 0, typeDistribution: [:], categoryStats: [:])
    
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

/// 存储管理器：负责计算目录体积与类型分布
final class StorageManager {
    static let shared = StorageManager()
    private init() {}
    
    /// 计算指定目录和记录列表的存储统计信息
    /// - Parameters:
    ///   - directory: 附件存储目录 URL
    ///   - records: 当前记录列表
    /// - Returns: 统计结果
    func calculateStats(for directory: URL, records: [Record]) -> StorageStats {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        var fileCount: Int64 = 0
        var typeDistribution: [String: Int64] = [:]
        var categoryStats: [RecordType: (count: Int, size: Int64)] = [:]
        
        // 1. 先扫描目录获取物理文件信息
        guard let enumerator = fileManager.enumerator(at: directory, 
                                                    includingPropertiesForKeys: [URLResourceKey.fileSizeKey, URLResourceKey.isDirectoryKey],
                                                    options: [.skipsHiddenFiles]) else {
            return .empty
        }
        
        var fileSizes: [String: Int64] = [:] // fileName -> size
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [URLResourceKey.fileSizeKey, URLResourceKey.isDirectoryKey])
                
                if let isDirectory = resourceValues.isDirectory, isDirectory {
                    continue
                }
                
                if let fileSize = resourceValues.fileSize {
                    let size = Int64(fileSize)
                    totalSize += size
                    fileCount += 1
                    
                    let fileName = fileURL.lastPathComponent
                    fileSizes[fileName] = size
                    
                    let ext = fileURL.pathExtension.lowercased()
                    let key = ext.isEmpty ? "other" : ext
                    typeDistribution[key, default: 0] += size
                }
            } catch {
                print("[DEBUG] StorageManager error: \(error.localizedDescription)")
            }
        }
        
        // 2. 根据记录列表进行分类统计
        for record in records {
            let type = record.type
            let current = categoryStats[type, default: (0, 0)]
            
            var recordSize: Int64 = 0
            if type != .text {
                // 对于非文本记录，尝试匹配文件大小
                let fileName = URL(fileURLWithPath: record.content).lastPathComponent
                recordSize = fileSizes[fileName] ?? 0
            }
            
            categoryStats[type] = (current.count + 1, current.size + recordSize)
        }
        
        // 3. 转换为最终的 StorageStats
        let finalCategoryStats = categoryStats.mapValues { 
            StorageStats.CategoryStat(count: $0.count, size: $0.size) 
        }
        
        return StorageStats(totalSize: totalSize, 
                          fileCount: fileCount, 
                          typeDistribution: typeDistribution,
                          categoryStats: finalCategoryStats)
    }
}
