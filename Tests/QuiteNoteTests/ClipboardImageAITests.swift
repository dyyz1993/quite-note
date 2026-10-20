import XCTest
import QuiteNoteSharedStorage
@testable import QuiteNote

/// 图片“剪贴板历史 → 闪记 → AI 提炼”的关键行为：
/// OCR 文本是图片参与普通文本提炼的唯一输入；无 OCR 文本绝不发空内容给模型。
final class ClipboardImageAITests: XCTestCase {
    private final class RoutingSpyAIService: AIServiceProtocol {
        var imageContextIDs: [String] = []
        var textContextIDs: [String] = []

        func summarize(
            contextId: String?,
            titleLimit: Int,
            summaryLimit: Int,
            content: String,
            existingTags: [String],
            completion: @escaping (Result<SummaryResult, Error>) -> Void
        ) {
            textContextIDs.append(contextId ?? "")
            completion(.failure(NSError(domain: "test", code: 1)))
        }

        func summarize(
            contextId: String?,
            titleLimit: Int,
            summaryLimit: Int,
            content: String,
            existingTags: [String],
            systemPrompt: String?,
            userPrompt: String?,
            completion: @escaping (Result<SummaryResult, Error>) -> Void
        ) {
            textContextIDs.append(contextId ?? "")
            completion(.failure(NSError(domain: "test", code: 1)))
        }

        func summarizeSingle(
            contextId: String?,
            _ content: String,
            existingTags: [String],
            completion: @escaping (Result<SummaryResult, Error>) -> Void
        ) {
            textContextIDs.append(contextId ?? "")
            completion(.failure(NSError(domain: "test", code: 1)))
        }

        func summarizeImage(
            contextId: String?,
            titleLimit: Int,
            summaryLimit: Int,
            content: String,
            imagePath: String,
            existingTags: [String],
            completion: @escaping (Result<SummaryResult, Error>) -> Void
        ) {
            imageContextIDs.append(contextId ?? "")
            completion(.failure(NSError(domain: "test", code: 2)))
        }
    }

    override func setUp() {
        super.setUp()
        TestStorageIsolation.activate
    }

    @MainActor func testImageDecisionUsesTrimmedOCRText() {
        let whitespaceOCR = "  QUITE NOTE IMAGE 9431\n\n"
        XCTAssertTrue(
            ClipboardFlashNoteService.imageAIDecision(ocrText: whitespaceOCR).shouldSummarize,
            "有 OCR 文本的图片应参与 AI 总结"
        )
        XCTAssertTrue(
            ClipboardFlashNoteService.imageAIDecision(ocrText: whitespaceOCR).content
                .contains("QUITE NOTE IMAGE 9431")
        )

        for empty in [nil, "", " \n\t "] {
            let decision = ClipboardFlashNoteService.imageAIDecision(ocrText: empty)
            XCTAssertEqual(decision.content, "")
            XCTAssertFalse(decision.shouldSummarize, "无 OCR 文本不得触发 AI")
        }
    }

