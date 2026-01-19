import Foundation

/// P4.1: 历史记录动作类型
enum HistoryAction {
    case delete(record: Record)
    case edit(recordId: UUID, oldContent: String, newContent: String)
    case toggleStar(recordId: UUID, oldState: Bool)
}

/// P4.1: 历史记录管理器 - 支持撤销/重做
final class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published private(set) var undoStack: [HistoryAction] = []
    @Published private(set) var redoStack: [HistoryAction] = []

    private let maxStackSize = 50

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private init() {}

    func push(_ action: HistoryAction) {
        undoStack.append(action)
        if undoStack.count > maxStackSize {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        print("[HistoryManager] Pushed action, undo stack size: \(undoStack.count)")
    }

    func undo(recordStore: RecordStore) {
        guard let action = undoStack.popLast() else { return }
        redoStack.append(action)

        switch action {
        case .delete(let record):
            print("[HistoryManager] Undoing delete for record: \(record.id)")
            restoreRecord(record, recordStore: recordStore)
        case .edit(let recordId, let oldContent, _):
            print("[HistoryManager] Undoing edit for record: \(recordId)")
            if let index = recordStore.records.firstIndex(where: { $0.id == recordId }) {
                let record = recordStore.records[index]
                // skipHistory: true 避免撤销操作本身被记录到历史
                recordStore.updateContent(id: recordId, content: oldContent, title: record.title, noteFrame: record.noteFrame, skipHistory: true)
            }
        case .toggleStar(let recordId, let oldState):
            print("[HistoryManager] Undoing toggle star for record: \(recordId)")
            if let record = recordStore.records.first(where: { $0.id == recordId }),
               record.starred != oldState {
                // 需要在 RecordStore.toggleStar 中添加 skipHistory 支持
                recordStore.toggleStar(record, skipHistory: true)
            }
        }
    }

    func redo(recordStore: RecordStore) {
        guard let action = redoStack.popLast() else { return }
        undoStack.append(action)

        switch action {
        case .delete(let record):
            print("[HistoryManager] Redoing delete for record: \(record.id)")
            recordStore.delete(record, skipHistory: true)
        case .edit(let recordId, _, let newContent):
            print("[HistoryManager] Redoing edit for record: \(recordId)")
            if let index = recordStore.records.firstIndex(where: { $0.id == recordId }) {
                let record = recordStore.records[index]
                // skipHistory: true 避免重做操作本身被记录到历史
                recordStore.updateContent(id: recordId, content: newContent, title: record.title, noteFrame: record.noteFrame, skipHistory: true)
            }
        case .toggleStar(let recordId, _):
            print("[HistoryManager] Redoing toggle star for record: \(recordId)")
            if let record = recordStore.records.first(where: { $0.id == recordId }) {
                recordStore.toggleStar(record, skipHistory: true)
            }
        }
    }

    private func restoreRecord(_ record: Record, recordStore: RecordStore) {
        // 使用 addExistingRecord 方法恢复记录（包含数据库保存和 UI 更新）
        recordStore.addExistingRecord(record)

        // 发送通知
        NotificationCenter.default.post(name: NSNotification.Name("RecordAdded"), object: record)
    }
}
