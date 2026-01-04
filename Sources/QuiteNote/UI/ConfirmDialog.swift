import SwiftUI

/// 确认对话框配置
struct ConfirmConfig {
    let title: String
    let message: String
    let confirmTitle: String
    let cancelTitle: String? // 可选，如果为 nil 则只显示一个确定按钮
    let isDestructive: Bool
    let action: () -> Void
    
    init(
        title: String,
        message: String,
        confirmTitle: String = "确定",
        cancelTitle: String? = "取消",
        isDestructive: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.isDestructive = isDestructive
        self.action = action
    }
}

/// 统一风格的确认对话框视图
struct UnifiedConfirmView: View {
    let config: ConfirmConfig
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture { onDismiss() }
            
            // 对话框卡片
            VStack(spacing: 0) {
                // 标题
                Text(config.title)
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
                    .padding(.top, 24)
                    .padding(.horizontal, 24)
                
                // 内容
                Text(config.message)
                    .font(.themeBody)
                    .foregroundColor(.themeTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                
                Divider().background(Color.themeBorderSubtle)
                
                // 按钮组
                HStack(spacing: 0) {
                    // 取消按钮
                    if let cancelTitle = config.cancelTitle {
                        Button(action: onDismiss) {
                            Text(cancelTitle)
                                .font(.themeBody)
                                .foregroundColor(.themeTextSecondary)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        Divider()
                            .frame(height: 48)
                            .background(Color.themeBorderSubtle)
                    }
                    
                    // 确定按钮
                    Button(action: {
                        config.action()
                        onDismiss()
                    }) {
                        Text(config.confirmTitle)
                            .font(.themeBody)
                            .fontWeight(.semibold)
                            .foregroundColor(config.isDestructive ? .themeStatusError : .themeBlue400)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 300)
            .background(Color.themeBackground)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.themeBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}
