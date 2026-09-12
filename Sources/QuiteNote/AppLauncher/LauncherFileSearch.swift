import AppKit

/// 文件名搜索（范围模式）：**目录索引缓存优先**（首扫落盘，之后内存过滤毫秒级）。
///
/// 背景：本机 Spotlight 索引未启用，每次搜索现扫目录要数秒（用户实测"几乎用不了"）。
/// 方案：首次搜索后台全量扫常用目录（递归 5 层）持久化 JSON，之后每次搜索 =
/// 读缓存 + 内存过滤（<10ms，和应用目录缓存同一套路）。缓存 10 分钟过期后台重扫
/// 静默更新；Spotlight 查询仅在无索引时作为首查补充。
@MainActor
final class LauncherFileSearch {
    static let shared = LauncherFileSearch()

    private var query: NSMetadataQuery?
    private var debounceWork: DispatchWorkItem?
    private var timeoutWork: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.15
    private let queryTimeout: TimeInterval = 1.5

    private init() {}

    // MARK: - 索引缓存（内存 + 磁盘）

    /// 内存态全量索引（目录扫描产物）。搜索 = 内存过滤，快到无感
    private(set) var index: [LauncherFile] = []
    private var indexLoaded = false
    private var indexScanning = false
    private var lastIndexDate: Date?
    private let indexStaleInterval: TimeInterval = 600   // 10 分钟

    /// 缓存文件位置（同应用目录缓存：按 Bundle ID 分目录，测试进程重定向）
    nonisolated static var indexCacheURL: URL {
        if let testRoot = ProcessInfo.processInfo.environment["QN_TEST_STORAGE_ROOT"] {
            return URL(fileURLWithPath: testRoot, isDirectory: true)
                .appendingPathComponent("LauncherFileIndex.json")
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let dirName = Bundle.main.bundleIdentifier ?? "com.quitenote.app"
        return appSupport.appendingPathComponent(dirName, isDirectory: true)
            .appendingPathComponent("LauncherFileIndex.json")
    }

    private struct IndexWrapper: Codable {
        let version: Int
        let indexedAt: Date
        let files: [LauncherFile]
    }

    nonisolated static func encodeIndex(_ files: [LauncherFile], at date: Date) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(IndexWrapper(version: 1, indexedAt: date, files: files))
    }

