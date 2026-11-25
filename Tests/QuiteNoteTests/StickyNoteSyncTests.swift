import XCTest
@testable import QuiteNote

/// 便利贴 ↔ 记录同步：直接调用 RecordStore 并使用返回值（不经通知绕路）
///
/// 隔离库在同进程的各测试类之间共享，里面可能有别的测试留下的记录：
/// 断言只看自己建的记录，结束时也只删自己建的记录
@MainActor
final class StickyNoteSyncTests: StickyNoteTestCase {
    private var manager: StickyNoteManager!
    private var store: RecordStore!
    /// 本用例新建的记录（便签记录、填充记录），tearDown 逐条删掉
    private var createdRecords: [QuiteNote.Record] = []

    override func setUp() {
        super.setUp()
        manager = warmUpStickyManager()
        store = makeIsolatedStore()
        manager.recordStore = store
    }

    override func tearDown() {
        manager.recordStore = nil
        for record in createdRecords {
            store.delete(record)
        }
        createdRecords = []
        manager = nil
        store = nil
        super.tearDown()
    }

    /// 内存里便签类型记录的 id 集合。断言"没有新建记录"时比较它前后是否一致——
    /// 别的测试类会在共用库里留下记录，记录总数不可用
    private func noteRecordIDs() -> Set<UUID> {
        Set(store.records.filter { $0.type == .note }.map(\.id))
    }

    /// 直接查库（只读、同步）。「更新记录」是同步写库的，调用返回后就能查到最新值
    private func rowInDatabase(_ id: UUID) -> QuiteNote.Record? {
        try? RecordRepository().find(id: id)
    }

    /// 往隔离库里写一条记录（记进 createdRecords，用例结束后删除）
    @discardableResult
    private func addRecord(_ content: String, type: QuiteNote.RecordType = .text, starred: Bool = false) -> QuiteNote.Record? {
        let hash = "sync-test-\(UUID())"
        guard let created = store.addRecord(content: content, hash: hash, type: type, skipAI: true) else { return nil }
        createdRecords.append(created)
        drainMainQueue()
        if starred, let stored = store.records.first(where: { $0.id == created.id }) {
            store.toggleStar(stored)
            drainMainQueue()
        }
        let current = store.records.first(where: { $0.id == created.id }) ?? created
        createdRecords[createdRecords.count - 1] = current
        return current
    }

    /// 同步成功后把关联的记录记下来，用例结束时删除
    private func trackCreatedRecord(noteID: UUID) {
        if let id = note(noteID)?.syncRecordId, let record = store.records.first(where: { $0.id == id }) {
            createdRecords.append(record)
        }
    }

    private func addNote(_ firstPage: String, secondPage: String = "", syncRecordId: UUID? = nil) -> StickyNoteModel {
        let note = StickyNoteModel(
            pages: [StickyNotePage(content: firstPage), StickyNotePage(content: secondPage)],
            syncRecordId: syncRecordId
        )
        manager.notes.append(note)
        return note
    }

    /// addRecord 把记录插进内存列表是排在下一次主队列循环里做的，保存后排空再断言
    private func sync(_ id: UUID) -> Result<UUID, StickyNoteManager.SyncFailure> {
        let result = manager.syncToRecord(noteID: id)
        drainMainQueue()
        trackCreatedRecord(noteID: id)
        return result
    }

    private func note(_ id: UUID) -> StickyNoteModel? {
        manager.notes.first { $0.id == id }
    }

    private func record(_ id: UUID) -> QuiteNote.Record? {
        store.records.first { $0.id == id }
    }

    private final class Probe {
        var pinned: Bool?
    }

    // MARK: - 新建记录

