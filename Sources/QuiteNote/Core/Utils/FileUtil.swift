import Foundation

/// 文件操作工具类
struct FileUtil {
    
    /// 获取一个唯一的 URL，如果文件已存在，则添加数字后缀
    /// - Parameters:
    ///   - url: 原始期望的 URL
    ///   - directory: 目标目录
    /// - Returns: 唯一的 URL
    static func getUniqueURL(for fileName: String, in directory: URL) -> URL {
        let fileManager = FileManager.default
        let uniqueURL = directory.appendingPathComponent(fileName)
        
        // 如果文件不存在，直接返回
        if !fileManager.fileExists(atPath: uniqueURL.path) {
            return uniqueURL
        }
        
        // 文件已存在，拆分文件名和扩展名
        let fileExtension = uniqueURL.pathExtension
        let baseName = uniqueURL.deletingPathExtension().lastPathComponent
        
        var counter = 1
        while true {
            let newName = "\(baseName) (\(counter))\(fileExtension.isEmpty ? "" : ".\(fileExtension)")"
            let nextURL = directory.appendingPathComponent(newName)
            
            if !fileManager.fileExists(atPath: nextURL.path) {
                return nextURL
            }
            counter += 1
            
            // 安全退出：防止无限循环（虽然理论上不会，但增加一个上限）
            if counter > 1000 {
                return directory.appendingPathComponent("\(UUID().uuidString)_\(fileName)")
            }
        }
    }
}
