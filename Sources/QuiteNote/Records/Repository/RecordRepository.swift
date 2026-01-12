import Foundation
import CoreData
import os.log

/// 记录数据访问层：负责所有 CoreData 操作
final class RecordRepository {
    private static let logger = Logger(subsystem: "com.quitenote.app", category: "RecordRepository")
    private let stack: CoreDataStack

    init(stack: CoreDataStack = .shared) {
        self.stack = stack
    }

    // MARK: - JSON 序列化辅助方法

    private func parseJSONArray(_ json: String?) -> [String] {
        guard let json = json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private func toJSONString(_ array: [String]) -> String? {
        guard let data = try? JSONEncoder().encode(array) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 查询操作

    /// 分页加载记录
    func fetchRecords(limit: Int = 50, offset: Int = 0) throws -> [Record] {
        var records: [Record] = []
        var fetchError: Error?

        stack.context.performAndWait {
            do {
                let cds = try stack.fetchRecords(limit: limit, offset: offset)
                records = cds.map { self.cdRecordToRecord($0) }
            } catch {
                fetchError = error
            }
        }

        if let error = fetchError { throw error }
        return records
    }

    /// 根据 ID 查找记录
    func find(id: UUID) throws -> Record? {
        var record: Record?
        var fetchError: Error?

        stack.context.performAndWait {
            do {
                let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
                req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                req.fetchLimit = 1

                if let cd = try stack.context.fetch(req).first {
                    record = self.cdRecordToRecord(cd)
                }
            } catch {
                fetchError = error
            }
        }

        if let error = fetchError { throw error }
        return record
    }

    /// 根据哈希查找记录
    func findByHash(_ hash: String) throws -> Record? {
        var record: Record?
        var fetchError: Error?

        stack.context.performAndWait {
            do {
                let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
                req.predicate = NSPredicate(format: "digest == %@", hash)
                req.fetchLimit = 1

                if let cd = try stack.context.fetch(req).first {
                    record = self.cdRecordToRecord(cd)
                }
            } catch {
                fetchError = error
            }
        }

        if let error = fetchError { throw error }
        return record
    }

    /// 获取记录总数
    func getCount() throws -> Int {
        var count = 0
        var fetchError: Error?

        stack.context.performAndWait {
            do {
                count = try stack.getRecordsCount()
            } catch {
                fetchError = error
            }
        }

        if let error = fetchError { throw error }
        return count
    }

    // MARK: - 保存操作

    /// 保存新记录（异步，后台任务）
    func save(_ record: Record) throws {
        stack.performBackgroundTask { [weak self] context in
            guard let self = self else { return }
            do {
                let cd = CDRecord(context: context)
                self.mapRecordToCDRecord(record, into: cd)
                try context.save()
                Self.logger.info("新记录已保存到数据库: \(record.id)")
            } catch {
                Self.logger.error("保存记录失败: \(error.localizedDescription)")
            }
        }
    }

    /// 同步保存新记录（用于导入等需要立即确认的场景）
    func saveSync(_ record: Record) throws {
        var saveError: Error?
        stack.context.performAndWait {
            let context = self.stack.context
            let cd = CDRecord(context: context)
            self.mapRecordToCDRecord(record, into: cd)
            do {
                try context.save()
                Self.logger.info("新记录已同步保存到数据库: \(record.id)")
            } catch {
                saveError = error
            }
        }
        if let error = saveError { throw error }
    }

    /// 同步更新现有记录（用于便签更新等场景）
    func updateSync(_ record: Record) throws {
        var updateError: Error?
        stack.context.performAndWait {
            let context = self.stack.context
            let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
            req.predicate = NSPredicate(format: "id == %@", record.id as CVarArg)
            req.fetchLimit = 1

            do {
                if let cd = try context.fetch(req).first {
                    // 找到现有记录，更新它
                    self.mapRecordToCDRecord(record, into: cd)
                    try context.save()
                    Self.logger.info("记录已同步更新到数据库: \(record.id)")
                } else {
                    // 未找到记录，创建新记录
                    let cd = CDRecord(context: context)
                    self.mapRecordToCDRecord(record, into: cd)
                    try context.save()
                    Self.logger.info("记录不存在，已创建新记录: \(record.id)")
                }
            } catch {
                updateError = error
            }
        }
        if let error = updateError { throw error }
    }

    /// 更新记录时间戳
    func updateTimestamp(id: UUID, to date: Date) throws {
        stack.performBackgroundTask { context in
            let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            do {
                if let cd = try context.fetch(req).first {
                    cd.createdAt = date
                    try context.save()
                }
            } catch {
                Self.logger.error("更新时间戳失败: \(error.localizedDescription)")
            }
        }
    }

    /// 更新记录的 sourceUrl
    func updateSourceUrl(id: UUID, sourceUrl: String) throws {
        stack.performBackgroundTask { context in
            let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            do {
                if let cd = try context.fetch(req).first {
                    cd.sourceUrl = sourceUrl
                    try context.save()
                }
            } catch {
                Self.logger.error("更新 sourceUrl 失败: \(error.localizedDescription)")
            }
        }
    }

    /// 更新记录的文件大小
    func updateSize(id: UUID, size: Int64) throws {
        stack.performBackgroundTask { context in
            let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            do {
                if let cd = try context.fetch(req).first {
                    cd.size = size
                    try context.save()
                }
            } catch {
                Self.logger.error("更新记录大小失败: \(error.localizedDescription)")
            }
        }
    }

    /// 更新记录的 AI 处理结果
    func updateAI(
        id: UUID,
        title: String? = nil,
        summary: String? = nil,
        confidence: Double? = nil,
        aiStatus: String? = nil,
        tags: [String]? = nil,
        keywords: [String]? = nil
    ) {
        stack.performBackgroundTask { [weak self] context in
            guard let self = self else { return }
            let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            do {
                if let cd = try context.fetch(req).first {
                    if let title = title { cd.title = title }
                    if let summary = summary { cd.summary = summary }
                    if let confidence = confidence { cd.summaryConfidence = confidence }
                    if let aiStatus = aiStatus { cd.aiStatus = aiStatus }
                    if let tags = tags { cd.tagsRaw = self.toJSONString(tags) }
                    if let keywords = keywords { cd.keywordsRaw = self.toJSONString(keywords) }

                    try context.save()
                }
            } catch {
                Self.logger.error("更新 AI 结果失败: \(error.localizedDescription)")
            }
        }
    }

    /// 切换收藏状态
    func toggleStar(id: UUID) throws {
        stack.performBackgroundTask { context in
            let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            do {
                if let cd = try context.fetch(req).first {
                    cd.starred = !cd.starred
                    try context.save()
                }
            } catch {
                Self.logger.error("切换收藏状态失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 删除操作

    /// 删除指定记录（同步执行，确保删除完成）
    func delete(id: UUID) {
        print("[DEBUG RecordRepository.delete()] 开始删除记录, ID: \(id)")
        Self.logger.info("RecordRepository.delete() 开始删除, ID: \(id)")

        stack.context.performAndWait {
            let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            do {
                let results = try stack.context.fetch(req)
                print("[DEBUG RecordRepository.delete()] 查询结果: 找到 \(results.count) 条记录")

                if let cd = results.first {
                    print("[DEBUG RecordRepository.delete()] 准备删除 CDRecord")
                    stack.context.delete(cd)
                    print("[DEBUG RecordRepository.delete()] 已调用 delete(), 准备 save()")
                    try stack.context.save()
                    print("[DEBUG RecordRepository.delete()] save() 成功")
                    Self.logger.info("记录已删除: \(id)")
                } else {
                    print("[DEBUG RecordRepository.delete()] 未找到要删除的记录")
                    Self.logger.warning("未找到要删除的记录: \(id)")
                }
            } catch {
                print("[DEBUG RecordRepository.delete()] 删除失败: \(error.localizedDescription)")
                Self.logger.error("删除记录失败: \(error.localizedDescription)")
            }
        }
        print("[DEBUG RecordRepository.delete()] performAndWait 完成")
    }

    /// 清空所有记录
    func deleteAll() {
        stack.performBackgroundTask { context in
            let req = NSFetchRequest<NSFetchRequestResult>(entityName: "CDRecord")
            let deleteReq = NSBatchDeleteRequest(fetchRequest: req)
            do {
                try context.execute(deleteReq)
                try context.save()
            } catch {
                Self.logger.error("清空记录失败: \(error.localizedDescription)")
            }
        }
    }

    /// 清理 pending 状态的记录
    func clearPendingStatus(for ids: [UUID]) {
        guard !ids.isEmpty else { return }
        stack.performBackgroundTask { context in
            let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
            req.predicate = NSPredicate(format: "id IN %@", ids)
            do {
                let objects = try context.fetch(req)
                for obj in objects {
                    obj.aiStatus = nil
                }
                try context.save()
            } catch {
                Self.logger.error("清理 pending 状态失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 映射方法

    private func cdRecordToRecord(_ cd: CDRecord) -> Record {
        // 检查并重置 pending 状态的记录
        let aiStatus = cd.aiStatus == "pending" ? nil : cd.aiStatus

        // 解码 noteFrame - 使用 NSValue 包装
        var noteFrame: NSRect? = nil
        if let data = cd.noteFrameData {
            do {
                if let nsValue = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSValue.self, from: data) {
                    noteFrame = nsValue.rectValue
                }
            } catch {
                Self.logger.error("解码 noteFrame 失败: \(error.localizedDescription)")
            }
        }

        return Record(
            id: cd.id ?? UUID(),
            title: cd.title,
            content: cd.content ?? "",
            createdAt: cd.createdAt ?? Date(),
            hash: cd.digest ?? "",
            aiStatus: aiStatus,
            summary: cd.summary,
            summaryConfidence: cd.summaryConfidence,
            starred: cd.starred,
            copiedAt: cd.copiedAt,
            tags: parseJSONArray(cd.tagsRaw),
            keywords: parseJSONArray(cd.keywordsRaw),
            sourceApp: cd.sourceApp,
            sourceUrl: cd.sourceUrl,
            type: RecordType(rawValue: cd.type ?? "text") ?? .text,
            skipAI: cd.skipAI,
            size: cd.size,
            noteFrame: noteFrame
        )
    }

    private func mapRecordToCDRecord(_ record: Record, into cd: CDRecord) {
        cd.id = record.id
        cd.content = record.content
        cd.createdAt = record.createdAt
        cd.digest = record.hash
        cd.aiStatus = record.aiStatus
        cd.title = record.title
        cd.summary = record.summary
        cd.summaryConfidence = record.summaryConfidence ?? 0.0
        cd.starred = record.starred
        cd.copiedAt = record.copiedAt
        cd.tagsRaw = toJSONString(record.tags)
        cd.keywordsRaw = toJSONString(record.keywords)
        cd.sourceApp = record.sourceApp
        cd.sourceUrl = record.sourceUrl
        cd.type = record.type.rawValue
        cd.skipAI = record.skipAI
        cd.size = record.size

        // 编码 noteFrame - 使用 NSValue 包装
        if let frame = record.noteFrame {
            let nsValue = NSValue(rect: frame)
            cd.noteFrameData = try? NSKeyedArchiver.archivedData(withRootObject: nsValue, requiringSecureCoding: true)
        }
    }
}
