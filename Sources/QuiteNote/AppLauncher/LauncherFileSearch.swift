import AppKit

/// 文件名 Spotlight 查询服务（`f ` 前缀模式）
///
/// NSMetadataQuery 查 `kMDItemFSName CONTAINS[cd]`，范围家目录（Spotlight 默认不索引
/// ~/Library，噪声天然少）；防抖 150ms + 1.5s 超时兜底；按修改时间倒序、封顶 50 条。
/// 与应用扫描共用同一套 NSMetadataQuery 用法（didFinishGathering 一次性收集 + 超时退出）。
@MainActor
final class LauncherFileSearch {
    static let shared = LauncherFileSearch()

    private var query: NSMetadataQuery?
    private var debounceWork: DispatchWorkItem?
    private var timeoutWork: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.15
    private let queryTimeout: TimeInterval = 1.5

    private init() {}

    /// 搜索文件名；连续按键经 150ms 防抖合并。term 为空 = 退出文件模式，回调空结果
    func search(_ rawTerm: String, completion: @escaping ([LauncherFile]) -> Void) {
        debounceWork?.cancel()
        timeoutWork?.cancel()
        stopQuery()

        let term = rawTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else {
            completion([])
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.runQuery(term, completion: completion)
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    func cancel() {
        debounceWork?.cancel()
        timeoutWork?.cancel()
        stopQuery()
    }

    private func runQuery(_ term: String, completion: @escaping ([LauncherFile]) -> Void) {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemFSName CONTAINS[cd] %@", term)
        // 本 SDK 未暴露 NSMetadataQueryHomeScope 常量，用其文档值（Spotlight 家目录域）
        query.searchScopes = ["kMDQueryScopeHome"]
        self.query = query

        var didFinish = false
        var observer: NSObjectProtocol?
        weak var weakQuery = query

        func finish(_ files: [LauncherFile]) {
            guard !didFinish else { return }
            didFinish = true
            if let observer { NotificationCenter.default.removeObserver(observer) }
            weakQuery?.stop()
            if files.isEmpty {
                // Spotlight 空结果（索引未开启/未覆盖是常态——本机实测全盘 mdfind 也空）
                // → 常用目录兜底扫描，后台执行避免阻塞主线程
                DispatchQueue.global(qos: .userInitiated).async {
                    let fallback = Self.scanCommonDirectories(term: term)
                    DiagnosticCenter.info("Launcher", "文件搜索：Spotlight 空 → 目录兜底 \(fallback.count) 条（term=\(term)）")
                    DispatchQueue.main.async { completion(fallback) }
                }
            } else {
                DiagnosticCenter.info("Launcher", "文件搜索：Spotlight \(files.count) 条（term=\(term)）")
                completion(files)
            }
        }

        observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: .main
        ) { _ in
            let files = query.results.compactMap { result -> LauncherFile? in
                guard let item = result as? NSMetadataItem,
                      let path = item.value(forAttribute: "kMDItemPath") as? String else { return nil }
                let url = URL(fileURLWithPath: path)
                let name = (item.value(forAttribute: "kMDItemFSName") as? String) ?? url.lastPathComponent
                let kind = (item.value(forAttribute: "kMDItemKind") as? String) ?? ""
                let modified = item.value(forAttribute: "kMDItemContentModificationDate") as? Date
                let contentType = (item.value(forAttribute: "kMDItemContentType") as? String) ?? ""
                return LauncherFile(name: name, url: url, kindDescription: kind,
                                    modifiedDate: modified,
                                    isDirectory: contentType == "public.directory")
            }
            .sorted { ($0.modifiedDate ?? .distantPast) > ($1.modifiedDate ?? .distantPast) }
            .prefix(50)
            finish(Array(files))
        }

        // 超时兜底：Spotlight 无响应按空结果处理（索引关闭/权限异常时不挂死列表）
        let timeout = DispatchWorkItem { finish([]) }
        timeoutWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + queryTimeout, execute: timeout)

        query.start()
    }

    private func stopQuery() {
        query?.stop()
        query = nil
    }

    /// Spotlight 不可用时的目录兜底：扫家目录顶层 + 六个用户内容目录的一层，
    /// 文件名包含匹配（不递归深层——要全量深度搜索请开系统 Spotlight 索引）
    nonisolated static func scanCommonDirectories(term: String) -> [LauncherFile] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let directories = [
            home, home + "/Desktop", home + "/Documents", home + "/Downloads",
            home + "/Pictures", home + "/Movies", home + "/Music",
        ]
        let lowerTerm = term.lowercased()
        var results: [LauncherFile] = []
        for dir in directories {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries {
                guard !entry.hasPrefix("."),
                      entry.lowercased().contains(lowerTerm) else { continue }
                let url = URL(fileURLWithPath: dir).appendingPathComponent(entry)
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                let isDir = values?.isDirectory ?? false
                let kind = isDir ? "" : Self.kindDescription(extension: url.pathExtension)
                results.append(LauncherFile(name: entry, url: url, kindDescription: kind,
                                            modifiedDate: values?.contentModificationDate,
                                            isDirectory: isDir))
            }
        }
        return results
            .sorted { ($0.modifiedDate ?? .distantPast) > ($1.modifiedDate ?? .distantPast) }
            .prefix(50)
            .map { $0 }
    }

    /// 常见扩展名 → 本地化类型描述（Spotlight 的 kMDItemKind 平替，兜底用）
    nonisolated static func kindDescription(extension ext: String) -> String {
        let map: [String: String] = [
            "pdf": "PDF 文档", "doc": "Word 文档", "docx": "Word 文档",
            "xls": "Excel 表格", "xlsx": "Excel 表格", "csv": "CSV 表格",
            "ppt": "PowerPoint", "pptx": "PowerPoint",
            "png": "PNG 图像", "jpg": "JPEG 图像", "jpeg": "JPEG 图像",
            "gif": "GIF 图像", "heic": "HEIC 图像", "svg": "SVG 图像",
            "psd": "PSD 图像", "sketch": "Sketch 文稿",
            "mp4": "MP4 视频", "mov": "QuickTime 视频", "avi": "AVI 视频",
            "mp3": "MP3 音频", "wav": "WAV 音频", "m4a": "M4A 音频",
            "zip": "ZIP 压缩包", "rar": "RAR 压缩包", "dmg": "磁盘映像",
            "txt": "纯文本", "md": "Markdown", "json": "JSON 文件",
            "swift": "Swift 源码", "js": "JavaScript", "ts": "TypeScript",
            "py": "Python 脚本", "sh": "Shell 脚本", "html": "HTML 文档",
        ]
        return map[ext.lowercased()] ?? ""
    }
}
