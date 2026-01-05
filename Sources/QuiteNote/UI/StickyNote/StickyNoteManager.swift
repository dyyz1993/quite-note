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
        print("[DEBUG] StickyNoteManager shortcut registration sent to GlobalHotkeyManager")
    }
    
    /// 将贴纸存入主记录并清空
    func saveToRecords(note: StickyNoteModel) {
        // 合并所有页面的非空内容
        let content = note.pages
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n---\n\n")

        guard !content.isEmpty else {
            print("[DEBUG] Content is empty, skipping save")
            return
        }
        
        // 1. 获取 RecordStore 实例并调用其添加记录的方法
        // 注意：由于 RecordStore 是 ObservableObject 且在 FloatingRootView 中使用，
        // 我们需要找到一种方式访问它。通常在项目中会有单例或共享实例。
        // 根据 RecordStore.swift，它似乎没有静态单例。
        // 但根据应用架构，主窗口通常持有一个 store。
        
        // 发送通知让主记录库处理
        NotificationCenter.default.post(
            name: NSNotification.Name("StickyNoteSaveToRecord"),
            object: nil,
            userInfo: [
                "content": content,
                "type": "text",
                "source": "Sticky Note"
            ]
        )
        
        print("[DEBUG] Sent notification to save sticky note content: \(content.prefix(20))...")
    }
    
    /// 创建新贴纸
    func createNewNote() {
        let newNote = StickyNoteModel(
            frame: NSRect(x: 400, y: 400, width: 300, height: 200)
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
            window.makeKeyAndOrderFront(nil)
        }
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
    
    /// 更新贴纸内容或位置
    func updateNote(_ note: StickyNoteModel) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
            saveNotes()
        }
    }
}
