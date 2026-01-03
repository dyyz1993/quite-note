import SwiftUI

/// 选区手柄视图 - 渲染选区四角和四边的调整手柄
struct V2SelectionHandlesView: View {
    let selection: CGRect
    let isEditing: Bool
    let isLongScreenshotMode: Bool

    var body: some View {
        // ⚠️ 编辑模式或长图模式下禁止调整选区位置和大小
        if !isEditing && !isLongScreenshotMode {
            handlesContent
        } else {
            EmptyView()
        }
    }

    // MARK: - 子视图

    private var handlesContent: some View {
        let handleSize = V2LayoutConstants.handleSize

        return ZStack {
            // 四角手柄
            ForEach(SelectionHandle.cornerHandles, id: \.self) { handle in
                handleView(for: handle, in: selection, size: handleSize)
            }

            // 四边手柄
            ForEach(SelectionHandle.edgeHandles, id: \.self) { handle in
                handleView(for: handle, in: selection, size: handleSize)
            }
        }
    }

    @ViewBuilder
    private func handleView(for handle: SelectionHandle, in rect: CGRect, size: CGFloat) -> some View {
        let position = handle.position(in: rect)

        RoundedRectangle(cornerRadius: 4)
            .fill(Color.white)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.blue, lineWidth: 1)
            )
            .position(position)
            .allowsHitTesting(false) // 仅用于显示，事件由 DragGesture 处理
    }
}

// MARK: - SelectionHandle Extension

extension SelectionHandle {
    /// 四角手柄
    static var cornerHandles: [SelectionHandle] {
        [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }

    /// 四边手柄
    static var edgeHandles: [SelectionHandle] {
        [.top, .bottom, .left, .right]
    }
}
