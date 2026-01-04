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
    
    /// 缓存的统计结果
    private var cachedStats: StorageStats = .empty
    private var lastCalculatedAt: Date = .distantPast
    private var lastRecordCount: Int = 0
    private var lastAttachmentsPath: String = ""

    /// 计算指定目录和记录列表的存储统计信息
    /// - Parameters:
    ///   - directory: 附件存储目录 URL
    ///   - records: 当前记录列表
    ///   - force: 是否强制重新计算
    /// - Returns: 统计结果
    func calculateStats(for directory: URL, records: [Record], force: Bool = false) -> StorageStats {
        // 如果不是强制刷新，且记录数量和路径没变，直接返回缓存
        if !force && 
           records.count == lastRecordCount && 
           directory.path == lastAttachmentsPath && 
           Date().timeIntervalSince(lastCalculatedAt) < 60 {
            return cachedStats
        }

        var totalSize: Int64 = 0
        var typeDistribution: [String: Int64] = [:]
        var categoryStats: [RecordType: (count: Int, size: Int64)] = [:]
        
        // 直接从记录列表中进行分类统计，不再扫描磁盘
        // 这极大地提高了性能，特别是在记录很多时
        for record in records {
            let type = record.type
            let size = record.size
            
            let current = categoryStats[type, default: (0, 0)]
            categoryStats[type] = (current.count + 1, current.size + size)
            
            totalSize += size
            
            // 类型分布统计
            let ext: String
            if type == .text {
                ext = "txt"
            } else if let path = record.sourceUrl ?? record.content.components(separatedBy: "\n").first {
                ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            } else {
                ext = "other"
            }
            let key = ext.isEmpty ? "other" : ext
            typeDistribution[key, default: 0] += size
        }
        
        // 转换为最终的 StorageStats
        let finalCategoryStats = categoryStats.mapValues { 
            StorageStats.CategoryStat(count: $0.count, size: $0.size) 
        }
        
        let newStats = StorageStats(totalSize: totalSize, 
                          fileCount: Int64(records.count), 
                          typeDistribution: typeDistribution,
                          categoryStats: finalCategoryStats)
        
        // 更新缓存
        self.cachedStats = newStats
        self.lastCalculatedAt = Date()
        self.lastRecordCount = records.count
        self.lastAttachmentsPath = directory.path
        
        return newStats
    }
}
