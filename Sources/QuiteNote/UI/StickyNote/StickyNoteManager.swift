import SwiftUI
import AppKit
import Combine

/// 便利贴管理器：生命周期、本地持久化（UserDefaults「StickyNotes」）、与记录库同步。
///
/// 便利贴 ↔ 记录的保存/更新一律同步调用 RecordStore 并使用返回值，不经通知绕路
/// （旧实现把回执建立在"records[0] 就是刚建的记录"的假设上，收藏优先排序时不成立）。
final class StickyNoteManager: ObservableObject {
    static let shared = StickyNoteManager()

    @Published var notes: [StickyNoteModel] = []
    private var windows: [UUID: StickyNoteWindow] = [:]
    private var cancellables = Set<AnyCancellable>()

    /// 记录库由 AppDelegate 在创建后注入
    weak var recordStore: RecordStore?

    /// 新建便利贴用的底色（设置页可改）
    var defaultColorForNewNotes: StickyNoteColor {
        get { StickyNoteColor.from(PreferencesManager.shared.stickyNoteDefaultColor) }
        set { PreferencesManager.shared.setStickyNoteDefaultColor(newValue) }
    }

    /// 保存 / 更新便利贴记录失败的原因
    enum SyncFailure: Error, Equatable {
        /// 便利贴已被移除
        case noteMissing
        /// 便签是空的，没有可保存的内容
        case blankContent
        /// 记录库还没接入
        case storeUnavailable
        /// 关联的记录已被删除（关联随之解除，再同步会保存成新记录）
        case recordMissing
        case updateFailed(String)
        case saveFailed
    }

    // MARK: - 持久化

    static let storageKey = "StickyNotes"
    /// 解码失败时把原数据挪到这里保留现场，免得被下一次保存覆盖掉
    static let recoveryKey = "StickyNotes.recovery"
    /// 内容、窗口位置这类高频变更的合并落盘延迟
    static let saveDebounceInterval: TimeInterval = 0.4
    private var pendingSave: DispatchWorkItem?
    /// 首次访问时排的"恢复所有便利贴窗口"任务是否已排空（测试夹具往里塞数据前要先确认）
    private(set) var didRestoreWindows = false

