import SwiftUI

/// V2 标注工具栏 - 完整的 11 种标注工具（精致的浮动子工具栏设计）
struct V2AnnotationToolbar: View {
    @ObservedObject var stateManager: V2PrimaryScreenStateManager

    private let colors: [Color] = [.red, .yellow, .green, .blue, .white, .black]
    @State private var expandedGroup: AnnotationToolGroup? = nil
    // P2.1: 自定义 tooltip 状态
    @State private var tooltipText: String = ""
    @State private var tooltipPosition: CGPoint = .zero
    @State private var showTooltip: Bool = false

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
        // P2.1: 自定义 tooltip 覆盖层
        .overlay(
            Group {
                if showTooltip {
                    Text(tooltipText)
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.themeShadowHeavy)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .position(x: tooltipPosition.x, y: tooltipPosition.y - 35)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    showTooltip = false
                                }
                            }
                        }
                }
            }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: expandedGroup)
        .frame(maxWidth: 650) // 恢复宽度，新交互更省空间
    }

    private var mainToolbarContent: some View {
        HStack(spacing: 12) {
            toolSelectionGroup
            
            if stateManager.selectedTool.supportsColor {
                colorSelectionGroup
            }
            
            if stateManager.selectedTool.supportsSize {
                sizeSelectionGroup
            }
            
            // ✨ 新增：放大镜倍率调节
            if stateManager.selectedTool == .magnifier || (stateManager.selectedTool == .cursor && isSelectedElementMagnifier) {
                magnifierScaleGroup
            }
            
            Divider().frame(height: 24).background(Color.white.opacity(0.2))
            actionButtonsGroup
            Divider().frame(width: 1, height: 24).background(Color.white.opacity(0.2))

            // OCR 文字识别按钮：对选区最终图跑本地 Vision 识别
            Button(action: {
                NotificationCenter.default.post(name: NSNotification.Name("OCRScreenshot"), object: nil)
            }) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.indigo.opacity(0.8), Color.indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 34, height: 34)

                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    tooltipText = "文字识别 (⌘O)"
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showTooltip = true
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showTooltip = false
                    }
                }
            }

            // P3.3: 保存按钮 (Command+S) - 使用 SF Symbols
            Button(action: {
                NotificationCenter.default.post(name: NSNotification.Name("SaveScreenshot"), object: nil)
            }) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.blue.opacity(0.8), Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 34, height: 34)

                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    tooltipText = "保存文件并复制路径 (⌘S)"
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showTooltip = true
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showTooltip = false
                    }
                }
            }

            // P3.3: 复制按钮 (Command+C) - 使用 SF Symbols
            Button(action: {
                NotificationCenter.default.post(name: NSNotification.Name("CopyScreenshot"), object: nil)
            }) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.green.opacity(0.8), Color.green],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 34, height: 34)

                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    tooltipText = "复制到剪贴板 (Command+C)"
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showTooltip = true
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showTooltip = false
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.themeShadowHeavy.opacity(0.7))
        )
    }

    private var sizeSelectionGroup: some View {
        Group {
            Divider().frame(height: 24).background(Color.themeBorderSubtle)
            V2SizeDragControl(stateManager: stateManager)
        }
    }

    private var magnifierScaleGroup: some View {
        Group {
            Divider().frame(height: 24).background(Color.themeBorderSubtle)
            V2MagnifierScaleControl(stateManager: stateManager)
        }
    }

    private var isSelectedElementMagnifier: Bool {
        if let id = stateManager.selectedElementId,
           let element = stateManager.elements.first(where: { $0.id == id }) {
            return element.tool == .magnifier
        }
        return false
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
            .background(Color.themeShadowMedium)
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
                        color: stateManager.selectedTool == tool ? .white : Color.white.opacity(0.6)
                    )
                    .frame(width: 30, height: 30)
                    .background(stateManager.selectedTool == tool ? Color.themeBlue500.opacity(0.6) : Color.white.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.themeBackground.opacity(0.95))
                .shadow(color: Color.themeShadowMedium, radius: 5, x: 0, y: 3)
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

    /// P2.1: 操作按钮 - 使用自定义 tooltip
    private func actionButton(icon: IconName, action: @escaping () -> Void, tooltip: String, primary: Bool = false) -> some View {
        GeometryReader { geometry in
            Button(action: action) {
                LucideView(name: icon, size: 18, color: .white)
                    .frame(width: 34, height: 34)
                    .background(primary ? Color.themeBlue500 : Color.white.opacity(0.1))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    // 获取按钮在全局坐标系中的中心位置
                    let bounds = geometry.frame(in: .global)
                    tooltipPosition = CGPoint(x: bounds.midX, y: bounds.minY)
                    tooltipText = tooltip
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showTooltip = true
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showTooltip = false
                    }
                }
            }
        }
        .frame(width: 34, height: 34)
    }
}