    /// 旧实现的回执把 records[0] 当成"刚建的新记录"，而列表是收藏优先排序的：
    /// 只要有收藏记录，便利贴就关联到收藏记录上，之后更新会覆盖收藏记录的正文
    func testSyncLinksTheStickyToItsOwnRecordEvenWhenStarredRecordsExist() {
        guard let starred = addRecord("收藏的重要记录", starred: true) else {
            XCTFail("前置条件：收藏记录应建成")
            return
        }
        XCTAssertEqual(store.records.first?.id, starred.id, "前置条件：收藏记录排在列表第一位")

        let sticky = addNote("便签正文")
        let result = sync(sticky.id)

        guard case .success(let recordID) = result else {
            XCTFail("应保存成功，实际 \(result)")
            return
        }
        XCTAssertNotEqual(recordID, starred.id, "便利贴不能关联到收藏记录")
        XCTAssertEqual(note(sticky.id)?.syncRecordId, recordID)
        XCTAssertEqual(record(recordID)?.type, .note)
        XCTAssertEqual(record(recordID)?.content, "便签正文")
        XCTAssertEqual(record(starred.id)?.content, "收藏的重要记录", "收藏记录的正文不得被覆盖")
        XCTAssertEqual(record(starred.id)?.starred, true, "收藏状态也不得被改动")

        XCTAssertEqual(storedRecord(recordID, until: { $0.content == "便签正文" })?.content, "便签正文", "新记录应已落库")
        XCTAssertEqual(storedRecord(starred.id, until: { $0.starred })?.content, "收藏的重要记录", "收藏记录在库里原样")
    }

    func testBlankNoteIsNotSaved() {
        let blank = addNote("   ", secondPage: "")
        let before = noteRecordIDs()
        XCTAssertEqual(sync(blank.id), .failure(.blankContent))
        XCTAssertEqual(noteRecordIDs(), before, "空便签不应产生记录")
        XCTAssertNil(note(blank.id)?.syncRecordId)
    }

    func testSyncWithoutRecordStoreReportsUnavailable() {
        manager.recordStore = nil
        let sticky = addNote("内容")
        XCTAssertEqual(sync(sticky.id), .failure(.storeUnavailable))
    }

    // MARK: - 更新记录

    func testSyncUpdatesTheLinkedRecordInsteadOfCreatingAnother() {
        let sticky = addNote("第一版")
        guard case .success(let recordID) = sync(sticky.id) else {
            XCTFail("首次保存应成功")
            return
        }
        let noteRecordsBefore = noteRecordIDs()

        var pages = note(sticky.id)!.pages
        pages[0].content = "第二版"
        manager.updateContent(noteID: sticky.id, pages: pages, currentPageIndex: 0)
        let frame = NSRect(x: 10, y: 20, width: 320, height: 240)
        manager.setFrame(noteID: sticky.id, frame: frame)

        XCTAssertEqual(sync(sticky.id), .success(recordID))
        XCTAssertEqual(noteRecordIDs(), noteRecordsBefore, "更新不应再建一条记录")
        XCTAssertEqual(record(recordID)?.content, "第二版")
        XCTAssertEqual(record(recordID)?.title, "第二版", "标题跟随首行")
        XCTAssertEqual(record(recordID)?.noteFrame, frame, "记录记住便利贴的位置")
        XCTAssertEqual(rowInDatabase(recordID)?.content, "第二版", "更新应已写进数据库")
    }

    /// 「保存到记录」返回成功时，记录必须已经在库里。启动后的僵尸清理按"关联的记录在不在库里"
    /// 决定要不要删便利贴：记录若还在后台排队没落库，刚同步的便利贴会被当成僵尸删掉
    func testSavePutsTheRecordInTheDatabaseBeforeLinkingTheSticky() {
        let sticky = addNote("同步落库的便签")

        XCTAssertEqual(sync(sticky.id), .success(note(sticky.id)!.syncRecordId!))
        XCTAssertEqual(rowInDatabase(note(sticky.id)!.syncRecordId!)?.content, "同步落库的便签", "调用返回时记录已在库中")
    }

    /// 旧实现里窗口缓存着创建时的便签副本，保存回执时用它回写管理器，
    /// 重启后在新恢复的便利贴里改的内容会被冲回启动时的样子
    func testSyncKeepsEditsMadeAfterRestore() {
        let restored = addNote("重启前的内容")
        var pages = restored.pages
        pages[0].content = "重启前的内容 + 新输入"
        manager.updateContent(noteID: restored.id, pages: pages, currentPageIndex: 0)

        guard case .success(let recordID) = sync(restored.id) else {
            XCTFail("保存应成功")
            return
        }

        XCTAssertEqual(note(restored.id)?.pages[0].content, "重启前的内容 + 新输入", "同步后管理器里的内容不能回退")
        XCTAssertEqual(record(recordID)?.content, "重启前的内容 + 新输入")
    }