    nonisolated static func decodeIndex(_ data: Data) -> (files: [LauncherFile], at: Date)? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let wrapper = try? decoder.decode(IndexWrapper.self, from: data),
              wrapper.version == 1 else { return nil }
        return (wrapper.files, wrapper.indexedAt)
    }

    /// 索引就绪（内存有就直接用；磁盘有就读盘并后台刷新；都没有触发首扫）
    private func ensureIndex() {
        if indexLoaded { return }
        if let data = try? Data(contentsOf: Self.indexCacheURL),
           let decoded = Self.decodeIndex(data), !decoded.files.isEmpty {
            index = decoded.files
            lastIndexDate = decoded.at
            indexLoaded = true
            DiagnosticCenter.info("Launcher", "文件索引缓存已加载：\(decoded.files.count) 项")
        }
        rescanIndexIfStale()
    }

    /// 过期（或从未扫描）→ 后台全量扫，完成后落盘并静默更新内存
    private func rescanIndexIfStale() {
        if let last = lastIndexDate, Date().timeIntervalSince(last) < indexStaleInterval { return }
        guard !indexScanning else { return }
        indexScanning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let t0 = DispatchTime.now()
            let files = Self.scanAllForIndex()
            let ms = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            DispatchQueue.main.async {
                guard let self else { return }
                self.index = files
                self.indexLoaded = true
                self.lastIndexDate = Date()
                self.indexScanning = false
                DiagnosticCenter.info("Launcher", "文件索引扫描完成：\(files.count) 项（\(String(format: "%.0f", ms))ms）")
                if let data = Self.encodeIndex(files, at: Date()) {
                    let url = Self.indexCacheURL
                    DispatchQueue.global(qos: .utility).async {
                        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? data.write(to: url, options: .atomic)
                    }
                }
            }
        }
    }

    /// 全量索引扫描（后台队列）。实测要点（2026-09-12 基准）：
    /// - **必须 skipsPackageDescendants**——.app/照片图库等"包"内部有成千上万文件，
    ///   朴素递归 60s 跑不完（用户实测"非常非常久"）；跳包后 3 目录 3 层 0.58s/11105 项
    /// - 硬截止 4s：iCloud 未下载文件的属性访问走网络，防个别文件拖死全扫（部分索引仍可用）
    /// - BFS 逐层枚举（skipsSubdirectoryDescendants + 手动入队），深度 ≤3 层
    nonisolated static func scanAllForIndex() -> [LauncherFile] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let roots = [home + "/Desktop", home + "/Documents", home + "/Downloads"]
        // ⚠️ 本 SDK（macOS 26）两个 API 的 key 参数类型：enumerator 要 Array，resourceValues 要 Set
        let enumKeys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .isPackageKey]
        let statKeys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey, .isPackageKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]
        let deadline = Date().addingTimeInterval(4)
        var results: [LauncherFile] = []

        for root in roots {
            var queue: [(URL, Int)] = [(URL(fileURLWithPath: root), 0)]
            while !queue.isEmpty {
                let (dir, depth) = queue.removeFirst()
                guard depth < 3, Date() < deadline,
                      let en = fm.enumerator(at: dir, includingPropertiesForKeys: enumKeys, options: options) else { continue }
                while let item = en.nextObject() as? URL {
                    guard Date() < deadline else { break }
                    guard let values = try? item.resourceValues(forKeys: statKeys) else { continue }
                    let isDir = values.isDirectory ?? false
                    let isPackage = values.isPackage ?? false
                    let kind = isDir ? "" : Self.kindDescription(extension: item.pathExtension)
                    results.append(LauncherFile(name: item.lastPathComponent, url: item, kindDescription: kind,
                                                modifiedDate: values.contentModificationDate,
                                                isDirectory: isDir))
                    if isDir, !isPackage { queue.append((item, depth + 1)) }
                }
            }
        }
        return results
    }

    /// 内存过滤（索引就绪后的搜索路径，<10ms）：文件夹排前（用户要求区分），
    /// 同类内按修改时间倒序
    nonisolated static func filterIndex(_ term: String, in files: [LauncherFile]) -> [LauncherFile] {
        let lower = term.lowercased()
        return files
            .filter { $0.name.lowercased().contains(lower) }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }   // 文件夹优先
                return ($0.modifiedDate ?? .distantPast) > ($1.modifiedDate ?? .distantPast)
            }
            .prefix(50)
            .map { $0 }
    }

    // MARK: - 搜索入口

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

        // 索引路径（常态）：内存过滤毫秒级返回；顺手触发过期重扫（静默）
        ensureIndex()   // ensureIndex 会顺带触发首扫/过期重扫（后台，不阻塞本次搜索）
        if indexLoaded, !index.isEmpty {
            completion(Self.filterIndex(term, in: index))
            rescanIndexIfStale()
            return
        }
        // 首扫进行中（首次使用）：立即用 Spotlight+旧兜底出结果，扫完下次生效

        // 首次（无任何索引）：Spotlight + 目录扫描兜底（旧路径，一次性成本）
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

    /// Spotlight 不可用时的目录兜底：家目录顶层 + 六个用户内容目录**递归 4 层**
    /// （覆盖 ~/Documents/子目录/孙目录/文件 的常见结构），文件名包含匹配；
    /// 扫描量上限 3000 项防爆，后台队列执行。再深请开系统 Spotlight 索引
    nonisolated static func scanCommonDirectories(term: String, homePath: String = NSHomeDirectory()) -> [LauncherFile] {
        let fm = FileManager.default
        let home = homePath
        let roots = [
            home, home + "/Desktop", home + "/Documents", home + "/Downloads",
            home + "/Pictures", home + "/Movies", home + "/Music",
        ]
        let lowerTerm = term.lowercased()
        var results: [LauncherFile] = []
        var scanned = 0
        let scanLimit = 3000

        func scan(dir: String, depth: Int) {
            guard depth <= 4, scanned < scanLimit,
                  let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for entry in entries {
                scanned += 1
                guard scanned < scanLimit else { return }
                guard !entry.hasPrefix(".") else { continue }
                let url = URL(fileURLWithPath: dir).appendingPathComponent(entry)
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                let isDir = values?.isDirectory ?? false
                if entry.lowercased().contains(lowerTerm) {
                    let kind = isDir ? "" : Self.kindDescription(extension: url.pathExtension)
                    results.append(LauncherFile(name: entry, url: url, kindDescription: kind,
                                                modifiedDate: values?.contentModificationDate,
                                                isDirectory: isDir))
                }
                if isDir, depth < 4 {
                    scan(dir: url.path, depth: depth + 1)
                }
            }
        }
        for dir in roots { scan(dir: dir, depth: 1) }
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
