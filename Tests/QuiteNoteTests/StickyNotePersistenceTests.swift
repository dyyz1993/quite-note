import XCTest
@testable import QuiteNote

/// 便利贴本地持久化：容错解码、合并落盘、记录正文的分页往返
@MainActor
final class StickyNotePersistenceTests: StickyNoteTestCase {

    private func decode(_ json: String) throws -> [StickyNoteModel] {
        try JSONDecoder().decode([StickyNoteModel].self, from: Data(json.utf8))
    }

    // MARK: - 解码

    /// 合成 Codable 对带默认值的非可选字段要求键必须存在。解码失败后 notes 为空，
    /// 下一次保存就用空数组把原数据覆盖了——老版本存下的数据缺字段必须还能读
    func testDecodesDataSavedBeforeAFieldExisted() throws {
        let legacy = """
        [{"id":"\(UUID().uuidString)","pages":[{"content":"旧便利贴"}],"currentPageIndex":0,
         "frame":[[100,200],[300,200]],"opacity":0.95}]
        """
        let notes = try decode(legacy)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].pages[0].content, "旧便利贴")
        XCTAssertEqual(notes[0].frame, NSRect(x: 100, y: 200, width: 300, height: 200))
        XCTAssertFalse(notes[0].pinnedToAllSpaces)
        XCTAssertNil(notes[0].syncRecordId)
    }

    func testDecodesWhenAFieldIsNullOrHasTheWrongType() throws {
        let json = """
        [{"id":null,"pages":null,"currentPageIndex":"x","frame":null,"opacity":"x",
          "pinnedToAllSpaces":null,"syncRecordId":123}]
        """
        let notes = try decode(json)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].pages.count, 1, "页表缺失时给一张空页")
        XCTAssertEqual(notes[0].currentPageIndex, 0)
        XCTAssertEqual(notes[0].frame, StickyNoteModel.defaultFrame)
        XCTAssertNil(notes[0].syncRecordId)
    }

    func testDecodedNoteIsNormalizedToAValidState() throws {
        let json = """
        [{"pages":[],"currentPageIndex":7,"frame":[0,0,0,0]}]
        """
        let note = try decode(json)[0]
        XCTAssertEqual(note.pages.count, 1)
        XCTAssertEqual(note.currentPageIndex, 0)
        XCTAssertEqual(note.frame, StickyNoteModel.defaultFrame, "零尺寸/非法 frame 不能带进窗口创建")
    }

    func testOneCorruptNoteDoesNotDropTheOthers() {
        let good = String(data: try! JSONEncoder().encode(StickyNoteModel(pages: [StickyNotePage(content: "好的")])), encoding: .utf8)!
        let data = Data("[\(good),42,\"不是对象\",\(good)]".utf8)

        let notes = StickyNoteManager.decodeNotes(from: data)

        XCTAssertEqual(notes.count, 2)
        XCTAssertNotNil(
            UserDefaults.standard.data(forKey: StickyNoteManager.recoveryKey),
            "有数据解不开时，原数据要挪到恢复键保留现场，不能被下次保存覆盖"
        )
    }

    func testNonArrayDataIsPreservedForRecovery() {
        XCTAssertTrue(StickyNoteManager.decodeNotes(from: Data("{\"oops\":true}".utf8)).isEmpty)
        XCTAssertNotNil(UserDefaults.standard.data(forKey: StickyNoteManager.recoveryKey))
    }

    func testRoundTripPreservesTheNote() throws {
        let note = StickyNoteModel(
            frame: NSRect(x: 11, y: 22, width: 300, height: 200),
            pages: [StickyNotePage(content: "一"), StickyNotePage(content: "二"), StickyNotePage(content: "三")],
            syncRecordId: UUID()
        )
        var decoded = try JSONDecoder().decode([StickyNoteModel].self, from: JSONEncoder().encode([note]))
        XCTAssertEqual(decoded, [note])
        decoded[0].currentPageIndex = 2
        XCTAssertNotEqual(decoded[0].currentContent, note.currentContent)
    }

    // MARK: - 落盘

    func testContentEditsAreCoalescedIntoOneDelayedWrite() {
        let manager = warmUpStickyManager()
        let note = StickyNoteModel()
        manager.notes.append(note)
        manager.saveNotes()
        let before = storedStickyNotesData()

        var pages = note.pages
        pages[0].content = "按键 1"
        manager.updateContent(noteID: note.id, pages: pages, currentPageIndex: 0)
        pages[0].content = "按键 2"
        manager.updateContent(noteID: note.id, pages: pages, currentPageIndex: 0)
        XCTAssertEqual(storedStickyNotesData(), before, "每次按键不做同步落盘")
        XCTAssertEqual(manager.notes[0].pages[0].content, "按键 2", "内存里始终是最新内容")

        func persistedContent() -> String? {
            StickyNoteManager.decodeNotes(from: storedStickyNotesData() ?? Data()).first?.pages[0].content
        }
        XCTAssertTrue(waitUntil(timeout: 5) { persistedContent() == "按键 2" },
                      "停手后应延迟写入最后一次内容，实际 \(String(describing: persistedContent()))")
    }

    func testStructuralChangesAreWrittenImmediately() {
        let manager = warmUpStickyManager()
        let kept = StickyNoteModel(pages: [StickyNotePage(content: "保留")])
        let removed = StickyNoteModel()
        manager.notes.append(kept)
        manager.notes.append(removed)

        manager.removeNote(id: removed.id)

        XCTAssertEqual(StickyNoteManager.decodeNotes(from: storedStickyNotesData() ?? Data()).map(\.id), [kept.id])
    }

    func testClearingAPageSurvivesARestart() {
        let manager = warmUpStickyManager()
        let note = StickyNoteModel(pages: [StickyNotePage(content: "保留"), StickyNotePage(content: "将被清空")])
        manager.notes.append(note)

        var pages = note.pages
        pages[1].content = ""            // 用户把第 2 页内容全删
        manager.updateContent(noteID: note.id, pages: pages, currentPageIndex: 0)
        manager.saveNotes()

        XCTAssertEqual(StickyNoteManager.decodeNotes(from: storedStickyNotesData() ?? Data())[0].pages[1].content, "")
    }

    func testUpdateContentIgnoresUnknownNotes() {
        let manager = warmUpStickyManager()
        manager.updateContent(noteID: UUID(), pages: [StickyNotePage(content: "无主内容")], currentPageIndex: 0)
        manager.setFrame(noteID: UUID(), frame: .zero)
        manager.setCurrentPage(noteID: UUID(), pageIndex: 2)
        XCTAssertTrue(manager.notes.isEmpty)
    }

    // MARK: - 记录正文 ↔ 页

    func testRecordContentKeepsEmptyPagesThatAreFollowedByContent() {
        let content = StickyNoteManager.recordContent(
            from: [StickyNotePage(content: " A "), StickyNotePage(content: ""), StickyNotePage(content: " C ")]
        )
        XCTAssertEqual(content, "A\(StickyNoteManager.pageSeparator)\(StickyNoteManager.pageSeparator)C")
        XCTAssertEqual(StickyNoteManager.pages(fromRecordContent: content).map(\.content), ["A", "", "C"],
                       "第 3 页的内容重开后不能跑到第 2 页")
    }

    func testTrailingEmptyPagesAreNotWritten() {
        XCTAssertEqual(
            StickyNoteManager.recordContent(from: [StickyNotePage(content: " A "), StickyNotePage(), StickyNotePage()]),
            "A"
        )
        XCTAssertEqual(StickyNoteManager.recordContent(from: [StickyNotePage(content: " "), StickyNotePage()]), "")
        XCTAssertEqual(
            StickyNoteManager.pages(fromRecordContent: "A").map(\.content), ["A", "", ""],
            "读回时补足三页，位置不变"
        )
    }

    /// 正文里自带分隔符（粘贴进来的）会分出多于 3 页，不能只取前 3 页——
    /// 否则"更新记录"会把第 4 页起永久写没
    func testRecordsWithMoreThanThreePagesAreNotTruncated() {
        let pages = (1...5).map { StickyNotePage(content: "第 \($0) 页") }
        let content = StickyNoteManager.recordContent(from: pages)
        XCTAssertEqual(StickyNoteManager.pages(fromRecordContent: content).map(\.content), pages.map(\.content))
        XCTAssertEqual(StickyNoteManager.recordContent(from: StickyNoteManager.pages(fromRecordContent: content)), content)
    }

    /// 便签卡片只展示第一页。旧格式的正文以页眉开头，直接按分隔符切会得到一个空页
    func testFirstPageContent() {
        XCTAssertEqual(StickyNoteManager.firstPageContent(ofRecordContent: " 第一页 \n\(StickyNoteManager.pageSeparator)第二页"), "第一页")
        XCTAssertEqual(StickyNoteManager.firstPageContent(ofRecordContent: "只有一页"), "只有一页")
        XCTAssertEqual(
            StickyNoteManager.firstPageContent(ofRecordContent: "-------- Page 1 --------\n旧便签第一页\n-------- Page 2 --------\n第二页"),
            "旧便签第一页"
        )
    }

    func testLegacyPageSeparatorsAreConverted() {
        let legacy = "-------- Page 1 --------\n第一页\n-------- Page 2 --------\n第二页\n-------- Page 3 --------\n"
        XCTAssertEqual(StickyNoteManager.pages(fromRecordContent: legacy).map(\.content), ["第一页", "第二页", ""])
    }
}