    func testClearingAPageIsWrittenToTheRecord() {
        let sticky = addNote("保留", secondPage: "将被清空")
        guard case .success(let recordID) = sync(sticky.id) else {
            XCTFail("首次保存应成功")
            return
        }
        XCTAssertEqual(record(recordID)?.content, "保留\(StickyNoteManager.pageSeparator)将被清空")

        var pages = note(sticky.id)!.pages
        pages[1].content = ""          // 用户把第 2 页内容全删
        manager.updateContent(noteID: sticky.id, pages: pages, currentPageIndex: 0)
        _ = sync(sticky.id)

        XCTAssertEqual(note(sticky.id)?.pages[1].content, "", "被清空的页要真的清掉")
        XCTAssertEqual(record(recordID)?.content, "保留", "已删内容不能留在记录里")
    }

    /// 记录上的底色丢了（比如装回过旧版本再升回来，记录里没有底色）：点「更新记录」时跟着同步回来
    func testSyncingAgainRestoresTheColorOnTheRecord() {
        let sticky = addNote("琥珀色便签")
        guard case .success(let recordID) = sync(sticky.id) else {
            XCTFail("首次保存应成功")
            return
        }
        store.updateNoteColor(id: recordID, color: nil)          // 模拟：记录上的底色没了
        XCTAssertNil(rowInDatabase(recordID)?.noteColor)

        manager.setColor(noteID: sticky.id, color: .amber)

        // 未经 setColor 的即时同步、直接改库的情况：以一次「更新记录」兜底
        store.updateNoteColor(id: recordID, color: nil)
        XCTAssertEqual(sync(sticky.id), .success(recordID))
        XCTAssertEqual(rowInDatabase(recordID)?.noteColor, StickyNoteColor.amber.rawValue)
        XCTAssertEqual(record(recordID)?.noteColor, StickyNoteColor.amber.rawValue)
    }

    /// 关联的记录已不存在：解除关联并如实报告，再同步时另存为新记录
    func testSyncReportsMissingRecordAndClearsTheLink() {
        let missingRecordID = UUID()
        let sticky = addNote("便利贴内容", syncRecordId: missingRecordID)   // 指向一条已不存在的记录

        XCTAssertEqual(sync(sticky.id), .failure(.recordMissing))
        XCTAssertNil(note(sticky.id)?.syncRecordId, "关联应解除")

        guard case .success(let newRecordID) = sync(sticky.id) else {
            XCTFail("解除关联后应能另存为新记录")
            return
        }
        XCTAssertEqual(record(newRecordID)?.content, "便利贴内容")
        XCTAssertEqual(note(sticky.id)?.syncRecordId, newRecordID)
    }

    /// 内存里只保留最近 100~200 条记录，便利贴关联的往往是几个月前的记录。
    /// 旧实现更新时只查内存，查不到就当成"记录不存在"，同步静默失效
    func testSyncUpdatesARecordThatSlidOutOfTheMemoryWindow() {
        let sticky = addNote("很早之前保存的便签")
        guard case .success(let recordID) = sync(sticky.id) else {
            XCTFail("首次保存应成功")
            return
        }
        let baseline = (try? RecordRepository().getCount()) ?? 0
        for index in 0..<101 {                       // 之后产生了 100 多条更新的记录
            addRecord("后来的记录 \(index)")
        }
        XCTAssertTrue(waitUntil { ((try? RecordRepository().getCount()) ?? -1) == baseline + 101 }, "前置条件：后来的记录都已落库")

        // 模拟重启：新 store 的首屏只取最新 100 条，便签记录不在内存里
        let relaunched = makeIsolatedStore()
        XCTAssertFalse(relaunched.records.contains { $0.id == recordID }, "前置条件：便签记录已滑出内存窗口")
        manager.recordStore = relaunched

        var pages = note(sticky.id)!.pages
        pages[0].content = "便签里的最新内容"
        manager.updateContent(noteID: sticky.id, pages: pages, currentPageIndex: 0)

        XCTAssertEqual(sync(sticky.id), .success(recordID), "记录还在库里，更新必须成功")
        XCTAssertEqual(rowInDatabase(recordID)?.content, "便签里的最新内容", "最新内容应写进那条老记录")
        XCTAssertEqual(note(sticky.id)?.syncRecordId, recordID, "关联不应被解除")
    }

