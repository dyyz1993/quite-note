import CoreData
import XCTest
@testable import QuiteNote

/// Repository 写库结果回调：异步落库失败不能再被静默吞掉——记录只在内存里、
/// 重启即丢，调用方（RecordStore）要靠 completion 弹 toast 提示用户
@MainActor
final class RecordRepositoryResultTests: StickyNoteTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("qn-repo-result-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - 夹具

    /// 只读库注入：加载成功、写入必失败——比损坏库更可靠的失败开关
    /// （损坏库上后台 save 不一定报错）。模型按 makePrivateStore 的同款做法现做一份
    private func injectReadOnlyStoreFailure(into repository: RecordRepository) throws {
        let model = CoreDataStack.makeModel(includesNoteColor: true, includesFileCount: true)
        let storeURL = tempDirectory.appendingPathComponent("readonly-\(UUID().uuidString).sqlite")
        // 只读挂载要求库文件已存在：先读写建一个空库并干净关闭（WAL 一并收掉）
        try autoreleasepool {
            let bootstrap = NSPersistentStoreCoordinator(managedObjectModel: model)
            let store = try bootstrap.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
            try bootstrap.remove(store)
        }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: [NSReadOnlyPersistentStoreOption: true]
        )
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        repository.backgroundTaskHandler = { block in
            context.perform { block(context) }
        }
    }

    // MARK: - 用例

    func testSaveReportsSuccessOnAHealthyStore() throws {
        let repository = RecordRepository(stack: CoreDataStack(databaseURL: tempDirectory.appendingPathComponent("healthy.sqlite")))
        let record = QuiteNote.Record(id: UUID(), content: "成功路径", createdAt: Date(), hash: "result-ok")

        var result: Result<Void, Error>?
        repository.save(record) { result = $0 }
        XCTAssertTrue(waitUntil { result != nil }, "健康库上后台保存也应回调")

        guard case .success = result else {
            return XCTFail("健康库上应成功：\(String(describing: result))")
        }
        XCTAssertEqual(try repository.find(id: record.id)?.content, "成功路径", "成功回调时记录必须已在库里")
    }

    /// 真实失败路径：只读库上后台 save 报错，completion 必须收到 .failure
    /// （原来的实现把错误吞进后台闭包，调用方的 do/catch 全是死代码）
    func testSaveReportsFailureWhenTheStoreCannotWrite() throws {
        let repository = RecordRepository(stack: CoreDataStack(databaseURL: tempDirectory.appendingPathComponent("doomed.sqlite")))
        try injectReadOnlyStoreFailure(into: repository)
        let record = QuiteNote.Record(id: UUID(), content: "写不进去", createdAt: Date(), hash: "result-fail")

        var result: Result<Void, Error>?
        repository.save(record) { result = $0 }
        XCTAssertTrue(waitUntil { result != nil }, "失败也必须回调，不能静默吞掉")

        guard case .failure = result else {
            return XCTFail("只读库上的写入必须报失败：\(String(describing: result))")
        }
    }

    /// addRecord 非同步路径：落库失败弹错误 toast，让用户知道这条重启会丢
    func testAddRecordShowsAToastWhenTheDatabaseSaveFails() throws {
        let repository = RecordRepository(stack: CoreDataStack(databaseURL: tempDirectory.appendingPathComponent("toast.sqlite")))
        try injectReadOnlyStoreFailure(into: repository)
        let store = RecordStore(repository: repository)
        try withExtendedLifetime(store) {
            store.addRecord(content: "短内容", hash: "toast-\(UUID().uuidString)", skipAI: true)
            XCTAssertTrue(
                waitUntil { store.toast?.text == "记录没能写进数据库，重启后会丢失" && store.toast?.type == "error" },
                "落库失败要弹错误 toast"
            )
        }
    }

    /// delete 失败：内存已删但库里还在，重启后记录会"回来"，必须提示用户重试
    func testDeleteShowsAToastWhenTheDatabaseDeleteFails() {
        let corruptURL = tempDirectory.appendingPathComponent("corrupt-\(UUID().uuidString).sqlite")
        try? Data("不是 SQLite 文件的占位字节".utf8).write(to: corruptURL)
        let store = RecordStore(repository: RecordRepository(stack: CoreDataStack(databaseURL: corruptURL)))
        withExtendedLifetime(store) {
            let record = QuiteNote.Record(id: UUID(), content: "删不掉", createdAt: Date(), hash: "delete-fail")
            store.delete(record)
            XCTAssertTrue(
                waitUntil { store.toast?.text == "删除失败，请重试" && store.toast?.type == "error" },
                "删除失败要弹错误 toast"
            )
        }
    }
}
