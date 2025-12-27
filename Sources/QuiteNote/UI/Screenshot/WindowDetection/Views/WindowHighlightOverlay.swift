import SwiftUI
import AppKit

/// 窗口高亮覆盖层
struct WindowHighlightOverlay: View {
    let window: WindowInfo?
    let animation: Animation?
    let windowFrame: CGRect  // 窗口的屏幕框架（用于坐标转换）
    let useCALayer: Bool  // 是否使用 CALayer 渲染（绕过 SwiftUI 限制）

    init(window: WindowInfo?, animation: Animation? = .easeInOut(duration: 0.15), windowFrame: CGRect = .zero, useCALayer: Bool = false) {
        self.window = window
        self.animation = animation
        self.windowFrame = windowFrame
        self.useCALayer = useCALayer
    }

    var body: some View {
        if let window = window {
            // ✅ 使用统一的坐标系统转换
            let localBounds: CGRect = {
                guard let screen = NSScreen.main else {
                    return window.bounds
                }
                return CoordinateSystem.screenToLocal(
                    window.bounds,
                    windowFrame: windowFrame,
                    screen: screen
                )
            }()

            // ✅ 修复：使用单一 ZStack 渲染，避免双重边框
            ZStack {
                // 1. 半透明背景填充
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: localBounds.width, height: localBounds.height)

                // 2. 单一边框（蓝色外框 + 白色内边框）
                ZStack {
                    // 蓝色外边框
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue, lineWidth: 4)

                    // 白色内边框
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white, lineWidth: 2)
                }
            }
            .frame(width: localBounds.width, height: localBounds.height)
            .position(x: localBounds.midX, y: localBounds.midY)
            .onAppear {
                print("[DEBUG WindowHighlightOverlay] 显示高亮 - 窗口: \(window.displayTitle)")
                print("[DEBUG WindowHighlightOverlay] 窗口框架: \(windowFrame)")
                print("[DEBUG WindowHighlightOverlay] 屏幕坐标: \(window.bounds)")
                print("[DEBUG WindowHighlightOverlay] 局部坐标: \(localBounds)")
            }
        } else {
            Color.clear
                .onAppear {
                    print("[DEBUG WindowHighlightOverlay] window 为 nil")
                }
        }
    }

    @ViewBuilder
    private func windowInfoLabel(for window: WindowInfo) -> some View {
        VStack(spacing: 2) {
            Text(window.displayTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)

            Text("\(window.sizeDescription) | \(window.positionDescription)")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.8))
        )
    }
}

/// 框选拖拽层
struct SelectionDragLayer: View {
    @Binding var selectionRect: CGRect
    let isDragging: Bool
    let animation: Animation?

    init(selectionRect: Binding<CGRect>, isDragging: Bool, animation: Animation? = .easeInOut(duration: 0.1)) {
        self._selectionRect = selectionRect
        self.isDragging = isDragging
        self.animation = animation
    }

    var body: some View {
        if !selectionRect.isNull && !selectionRect.isEmpty {
            ZStack {
                // 半透明填充
                Rectangle()
                    .path(in: selectionRect)
                    .fill(Color.blue.opacity(0.1))

                // 虚线边框
                Rectangle()
                    .path(in: selectionRect)
                    .stroke(
                        Color.blue,
                        style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                    )

                // 尺寸标签
                sizeLabel
                    .position(x: selectionRect.midX, y: selectionRect.minY - 15)
            }
            .animation(animation, value: selectionRect)
        }
    }

    @ViewBuilder
    private var sizeLabel: some View {
        Text("\(Int(selectionRect.width)) × \(Int(selectionRect.height))")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.7))
            )
    }
}

// MARK: - Preview

#Preview("Window Highlight") {
    // 模拟窗口位于屏幕 (100, 100) 位置
    let windowFrame = CGRect(x: 100, y: 100, width: 600, height: 400)

    WindowHighlightOverlay(
        window: WindowInfo(
            windowNumber: 1,
            windowID: 1,
            bounds: CGRect(x: 150, y: 150, width: 400, height: 300),  // 窗口在屏幕上的位置
            ownerName: "Safari",
            windowName: "Browser",
            layer: 0,
            alpha: 1.0,
            isOnscreen: true
        ),
        windowFrame: windowFrame  // 遮罩窗口的位置
    )
    .frame(width: 600, height: 400)
    .background(Color.gray.opacity(0.2))
}

#Preview("Selection Drag") {
    struct PreviewWrapper: View {
        @State private var selectionRect = CGRect(x: 150, y: 120, width: 300, height: 200)

        var body: some View {
            SelectionDragLayer(
                selectionRect: $selectionRect,
                isDragging: false
            )
            .frame(width: 600, height: 400)
            .background(Color.gray.opacity(0.2))
        }
    }

    return PreviewWrapper()
}
