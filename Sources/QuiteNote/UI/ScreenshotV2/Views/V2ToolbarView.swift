import SwiftUI

/// V2 截图工具栏 - 显示在选中区域/窗口的线框上
struct V2ToolbarView: View {
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // 取消按钮
            Button(action: onCancel) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                    Text("取消")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.2))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // 保存按钮
            Button(action: onSave) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                    Text("保存")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.8))
        )
    }
}

#Preview {
    V2ToolbarView(
        onSave: { print("保存") },
        onCancel: { print("取消") }
    )
}
