import Foundation

/// 文件夹的 tree 结构文本生成（拖入文件夹建记录时用）。
/// 从 RecordStore.generateTreeStructure 逐字搬运：文件夹排前、按名排序、无深度上限、
/// 读不了的子目录显示"(无法读取内容)"都是现状语义，保持不变
enum FolderTreeRenderer {
    /// 生成 tree 结构文本行；fileCount 是树里文件（非目录）的总数
    static func renderLines(for folderURL: URL) -> (lines: [String], fileCount: Int) {
        let folderName = folderURL.lastPathComponent
        let folderPath = folderURL.path

        // 递归遍历文件夹，生成 tree 结构
        func traverseDirectory(_ url: URL, level: Int = 0) -> (lines: [String], fileCount: Int) {
            var lines: [String] = []
            var fileCount = 0
            let indent = String(repeating: "│  ", count: level)
            _ = String(repeating: "└── ", count: 1)

            do {
                let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.nameKey, .isDirectoryKey], options: [.skipsHiddenFiles])

                // 排序：文件夹在前，文件在后
                let sorted = contents.sorted { a, b in
                    let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if aIsDir != bIsDir {
                        return aIsDir && !bIsDir  // 文件夹排在前面
                    }
                    return a.lastPathComponent < b.lastPathComponent
                }

                for (index, item) in sorted.enumerated() {
                    let name = item.lastPathComponent
                    let isDirectory = (try? item.resourceValues(forKeys: [URLResourceKey.isDirectoryKey]))?.isDirectory ?? false

                    let isLast = index == sorted.count - 1
                    let prefix = isLast ? "└── " : "├── "
                    let connector = isLast ? "    " : "│   "

                    if isDirectory {
                        lines.append("\(indent)\(prefix)\(name)/")
                        let subResult = traverseDirectory(item, level: level + 1)
                        fileCount += subResult.fileCount

                        // 添加子项内容
                        for subLine in subResult.lines {
                            lines.append("\(indent)\(connector)\(subLine)")
                        }
                    } else {
                        lines.append("\(indent)\(prefix)\(name)")
                        fileCount += 1
                    }
                }
            } catch {
                lines.append("\(indent)└── (无法读取内容)")
            }

            return (lines, fileCount)
        }

        var resultLines: [String] = []
        resultLines.append("文件夹路径: \(folderPath)")
        resultLines.append("文件夹名: \(folderName)")
        resultLines.append("文件结构:")
        resultLines.append(".")

        let (treeLines, totalFiles) = traverseDirectory(folderURL)
        resultLines.append(contentsOf: treeLines)

        return (resultLines, totalFiles)
    }
}
