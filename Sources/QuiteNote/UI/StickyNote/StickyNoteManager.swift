import SwiftUI
import AppKit
import Combine

/// 贴纸管理器 - 负责贴纸的生命周期管理、数据持久化和全局快捷键响应
final class StickyNoteManager: ObservableObject {
    static let shared = StickyNoteManager()
    
    @Published var notes: [StickyNoteModel] = []
    private var windows: [UUID: StickyNoteWindow] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        loadNotes()
        setupShortcuts()
        setupNotificationObservers()
    }

    /// 设置通知监听器
    private func setupNotificationObservers() {
        // 监听保存完成通知
        NotificationCenter.default.publisher(for: NSNotification.Name("qn.stickynote.save.completed"))
            .sink { [weak self] notification in
                guard let self = self,
                      let userInfo = notification.userInfo,
                      let noteId = userInfo["noteId"] as? UUID,
                      let recordId = userInfo["recordId"] as? UUID else { return }
                self.handleSaveCompleted(noteId: noteId, recordId: recordId)
            }
            .store(in: &cancellables)

        // 监听从记录打开便签的通知
        NotificationCenter.default.publisher(for: NSNotification.Name("qn.stickynote.open.from.record"))
            .sink { [weak self] notification in
                guard let self = self,
                      let userInfo = notification.userInfo,
                      let record = userInfo["record"] as? Record else { return }
                self.createNoteFromRecord(record)
            }
            .store(in: &cancellables)

        // 监听更新失败通知（记录被删除等情况）
        NotificationCenter.default.publisher(for: NSNotification.Name("StickyNoteUpdateFailed"))
            .sink { [weak self] notification in
                guard let self = self,
                      let recordId = notification.object as? UUID else { return }
                self.handleUpdateFailed(recordId: recordId)
            }
            .store(in: &cancellables)

        // 监听记录删除通知，清理关联的便签
        NotificationCenter.default.publisher(for: NSNotification.Name("RecordDeleted"))
            .sink { [weak self] notification in
                guard let self = self,
                      let recordId = notification.object as? UUID else { return }
                self.handleRecordDeleted(recordId: recordId)
            }
            .store(in: &cancellables)
    }
    
    /// 加载保存的贴纸数据
    private func loadNotes() {
        // 初始加载，如果没有贴纸，不主动创建，等待用户快捷键
        if let data = UserDefaults.standard.data(forKey: "StickyNotes"),
           let decoded = try? JSONDecoder().decode([StickyNoteModel].self, from: data) {
            self.notes = decoded
            // 恢复窗口
            DispatchQueue.main.async {
                for note in self.notes {
                    self.showWindow(for: note)
                }
            }
        }
    }
    
    /// 保存贴纸数据
    func saveNotes() {
        if let encoded = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(encoded, forKey: "StickyNotes")
        }
    }
    
    /// 设置全局快捷键
    private func setupShortcuts() {
        print("[DEBUG] StickyNoteManager setting up global shortcuts...")
        // 使用一个更不容易冲突的 ID，例如 5001
        GlobalHotkeyManager.shared.register(
            key: "n",
            modifiers: [.command, .shift],
            id: 5001
        ) { [weak self] in
            print("[DEBUG] Global Hotkey Triggered: Command + Shift + N")
            self?.createNewNote()
        }
        // P2.3: 添加切换 Space 固定的快捷键 (⌘⌥P)
        // 切换便签是否在所有 Desktop Space 显示
        GlobalHotkeyManager.shared.register(
            key: "p",
            modifiers: [.command, .option],
            id: 5002
        ) { [weak self] in
            print("[DEBUG] Toggle Space pin hotkey triggered: Command + Option + P")
            self?.toggleSpacePinning()
        }
        print("[DEBUG] StickyNoteManager shortcut registration sent to GlobalHotkeyManager")
    }
    
    /// 保存或更新贴纸到记录
    func saveToRecords(note: StickyNoteModel) {
        print("[DEBUG] saveToRecords called - noteId: \(note.id)")
        print("[DEBUG] note.pages: \(note.pages.map { "\"\($0.content)\"".prefix(50) })")

        // 格式化多页内容
        let content = formatPagesForSaving(note.pages)

        print("[DEBUG] formatted content: \"\(content.prefix(100))\"")

        guard !content.isEmpty else {
            print("[DEBUG] Content is empty, skipping save")
            return
        }

        // 提取标题
        let title = note.extractNoteTitle()

        // 检查是否已有关联的记录
        if let recordId = note.syncRecordId {
            // 更新现有记录
            NotificationCenter.default.post(
                name: NSNotification.Name("StickyNoteUpdateRecord"),
                object: nil,
                userInfo: [
                    "recordId": recordId,
                    "content": content,
                    "noteFrame": note.frame,
                    "title": title,
                    "noteId": note.id
                ]
            )
            print("[DEBUG] Sent notification to update existing record, recordId: \(recordId)")
        } else {
            // 创建新记录
            NotificationCenter.default.post(
                name: NSNotification.Name("StickyNoteSaveToRecord"),
                object: nil,
                userInfo: [
                    "content": content,
                    "noteFrame": note.frame,
                    "title": title,
                    "type": "note",
                    "noteId": note.id
                ]
            )
            print("[DEBUG] Sent notification to create new record, title: \(title)")
        }
    }

    /// 格式化页面内容为带分隔符的字符串
    /// 使用特殊的内部分隔符，避免与用户内容冲突
    func formatPagesForSaving(_ pages: [StickyNotePage]) -> String {
        let pageSeparator = "\n---NOTE_PAGE_BREAK---\n"
        return pages.enumerated().map { index, page in
            let content = page.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? "" : content
        }.filter { !$0.isEmpty }
         .joined(separator: pageSeparator)
    }

    /// 从记录创建便签
    func createNoteFromRecord(_ record: Record) {
        print("[DEBUG] createNoteFromRecord called, recordId: \(record.id)")
        print("[DEBUG] record.content preview: \(record.content.prefix(100))")

        // 检查是否已有对应的便签
        if let index = notes.firstIndex(where: { $0.syncRecordId == record.id }) {
            // 已存在便签：更新内容和位置
            let pages = parseRecordContent(record.content)
            let frame = record.noteFrame ?? notes[index].frame

            print("[DEBUG] Updating existing note at index \(index)")
            print("[DEBUG] First page content: \(pages.first?.content.prefix(50) ?? "empty")")

            notes[index].pages = pages
            notes[index].frame = frame

            // 更新窗口并确保前置
            if let window = windows[notes[index].id] {
                window.updateFromNote(notes[index])
                // 确保窗口被前置到最前面
                window.makeKeyAndOrderFront(nil)
            } else {
                // 窗口不存在，需要重新创建
                showWindow(for: notes[index])
            }

            saveNotes()
            return
        }

        // 创建新便签
        let pages = parseRecordContent(record.content)
        let frame = record.noteFrame ?? defaultFrame()

        print("[DEBUG] Creating new note")
        print("[DEBUG] First page content: \(pages.first?.content.prefix(50) ?? "empty")")

        var note = StickyNoteModel(
            pages: pages,
            frame: frame,
            syncRecordId: record.id
        )

        notes.append(note)
        showWindow(for: note)
        saveNotes()
    }

    /// 解析记录内容为多页
    /// 支持向后兼容：自动检测并转换旧格式
    private func parseRecordContent(_ content: String) -> [StickyNotePage] {
        var processedContent = content
        let newSeparator = "\n---NOTE_PAGE_BREAK---\n"

        // 检测并转换旧格式 -------- Page X --------
        if content.contains("-------- Page ") {
            let oldPattern = "(?:\\n|^)\\s*-------- Page \\d+ --------\\s*(?:\\n|$)"
            if let regex = try? NSRegularExpression(pattern: oldPattern) {
                processedContent = regex.stringByReplacingMatches(
                    in: content,
                    options: [],
                    range: NSRange(location: 0, length: content.utf16.count),
                    withTemplate: newSeparator
                )
                print("[DEBUG] Converted old page separator format to new format")
            }
        }

        // 按分隔符分页
        let parts = processedContent.components(separatedBy: newSeparator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var pages = parts.prefix(3).map { StickyNotePage(content: $0) }
        while pages.count < 3 {
            pages.append(StickyNotePage())
        }
        return pages
    }

    /// 处理保存完成通知
    func handleSaveCompleted(noteId: UUID, recordId: UUID) {
        if let index = notes.firstIndex(where: { $0.id == noteId }) {
            notes[index].syncRecordId = recordId
            saveNotes()
            // 更新窗口工具栏状态
            if let window = windows[noteId] {
                window.updateSyncStatus(recordId: recordId)
            }
            // 发送通知时包含 recordId，让视图只更新 syncRecordId 而不替换整个 note
            NotificationCenter.default.post(
                name: NSNotification.Name("StickyNoteSyncStatusChanged"),
                object: noteId,
                userInfo: ["recordId": recordId]
            )
        }
    }

    /// 处理更新失败通知（记录被删除等情况）
    func handleUpdateFailed(recordId: UUID) {
        // 查找所有关联到该记录的便签，清除 syncRecordId
        for index in notes.indices where notes[index].syncRecordId == recordId {
            notes[index].syncRecordId = nil
            // 通知窗口更新状态
            NotificationCenter.default.post(name: NSNotification.Name("StickyNoteSyncStatusChanged"), object: notes[index].id)
        }
        saveNotes()
    }

    /// 处理记录删除通知，删除关联的便签
    func handleRecordDeleted(recordId: UUID) {
        print("[DEBUG StickyNoteManager.handleRecordDeleted()] 收到删除通知, recordId: \(recordId)")
        print("[DEBUG StickyNoteManager.handleRecordDeleted()] 当前便签数量: \(notes.count)")

        // 查找所有关联到该记录的便签
        let notesToDelete = notes.filter { $0.syncRecordId == recordId }
        print("[DEBUG StickyNoteManager.handleRecordDeleted()] 找到 \(notesToDelete.count) 个关联便签")

        for note in notesToDelete {
            print("[DEBUG] 删除关联便签，noteId: \(note.id), recordId: \(recordId)")
            removeNote(id: note.id)
        }

        if !notesToDelete.isEmpty {
            print("[DEBUG] 已删除 \(notesToDelete.count) 个关联便签")
            saveNotes()
        }
    }

    /// 清理僵尸便签（关联到已删除记录的便签）
    /// - Parameter recordExists: 检查记录是否存在的回调函数
    func cleanupZombieNotes(recordExists: (UUID) -> Bool) {
        var zombieCount = 0

        // 遍历所有便签，找出关联到不存在记录的便签
        for note in notes {
            guard let recordId = note.syncRecordId else { continue }

            if !recordExists(recordId) {
                print("[DEBUG] 发现僵尸便签，noteId: \(note.id), 不存在的记录ID: \(recordId)")
                removeNote(id: note.id)
                zombieCount += 1
            }
        }

        if zombieCount > 0 {
            print("[DEBUG] 已清理 \(zombieCount) 个僵尸便签")
            saveNotes()
        }
    }

    /// 默认窗口位置
    private func defaultFrame() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let currentScreen = screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main

        let width: CGFloat = 300
        let height: CGFloat = 200

        var x = mouseLocation.x - width / 2
        var y = mouseLocation.y - height / 2

        if let screen = currentScreen {
            let screenFrame = screen.visibleFrame
            x = max(screenFrame.minX + 10, min(x, screenFrame.maxX - width - 10))
            y = max(screenFrame.minY + 10, min(y, screenFrame.maxY - height - 10))
        }

        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    /// 创建新贴纸
    func createNewNote() {
        // 获取当前鼠标位置和屏幕
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let currentScreen = screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main ?? screens.first
        
        let width: CGFloat = 300
        let height: CGFloat = 200
        
        // 默认将贴纸中心放在鼠标位置
        var x = mouseLocation.x - width / 2
        var y = mouseLocation.y - height / 2
        
        // 确保贴纸在屏幕范围内
        if let screen = currentScreen {
            let screenFrame = screen.visibleFrame
            
            // 限制在屏幕边界内，并留出一点边距
            x = max(screenFrame.minX + 10, min(x, screenFrame.maxX - width - 10))
            y = max(screenFrame.minY + 10, min(y, screenFrame.maxY - height - 10))
        }
        
        let newNote = StickyNoteModel(
            frame: NSRect(x: x, y: y, width: width, height: height)
        )
        notes.append(newNote)
        showWindow(for: newNote)
        saveNotes()
    }
    
    /// 显示/创建贴纸窗口
    private func showWindow(for note: StickyNoteModel) {
        if windows[note.id] == nil {
            let window = StickyNoteWindow(note: note)
            windows[note.id] = window
        }
        // 无论窗口是否已存在，都要前置到最前面
        windows[note.id]?.makeKeyAndOrderFront(nil)
    }
    
    /// 删除贴纸 (不保留数据)
    func deleteNote(_ note: StickyNoteModel) {
        // 如果需要，可以在这里添加删除确认逻辑
        removeNote(id: note.id)
        print("[DEBUG] Sticky note deleted permanently")
    }
    
    /// 移除贴纸并销毁窗口
    func removeNote(id: UUID) {
        notes.removeAll { $0.id == id }
        windows[id]?.close()
        windows.removeValue(forKey: id)
        saveNotes()
    }
    
    /// 更新贴纸内容或位置（智能合并，避免数据丢失）
    func updateNote(_ note: StickyNoteModel) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            var existing = notes[index]

            // 优先保留最新的内容（如果有内容变化）
            // 只在传入的 note 有新内容时才更新
            if !note.pages.isEmpty {
                var hasNewContent = false
                // 检查是否有非空内容
                for page in note.pages {
                    if !page.content.isEmpty {
                        hasNewContent = true
                        break
                    }
                }

                if hasNewContent {
                    // 合并页面内容：保留非空页面
                    for i in 0..<min(note.pages.count, existing.pages.count) {
                        if !note.pages[i].content.isEmpty {
                            existing.pages[i].content = note.pages[i].content
                        }
                    }
                    // 如果 note 有更多页面，添加到 existing
                    if note.pages.count > existing.pages.count {
                        for i in existing.pages.count..<note.pages.count {
                            existing.pages.append(note.pages[i])
                        }
                    }
                }
            }

            // 更新其他属性（无条件更新，因为这些都是结构属性）
            if note.syncRecordId != nil {
                existing.syncRecordId = note.syncRecordId
            }
            // 总是更新 frame，因为窗口移动/调整大小时需要同步
            existing.frame = note.frame
            existing.opacity = note.opacity
            existing.currentPageIndex = note.currentPageIndex

            notes[index] = existing
            saveNotes()
        }
    }

    // P2.3: 切换便签的 Space 固定状态
    func toggleSpacePinning() {
        // 获取当前 key window（应该是当前正在编辑的便签窗口）
        guard let currentWindow = NSApp.keyWindow as? StickyNoteWindow,
              let index = notes.firstIndex(where: { $0.id == currentWindow.id }) else {
            print("[DEBUG] No sticky note window is currently focused")
            return
        }

        // 切换固定状态
        let note = notes[index]
        let newState = !note.pinnedToAllSpaces
        notes[index].pinnedToAllSpaces = newState
        saveNotes()

        // 更新窗口的 collectionBehavior
        currentWindow.updateFromNote(notes[index])

        // 显示提示
        let message = newState ? "已固定到所有 Space" : "仅在当前 Space 显示"
        NotificationCenter.default.post(
            name: Notification.Name("ShowLightHint"),
            object: message
        )

        print("[DEBUG] Toggled Space pinning for note \(note.id): \(newState)")
    }

    deinit {
        cancellables.removeAll()
    }
}