    private init() {
        loadNotes()
        setupNotificationObservers()
        // 退出前把延迟的落盘冲掉
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.saveNotes() }
            .store(in: &cancellables)
    }

    /// 监听记录库事件与"从记录打开便签"
    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: QuiteNoteNotification.openStickyNoteFromRecord.name)
            .sink { [weak self] notification in
                guard let record = notification.userInfo?["record"] as? Record else { return }
                self?.createNoteFromRecord(record)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: QuiteNoteNotification.noteRecordDeleted.name)
            .compactMap { $0.object as? UUID }
            .sink { [weak self] recordID in self?.handleRecordDeleted(recordID: recordID) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: QuiteNoteNotification.recordsCleared.name)
            .sink { [weak self] _ in self?.handleRecordsCleared() }
            .store(in: &cancellables)
    }

    /// 加载保存的便利贴并恢复窗口。启动恢复只把窗口摆出来，不抢键盘焦点——
    /// 登录后用户接着在别的 App 里打字，不应该莫名打进便利贴
    private func loadNotes() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey) {
            notes = Self.decodeNotes(from: data)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for note in self.notes {
                self.showWindow(for: note, makeKey: false)
            }
            self.didRestoreWindows = true
        }
    }

    /// 逐条容错解码：一条坏数据只丢它自己，不连累其余便利贴
    static func decodeNotes(from data: Data) -> [StickyNoteModel] {
        guard let elements = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            preserveForRecovery(data, reason: "便利贴数据不是 JSON 数组")
            return []
        }
        var loaded: [StickyNoteModel] = []
        var failed = 0
        for element in elements {
            // JSONSerialization 只接受字典/数组这类顶层容器，裸字符串、数字会抛 ObjC 异常
            // （try? 接不住），先筛一遍
            guard let object = element as? [String: Any],
                  let itemData = try? JSONSerialization.data(withJSONObject: object),
                  let note = try? JSONDecoder().decode(StickyNoteModel.self, from: itemData) else {
                failed += 1
                continue
            }
            loaded.append(note)
        }
        if failed > 0 {
            preserveForRecovery(data, reason: "便利贴数据有 \(failed)/\(elements.count) 条无法解码")
        }
        return loaded
    }

    private static func preserveForRecovery(_ data: Data, reason: String) {
        DiagnosticCenter.error("StickyNote", "\(reason)，原数据已挪到恢复键 \(recoveryKey)")
        UserDefaults.standard.set(data, forKey: recoveryKey)
    }

    /// 立即落盘：新建、删除、同步状态这类结构性变更用这个
    func saveNotes() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(notes), forKey: Self.storageKey)
        } catch {
            DiagnosticCenter.error("StickyNote", "便利贴落盘失败：\(error.localizedDescription)")
        }
    }

    /// 延迟落盘：每次按键、拖动窗口的每一帧都会调它，合并成一次写入
    private func scheduleSave() {
        guard pendingSave == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            self?.pendingSave = nil
            self?.saveNotes()
        }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDebounceInterval, execute: item)
    }

    // MARK: - 模型变更

    // 每个入口只动自己的字段。视图里的 note 是一份副本，frame、固定状态这些字段
    // 可能是旧的，整份回写会把别处刚改的字段覆盖回去

    private func index(of noteID: UUID) -> Int? {
        notes.firstIndex { $0.id == noteID }
    }

    /// 编辑器内容回写（每次按键）。传入的就是最新状态：整页覆盖，包括被清空的页
    func updateContent(noteID: UUID, pages: [StickyNotePage], currentPageIndex: Int) {
        guard let index = index(of: noteID) else { return }
        guard notes[index].pages != pages || notes[index].currentPageIndex != currentPageIndex else { return }
        notes[index].pages = pages
        notes[index].currentPageIndex = currentPageIndex
        scheduleSave()
    }

    func setCurrentPage(noteID: UUID, pageIndex: Int) {
        guard let index = index(of: noteID), notes[index].currentPageIndex != pageIndex else { return }
        notes[index].currentPageIndex = pageIndex
        scheduleSave()
    }

    func setFrame(noteID: UUID, frame: NSRect) {
        guard let index = index(of: noteID), notes[index].frame != frame else { return }
        notes[index].frame = frame
        scheduleSave()
    }

    func setPinned(noteID: UUID, pinned: Bool) {
        guard let index = index(of: noteID), notes[index].pinnedToAllSpaces != pinned else { return }
        notes[index].pinnedToAllSpaces = pinned
        saveNotes()
        windows[noteID]?.setPinned(pinned)
        QuiteNoteNotification.post(.stickyNotePinChanged, object: noteID, userInfo: ["pinned": pinned])
    }

    /// 换便签底色。已同步的便利贴立即把颜色写进记录，记录卡片跟着变色
    func setColor(noteID: UUID, color: StickyNoteColor) {
        guard let index = index(of: noteID), notes[index].color != color else { return }
        notes[index].color = color
        saveNotes()
        if let recordID = notes[index].syncRecordId {
            recordStore?.updateNoteColor(id: recordID, color: color.rawValue)
        }
    }

    private func setSyncLink(noteID: UUID, recordID: UUID?) {
        guard let index = index(of: noteID), notes[index].syncRecordId != recordID else { return }
        notes[index].syncRecordId = recordID
        saveNotes()
        // 视图只更新 syncRecordId，不整体替换 note，避免冲掉正在编辑的内容
        QuiteNoteNotification.post(.stickyNoteSyncChanged, object: noteID, userInfo: ["recordId": recordID as Any])
    }

    // MARK: - 便利贴 ↔ 记录

    static let pageSeparator = "\n---NOTE_PAGE_BREAK---\n"
    private static let legacyPageSeparator = "(?:\\n|^)\\s*-------- Page \\d+ --------\\s*(?:\\n|$)"
    private static let legacySeparatorRegex = try? NSRegularExpression(pattern: legacyPageSeparator)

    /// 便利贴内容 → 记录正文。末尾的空页不写（读回时会补齐，位置不变）；中间的空页
    /// 要保留，否则第 3 页的内容重开后会跑到第 2 页
    static func recordContent(from pages: [StickyNotePage]) -> String {
        let trimmed = pages.map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
        let lastFilled = trimmed.lastIndex { !$0.isEmpty } ?? -1
        return trimmed[...max(lastFilled, 0)].joined(separator: pageSeparator)
    }

    /// 记录正文 → 页。支持旧格式（-------- Page N --------）；超过 3 页的内容不截断，
    /// 否则"更新记录"会把第 4 页起永久写没
    static func pages(fromRecordContent content: String) -> [StickyNotePage] {
        let isLegacy = content.contains("-------- Page ")
        var normalized = content
        if isLegacy, let regex = legacySeparatorRegex {
            normalized = regex.stringByReplacingMatches(
                in: content, options: [], range: NSRange(location: 0, length: content.utf16.count),
                withTemplate: pageSeparator
            )
        }
        var pages = normalized
            .components(separatedBy: pageSeparator)
            .map { StickyNotePage(content: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        // 旧格式的正文以 "-------- Page 1 --------" 开头，换算后前面多出一个空页；
        // 它不是"内容从第 2 页开始"的意思
        if isLegacy, pages.count > 1, pages[0].content.isEmpty {
            pages.removeFirst()
        }
        while pages.count < 3 {
            pages.append(StickyNotePage())
        }
        return pages
    }

    /// 记录正文的第一页（便签卡片只展示第一页）
    static func firstPageContent(ofRecordContent content: String) -> String {
        pages(fromRecordContent: content).first?.content ?? ""
    }

    /// 从记录构造便利贴模型（纯函数，便于单测）
    static func makeNote(from record: Record, defaultFrame: NSRect) -> StickyNoteModel {
        StickyNoteModel(
            frame: record.noteFrame ?? defaultFrame,
            pages: pages(fromRecordContent: record.content),
            syncRecordId: record.id,
            color: StickyNoteColor.from(record.noteColor)
        )
    }

    /// 把便利贴写进记录库：已关联则更新，未关联则新建。同步执行，成功返回关联的记录 id
    @discardableResult
    func syncToRecord(noteID: UUID) -> Result<UUID, SyncFailure> {
        guard let note = notes.first(where: { $0.id == noteID }) else { return .failure(.noteMissing) }
        guard !note.isBlank else { return .failure(.blankContent) }
        guard let store = recordStore else { return .failure(.storeUnavailable) }

        let content = Self.recordContent(from: note.pages)
        let title = note.extractNoteTitle()
        if let recordID = note.syncRecordId {
            switch store.updateContent(id: recordID, content: content, title: title, noteFrame: note.frame) {
            case .updated:
                // 底色跟着一起同步：平时换底色是即时写进记录的，这里只是兜底——比如装回过旧版本
                //（旧版本会把库迁回没有底色的结构）再升回来，记录上的底色是空的
                store.updateNoteColor(id: recordID, color: note.color.rawValue)
                return .success(recordID)
            case .recordNotFound:
                setSyncLink(noteID: noteID, recordID: nil)
                return .failure(.recordMissing)
            case .failed(let message):
                return .failure(.updateFailed(message))
            }
        }

        guard let record = store.addRecord(
            content: content,
            hash: ClipboardService.sha1(content + UUID().uuidString),
            sourceApp: "Sticky Note",
            type: .note,
            fileName: title,
            noteFrame: note.frame,
            noteColor: note.color.rawValue,
            synchronousSave: true
        ) else {
            return .failure(.saveFailed)
        }
        store.filterType = nil   // 主面板切到"全部"，新记录才看得见
        setSyncLink(noteID: noteID, recordID: record.id)
        return .success(record.id)
    }

    // MARK: - 记录库事件

    /// 删除 note 记录时连带移除关联的便利贴
    func handleRecordDeleted(recordID: UUID) {
        for note in notes.filter({ $0.syncRecordId == recordID }) {
            DiagnosticCenter.info("StickyNote", "关联记录已删除，移除便利贴")
            removeNote(id: note.id)
        }
    }

    /// 清空所有记录时移除所有已同步的便利贴（与单条删除行为一致，不必等下次启动）
    func handleRecordsCleared() {
        for note in notes.filter({ $0.syncRecordId != nil }) {
            removeNote(id: note.id)
        }
    }

    /// 清理僵尸便利贴（关联到已不存在的记录）。recordExists 返回 true 表示保留
    func cleanupZombieNotes(recordExists: (UUID) -> Bool) {
        var removed = 0
        for note in notes where note.syncRecordId != nil && !recordExists(note.syncRecordId!) {
            removeNote(id: note.id)
            removed += 1
        }
        if removed > 0 {
            DiagnosticCenter.warning("StickyNote", "已清理 \(removed) 张关联记录不存在的便利贴")
        }
    }

    // MARK: - 生命周期

    /// 新建便利贴：出现在鼠标所在屏，以鼠标位置为中心
    func createNewNote() {
        let frame = StickyNoteGeometry.newNoteFrame(
            mouseLocation: NSEvent.mouseLocation,
            screens: StickyNoteGeometry.currentScreens(),
            existingFrames: windows.values.map(\.frame)
        )
        let note = StickyNoteModel(frame: frame, color: defaultColorForNewNotes)
        notes.append(note)
        showWindow(for: note, makeKey: true)
        saveNotes()
    }

    /// 从记录卡片打开：已有关联的便利贴就把它前置，**不用记录内容覆盖**——
    /// 便利贴里可能有还没点"更新记录"的新输入
    func createNoteFromRecord(_ record: Record) {
        let defaultFrame = StickyNoteGeometry.newNoteFrame(
            mouseLocation: NSEvent.mouseLocation,
            screens: StickyNoteGeometry.currentScreens()
        )
        let note = noteForOpening(record: record, defaultFrame: defaultFrame)
        showWindow(for: note, makeKey: true)
    }

    /// "从记录打开"落到的便利贴：已有关联的就返回它（内容原样保留），否则按记录内容新建
    @discardableResult
    func noteForOpening(record: Record, defaultFrame: NSRect) -> StickyNoteModel {
        if let existing = notes.first(where: { $0.syncRecordId == record.id }) {
            return existing
        }
        let note = Self.makeNote(from: record, defaultFrame: defaultFrame)
        notes.append(note)
        saveNotes()
        return note
    }

    /// 移除便利贴并销毁窗口（记录不受影响）
    func removeNote(id: UUID) {
        notes.removeAll { $0.id == id }
        windows[id]?.close()
        windows.removeValue(forKey: id)
        saveNotes()
    }

    func window(for noteID: UUID) -> StickyNoteWindow? {
        windows[noteID]
    }

    private func showWindow(for note: StickyNoteModel, makeKey: Bool) {
        let window: StickyNoteWindow
        if let existing = windows[note.id] {
            window = existing
        } else {
            window = StickyNoteWindow(note: note)
            windows[note.id] = window
        }
        if makeKey {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    /// 切换"固定到所有 Space"。作用于当前聚焦的便利贴，其次是鼠标正停着的那张；
    /// 成功后在便利贴上给一条短暂提示。返回是否生效
    @discardableResult
    func toggleSpacePinning() -> Bool {
        let window = (NSApp.keyWindow as? StickyNoteWindow)
            ?? windows.values.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        guard let window, let index = index(of: window.id) else {
            // 没有可作用的对象：悬浮面板开着的话在面板上提示
            recordStore?.postLightHint("请先把鼠标移到要固定的便利贴上")
            return false
        }
        let pinned = !notes[index].pinnedToAllSpaces
        setPinned(noteID: window.id, pinned: pinned)
        showHint(pinned ? "已固定到所有 Space" : "仅在当前 Space 显示", for: window.id)
        return true
    }

    /// 在指定便利贴上显示一条短暂提示
    func showHint(_ message: String, for noteID: UUID) {
        QuiteNoteNotification.post(.stickyNoteHint, object: noteID, userInfo: ["message": message])
    }
}
