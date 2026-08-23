import Foundation
import AppKit

/// 剪贴板图片 OCR 队列（PRD 10）
///
/// 串行处理：新图片条目进入队列 → 后台 Vision 识别（本地，不联网）→ 结果写回条目。
/// OCR 不阻塞捕获（捕获在 Monitor 完成，这里只消费 waiting 状态的条目）。
/// 失败自动重试一次（可在设置关闭）；用户可手动重试。
@MainActor
final class ClipboardOCRQueue {
    static let shared = ClipboardOCRQueue()

    /// 是否有识别任务在进行（避免重复启动）
    private var isProcessing = false
    /// 自动重试已花费次数（按条目记，手动重试重置）
    private var autoRetriedIDs = Set<UUID>()
    /// 每条目累计处理次数（死循环止损用；成功后清除）
    private var processedCount: [UUID: Int] = [:]
    private var observer: NSObjectProtocol?

    private init() {
        // 新条目捕获后自动入队
        observer = QuiteNoteNotification.observe(.clipboardEntryAdded, observer: self) { [weak self] note in
            guard let id = note.userInfo?["id"] as? UUID else { return }
            self?.enqueueIfNeeded(id: id)
        }
        // 启动时把存量 waiting 的图片条目捞起来
        processNextIfIdle()
    }

    /// 条目进入 OCR 流程（图片 + OCR 开启 + waiting 状态）
    func enqueueIfNeeded(id: UUID) {
        guard let entry = ClipboardHistoryStore.shared.entry(id: id),
              entry.type == .image,
              entry.ocrStatus == .waiting else { return }
        processNextIfIdle()
    }

    /// 手动重试（OCR 失败状态条目上的重试按钮）
    func retry(entryID: UUID) {
        guard let entry = ClipboardHistoryStore.shared.entry(id: entryID),
              entry.type == .image else { return }
        autoRetriedIDs.remove(entryID)
        processedCount[entryID] = nil
        ClipboardHistoryStore.shared.updateOCR(id: entryID, text: nil, status: .waiting)
        processNextIfIdle()
    }

    func processNextIfIdle() {
        guard !isProcessing else { return }
        guard PreferencesManager.shared.clipboardEnableOCR else { return }

        // 找最早一条 waiting 的图片条目
        guard let entry = ClipboardHistoryStore.shared.entries
            .last(where: { $0.type == .image && $0.ocrStatus == .waiting }) else { return }

        // 止损：同一条目连续处理超过 3 次仍回到 waiting → 强制 failed，防止异常状态下死循环
        if processedCount[entry.id, default: 0] >= 3 {
            DiagnosticCenter.error("Clipboard", "OCR 止损：条目 \(entry.id) 反复排队，强制标记失败")
            ClipboardHistoryStore.shared.updateOCR(id: entry.id, text: nil, status: .failed)
            processNextIfIdle()
            return
        }
        processedCount[entry.id, default: 0] += 1

        isProcessing = true
        DiagnosticCenter.info("Clipboard", "OCR 开始：条目 \(String(entry.id.uuidString.prefix(8)))（第 \(processedCount[entry.id] ?? 0) 次）")
        ClipboardHistoryStore.shared.updateOCR(id: entry.id, text: nil, status: .processing)

        // 读取原图（后台）→ 主线程发起 Vision 识别
        guard let virtualPath = entry.assetPath,
              let url = FileCoordinator.shared.resolveVirtualPath(virtualPath),
              let image = NSImage(contentsOf: url) else {
            finish(entryID: entry.id, text: nil, success: false)
            return
        }

        let languages = Self.resolvedLanguages()
        V2OCRService.shared.recognizeText(in: image, languages: languages) { [weak self] text in
            self?.finish(entryID: entry.id, text: text, success: text != nil)
        }
    }

    private func finish(entryID: UUID, text: String?, success: Bool) {
        isProcessing = false

        if success {
            processedCount[entryID] = nil
            ClipboardHistoryStore.shared.updateOCR(id: entryID, text: text, status: .success)
            QuiteNoteNotification.post(.clipboardOCRCompleted, object: nil, userInfo: ["id": entryID])
            DiagnosticCenter.info("Clipboard", "OCR 完成（\(text?.count ?? 0) 字）")
        } else {
            // 失败自动重试一次（PRD 8.3）
            if PreferencesManager.shared.clipboardOCRAutoRetry, autoRetriedIDs.insert(entryID).inserted {
                ClipboardHistoryStore.shared.updateOCR(id: entryID, text: nil, status: .waiting)
                DiagnosticCenter.warning("Clipboard", "OCR 失败，自动重试一次")
            } else {
                ClipboardHistoryStore.shared.updateOCR(id: entryID, text: nil, status: .failed)
                DiagnosticCenter.error("Clipboard", "OCR 失败（条目 \(entryID)）")
            }
        }

        processNextIfIdle()
    }

    /// 语言组合来自设置（PRD 8.3：中文识别/英文识别独立开关）
    nonisolated private static func resolvedLanguages() -> [String] {
        let prefs = PreferencesManager.shared
        var languages: [String] = []
        if prefs.clipboardOCRChinese { languages.append("zh-Hans") }
        if prefs.clipboardOCREnglish { languages.append("en-US") }
        return languages
    }
}
