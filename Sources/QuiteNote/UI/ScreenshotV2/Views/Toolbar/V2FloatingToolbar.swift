import SwiftUI

/// 截图工具栏
struct V2FloatingToolbar: View {
    let selection: CGRect
    let screen: NSScreen
    @ObservedObject var stateManager = V2PrimaryScreenStateManager.shared

    var body: some View {
        if stateManager.isLongScreenshotMode {
            // 长图模式：显示专用工具栏
            basicToolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.4))
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    }
                )
                .shadow(color: .black.opacity(0.5), radius: 15, x: 0, y: 8)
                .onHover { hovering in
                    stateManager.isMouseOverUI = hovering
                }
                .position(calculatePosition())
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: selection)
        } else {
            // 选区模式和编辑模式：都显示完整标注工具栏
            V2AnnotationToolbar(stateManager: stateManager)
                .overlay(alignment: .topLeading) {
                    if stateManager.isEditing {
                        // 仅在编辑模式显示退出按钮
                        Button(action: { stateManager.setEditing(false) }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                Text("退出")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.4))
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    }
                )
                .shadow(color: .black.opacity(0.5), radius: 15, x: 0, y: 8)
                .onHover { hovering in
                    stateManager.isMouseOverUI = hovering
                }
                .position(calculatePosition())
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: selection)
        }
    }

    private var basicToolbar: some View {
        HStack(spacing: 16) {
            if stateManager.isLongScreenshotMode {
                // 长图模式下的专用工具栏
                Text("长图采集模式")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.green)

                Divider()
                    .frame(width: 1, height: 24)
                    .background(Color.white.opacity(0.2))

                ToolbarButton(icon: "record.circle", color: .red, label: "开始滚动") {
                    stateManager.setCapturing(true)
                    V2ScreenshotDebugController.setLongScreenshotControlVisible(
                        true,
                        selection: stateManager.selectedArea,
                        screen: screen
                    )
                }

                ToolbarButton(icon: "xmark.circle", color: .white, label: "取消") {
                    stateManager.setCapturing(false)
                    V2ScreenshotDebugController.setLongScreenshotControlVisible(false)
                    stateManager.setLongScreenshotMode(false)
                }
            } else {
                // 编辑模式切换
                ToolbarButton(
                    icon: stateManager.isEditing ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle",
                    color: stateManager.isEditing ? .orange : .white,
                    label: stateManager.isEditing ? "绘画中" : "编辑"
                ) {
                    stateManager.setEditing(!stateManager.isEditing)
                }

                // 长图模式按钮
                ToolbarButton(
                    icon: "scroll",
                    color: .white,
                    label: "长图"
                ) {
                    stateManager.setLongScreenshotMode(true)
                }

                // 清除画板（兼容旧版本）
                if !stateManager.drawingPaths.isEmpty {
                    ToolbarButton(icon: "arrow.uturn.backward", color: .white, label: "撤销") {
                        if !stateManager.drawingPaths.isEmpty {
                            stateManager.drawingPaths.removeLast()
                        }
                    }

                    ToolbarButton(icon: "trash", color: .red, label: "清空") {
                        stateManager.clearPaths()
                    }
                }

                Divider()
                    .frame(width: 1, height: 24)
                    .background(Color.white.opacity(0.2))

                // 完成并保存
                ToolbarButton(icon: "checkmark", color: .green, label: "完成", isPrimary: true) {
                    NotificationCenter.default.post(name: NSNotification.Name("SaveScreenshot"), object: nil)
                }
            }
        }
    }

    /// 计算工具栏位置
    private func calculatePosition() -> CGPoint {
        let toolbarHeight: CGFloat = 60
        let spacing: CGFloat = 12

        // 1. 优先尝试底部
        let bottomY = selection.maxY + toolbarHeight/2 + spacing
        if bottomY < screen.frame.height - 40 {
            return CGPoint(x: selection.midX, y: bottomY)
        }

        // 2. 尝试顶部
        let topY = selection.minY - toolbarHeight/2 - spacing
        if topY > 40 {
            return CGPoint(x: selection.midX, y: topY)
        }

        // 3. 全屏或空间不足：显示在选区内部底部
        return CGPoint(
            x: selection.midX,
            y: selection.maxY - toolbarHeight/2 - spacing - 10
        )
    }
}
