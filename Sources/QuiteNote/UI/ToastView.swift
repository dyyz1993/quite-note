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
        case "success": return Color.themeGreen500.opacity(0.8) // bg-green-500/80
        case "error": return Color.themeRed500.opacity(0.8) // bg-red-500/80
        case "warning": return Color.themeYellow500.opacity(0.8) // bg-yellow-500/80
        default: return Color.themeGray800.opacity(0.8) // bg-gray-800/80
        }
    }

    var textColor: Color {
        switch message.type {
        case "warning": return Color.themeGray900 // text-gray-900
        case "info": return Color.themeGray100 // text-gray-100
        default: return .white // text-white
        }
    }

    var iconNameLucide: IconName {
        switch message.type {
        case "success": return .check
        case "error": return .x
        case "warning": return .zap
        default: return .clipboard
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            LucideView(name: iconNameLucide, size: 16, color: textColor)
            Text(message.text).font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(textColor)
        .padding(12) // p-3
        .background(bgColor)
        .background(.ultraThinMaterial) // backdrop-blur-md
        .clipShape(RoundedRectangle(cornerRadius: 12)) // rounded-xl
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5) // shadow-2xl approximation
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}
