import SwiftUI

/// 截图标注工具栏 - 模块化组件
struct ScreenshotToolbar: View {
    @Binding var selectedTool: AnnotationTool
    @Binding var selectedColor: Color
    @Binding var fontSize: CGFloat

    let isCropping: Bool // 是否在裁剪模式
    let onToolSelect: () -> Void // 点击工具时的回调
    let onUndo: () -> Void
    let onCancel: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void

    @State private var expandedGroup: AnnotationToolGroup? = nil

    // 可选颜色列表
    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]

    var body: some View {
        ZStack(alignment: .top) {
            // 1. 子工具栏 (浮动在主工具栏下方，因为主工具栏在屏幕顶部)
            if let group = expandedGroup, let tools = getSubTools(for: group), tools.count > 1 {
                subToolbar(for: tools)
                    .offset(y: 60) // 改为在下方弹出，避免遮挡或超出屏幕顶部
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 2. 主工具栏
            HStack(spacing: 12) {
                // 工具选择组
                HStack(spacing: 4) {
                    ForEach(AnnotationToolGroup.allCases, id: \.self) { group in
                        groupButton(group)
                    }
                }
                .padding(4)
                .background(Color.black.opacity(0.4))
                .cornerRadius(8)
                
                if selectedTool.group == .text || selectedTool == .mosaic || selectedTool == .magnifier {
                    Divider().frame(height: 24).background(Color.white.opacity(0.2))
                    
                    // 尺寸/字号选择
                    HStack(spacing: 8) {
                        ForEach([14, 20, 28, 36], id: \.self) { size in
                            Button(action: { fontSize = CGFloat(size) }) {
                                Text("\(size)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(fontSize == CGFloat(size) ? .white : .white.opacity(0.5))
                                    .frame(width: 24, height: 24)
                                    .background(fontSize == CGFloat(size) ? Color.blue.opacity(0.6) : Color.clear)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(8)
                }
                
                Divider().frame(height: 24).background(Color.white.opacity(0.2))
                
                // 颜色选择组
                HStack(spacing: 6) {
                    ForEach(colors, id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: selectedColor == color ? 2 : 0)
                            )
                            .onTapGesture {
                                selectedColor = color
                            }
                    }
                }
                .padding(6)
                .background(Color.black.opacity(0.4))
                .cornerRadius(8)
                
                Divider().frame(height: 24).background(Color.white.opacity(0.2))
                
                // 操作按钮组
                HStack(spacing: 8) {
                    actionButton(icon: .rotateCcw, action: onUndo, tooltip: "撤销")
                    actionButton(icon: .x, action: onCancel, tooltip: "取消")
                    actionButton(icon: .copy, action: onCopy, tooltip: "复制到剪贴板")
                    actionButton(icon: .save, action: onSave, tooltip: "保存到本地", primary: true)
                }
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
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: expandedGroup)
        .onChange(of: selectedTool) { newTool in
            // 当切换到选择工具时，自动关闭二级工具栏
            if newTool == .cursor {
                expandedGroup = nil
            }
        }
    }
    
    /// 子工具栏
    private func subToolbar(for tools: [AnnotationTool]) -> some View {
        HStack(spacing: 8) {
            ForEach(tools, id: \.self) { tool in
                Button(action: {
                    selectedTool = tool
                    AnnotationSettings.shared.setLastTool(tool)
                    expandedGroup = nil // 选中后关闭
                }) {
                    LucideView(
                        name: IconName(rawValue: tool.rawValue) ?? .penTool,
                        size: 16,
                        color: selectedTool == tool ? .white : .white.opacity(0.6)
                    )
                    .frame(width: 30, height: 30)
                    .background(selectedTool == tool ? Color.blue.opacity(0.6) : Color.white.opacity(0.1))
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
        let isSelected = selectedTool.group == group
        let lastTool = AnnotationSettings.shared.getLastTool(for: group)

        Button(action: {
            selectedTool = lastTool
            // 点击工具时触发回调（用于退出裁剪模式）
            onToolSelect()

            if tools.count > 1 {
                // 只要有子工具，点击就显示。如果已经是该组且已显示，则切换隐藏
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
                name: IconName(rawValue: isSelected ? selectedTool.rawValue : lastTool.rawValue) ?? .penTool,
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
    
    /// 工具名称映射
    private func toolName(_ tool: AnnotationTool) -> String {
        switch tool {
        case .cursor: return "选择"
        case .rectangle: return "矩形"
        case .circle: return "圆形"
        case .arrow: return "箭头"
        case .line: return "直线"
        case .text: return "文字"
        case .pen: return "画笔"
        case .mosaic: return "马赛克"
        case .spotlight: return "聚光灯"
        case .magnifier: return "放大镜"
        case .steps: return "步骤"
        }
    }
}
