import Foundation
import AppKit
import CoreData

/// 剪贴板历史中心 Store
///
/// 内存列表 + 独立 CoreData 持久化；写入走后台 Context，读回后统一发布。
/// 保留策略（PRD 4.3）：普通历史按天数过期 + 总量上限，置顶与已加闪记的条目不自动清理；
/// 清理时同步删除未关联闪记的图片文件。
@MainActor
final class ClipboardHistoryStore: ObservableObject {
    static let shared = ClipboardHistoryStore()

    /// 全部历史条目（置顶在前，其余按复制时间倒序）
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published private(set) var isLoaded = false

    private let persistence: ClipboardHistoryPersistence
    /// 防止图片文件删除与批量清理重入
    private var isApplyingRetention = false
    /// 周期自动清理（每 6 小时；捕获/启动时也会即时触发）
    private var retentionTimer: Timer?

    init(persistence: ClipboardHistoryPersistence = .shared) {
        self.persistence = persistence
    }

    // MARK: - 读取

    func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        DiagnosticCenter.measure("Clipboard", "历史加载", threshold: 0.2) {
            reload()
        }
        applyRetentionIfNeeded()
        startRetentionTimer()
    }

    /// 定期清理：应用长时间运行且用户一直没复制时，过期条目也能被清掉
    private func startRetentionTimer() {
        guard retentionTimer == nil else { return }
        let t = Timer(timeInterval: 6 * 3600, target: self, selector: #selector(retentionTick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        retentionTimer = t
    }

    @objc private func retentionTick() {
        applyRetentionIfNeeded()
    }

    func reload() {
        entries = fetchPage(limit: Self.pageSize, offset: 0)
        hasMore = totalCount() > entries.count
    }

    // MARK: - 按需分页加载（防止大库全量物化撑爆内存）
    //
    // reload 只取首页（置顶优先 + 时间倒序，与列表展示一致）；滚动接近底部时
    // loadMore() 翻下一页；搜索需要全量时 loadAllIfNeeded() 一次性补齐（搜索是
    // 低频动作，一次 DB 取页可接受）。每页 500 条 × 平均几 KB 文本 = 单页几 MB。

    static let pageSize = 500

    /// 是否还有未加载的页（视图据此在滚动近底部时触发 loadMore）
    @Published private(set) var hasMore = false

    private func fetchPage(limit: Int, offset: Int) -> [ClipboardEntry] {
        let request = NSFetchRequest<CDClipboardEntry>(entityName: "CDClipboardEntry")
        request.sortDescriptors = [
            NSSortDescriptor(key: "isPinned", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false),
        ]
        request.fetchLimit = limit
        request.fetchOffset = offset
        let objects = (try? persistence.context.fetch(request)) ?? []
        return objects.map(\.asValue)
    }

    private func totalCount() -> Int {
        let request = NSFetchRequest<CDClipboardEntry>(entityName: "CDClipboardEntry")
        return (try? persistence.context.count(for: request)) ?? 0
    }

    /// 滚动近底部时翻下一页（同步主线程：单页 DB 取值 <50ms）
    func loadMore() {
        guard hasMore else { return }
        let next = fetchPage(limit: Self.pageSize, offset: entries.count)
        guard !next.isEmpty else {
            hasMore = false
            return
        }
        entries.append(contentsOf: next)
        hasMore = totalCount() > entries.count
        DiagnosticCenter.info("Clipboard", "按需加载下一页：共 \(entries.count)/\(totalCount()) 条")
    }

    /// 搜索前补齐全量（幂等；只补一次）
    func loadAllIfNeeded() {
        guard hasMore else { return }
        let remaining = fetchPage(limit: totalCount() - entries.count, offset: entries.count)
        entries.append(contentsOf: remaining)
        hasMore = false
    }

    /// 测试辅助：清空全部条目（仅测试目标可见）
    #if DEBUG
    func deleteAllForTesting() {
        let context = persistence.context
        let request = NSFetchRequest<CDClipboardEntry>(entityName: "CDClipboardEntry")
        let objects = (try? context.fetch(request)) ?? []
        objects.forEach(context.delete)
        try? context.save()
        entries = []
        hasMore = false
    }
    #endif

    func entry(id: UUID) -> ClipboardEntry? {
        entries.first { $0.id == id }
    }

    // MARK: - 写入

    /// 新捕获一条剪贴板内容（PRD 5.2 去重：相同内容只更新时间并置顶展示）
    /// - Returns: 去重命中返回已有条目，新插入返回新条目
    @discardableResult
    func insertOrUpdate(_ entry: ClipboardEntry) -> ClipboardEntry {
        loadIfNeeded()

        if let index = entries.firstIndex(where: { $0.contentHash == entry.contentHash }) {
            var touched = entries[index]
            touched.createdAt = entry.createdAt
            touched.lastUsedAt = entry.lastUsedAt
            // 类型可能升级（比如先复制了文本后来同 hash 不可能变化，仅保守处理）
            entries[index] = touched
            persist(touched)
            moveToFront(index)
            return entries.first { $0.id == touched.id } ?? touched
        }

        entries.insert(entry, at: 0)
        persist(entry)

        QuiteNoteNotification.post(.clipboardEntryAdded, object: nil, userInfo: ["id": entry.id])
        DiagnosticCenter.info("Clipboard", "捕获 \(entry.type.rawValue)：hash \(String(entry.contentHash.prefix(8)))… 来源 \(entry.sourceApp ?? "未知")")

        applyRetentionIfNeeded()
        return entry
    }

    /// 粘贴后更新使用统计（PRD 5.2：更新最近复制时间；pasteCount 记录粘贴次数）
    func markPasted(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].pasteCount += 1
        entries[index].lastUsedAt = Date()
        persist(entries[index])
    }

    /// 置顶 / 取消置顶（PRD 3.2：置顶条目不自动清理）
    func togglePin(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isPinned.toggle()
        let entry = entries[index]
        persist(entry)
        resortInPlace()
    }

    /// 更新 OCR 结果（OCR 队列回调）
    func updateOCR(id: UUID, text: String?, status: ClipboardOCRStatus) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].ocrText = text
        entries[index].ocrStatus = status
        persist(entries[index])
    }

    /// 加入闪记后记录关联
    func linkRecord(entryID: UUID, recordID: UUID?) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].savedRecordID = recordID
        persist(entries[index])
    }

    // MARK: - 删除与清理

    /// 删除单条（同步清理图片文件；已加闪记的图片保留——正式记录还在引用它）
    func delete(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        deletePersisted(id: entry.id)
        if entry.savedRecordID == nil {
            removeAssetFiles(entry)
        }
        DiagnosticCenter.info("Clipboard", "删除条目 \(entry.type.rawValue)")
    }

    /// 清空全部历史（PRD 17：不清空已加入闪记的正式记录；图片文件按是否关联闪记决定去留）
    func clearAll() {
        let all = entries
        entries.removeAll()
        let context = persistence.context
        let request = NSFetchRequest<CDClipboardEntry>(entityName: "CDClipboardEntry")
        if let objects = try? context.fetch(request) {
            objects.forEach(context.delete)
        }
        try? context.save()
        for entry in all where entry.savedRecordID == nil {
            removeAssetFiles(entry)
        }
        DiagnosticCenter.info("Clipboard", "清空全部剪贴板历史（\(all.count) 条）")
    }

    /// 立即执行保留策略（设置页「清理过期记录」按钮）
    func cleanExpiredNow() {
        applyRetentionIfNeeded(force: true)
    }

    // MARK: - 磁盘占用统计（设置页展示）

    @Published private(set) var diskUsageBytes: Int64 = 0

    /// 后台统计剪贴板历史占用：附件图片目录 + 数据库文件（含 -wal/-shm）
    func refreshDiskUsage() {
        let clipDir = FileCoordinator.shared.getDirectoryURL(for: .clipboard)
        let dbPath = persistence.storeURL.path
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fm = FileManager.default
            var total: Int64 = 0
            if let enumerator = fm.enumerator(at: clipDir, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let url as URL in enumerator {
                    total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
            }
            for suffix in ["", "-wal", "-shm"] {
                let url = URL(fileURLWithPath: dbPath + suffix)
                total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            DispatchQueue.main.async {
                self?.diskUsageBytes = total
            }
        }
    }

    /// 保留策略（纯函数计算 + 应用，PRD 4.3）：
    /// 1. 未置顶且超过保留天数的条目过期；2. 超过数量上限时按最旧清理未置顶条目。
    private func applyRetentionIfNeeded(force: Bool = false) {
        guard !isApplyingRetention else { return }
        isApplyingRetention = true
        defer { isApplyingRetention = false }

        let prefs = PreferencesManager.shared
        let ids = Self.retentionVictims(entries, now: Date(), retentionDays: prefs.clipboardRetentionDays, maxEntries: prefs.clipboardMaxEntries)
        guard !ids.isEmpty else { return }

        let victims = entries.filter { ids.contains($0.id) }
        entries.removeAll { ids.contains($0.id) }
        let context = persistence.context
        // 先刷新全部注册对象再删除：清理流程没有合法的待存修改（条目变更已由
        // persist 落库），旧快照若与 DB 不一致（外部改动过），save 时会抛
        // CoreData 乐观锁 NSException（try? 接不住，直接闪退——2026-09-12 实锤）。
        // persist() 里不能这么做（会丢掉刚 apply 的数据），那里单行现取现改无此风险
        context.refreshAllObjects()
        let request = NSFetchRequest<CDClipboardEntry>(entityName: "CDClipboardEntry")
        request.predicate = NSPredicate(format: "id IN %@", Array(ids))
        if let objects = try? context.fetch(request) {
            objects.forEach(context.delete)
        }
        try? context.save()
        for entry in victims where entry.savedRecordID == nil {
            removeAssetFiles(entry)
        }
        DiagnosticCenter.info("Clipboard", "保留策略清理 \(ids.count) 条（上限 \(prefs.clipboardMaxEntries)，保留 \(prefs.clipboardRetentionDays) 天）")
    }

    /// 计算应清理的条目 id（纯函数，可单测）
    /// - 注意：置顶条目永不过期、不占上限清理；已加闪记的条目同样保留（正式记录语义上不该消失）
    nonisolated static func retentionVictims(
        _ entries: [ClipboardEntry],
        now: Date,
        retentionDays: Int,
        maxEntries: Int
    ) -> Set<UUID> {
        var victims = Set<UUID>()

        // 1. 按时间过期（retentionDays <= 0 视为永不过期）
        if retentionDays > 0 {
            let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86400)
            for entry in entries where !entry.isPinned && entry.savedRecordID == nil && entry.createdAt < cutoff {
                victims.insert(entry.id)
            }
        }

        // 2. 按数量上限（只数「可清理」的条目：未置顶且未加闪记）
        let evictable = entries
            .filter { !$0.isPinned && $0.savedRecordID == nil && !victims.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
        let survivingEvictable = evictable.count - victims.count
        if survivingEvictable > maxEntries {
            let overflow = survivingEvictable - maxEntries
            for entry in evictable.prefix(overflow) {
                victims.insert(entry.id)
            }
        }

        return victims
    }

    // MARK: - 私有

    private func moveToFront(_ index: Int) {
        let entry = entries.remove(at: index)
        entries.insert(entry, at: 0)
        resortInPlace()
    }

    private func resortInPlace() {
        entries.sort { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.createdAt > b.createdAt
        }
    }

    /// 同步持久化单条（viewContext upsert）
    ///
    /// 之前用 performBackgroundTask + fetch-by-id：后台 context 看不到 viewContext
    /// 未保存的行 → fetch 落空 → 重复插入（实测同一 hash 被写成多行，OCR 队列被
    /// 僵尸 waiting 条目喂成死循环）。剪贴板条目写入频率低、单行小，主线程
    /// viewContext 同步 upsert 微秒级完成，正确性优先于后台化。
    private func persist(_ entry: ClipboardEntry) {
        let context = persistence.context
        context.performAndWait {
            let request = NSFetchRequest<CDClipboardEntry>(entityName: "CDClipboardEntry")
            request.predicate = NSPredicate(format: "id == %@", entry.id as CVarArg)
            request.fetchLimit = 1
            let object = (try? context.fetch(request))?.first ?? CDClipboardEntry(context: context)
            object.apply(entry)
            try? context.save()
        }
    }

    private func deletePersisted(id: UUID) {
        let context = persistence.context
        let request = NSFetchRequest<CDClipboardEntry>(entityName: "CDClipboardEntry")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let objects = try? context.fetch(request) {
            objects.forEach(context.delete)
        }
        try? context.save()
    }

    /// 删除条目对应的图片原图（FileCoordinator 每张图独立子目录，删子目录即可）
    private func removeAssetFiles(_ entry: ClipboardEntry) {
        guard let virtualPath = entry.assetPath,
              let url = FileCoordinator.shared.resolveVirtualPath(virtualPath) else { return }
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
                // 原图在唯一子目录里，删整个子目录（FileCoordinator.storeImage 的布局）
                let dirToDelete = isDir.boolValue ? url : url.deletingLastPathComponent()
                try? fm.removeItem(at: dirToDelete)
            }
            ThumbnailGenerator.shared.removeThumbnail(for: url)
        }
    }
}
