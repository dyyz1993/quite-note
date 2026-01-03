import SwiftUI

/// 文本编辑控制器 - 管理文本编辑的生命周期和状态协调
@MainActor
class TextEditController: ObservableObject {
    static let shared = TextEditController()

    @Published var currentTextEdit: TextEditState?

    private init() {}

    /// 开始创建新文本
    func startNewText(at position: CGPoint, stateManager: V2PrimaryScreenStateManager) {
        // 先完成之前的编辑
        if currentTextEdit != nil {
            finishEditing(stateManager: stateManager)
        }

        let element = DrawingElement(
            tool: .text,
            points: [position],
            color: stateManager.selectedColor,
            lineWidth: 0,
            text: "",
            fontSize: stateManager.fontSize
        )

        // 创建编辑状态
        currentTextEdit = TextEditState(
            elementId: element.id,
            position: position,
            text: "",
            color: stateManager.selectedColor,
            fontSize: stateManager.fontSize,
            isEditing: true
        )

        // 添加元素到列表（初始为空文本）
        stateManager.elements.append(element)
        stateManager.selectedElementId = element.id
    }

    /// 开始编辑现有文本
    func startEditing(element: DrawingElement, stateManager: V2PrimaryScreenStateManager) {
        guard let position = element.points.first else { return }

        // 先完成之前的编辑
        if currentTextEdit != nil {
            finishEditing(stateManager: stateManager)
        }

        currentTextEdit = TextEditState(
            elementId: element.id,
            position: position,
            text: element.text,
            color: element.color,
            fontSize: element.fontSize,
            isEditing: true
        )

        stateManager.selectedElementId = element.id
    }

    /// 完成编辑
    func finishEditing(stateManager: V2PrimaryScreenStateManager, newText: String? = nil) {
        guard let editState = currentTextEdit else { return }

        // 使用提供的文本或保持原文本
        let finalText = newText ?? editState.text

        // 检查文本是否为空，为空则删除元素
        if finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            stateManager.elements.removeAll { $0.id == editState.elementId }
            stateManager.selectedElementId = nil
        } else {
            // 更新元素文本
            if let index = stateManager.elements.firstIndex(where: { $0.id == editState.elementId }) {
                stateManager.elements[index].text = finalText
            }
        }

        currentTextEdit = nil
    }

    /// 取消编辑
    func cancelEditing(stateManager: V2PrimaryScreenStateManager) {
        guard let editState = currentTextEdit else { return }

        // 如果是新创建的（文本为空），删除元素
        if editState.text.isEmpty {
            stateManager.elements.removeAll { $0.id == editState.elementId }
        }

        currentTextEdit = nil
    }

    /// 更新当前编辑的文本
    func updateText(_ newText: String, stateManager: V2PrimaryScreenStateManager) {
        guard let editState = currentTextEdit else { return }

        // 更新状态中的文本
        currentTextEdit?.text = newText

        // 同时更新元素中的文本
        if let index = stateManager.elements.firstIndex(where: { $0.id == editState.elementId }) {
            stateManager.elements[index].text = newText
        }
    }
}
