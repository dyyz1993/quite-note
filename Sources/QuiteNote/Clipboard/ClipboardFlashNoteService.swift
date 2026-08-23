import Foundation
import AppKit

/// 剪贴板条目 → 正式闪记（PRD 11）
///
/// 只有用户主动点击「加入闪记」才走 RecordStore.addRecord（自动历史绝不写正式记录）。
/// 取消关联只清 savedRecordID，不删正式记录；正式记录删除由闪记界面处理。
/// 剪贴板清理不会删已加闪记条目引用的图片文件。
@MainActor
final class ClipboardFlashNoteService {
    static let shared = ClipboardFlashNoteService()

    weak var recordStore: RecordStore?

    private init() {}

    /// 把条目提升为正式 Record 并建立关联
    /// - Returns: 成功关联的正式记录 id
    @discardableResult
    func save(_ entry: ClipboardEntry) -> UUID? {
        guard let store = recordStore else {
            DiagnosticCenter.error("Clipboard", "加入闪记失败：RecordStore 未接入")
            return nil
        }
        guard entry.savedRecordID == nil else { return entry.savedRecordID }

        let record: Record?
        switch entry.type {
        case .text:
            record = store.addRecord(
                content: entry.plainText ?? "",
                hash: entry.contentHash,
                sourceApp: entry.sourceApp,
                type: .text
            )
        case .link:
            record = store.addRecord(
                content: entry.plainText ?? entry.sourceURL ?? "",
                hash: entry.contentHash,
                sourceApp: entry.sourceApp,
                sourceUrl: entry.sourceURL,
                type: .url
            )
        case .image:
            // 复用同一份原图文件（虚拟路径），OCR 文本进正文便于原搜索命中（PRD 11：保留原图和 OCR 文本）
            record = store.addRecord(
                content: entry.ocrText ?? "",
                hash: entry.contentHash,
                sourceApp: entry.sourceApp,
                sourceUrl: entry.assetPath,
                type: .image,
                skipAI: true
            )
        case .file:
            record = saveFileRecord(entry, store: store)
        }

        guard let record else {
            DiagnosticCenter.error("Clipboard", "加入闪记失败（\(entry.type.rawValue)）")
            return nil
        }

        ClipboardHistoryStore.shared.linkRecord(entryID: entry.id, recordID: record.id)
        DiagnosticCenter.info("Clipboard", "已加入闪记：\(entry.type.rawValue) → record \(record.id)")
        return record.id
    }

    /// 取消关联（不删正式记录，PRD 11）
    func unlink(entryID: UUID) {
        ClipboardHistoryStore.shared.linkRecord(entryID: entryID, recordID: nil)
    }

    /// 文件条目：把文件拷进附件库再建正式记录；文件已丢失则退化为文本记录（路径字符串）
    private func saveFileRecord(_ entry: ClipboardEntry, store: RecordStore) -> Record? {
        guard let path = entry.plainText else { return nil }
        let sourceURL = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path),
              let stored = try? FileCoordinator.shared.storeFile(at: sourceURL, type: .file),
              let virtualPath = FileCoordinator.shared.convertToVirtualPath(from: stored) else {
            // 文件丢失：保留路径为文本记录，至少可搜
            return store.addRecord(
                content: path,
                hash: ClipboardService.sha1("missing-\(entry.contentHash)"),
                sourceApp: entry.sourceApp,
                type: .text,
                skipAI: true
            )
        }

        return store.addRecord(
            content: sourceURL.lastPathComponent,
            hash: entry.contentHash,
            sourceApp: entry.sourceApp,
            sourceUrl: virtualPath,
            type: .file,
            skipAI: true,
            fileName: sourceURL.lastPathComponent
        )
    }
}
