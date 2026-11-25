import CoreData
import XCTest
@testable import QuiteNote

/// 记录数据库的模型迁移。数据模型是代码手写的，Core Data 自己找不到旧模型：
/// 这里用"加 noteColor 之前的模型"真实建库、写入数据，再验证升级后一条不丢
final class RecordStoreMigrationTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        TestStorageIsolation.activate
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("qn-store-migration-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - 夹具

    /// 用旧模型建的库里的样例记录（覆盖各个字段类型）
    private struct Sample {
        let id = UUID()
        let frame = NSRect(x: 12, y: 34, width: 300, height: 200)
        var asRecord: QuiteNote.Record {
            var noteRecord = QuiteNote.Record(
                id: id, title: "旧便签", content: "迁移前写的便签\n---NOTE_PAGE_BREAK---\n第二页",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000), hash: "legacy-\(id.uuidString)",
                starred: true, tags: ["工作", "便签"], keywords: ["迁移"], sourceApp: "Sticky Note",
                type: .note, size: 42, noteFrame: frame
            )
            noteRecord.summary = "旧的 AI 总结"
            noteRecord.aiStatus = "success"
            noteRecord.summaryConfidence = 0.87
            noteRecord.copiedAt = Date(timeIntervalSince1970: 1_700_000_100)
            return noteRecord
        }
    }

    /// 用"加 noteColor 之前的模型"建库并写入样例记录。写完把容器和模型都放掉：
    /// 同一进程里两个模型都活着时，CDRecord 这个类会被两个实体声明认领
    private func makeLegacyStore(at url: URL, record: Sample) throws {
        try autoreleasepool {
            let container = NSPersistentContainer(
                name: "QuiteNote", managedObjectModel: CoreDataStack.makeModel(includesNoteColor: false)
            )
            container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
            var loadError: Error?
            container.loadPersistentStores { _, error in loadError = error }
            XCTAssertNil(loadError)

            let context = container.newBackgroundContext()
            try context.performAndWait {
                let cd = NSEntityDescription.insertNewObject(forEntityName: "CDRecord", into: context) as! CDRecord
                let value = record.asRecord
                cd.id = value.id
                cd.title = value.title
                cd.content = value.content
                cd.createdAt = value.createdAt
                cd.digest = value.hash
                cd.aiStatus = value.aiStatus
                cd.summary = value.summary
                cd.summaryConfidence = value.summaryConfidence ?? 0
                cd.starred = value.starred
                cd.copiedAt = value.copiedAt
                cd.tagsRaw = "[\"工作\",\"便签\"]"
                cd.keywordsRaw = "[\"迁移\"]"
                cd.sourceApp = value.sourceApp
                cd.type = value.type.rawValue
                cd.skipAI = value.skipAI
                cd.size = value.size
                cd.noteFrameData = try NSKeyedArchiver.archivedData(
                    withRootObject: NSValue(rect: value.noteFrame ?? .zero), requiringSecureCoding: true
                )
                try context.save()
            }
        }
    }

    private func contents(of directory: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    // MARK: - 用例

    func testCurrentModelHasTheColorFieldAndTheLegacyModelDoesNot() {
        let current = CoreDataStack.makeModel(includesNoteColor: true)
        let legacy = CoreDataStack.makeModel(includesNoteColor: false)
        let names: (NSManagedObjectModel) -> Set<String> = { model in
            Set(model.entitiesByName["CDRecord"]?.attributesByName.keys.map { $0 } ?? [])
        }
        XCTAssertEqual(names(current).subtracting(names(legacy)), ["noteColor"])
        XCTAssertTrue(names(legacy).subtracting(names(current)).isEmpty, "历史模型不得有现在没有的属性")
        XCTAssertEqual(names(current).count, 19)
    }

    func testFreshDatabaseOpensAndNeverNeedsMigration() throws {
        let url = tempDirectory.appendingPathComponent("fresh.sqlite")

        let stack = CoreDataStack(databaseURL: url)

        XCTAssertNil(stack.loadError)
        XCTAssertFalse(try CoreDataStack.migrateStoreIfNeeded(at: url, to: CoreDataStack.makeModel(includesNoteColor: true)))
    }

    /// 老用户的库是加 noteColor 之前的模型建的：升级后必须能直接打开，记录一条不丢
    func testStoreCreatedByThePreviousModelOpensAndKeepsTheRecord() throws {
        let url = tempDirectory.appendingPathComponent("legacy.sqlite")
        let sample = Sample()
        try makeLegacyStore(at: url, record: sample)
        let currentModel = CoreDataStack.makeModel(includesNoteColor: true)
        XCTAssertFalse(try CoreDataStack.migrateStoreIfNeeded(at: url, to: currentModel) == false,
                       "前置条件：旧库与当前模型不兼容，需要迁移")

        let stack = CoreDataStack(databaseURL: url)

        XCTAssertNil(stack.loadError, "旧库应能迁移后正常打开：\(String(describing: stack.loadError))")
        let repository = RecordRepository(stack: stack)
        let records = try repository.fetchRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0], sample.asRecord, "迁移后记录的每个字段都要原样")
        XCTAssertNil(records[0].noteColor)

        // 迁移后的库可以正常读写新字段
        var updated = records[0]
        updated.noteColor = StickyNoteColor.teal.rawValue
        try repository.updateSync(updated)
        XCTAssertEqual(try repository.find(id: sample.id)?.noteColor, "teal")
        try repository.saveSync(QuiteNote.Record(id: UUID(), content: "迁移后新建", createdAt: Date(), hash: "new", noteColor: "amber"))
        XCTAssertEqual(try repository.fetchRecords().count, 2)

        // 再开一次（模拟下次启动）：直接打开，不用再迁移，数据都在
        XCTAssertFalse(try CoreDataStack.migrateStoreIfNeeded(at: url, to: currentModel))
        let reopened = CoreDataStack(databaseURL: url)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(try RecordRepository(stack: reopened).fetchRecords().compactMap(\.noteColor).sorted(), ["amber", "teal"])
    }

    /// 正常升级走的是 Core Data 的自动迁移（原地改库），迁移函数根本不会被调到：
    /// 动手之前也要留原库备份，备份连同 WAL 一起拷，而且备份本身还是旧模型、记录还在
    /// （2026-11-25 实机验证发现：备份只在手工迁移那条兜底路径里做，正常升级其实没有备份）
    func testAutomaticUpgradeLeavesAUsableBackupOfTheOldStore() throws {
        let url = tempDirectory.appendingPathComponent("auto.sqlite")
        let sample = Sample()
        try makeLegacyStore(at: url, record: sample)
        let hadWAL = FileManager.default.fileExists(atPath: url.path + "-wal")
        let backup = url.appendingPathExtension("pre-migration")

        let stack = CoreDataStack(databaseURL: url)

        XCTAssertNil(stack.loadError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path), "自动迁移之前也要留原库备份")
        XCTAssertEqual(FileManager.default.fileExists(atPath: backup.path + "-wal"), hadWAL, "备份要连同 WAL 一起拷")
        let backupMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: backup, options: nil)
        XCTAssertTrue(CoreDataStack.makeModel(includesNoteColor: false).isConfiguration(withName: nil, compatibleWithStoreMetadata: backupMetadata),
                      "备份应该还是旧模型的库")
        XCTAssertFalse(CoreDataStack.makeModel(includesNoteColor: true).isConfiguration(withName: nil, compatibleWithStoreMetadata: backupMetadata))

        // 打开备份数记录。实体类名换成 NSManagedObject：当前模型的容器还活着，同一个类不能被两个实体认领
        try autoreleasepool {
            let model = CoreDataStack.makeModel(includesNoteColor: false)
            model.entitiesByName["CDRecord"]?.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
            let container = NSPersistentContainer(name: "QuiteNoteBackup", managedObjectModel: model)
            container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: backup)]
            var loadError: Error?
            container.loadPersistentStores { _, error in loadError = error }
            XCTAssertNil(loadError)
            let context = container.newBackgroundContext()
            try context.performAndWait {
                let request = NSFetchRequest<NSManagedObject>(entityName: "CDRecord")
                request.predicate = NSPredicate(format: "id == %@", sample.id as CVarArg)
                XCTAssertEqual(try context.count(for: request), 1, "备份里要有迁移前写的记录")
            }
        }
    }

    /// 已经是当前模型的库不留备份（每次启动都拷一份就成了垃圾）：全新库不留，写过再开也不留
    func testCurrentStoreGetsNoBackup() throws {
        let url = tempDirectory.appendingPathComponent("current.sqlite")
        let backup = url.appendingPathExtension("pre-migration")
        _ = CoreDataStack(databaseURL: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path), "全新库不该有备份")

        try RecordRepository(stack: CoreDataStack(databaseURL: url))
            .saveSync(QuiteNote.Record(id: UUID(), content: "当前模型写的", createdAt: Date(), hash: "current", noteColor: "teal"))
        _ = CoreDataStack(databaseURL: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path), "没迁移就不该留备份")
        XCTAssertEqual(try RecordRepository(stack: CoreDataStack(databaseURL: url)).fetchRecords().count, 1)
    }

    /// 迁移函数本身（新旧系统上 Core Data 的自动迁移行为不一样，这里直接对它下断言）：
    /// 提供旧模型 → 轻量迁移 → 替换前留原库备份 → 临时文件清掉
    func testManualMigrationKeepsTheRecordAndLeavesABackup() throws {
        let url = tempDirectory.appendingPathComponent("manual.sqlite")
        let sample = Sample()
        try makeLegacyStore(at: url, record: sample)
        let currentModel = CoreDataStack.makeModel(includesNoteColor: true)

        XCTAssertTrue(try CoreDataStack.migrateStoreIfNeeded(at: url, to: currentModel))

        let migratedMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: url, options: nil)
        XCTAssertTrue(currentModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: migratedMetadata),
                      "迁移后库应与当前模型兼容")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("pre-migration").path),
                      "替换前要留下原库备份")
        XCTAssertFalse(contents(of: tempDirectory).contains { $0.hasPrefix("migration-") }, "迁移的临时文件要清掉")
        XCTAssertFalse(try CoreDataStack.migrateStoreIfNeeded(at: url, to: currentModel), "迁移过一次之后不应再迁移")

        let repository = RecordRepository(stack: CoreDataStack(databaseURL: url))
        XCTAssertEqual(try repository.fetchRecords(), [sample.asRecord])
    }

    /// 库是某个不认识的历史模型建的：迁移函数必须报错并保留原库原样
    /// （绝不能清库重来——那等于把用户的全部记录删了）
    func testUnrecognizedStoreModelIsLeftUntouched() throws {
        let url = tempDirectory.appendingPathComponent("unknown.sqlite")
        try autoreleasepool {
            let model = CoreDataStack.makeModel(includesNoteColor: true)
            let rogue = NSAttributeDescription()
            rogue.name = "somethingFromTheFuture"
            rogue.attributeType = .stringAttributeType
            rogue.isOptional = true
            model.entitiesByName["CDRecord"]?.properties.append(rogue)
            let container = NSPersistentContainer(name: "QuiteNote", managedObjectModel: model)
            container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
            var loadError: Error?
            container.loadPersistentStores { _, error in loadError = error }
            XCTAssertNil(loadError)
        }
        let bytesBefore = try Data(contentsOf: url)

        XCTAssertThrowsError(try CoreDataStack.migrateStoreIfNeeded(at: url, to: CoreDataStack.makeModel(includesNoteColor: true))) { error in
            guard case CoreDataStack.StoreError.unrecognizedStoreModel = error else {
                return XCTFail("应报「不认识的库」，实际 \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: url), bytesBefore, "迁移不了的库必须原样保留")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("pre-migration").path))
    }
}
