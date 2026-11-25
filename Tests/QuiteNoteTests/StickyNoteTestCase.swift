import XCTest
@testable import QuiteNote

/// 便利贴测试的公共夹具：存储隔离 + UserDefaults 键保存/恢复 + 管理器预热 + 轮询等待
///
/// 测试进程里各测试类共用同一个隔离库（QN_TEST_STORAGE_ROOT），里面会有别的测试留下的记录，
/// 后台落库、异步加载的时机也不固定（机器忙时会明显变慢）：
/// 断言只看自己建的记录，等待一律轮询，不用写死的 sleep。
@MainActor
class StickyNoteTestCase: XCTestCase {
    private var savedValues: [String: Any?] = [:]
    private var temporaryDirectories: [URL] = []

    override func setUp() {
        super.setUp()
        TestStorageIsolation.activate
        for key in [StickyNoteManager.storageKey, StickyNoteManager.recoveryKey] {
            savedValues[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for note in StickyNoteManager.shared.notes {
            StickyNoteManager.shared.removeNote(id: note.id)
        }
        for (key, value) in savedValues {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        savedValues = [:]
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
        super.tearDown()
    }

    /// 首次访问 StickyNoteManager.shared 时 loadNotes 会排一个"恢复所有便利贴窗口"的
    /// main.async。先趁 notes 为空把它排空，之后往里塞测试数据就不会真的开出窗口
    func warmUpStickyManager() -> StickyNoteManager {
        let manager = StickyNoteManager.shared
        drainMainQueue()
        XCTAssertTrue(manager.didRestoreWindows, "恢复窗口的任务应已排空")
        return manager
    }

    func drainMainQueue(rounds: Int = 3) {
        for _ in 0..<rounds {
            let drained = expectation(description: "main queue drained")
            DispatchQueue.main.async { drained.fulfill() }
            wait(for: [drained], timeout: 5)
        }
    }

    /// 轮询直到条件成立（后台落库、异步加载这类没有通知可等的场景）。超时返回 false
    @discardableResult
    func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    /// 共用隔离库上的 RecordStore，等到首屏记录加载落地再返回
    func makeIsolatedStore() -> RecordStore {
        makeStore(on: RecordRepository())
    }

    /// 独立的私有库（每次一个临时目录）。会动到整库的用例（比如清空全部记录）
    /// 必须用它：共用的隔离库里还有别的测试类的记录，而且批量删除是后台异步执行的
    /// - Returns: store、它的数据访问层、数据库文件路径。注意：RecordStore 的首屏加载只弱引用自己，
    ///   store 没人持有就会在加载完成前被释放——用完后要通过 `withExtendedLifetime` 保住它
    func makePrivateStore() -> (store: RecordStore, repository: RecordRepository, databaseURL: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("qn-sticky-private-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        let databaseURL = directory.appendingPathComponent("QuiteNote.sqlite")
        let repository = RecordRepository(stack: CoreDataStack(databaseURL: databaseURL))
        return (makeStore(on: repository), repository, databaseURL)
    }

    private func makeStore(on repository: RecordRepository) -> RecordStore {
        let store = RecordStore(repository: repository)
        // 首屏加载是"后台查询 → 主线程发布"；首屏最多 100 条，发布后内存条数应与库里对得上
        //（总数每次重新读：别的测试的后台写入可能还在路上）
        waitUntil {
            let expected = min((try? repository.getCount()) ?? 0, 100)
            return store.records.count == expected
        }
        return store
    }

    /// 直接查库（只读、同步）。新建记录是后台异步落库的，要等到它满足条件再断言
    func storedRecord(_ id: UUID, timeout: TimeInterval = 10, until satisfied: (Record) -> Bool = { _ in true }) -> Record? {
        var record = (try? RecordRepository().find(id: id)) ?? nil
        waitUntil(timeout: timeout) {
            if let record, satisfied(record) { return true }
            record = (try? RecordRepository().find(id: id)) ?? nil
            return false
        }
        return record
    }

    func storedStickyNotesData() -> Data? {
        UserDefaults.standard.data(forKey: StickyNoteManager.storageKey)
    }
}
