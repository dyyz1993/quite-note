import SwiftUI

/// V2 标注工具栏 - 完整的 11 种标注工具（精致的浮动子工具栏设计）
struct V2AnnotationToolbar: View {
    @ObservedObject var stateManager: V2PrimaryScreenStateManager

    private let colors: [Color] = [.red, .yellow, .green, .blue, .white, .black]
    @State private var expandedGroup: AnnotationToolGroup? = nil

    var body: some View {
        ZStack(alignment: .top) {
            // 1. 子工具栏（浮动在主工具栏上方）
            if let group = expandedGroup, let tools = getSubTools(for: group), tools.count > 1 {
                subToolbar(for: tools)
                    .offset(y: -60)
                    .onHover { hovering in
                        stateManager.isMouseOverUI = hovering
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 2. 主工具栏
            mainToolbarContent
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: expandedGroup)
        .frame(maxWidth: 650)
    }

    private var mainToolbarContent: some View {
        HStack(spacing: 12) {
            toolSelectionGroup
            if stateManager.selectedTool.supportsColor {
                colorSelectionGroup
            }
            Divider().frame(height: 24).background(Color.white.opacity(0.2))
            actionButtonsGroup
            Divider().frame(width: 1, height: 24).background(Color.white.opacity(0.2))
            functionButtonsGroup
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.themeBackground.opacity(0.9))
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var toolSelectionGroup: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationToolGroup.allCases, id: \.self) { group in
                groupButton(group)
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.4))
        .cornerRadius(8)
    }

    private var colorSelectionGroup: some View {
        Group {
            Divider().frame(height: 24).background(Color.white.opacity(0.2))

            HStack(spacing: 6) {
                ForEach(colors, id: \.self) { color in
                    colorButton(color)
                }
            }
            .padding(6)
            .background(Color.black.opacity(0.4))
            .cornerRadius(8)
        }
    }

    private func colorButton(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 18, height: 18)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: stateManager.selectedColor == color ? 2 : 0)
            )
            .onTapGesture {
                stateManager.selectedColor = color
            }
    }

    private var actionButtonsGroup: some View {
        HStack(spacing: 8) {
            actionButton(icon: .rotateCcw, action: { stateManager.undoLastElement() }, tooltip: "撤销")
            actionButton(icon: .trash2, action: {
                if let id = stateManager.selectedElementId {
                    stateManager.elements.removeAll { $0.id == id }
                    stateManager.selectedElementId = nil
                }
            }, tooltip: "删除选中")
            actionButton(icon: .trash, action: { stateManager.clearElements() }, tooltip: "清空全部")
        }
    }

    private var functionButtonsGroup: some View {
        HStack(spacing: 8) {
            longScreenshotButton
            saveButton
        }
    }

    private var longScreenshotButton: some View {
        Button(action: {
            stateManager.setLongScreenshotMode(true)
        }) {
            HStack(spacing: 4) {
                LucideView(name: .refreshCw, size: 14, color: .white)
                Text("长图")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        Button(action: {
            NotificationCenter.default.post(name: NSNotification.Name("SaveScreenshot"), object: nil)
        }) {
            HStack(spacing: 4) {
                LucideView(name: .check, size: 14, color: .white)
                Text("完成")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.blue)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    /// 子工具栏
    private func subToolbar(for tools: [AnnotationTool]) -> some View {
        HStack(spacing: 8) {
            ForEach(tools, id: \.self) { tool in
                Button(action: {
                    stateManager.updateTool(tool)
                    AnnotationSettings.shared.setLastTool(tool)

                    // ✨ 选择标注工具时自动进入编辑模式
                    if tool != .cursor {
                        stateManager.setEditing(true)
                    }

                    expandedGroup = nil // 选中后关闭
                }) {
                    LucideView(
                        name: IconName(rawValue: tool.rawValue) ?? .penTool,
                        size: 16,
                        color: stateManager.selectedTool == tool ? .white : .white.opacity(0.6)
                    )
                    .frame(width: 30, height: 30)
                    .background(stateManager.selectedTool == tool ? Color.blue.opacity(0.6) : Color.white.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.themeBackground.opacity(0.95))
                .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func getSubTools(for group: AnnotationToolGroup) -> [AnnotationTool]? {
        let tools = AnnotationTool.allCases.filter { $0.group == group }
        return tools.count > 1 ? tools : nil
    }

    /// 工具组按钮
    @ViewBuilder
    private func groupButton(_ group: AnnotationToolGroup) -> some View {
        let tools = AnnotationTool.allCases.filter { $0.group == group }
        let isSelected = stateManager.selectedTool.group == group
        let lastTool = AnnotationSettings.shared.getLastTool(for: group)

        Button(action: {
            stateManager.updateTool(lastTool)
            AnnotationSettings.shared.setLastTool(lastTool)

            // ✨ 选择标注工具时自动进入编辑模式
            if lastTool != .cursor {
                stateManager.setEditing(true)
            }

            if tools.count > 1 {
                if isSelected && expandedGroup == group {
                    expandedGroup = nil
                } else {
                    expandedGroup = group
                }
            } else {
                expandedGroup = nil
            }
        }) {
            LucideView(
                name: IconName(rawValue: isSelected ? stateManager.selectedTool.rawValue : lastTool.rawValue) ?? .penTool,
                size: 18,
                color: isSelected ? .white : .white.opacity(0.5)
            )
            .frame(width: 34, height: 34)
            .background(isSelected ? Color.blue.opacity(0.8) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    /// 操作按钮
    private func actionButton(icon: IconName, action: @escaping () -> Void, tooltip: String, primary: Bool = false) -> some View {
        Button(action: action) {
            LucideView(name: icon, size: 18, color: .white)
                .frame(width: 34, height: 34)
                .background(primary ? Color.blue : Color.white.opacity(0.1))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