    // MARK: - 底色

    func testSavingANoteCarriesItsColorIntoTheRecord() {
        let sticky = addNote("有颜色的便签")
        manager.setColor(noteID: sticky.id, color: .teal)

        guard case .success(let recordID) = sync(sticky.id) else {
            XCTFail("保存应成功")
            return
        }
        XCTAssertEqual(record(recordID)?.noteColor, "teal")
        XCTAssertEqual(storedRecord(recordID, until: { $0.noteColor == "teal" })?.noteColor, "teal", "底色应随记录落库")
    }

    /// 换底色是即时生效的：已同步的便利贴不用再点「更新记录」，记录卡片就跟着变色
    func testChangingTheColorOfASyncedNoteUpdatesTheRecordImmediately() {
        let sticky = addNote("便签")
        guard case .success(let recordID) = sync(sticky.id) else {
            XCTFail("保存应成功")
            return
        }

        manager.setColor(noteID: sticky.id, color: .brick)

        XCTAssertEqual(note(sticky.id)?.color, .brick)
        XCTAssertEqual(record(recordID)?.noteColor, "brick", "内存里的记录立即更新")
        XCTAssertEqual(StickyNoteManager.decodeNotes(from: storedStickyNotesData() ?? Data()).first?.color, .brick,
                       "便利贴自己的底色立即落盘")
        XCTAssertEqual(rowInDatabase(recordID)?.noteColor, "brick", "记录的底色同步写进数据库")
    }

    func testChangingTheColorOfAnUnsyncedNoteDoesNotTouchRecords() {
        let sticky = addNote("未同步的便签")
        let before = noteRecordIDs()
        manager.setColor(noteID: sticky.id, color: .violet)
        XCTAssertEqual(note(sticky.id)?.color, .violet)
        XCTAssertEqual(noteRecordIDs(), before)
        XCTAssertNil(note(sticky.id)?.syncRecordId, "换颜色不应顺便建立同步")
    }

    func testOpeningARecordRestoresItsColor() {
        func storedRecord(color: String?) -> QuiteNote.Record {
            QuiteNote.Record(
                id: UUID(), content: "内容", createdAt: Date(), hash: "colored-\(UUID())", type: .note, noteColor: color
            )
        }
        XCTAssertEqual(manager.noteForOpening(record: storedRecord(color: StickyNoteColor.brick.rawValue), defaultFrame: .zero).color, .brick)
        XCTAssertEqual(manager.noteForOpening(record: storedRecord(color: nil), defaultFrame: .zero).color, .blue,
                       "没存颜色的老记录按默认深蓝")
        XCTAssertEqual(manager.noteForOpening(record: storedRecord(color: "不认识的值"), defaultFrame: .zero).color, .blue)
    }

    /// 从记录再打开时，便利贴用记录里存的底色（在别处换过颜色的记录也能还原）
    func testDefaultColorForNewNotesRoundTripsThroughPreferences() {
        XCTAssertEqual(manager.defaultColorForNewNotes, .blue)
        manager.defaultColorForNewNotes = .amber
        XCTAssertEqual(manager.defaultColorForNewNotes, .amber)
        manager.defaultColorForNewNotes = .blue
    }

    // MARK: - 从记录打开

