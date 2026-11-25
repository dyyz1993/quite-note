import XCTest
@testable import QuiteNote

/// 记录库加载状态：加载失败时不能被当成"记录都没了"——否则已同步的便利贴
/// 会在启动后的僵尸清理里被全部删掉
@MainActor
final class RecordStoreLoadFailureTests: StickyNoteTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("qn-store-load-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        super.tearDown()
    }

    private func corruptStore() -> CoreDataStack {
        let url = tempDirectory.appendingPathComponent("corrupt-\(UUID().uuidString).sqlite")
        try? Data("这不是一个 SQLite 文件，只是一串占用的字节".utf8).write(to: url)
        return CoreDataStack(databaseURL: url)
    }

    func testHealthyStoreLoads() throws {
        let stack = CoreDataStack(databaseURL: tempDirectory.appendingPathComponent("healthy.sqlite"))
        XCTAssertNil(stack.loadError)
        let repository = RecordRepository(stack: stack)
        XCTAssertFalse(repository.isStoreUnavailable)
        XCTAssertFalse(repository.stickyNoteRecordExists(UUID()), "库里没有这条记录就是没有")

        try repository.saveSync(QuiteNote.Record(id: UUID(), content: "内容", createdAt: Date(), hash: "h"))

        XCTAssertEqual(try repository.fetchRecords().count, 1)
    }

    func testCorruptStoreReportsLoadError() {
        let stack = corruptStore()

        XCTAssertNotNil(stack.loadError, "损坏的库必须暴露加载错误，不能静默吞掉")
        let repository = RecordRepository(stack: stack)
        XCTAssertTrue(repository.isStoreUnavailable)
        XCTAssertTrue(repository.stickyNoteRecordExists(UUID()),
                      "库打不开时'查不到'不等于'已删除'，要按记录仍在处理")
    }

    func testUpdatingARecordOnAnUnavailableStoreFailsInsteadOfReportingMissing() {
        let stack = corruptStore()
        guard stack.loadError != nil else {
            XCTFail("前置条件：这个文件应当加载失败")
            return
        }

        let result = RecordStore(repository: RecordRepository(stack: stack))
            .updateContent(id: UUID(), content: "内容", title: nil, noteFrame: nil)

        guard case .failed = result else {
            XCTFail("库打不开时更新必须报失败，不能报记录不存在：\(result)")
            return
        }
    }

    private func appendSyncedNote(to manager: StickyNoteManager) -> StickyNoteModel {
        let synced = StickyNoteModel(pages: [StickyNotePage(content: "已同步的便利贴")], syncRecordId: UUID())
        manager.notes.append(synced)
        return synced
    }

    /// 对照：库正常时，启动后的僵尸清理会移除关联记录已不存在的便利贴
    /// （证明下面那条"库打不开时保留"不是因为清理根本没跑）
    func testStartupCleanupRemovesSyncedNotesWhoseRecordIsGone() {
        let manager = warmUpStickyManager()
        let synced = appendSyncedNote(to: manager)

        let healthy = makePrivateStore()           // 健康的空库：这条记录不存在
        withExtendedLifetime(healthy.store) {
            XCTAssertTrue(waitUntil { manager.notes.first { $0.id == synced.id } == nil },
                          "库正常时，关联记录不存在的便利贴应被清理")
        }
    }

    /// 启动后的僵尸清理走真实的 RecordStore 路径：库打不开时一张便利贴都不能删
    func testStartupCleanupKeepsSyncedNotesWhenTheStoreDidNotLoad() {
        let manager = warmUpStickyManager()
        let synced = appendSyncedNote(to: manager)

        let store = RecordStore(repository: RecordRepository(stack: corruptStore()))
        withExtendedLifetime(store) {
            waitUntil(timeout: 2) { false }       // 给首屏加载和随后的清理留出时间
            XCTAssertEqual(manager.notes.map(\.id), [synced.id], "库没加载成功时不能把已同步的便利贴当僵尸清掉")
        }
    }
}
