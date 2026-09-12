import AppKit
import Combine

/// 应用启动器目录：扫描全机已安装应用（Spotlight 主路径 + 目录扫描兜底）、
/// 图标缓存、最近使用（MRU）记录。
///
/// 扫描策略：
/// 1. `NSMetadataQuery` 查 `kMDItemContentType == com.apple.application`——
///    走 Spotlight 索引，App Store 沙盒版同样可用，且直接给出本地化显示名；
/// 2. 结果 < 20 个（索引关闭 / 无权限 / 超时 2 秒）→ FileManager 扫描标准目录兜底
///    （非沙盒版可用），两路结果合并去重。
///
/// MRU（最近使用）为自维护记录（bundleID 数组 + 时间戳），不依赖 Spotlight 的
/// kMDItemLastUsedDate（不稳定）；纯逻辑 `updateMRU` 独立成静态函数便于单测。
@MainActor
final class AppCatalogStore: ObservableObject {
    static let shared = AppCatalogStore()

    @Published private(set) var apps: [LauncherApp] = []
    @Published private(set) var isLoaded = false

    /// 最近使用（最新在前），空搜索时按此顺序展示
    private(set) var recentIDs: [String] = []
    private var recentTimestamps: [String: Date] = [:]

    private var iconCache: [String: NSImage] = [:]
    private var lastScanDate: Date?
    private var isScanning = false
    private let scanStaleInterval: TimeInterval = 300

    private var metadataQuery: NSMetadataQuery?
    private var spotlightTimeoutWork: DispatchWorkItem?

    private let mruIDsKey = "launcherMruApps"
    private let mruTimestampsKey = "launcherMruTimestamps"
    private let mruLimit = 10

    private init() {}

    /// 面板每次 show 时调用：**缓存优先**——先读磁盘缓存立即出结果（秒开），
    /// 缓存缺失才同步等扫描；缓存过期（>5 分钟）则后台重扫、扫完经 catalogDidUpdate 静默刷新
    func loadIfNeeded() {
        loadMRU()
        loadCachedCatalogIfAvailable()
        if let last = lastScanDate, isLoaded, Date().timeIntervalSince(last) < scanStaleInterval {
            return
        }
        rescan()
    }

    func app(withID id: String) -> LauncherApp? {
        apps.first { $0.id == id }
    }

    func lastLaunchedDate(for id: String) -> Date? {
        recentTimestamps[id]
    }

    // MARK: - 图标（预缩放位图缓存：行渲染零解码成本）

    /// 行内图标 32pt × Retina 2x = 64px；缓存这个尺寸的位图，
    /// 避免每次行首建让 SwiftUI 光栅化 NSWorkspace 的大尺寸原图（首键 87ms 卡顿的元凶）
    nonisolated static let iconPixelSide: CGFloat = 64

    func icon(for app: LauncherApp) -> NSImage {
        if let cached = iconCache[app.id] { return cached }
        let image = Self.downscaledIcon(url: app.url, side: Self.iconPixelSide)
        iconCache[app.id] = image
        return image
    }

    /// 文件图标（`f ` 文件搜索模式），与应用图标共用缩放缓存（key 加 file: 前缀隔离）
    func fileIcon(for url: URL) -> NSImage {
        let key = "file:" + url.path
        if let cached = iconCache[key] { return cached }
        let image = Self.downscaledIcon(url: url, side: Self.iconPixelSide)
        iconCache[key] = image
        return image
    }