    /// 已关联的便利贴里可能有还没同步的新输入，从卡片打开时不能用记录内容覆盖
    func testOpeningARecordKeepsUnsyncedEditsInTheLinkedNote() {
        let sticky = addNote("记录里的旧内容")
        guard case .success(let recordID) = sync(sticky.id),
              let stored = record(recordID) else {
            XCTFail("首次保存应成功")
            return
        }
        var pages = note(sticky.id)!.pages
        pages[0].content = "便利贴里的新输入"
        manager.updateContent(noteID: sticky.id, pages: pages, currentPageIndex: 0)

        let opened = manager.noteForOpening(record: stored, defaultFrame: .zero)

        XCTAssertEqual(opened.id, sticky.id)
        XCTAssertEqual(note(sticky.id)?.pages[0].content, "便利贴里的新输入")
        XCTAssertEqual(manager.notes.count, 1, "同一条记录不应再开第二张便利贴")
    }

    func testOpeningAnUnlinkedRecordCreatesANoteFromItsContent() {
        let stored = QuiteNote.Record(
            id: UUID(), content: "第一页\n\(StickyNoteManager.pageSeparator)第二页", createdAt: Date(),
            hash: "unlinked-\(UUID())", type: .note, noteFrame: NSRect(x: 1, y: 2, width: 300, height: 200)
        )

        let opened = manager.noteForOpening(record: stored, defaultFrame: .zero)

        XCTAssertEqual(opened.syncRecordId, stored.id)
        XCTAssertEqual(opened.pages.map(\.content), ["第一页", "第二页", ""])
        XCTAssertEqual(opened.frame, stored.noteFrame)
        XCTAssertEqual(manager.notes.count, 1)
    }

    // MARK: - 记录库事件

    func testDeletingTheRecordRemovesTheLinkedNote() {
        let sticky = addNote("内容")
        guard case .success(let recordID) = sync(sticky.id),
              let stored = record(recordID) else {
            XCTFail("保存应成功")
            return
        }

        store.delete(stored)

        XCTAssertNil(note(sticky.id), "记录删了，关联的便利贴随之移除")
    }

    func testClearingAllRecordsRemovesOnlySyncedNotes() {
        // clearAll 是对整库的后台批量删除，只能在独立的私有库上做
        let privateStore = makePrivateStore()
        withExtendedLifetime(privateStore.store) {
            manager.recordStore = privateStore.store
        let synced = addNote("已同步")
        let unsynced = addNote("未同步")
        guard case .success(let recordID) = sync(synced.id) else {
            XCTFail("保存应成功")
            return
        }

        privateStore.store.clearAll()

            XCTAssertNil(note(synced.id), "已同步的便利贴随之移除")
            XCTAssertNotNil(note(unsynced.id), "没同步过的便利贴与记录无关，应保留")
            XCTAssertTrue(waitUntil { ((try? privateStore.repository.getCount()) ?? -1) == 0 }, "私有库里的记录应被清空")
        }
    }

    func testZombieCleanupOnlyRemovesNotesWhoseRecordIsGone() {
        let aliveRecordID = UUID()
        let alive = addNote("记录还在", syncRecordId: aliveRecordID)
        let gone = addNote("记录没了", syncRecordId: UUID())

        manager.cleanupZombieNotes { recordID in recordID == aliveRecordID }

        XCTAssertNotNil(note(alive.id))
        XCTAssertNil(note(gone.id))
    }

    // MARK: - 固定到所有 Space

    func testPinningIsPersistedAndReported() {
        let sticky = addNote("内容")
        let probe = Probe()
        let token = NotificationCenter.default.addObserver(
            forName: QuiteNoteNotification.stickyNotePinChanged.name, object: nil, queue: .main
        ) { notification in
            if notification.object as? UUID == sticky.id {
                probe.pinned = notification.userInfo?["pinned"] as? Bool
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        manager.setPinned(noteID: sticky.id, pinned: true)

        XCTAssertEqual(note(sticky.id)?.pinnedToAllSpaces, true)
        XCTAssertEqual(probe.pinned, true)
        XCTAssertEqual(
            StickyNoteManager.decodeNotes(from: storedStickyNotesData() ?? Data()).first?.pinnedToAllSpaces,
            true, "固定状态应立即落盘"
        )
    }
}