    @MainActor func testReadableImageWithoutOCRStillBecomesSummarizable() throws {
        TestStorageIsolation.activate
        let directory = FileCoordinator.shared.getDirectoryURL(for: .clipboard)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let imagePath = directory.appendingPathComponent("visual-only.png")

        let image = NSImage(size: NSSize(width: 20, height: 12))
        image.lockFocus()
        NSColor.purple.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 20, height: 12)).fill()
        image.unlockFocus()
        try image.tiffRepresentation?.write(to: imagePath)

        let decision = ClipboardFlashNoteService.imageAIDecision(
            ocrText: nil,
            imagePath: "app://Attachments/Clipboard/\(directory.lastPathComponent)/visual-only.png"
        )
        XCTAssertEqual(decision.content, "")
        XCTAssertTrue(decision.shouldSummarize, "可读原图即使 OCR 为空也应走多模态总结")
    }

    func testVisualRecordTypesCanBypassTextThreshold() {
        XCTAssertTrue(RecordType.image.isVisualRecord)
        XCTAssertTrue(RecordType.screenshot.isVisualRecord)
        XCTAssertTrue(RecordType.video.isVisualRecord)
        XCTAssertFalse(RecordType.text.isVisualRecord)
        XCTAssertFalse(RecordType.file.isVisualRecord)
        XCTAssertFalse(RecordType.folder.isVisualRecord)
    }

    /// 批量总结必须和单条总结使用同一套分发：可读视觉记录走原图，而不是空文本请求。
    @MainActor func testBulkResummarizeRoutesReadableVisualRecordsToImageModel() throws {
        TestStorageIsolation.activate
        let directory = FileCoordinator.shared.getDirectoryURL(for: .screenshot)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let imagePath = directory.appendingPathComponent("batch-vision.png")

        let image = NSImage(size: NSSize(width: 20, height: 12))
        image.lockFocus()
        NSColor.orange.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 20, height: 12)).fill()
        image.unlockFocus()
        try image.tiffRepresentation?.write(to: imagePath)

        let virtualPath = "app://Attachments/Screenshots/\(directory.lastPathComponent)/batch-vision.png"
        XCTAssertTrue(AIImagePayloadLoader.canLoad(path: virtualPath))

        let visualRecord = Record(
            id: UUID(),
            content: "",
            createdAt: Date(),
            hash: "bulk-vision-\(UUID().uuidString)",
            sourceUrl: virtualPath,
            type: .screenshot
        )
        let pendingRecord = Record(
            id: UUID(),
            content: "这条记录已经 pending，不应重复进入批量队列",
            createdAt: Date(),
            hash: "bulk-pending-\(UUID().uuidString)",
            aiStatus: "pending"
        )
        let missingVisualRecord = Record(
            id: UUID(),
            content: "",
            createdAt: Date(),
            hash: "bulk-missing-\(UUID().uuidString)",
            sourceUrl: "app://Attachments/Screenshots/missing.png",
            type: .screenshot
        )

        let service = RoutingSpyAIService()
        let coordinator = RecordAICOORDINATOR()
        coordinator.enableAI = true
        coordinator.attachAI(service: service)

        let progressExpectation = expectation(description: "visual record reports result")
        let completionExpectation = expectation(description: "bulk batch completes")
        coordinator.bulkResummarize(records: [
            pendingRecord,
            missingVisualRecord,
            visualRecord
        ]) { _, _, record, update in
            if record.id == visualRecord.id {
                if case .failure = update {
                    progressExpectation.fulfill()
                }
            }
        } completion: {
            completionExpectation.fulfill()
        }

        wait(for: [progressExpectation, completionExpectation], timeout: 3)
        XCTAssertEqual(service.imageContextIDs, [visualRecord.id.uuidString])
        XCTAssertTrue(service.textContextIDs.isEmpty)
        XCTAssertFalse(coordinator.isBulkProcessingActive)
    }

    func testImagePayloadLoaderEncodesPNGAndRejectsMissingFile() throws {
        TestStorageIsolation.activate
        let directory = FileCoordinator.shared.getDirectoryURL(for: .clipboard)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("vision.png")

        let image = NSImage(size: NSSize(width: 20, height: 12))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 20, height: 12)).fill()
        NSColor.black.setFill()
        NSBezierPath(rect: NSRect(x: 4, y: 4, width: 12, height: 4)).fill()
        image.unlockFocus()
        try image.tiffRepresentation?.write(to: url)

        XCTAssertTrue(AIImagePayloadLoader.canLoad(path: url.path))
        let payload = try XCTUnwrap(AIImagePayloadLoader.load(path: url.path))
        XCTAssertEqual(payload.mimeType, "image/png")
        let decoded = Data(base64Encoded: payload.base64)
        XCTAssertNotNil(decoded)
        XCTAssertGreaterThan(decoded?.count ?? 0, 100)

        let missing = directory.appendingPathComponent("missing.png").path
        XCTAssertFalse(AIImagePayloadLoader.canLoad(path: missing))
        XCTAssertNil(AIImagePayloadLoader.load(path: missing))
    }

    @MainActor func testMissingImageWithoutOCRKeepsSkipAI() {
        TestStorageIsolation.activate
        let store = RecordStore()
        let entry = ClipboardEntry(
            type: .image,
            contentHash: "test-image-no-ocr-\(UUID().uuidString)",
            assetPath: "app://attachments/Clipboard/missing.png"
        )

        let service = ClipboardFlashNoteService.shared
        service.recordStore = store
        let recordID = service.save(entry)
        let inserted = expectation(description: "RecordStore main-queue insert")
        DispatchQueue.main.async { inserted.fulfill() }
        wait(for: [inserted], timeout: 3)

        XCTAssertNotNil(recordID)
        XCTAssertEqual(store.record(id: recordID!)?.skipAI, true, "原图不存在且无 OCR 时不得发送请求")
        XCTAssertEqual(store.record(id: recordID!)?.content, "")
    }

    @MainActor func testLateOCRSuccessBackfillsSavedRecordAndBecomesSummarizable() {
        TestStorageIsolation.activate
        let store = RecordStore()
        let entryID = UUID()
        let recordID = UUID()
        let contentHash = "test-image-late-ocr-\(recordID.uuidString)"
        let entry = ClipboardEntry(
            id: entryID,
            type: .image,
            contentHash: contentHash,
            assetPath: "app://attachments/Clipboard/late.png",
            ocrStatus: .waiting,
            savedRecordID: recordID
        )

        let service = ClipboardFlashNoteService.shared
        service.recordStore = store
        store.replaceRecordsForTesting([
            Record(
                id: recordID,
                content: "",
                createdAt: Date(),
                hash: contentHash,
                type: .image,
                skipAI: true
            )
        ])

        _ = try? ClipboardHistoryRepository(persistence: .shared).insertOrUpdate(entry)
        ClipboardHistoryStore.shared.updateOCR(
            id: entryID,
            text: "QUITE NOTE IMAGE 9431",
            status: .success
        )

        let updated = store.record(id: recordID)
        XCTAssertEqual(updated?.content, "QUITE NOTE IMAGE 9431")
        XCTAssertEqual(updated?.skipAI, false)
    }
}