    /// 取应用图标并缩放为 side×side 位图（NSBitmapImageRep 上下文绘制，可在后台线程跑）
    nonisolated static func downscaledIcon(url: URL, side: CGFloat) -> NSImage {
        let source = NSWorkspace.shared.icon(forFile: url.path)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return source }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = ctx
        ctx?.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        return image
    }

    // MARK: - MRU

    /// 启动应用时记录最近使用
    func recordLaunch(_ app: LauncherApp) {
        recentIDs = Self.updateMRU(recentIDs, inserting: app.id, limit: mruLimit)
        recentTimestamps[app.id] = Date()
        UserDefaults.standard.set(recentIDs, forKey: mruIDsKey)
        UserDefaults.standard.set(recentTimestamps, forKey: mruTimestampsKey)
    }

    /// MRU 更新纯函数：新 id 插到最前、去重、截断到 limit
    nonisolated static func updateMRU(_ ids: [String], inserting id: String, limit: Int = 10) -> [String] {
        var updated = [id] + ids.filter { $0 != id }
        if updated.count > limit {
            updated = Array(updated.prefix(limit))
        }
        return updated
    }

    private func loadMRU() {
        recentIDs = UserDefaults.standard.stringArray(forKey: mruIDsKey) ?? []
        recentTimestamps = UserDefaults.standard.dictionary(forKey: mruTimestampsKey) as? [String: Date] ?? [:]
    }

    // MARK: - 目录磁盘缓存（首开秒显，后台刷新）

    /// 缓存文件位置：按 Bundle ID 分目录（dev 变体与生产隔离）；测试进程重定向到隔离根
    nonisolated static var catalogCacheURL: URL {
        if let testRoot = ProcessInfo.processInfo.environment["QN_TEST_STORAGE_ROOT"] {
            return URL(fileURLWithPath: testRoot, isDirectory: true)
                .appendingPathComponent("LauncherAppCatalog.json")
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let dirName = Bundle.main.bundleIdentifier ?? "com.quitenote.app"
        return appSupport.appendingPathComponent(dirName, isDirectory: true)
            .appendingPathComponent("LauncherAppCatalog.json")
    }

    private nonisolated static let catalogCacheVersion = 1

    /// 编码（纯函数，单测覆盖）：预计算字段一并持久化，恢复零重算
    nonisolated static func encodeCatalog(_ apps: [LauncherApp], scannedAt: Date) -> Data? {
        struct Wrapper: Codable {
            let version: Int
            let scannedAt: Date
            let apps: [LauncherApp]
        }
        let wrapper = Wrapper(version: catalogCacheVersion, scannedAt: scannedAt, apps: apps)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(wrapper)
    }

    /// 解码（纯函数）：版本不符（模型演进）返回 nil 丢弃缓存
    nonisolated static func decodeCatalog(_ data: Data) -> (apps: [LauncherApp], scannedAt: Date)? {
        struct Wrapper: Codable {
            let version: Int
            let scannedAt: Date
            let apps: [LauncherApp]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let wrapper = try? decoder.decode(Wrapper.self, from: data),
              wrapper.version == catalogCacheVersion else { return nil }
        return (wrapper.apps, wrapper.scannedAt)
    }

    /// 读缓存立即填充目录（面板秒开的关键路径；文件读取 <50ms）
    private func loadCachedCatalogIfAvailable() {
        guard apps.isEmpty, !isLoaded else { return }
        guard let data = try? Data(contentsOf: Self.catalogCacheURL),
              let decoded = Self.decodeCatalog(data), !decoded.apps.isEmpty else { return }
        apps = decoded.apps
        isLoaded = true
        lastScanDate = decoded.scannedAt
        QuiteNoteNotification.post(.appLauncherCatalogDidUpdate)
        DiagnosticCenter.info("Launcher", "应用目录缓存已加载：\(decoded.apps.count) 个（扫描于 \(decoded.scannedAt.formatted(.dateTime.month().day().hour().minute()))）")
    }

    /// 扫描完成后落盘（后台队列；原子写）
    private func saveCatalogCache(_ apps: [LauncherApp]) {
        let url = Self.catalogCacheURL
        guard let data = Self.encodeCatalog(apps, scannedAt: Date()) else { return }
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - 扫描

    func rescan() {
        guard !isScanning else { return }
        isScanning = true
        DiagnosticCenter.info("Launcher", "开始扫描应用目录")
        scanViaSpotlight { [weak self] spotlightApps in
            guard let self else { return }
            if let spotlightApps, spotlightApps.count >= 20 {
                self.finishScan(raw: spotlightApps, source: "Spotlight")
                return
            }
            // Spotlight 结果太少（索引关闭/沙盒受限/超时）→ 目录扫描兜底，两路合并去重
            DispatchQueue.global(qos: .utility).async {
                let dirApps = Self.scanDirectoryApps()
                let merged = (spotlightApps ?? []) + dirApps
                let source = spotlightApps == nil ? "目录扫描（Spotlight 超时）" : "目录扫描（Spotlight 结果过少）"
                DispatchQueue.main.async {
                    self.finishScan(raw: merged, source: source)
                }
            }
        }
    }

    /// Spotlight 主路径；完成/超时后回调（主线程）。nil = 超时或失败。
    private func scanViaSpotlight(completion: @escaping ([LauncherApp]?) -> Void) {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemContentType == %@", "com.apple.application")
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        metadataQuery = query

        var didFinish = false
        var observer: NSObjectProtocol?
        weak var weakQuery = query

        func finish(_ apps: [LauncherApp]?) {
            guard !didFinish else { return }
            didFinish = true
            if let observer { NotificationCenter.default.removeObserver(observer) }
            weakQuery?.stop()
            completion(apps)
        }

        observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: .main
        ) { _ in
            let apps = query.results.compactMap { result -> LauncherApp? in
                guard let item = result as? NSMetadataItem,
                      let path = item.value(forAttribute: "kMDItemPath") as? String else { return nil }
                let name = Self.cleanAppName(
                    (item.value(forAttribute: "kMDItemDisplayName") as? String)
                        ?? (path as NSString).lastPathComponent
                )
                let bundleID = (item.value(forAttribute: "kMDItemCFBundleIdentifier") as? String) ?? ""
                return LauncherApp(name: name, bundleID: bundleID,
                                   url: URL(fileURLWithPath: path),
                                   isSystem: path.hasPrefix("/System/"))
            }
            finish(apps)
        }

        // 超时兜底：Spotlight 无响应 2 秒视为不可用，交目录扫描接管
        let timeout = DispatchWorkItem { finish(nil) }
        spotlightTimeoutWork = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: timeout)

        query.start()
    }

    /// 目录扫描兜底（非沙盒可用）：只扫标准目录的一层 .app（深层嵌套如 Adobe 套件跳过）
    nonisolated static func scanDirectoryApps() -> [LauncherApp] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let directories = [
            "/Applications",
            "/System/Applications",
            "/Applications/Utilities",
            "/System/Applications/Utilities",
            home + "/Applications",
        ]
        var results: [LauncherApp] = []
        for dir in directories {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(entry)
                let name = Self.cleanAppName(fm.displayName(atPath: url.path))
                let bundleID = Bundle(url: url)?.bundleIdentifier ?? ""
                results.append(LauncherApp(name: name, bundleID: bundleID, url: url,
                                           isSystem: dir.hasPrefix("/System")))
            }
        }
        return results
    }

    private func finishScan(raw: [LauncherApp], source: String) {
        let apps = Self.dedup(raw)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.apps = apps
        isLoaded = true
        isScanning = false
        lastScanDate = Date()
        // 图标缓存只保留仍存在的应用，防卸载后常驻
        let ids = Set(apps.map(\.id))
        iconCache = iconCache.filter { ids.contains($0.key) }
        DiagnosticCenter.info("Launcher", "应用目录扫描完成：\(apps.count) 个应用（\(source)）")
        QuiteNoteNotification.post(.appLauncherCatalogDidUpdate)
        saveCatalogCache(apps)
        prefetchIcons(for: apps)
    }

    /// 图标后台预取 + 预缩放：NSWorkspace.icon 首次加载慢（读文件+图标服务），
    /// 且大尺寸 representation 若留给行渲染时光栅化会拖主线程（实测首键提交 87ms）。
    /// 扫描完成后后台一次性取齐并缩放为 64px 位图，主线程只做缓存合并。
    private func prefetchIcons(for apps: [LauncherApp]) {
        let missing = apps.filter { iconCache[$0.id] == nil }
        guard !missing.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var loaded: [String: NSImage] = [:]
            for app in missing {
                loaded[app.id] = Self.downscaledIcon(url: app.url, side: Self.iconPixelSide)
            }
            let result = loaded
            DispatchQueue.main.async {
                guard let self else { return }
                self.iconCache.merge(result) { current, _ in current }
                DiagnosticCenter.info("Launcher", "图标预取完成：\(result.count) 个")
            }
        }
    }

    /// 按 id（bundleID，缺省路径）去重，保留先出现的（Spotlight 结果优先于目录扫描）
    nonisolated static func dedup(_ apps: [LauncherApp]) -> [LauncherApp] {
        var seen = Set<String>()
        return apps.filter { seen.insert($0.id).inserted }
    }

    /// 显示名去掉 .app 后缀（kMDItemDisplayName 通常已不带；displayName(atPath:) 可能带）
    nonisolated static func cleanAppName(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
