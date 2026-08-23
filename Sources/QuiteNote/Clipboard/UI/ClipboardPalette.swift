import SwiftUI

/// 剪贴板历史面板配色（按用户指定的 Alfred「All Snippets」参考样式复刻）
///
/// 注意：这是有意为之的浅色主题（区别于 App 其余部分的深色主题规范），
/// 用户明确要求参考该设计。改动前先确认不是误改回深色。
enum ClipboardPalette {
    /// 窗口/列表区背景 #f0f2f5
    static let background = Color(red: 0.941, green: 0.949, blue: 0.961)
    /// 顶部标题栏深紫 #6c3483
    static let header = Color(red: 0.424, green: 0.204, blue: 0.514)
    /// 行卡片白
    static let row = Color.white
    /// 悬停 #f5f5f5
    static let rowHover = Color(red: 0.961, green: 0.961, blue: 0.961)
    /// 键盘选中 #e8eaf6（浅紫）
    static let rowSelected = Color(red: 0.910, green: 0.918, blue: 0.965)
    /// 主文字（黑，参考图为纯黑，实际用近黑减轻生硬）
    static let textPrimary = Color(red: 0.10, green: 0.10, blue: 0.10)
    /// 次文字 #666
    static let textSecondary = Color(red: 0.40, green: 0.40, blue: 0.40)
    /// 三级文字 #999
    static let textTertiary = Color(red: 0.60, green: 0.60, blue: 0.60)
    /// 强调紫（序号/选中边框，与标题栏同源）
    static let accent = header
    /// 输入框边框 #d9dde3
    static let inputBorder = Color(red: 0.851, green: 0.867, blue: 0.890)
    /// 状态绿（正在记录）
    static let statusActive = Color(red: 0.22, green: 0.72, blue: 0.47)
    /// 状态黄（已暂停）
    static let statusPaused = Color(red: 0.87, green: 0.65, blue: 0.10)
    /// 状态红（失败/删除）
    static let statusError = Color(red: 0.90, green: 0.32, blue: 0.29)

    /// 类型图标色（参考图：类型着色的 24px 图标）
    static func typeColor(_ type: ClipboardEntryType) -> Color {
        switch type {
        case .text: return Color(red: 0.26, green: 0.26, blue: 0.26)
        case .link: return Color(red: 0.26, green: 0.52, blue: 0.96)   // 蓝
        case .file: return Color(red: 0.96, green: 0.55, blue: 0.13)   // 橙
        case .image: return Color(red: 0.30, green: 0.62, blue: 0.35)  // 绿
        }
    }
}
