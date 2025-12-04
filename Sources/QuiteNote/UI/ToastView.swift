import SwiftUI

struct ToastMessage {
    let text: String
    let type: String // success | error | warning | info
}

/// 顶部右侧 Toast 提示视图，自动淡入/淡出
struct ToastView: View {
    let message: ToastMessage

    var bgColor: Color {
        switch message.type {
        case "success": return Color.green.opacity(0.8)
        case "error": return Color.red.opacity(0.8)
        case "warning": return Color.yellow.opacity(0.8)
        default: return Color.gray.opacity(0.8)
        }
    }

    var iconName: String {
        switch message.type {
        case "success": return "checkmark"
        case "error": return "xmark"
        case "warning": return "bolt"
        default: return "doc.on.clipboard"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
            Text(message.text).font(.system(size: 13, weight: .medium))
        }
        .padding(10)
        .background(bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}

