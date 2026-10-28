import QuiteNoteSharedStorage
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
    /// entries 内容版本号：任何变更（增删/置顶/OCR/翻页/重载）+1。
    /// 列表格子的"数据变没变"签名用 count+version O(1) 判定，替代旧 O(n) 签名串
    private(set) var entriesVersion = 0

    private func bumpVersion() { entriesVersion += 1 }
    @Published private(set) var isLoaded = false
    @Published private(set) var storageErrorDescription: String?

    private let persistence: ClipboardHistoryPersistence
    /// immutable 依赖：后台搜索只取仓库引用，CoreData 排队由仓库内部完成。
    private nonisolated let repository: ClipboardHistoryRepository
    private var remoteChangeObserverID: UUID?
    /// 防止图片文件删除与批量清理重入
    private var isApplyingRetention = false
    /// 周期自动清理（每 6 小时；捕获/启动时也会即时触发）
    private var retentionTimer: Timer?

    init(persistence: ClipboardHistoryPersistence = .shared) {
        self.persistence = persistence
        self.repository = ClipboardHistoryRepository(persistence: persistence)
        remoteChangeObserverID = repository.addRemoteChangeObserver { [weak self] in
            Task { @MainActor in
                self?.reloadFromRemoteStore()
            }
        }
    }

    deinit {
        if let timer = retentionTimer {
            // Timers must be invalidated on the run loop where they were installed.
            if Thread.isMainThread {
                timer.invalidate()
            } else {
                DispatchQueue.main.async { timer.invalidate() }
            }
        }
        if let remoteChangeObserverID {
            repository.removeRemoteChangeObserver(remoteChangeObserverID)
        }
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
        // A target-based repeating timer retains its target for the lifetime of
        // the run loop, preventing the store and its database from being released.
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyRetentionIfNeeded()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        retentionTimer = t
    }

    func reload() {
        storageErrorDescription = persistence.storageLoadErrorDescription
        entries = repository.fetchPage(limit: Self.pageSize, offset: 0)
        bumpVersion()
        hasMore = repository.totalCount() > entries.count
    }

    private func reloadFromRemoteStore() {
        guard isLoaded else { return }
        reload()
    }

    #if DEBUG
    /// 测试辅助：模拟 App 已完成首屏加载。
    @discardableResult
    func loadIfNeededForTesting() -> Bool {
        let wasLoaded = isLoaded
        loadIfNeeded()
        return wasLoaded
    }

    /// 测试辅助：等价于共享存储远程通知到达后的主线程刷新路径。
    func reloadFromRemoteStoreForTesting() {
        reloadFromRemoteStore()
    }
    #endif

    // MARK: - 按需分页加载（防止大库全量物化撑爆内存）
    //
    // reload 只取首页（置顶优先 + 时间倒序，与列表展示一致）；滚动接近底部时
    // loadMore() 翻下一页；搜索需要全量时 loadAllIfNeeded() 一次性补齐（搜索是
    // 低频动作，一次 DB 取页可接受）。每页 500 条 × 平均几 KB 文本 = 单页几 MB。

    static let pageSize = 500

    /// 是否还有未加载的页（视图据此在滚动近底部时触发 loadMore）
    @Published private(set) var hasMore = false

    /// 滚动近底部时翻下一页（同步主线程：单页 DB 取值 <50ms）
    func loadMore() {
        guard hasMore else { return }
        let next = repository.fetchPage(limit: Self.pageSize, offset: entries.count)
        guard !next.isEmpty else {
            hasMore = false
            return
        }
        entries.append(contentsOf: next)
        bumpVersion()
        let total = repository.totalCount()
        hasMore = total > entries.count
        DiagnosticCenter.info("Clipboard", "按需加载下一页：共 \(entries.count)/\(total) 条")
    }

    /// 搜索前补齐全量（幂等；只补一次）
    func loadAllIfNeeded() {
        guard hasMore else { return }
        let remaining = repository.fetchPage(limit: repository.totalCount() - entries.count, offset: entries.count)
        entries.append(contentsOf: remaining)
        bumpVersion()
        hasMore = false
    }

    /// 搜索用全量读取：后台 context 物化，不把 UI 线程当 CoreData 队列。
    ///
    /// 完成回调固定主线程。这里不改 `entries`：搜索语料是瞬时快照，避免把 UI
    /// 首页/翻页状态一次性撑到全库大小。
    nonisolated func loadAllEntriesInBackground(completion: @escaping ([ClipboardEntry]) -> Void) {
        repository.fetchAllInBackground(completion: completion)
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
        bumpVersion()
        hasMore = false
    }
    #endif

    func entry(id: UUID) -> ClipboardEntry? {
        entries.first { $0.id == id }
    }

    // MARK: - 写入

    /// 新捕获一条剪贴板内容（共享仓库负责去重、upsert 与持久化）
    @discardableResult
    func insertOrUpdate(_ entry: ClipboardEntry) -> ClipboardEntry {
        loadIfNeeded()
        guard let result = try? repository.insertOrUpdate(entry) else {
            DiagnosticCenter.error("Clipboard", "剪贴板写入失败，已保留当前 UI 列表")
            return entry
        }
        let savedEntry = result.entry

        if let index = entries.firstIndex(where: { $0.id == savedEntry.id }) {
            entries[index] = savedEntry
        } else if let index = entries.firstIndex(where: {
            $0.type == savedEntry.type && $0.contentHash == savedEntry.contentHash
        }) {
            entries[index] = savedEntry
        } else {
            let firstUnpinned = entries.firstIndex(where: { !$0.isPinned }) ?? entries.count
            entries.insert(savedEntry, at: min(firstUnpinned, entries.count))
        }
        bumpVersion()
        resortInPlace()

        if result.inserted {
            QuiteNoteNotification.post(.clipboardEntryAdded, object: nil, userInfo: ["id": savedEntry.id])
        }
        DiagnosticCenter.info("Clipboard", "捕获 \(savedEntry.type.rawValue)：hash \(String(savedEntry.contentHash.prefix(8)))… 来源 \(savedEntry.sourceApp ?? "未知")")
        applyRetentionIfNeeded()
        return savedEntry
    }

    /// 粘贴后更新使用统计（PRD 5.2：更新最近复制时间；pasteCount 记录粘贴次数）
    func markPasted(id: UUID) {
        guard let updated = repository.update(id: id, transform: { entry in
            entry.pasteCount += 1
            entry.lastUsedAt = Date()
        }) else { return }
        replaceEntry(updated)
    }

    /// 置顶 / 取消置顶（PRD 3.2：置顶条目不自动清理）
    func togglePin(id: UUID) {
        guard let updated = repository.update(id: id, transform: { entry in
            entry.isPinned.toggle()
        }) else { return }
        replaceEntry(updated)
        resortInPlace()
        bumpVersion()
    }

    /// 更新 OCR 结果（OCR 队列回调）
    func updateOCR(id: UUID, text: String?, status: ClipboardOCRStatus) {
        guard let updated = repository.update(id: id, transform: { entry in
            entry.ocrText = text
            entry.ocrStatus = status
        }) else { return }
        replaceEntry(updated)
        syncSavedImageRecordWithOCR(entry: updated)
    }

    /// 图片加入闪记时可能仍在 OCR 队列。OCR 成功后需要把结果回填正式记录；
    /// 如果 AI 开启且该记录原本因无文本跳过 AI，则回填后立即补触发提炼。
    private func syncSavedImageRecordWithOCR(entry: ClipboardEntry) {
        guard entry.type == .image,
              entry.ocrStatus == .success,
              let recordID = entry.savedRecordID,
              let ocrText = entry.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines),
              let store = ClipboardFlashNoteService.shared.recordStore,
              let record = store.record(id: recordID) else { return }

        guard record.content.trimmingCharacters(in: .whitespacesAndNewlines) != ocrText else { return }
        store.updateImageOCRContent(id: recordID, content: ocrText)
    }

    /// 加入闪记后记录关联
    func linkRecord(entryID: UUID, recordID: UUID?) {
        guard let updated = repository.update(id: entryID, transform: { entry in
            entry.savedRecordID = recordID
        }) else { return }
        replaceEntry(updated)
    }

    private func replaceEntry(_ updated: ClipboardEntry) {
        guard let index = entries.firstIndex(where: { $0.id == updated.id }) else {
            entries.insert(updated, at: min(entries.firstIndex(where: { !$0.isPinned }) ?? entries.count, entries.count))
            bumpVersion()
            return
        }
        entries[index] = updated
        bumpVersion()
    }

    // MARK: - 删除与清理

    /// 删除单条（同步清理图片文件；已加闪记的图片保留——正式记录还在引用它）
    func delete(id: UUID) {
        guard let entry = repository.delete(id: id) else { return }
        entries.removeAll { $0.id == id }
        bumpVersion()
        if entry.savedRecordID == nil {
            removeAssetFiles(entry)
        }
        DiagnosticCenter.info("Clipboard", "删除条目 \(entry.type.rawValue)")
    }

    /// 清空全部历史（PRD 17：不清空已加入闪记的正式记录；图片文件按是否关联闪记决定去留）
    func clearAll() {
        let all = repository.fetchPage(limit: .max, offset: 0)
        entries.removeAll()
        bumpVersion()
        repository.clearAll()
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
        let victims = repository.applyRetention(
            now: Date(),
            retentionDays: prefs.clipboardRetentionDays,
            maxEntries: prefs.clipboardMaxEntries
        )
        guard !victims.isEmpty else { return }
        let ids = Set(victims.map(\.id))
        entries.removeAll { ids.contains($0.id) }
        bumpVersion()
        for entry in victims where entry.savedRecordID == nil {
            removeAssetFiles(entry)
        }
        DiagnosticCenter.info("Clipboard", "保留策略清理 \(ids.count) 条（上限 \(prefs.clipboardMaxEntries)，保留 \(prefs.clipboardRetentionDays) 天）")
    }


    /// 计算应清理的条目 id（共享层纯函数；保留 App 签号方便既有测试与调用）
    /// - 注意：置顶条目永不过期、不占上限清理；已加闪记的条目同样保留（正式记录语义上不该消失）
    nonisolated static func retentionVictims(
        _ entries: [ClipboardEntry],
        now: Date,
        retentionDays: Int,
        maxEntries: Int
    ) -> Set<UUID> {
        ClipboardHistoryRepository.retentionVictims(
            entries,
            now: now,
            retentionDays: retentionDays,
            maxEntries: maxEntries
        )
    }

    // MARK: - 私有

    private func moveToFront(_ index: Int) {
        let entry = entries.remove(at: index)
        entries.insert(entry, at: 0)
        bumpVersion()
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
