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
        let cds = try stack.fetchRecords(limit: limit, offset: offset)
        return cds.map { cdRecordToRecord($0) }
    }

    /// 根据 ID 查找记录
    func find(id: UUID) throws -> Record? {
        let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1

        guard let cd = try stack.context.fetch(req).first else { return nil }
        return cdRecordToRecord(cd)
    }

    /// 根据哈希查找记录
    func findByHash(_ hash: String) throws -> Record? {
        let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
        req.predicate = NSPredicate(format: "digest == %@", hash)
        req.fetchLimit = 1

        guard let cd = try stack.context.fetch(req).first else { return nil }
        return cdRecordToRecord(cd)
    }

    /// 获取记录总数
    func getCount() throws -> Int {
        try stack.getRecordsCount()
    }

    // MARK: - 保存操作

    /// 保存新记录
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

    /// 更新记录时间戳
    func updateTimestamp(id: UUID, to date: Date) throws {
        stack.performBackgroundTask { context in
            let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            guard let cd = try? context.fetch(req).first else { return }
            cd.createdAt = date
            try? context.save()
        }
    }

    /// 更新记录的 AI 信息
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
            guard let cd = try? context.fetch(req).first else { return }

            if let title = title { cd.title = title }
            if let summary = summary { cd.summary = summary }
            if let confidence = confidence { cd.summaryConfidence = confidence }
            if let aiStatus = aiStatus { cd.aiStatus = aiStatus }
            if let tags = tags { cd.tagsRaw = self.toJSONString(tags) }
            if let keywords = keywords { cd.keywordsRaw = self.toJSONString(keywords) }

            try? context.save()
        }
    }

    /// 切换收藏状态
    func toggleStar(id: UUID) throws {
        stack.performBackgroundTask { context in
            let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            guard let cd = try? context.fetch(req).first else { return }
            cd.starred = !cd.starred
            try? context.save()
        }
    }

    // MARK: - 删除操作

    /// 删除指定记录
    func delete(id: UUID) {
        stack.performBackgroundTask { context in
            let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            guard let cd = try? context.fetch(req).first else { return }
            context.delete(cd)
            try? context.save()
        }
    }

    /// 清空所有记录
    func deleteAll() {
        stack.performBackgroundTask { context in
            let req = NSFetchRequest<NSFetchRequestResult>(entityName: "CDRecord")
            let deleteReq = NSBatchDeleteRequest(fetchRequest: req)
            _ = try? context.execute(deleteReq)
            try? context.save()
        }
    }

    /// 清理 pending 状态的记录
    func clearPendingStatus(for ids: [UUID]) {
        guard !ids.isEmpty else { return }
        stack.performBackgroundTask { context in
            let req = NSFetchRequest<CDRecord>(entityName: "CDRecord")
            req.predicate = NSPredicate(format: "id IN %@", ids)
            if let objects = try? context.fetch(req) {
                for obj in objects {
                    obj.aiStatus = nil
                }
                try? context.save()
            }
        }
    }

    // MARK: - 映射方法

    private func cdRecordToRecord(_ cd: CDRecord) -> Record {
        // 检查并重置 pending 状态的记录
        let aiStatus = cd.aiStatus == "pending" ? nil : cd.aiStatus
        return Record(
            id: cd.id,
            title: cd.title,
            content: cd.content,
            createdAt: cd.createdAt,
            hash: cd.digest,
            aiStatus: aiStatus,
            summary: cd.summary,
            summaryConfidence: cd.summaryConfidence,
            starred: cd.starred,
            copiedAt: cd.copiedAt,
            tags: parseJSONArray(cd.tagsRaw),
            keywords: parseJSONArray(cd.keywordsRaw),
            sourceApp: cd.sourceApp,
            sourceUrl: cd.sourceUrl
        )
    }

    private func mapRecordToCDRecord(_ record: Record, into cd: CDRecord) {
        cd.id = record.id
        cd.title = record.title
        cd.content = record.content
        cd.createdAt = record.createdAt
        cd.digest = record.hash
        cd.aiStatus = record.aiStatus
        cd.summary = record.summary
        cd.summaryConfidence = record.summaryConfidence ?? 0
        cd.starred = record.starred
        cd.copiedAt = record.copiedAt
        cd.tagsRaw = toJSONString(record.tags)
        cd.keywordsRaw = toJSONString(record.keywords)
        cd.sourceApp = record.sourceApp
        cd.sourceUrl = record.sourceUrl
    }
}
