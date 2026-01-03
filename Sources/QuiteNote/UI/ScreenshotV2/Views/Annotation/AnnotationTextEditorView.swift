import SwiftUI

/// 标注文本编辑器 - 采用“半虚拟化”方案实现
/// - Text 负责展示：解决所有换行、自适应和渲染一致性问题
/// - TextField 负责输入：作为透明层覆盖在 Text 之上，仅接收键盘事件
struct AnnotationTextEditorView: View {
    @Binding var text: String
    var color: Color
    var fontSize: CGFloat
    var onCommit: () -> Void
    
    @FocusState private var isFocused: Bool
    @State private var blinkCursor = true
    
    // 定时器用于光标闪烁
    private let timer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // 1. 真实展示层 (可见)
            ZStack(alignment: .topLeading) {
                Text(text.isEmpty ? " " : text)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundColor(color)
                    .lineSpacing(fontSize * 0.3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                
                // ✨ 虚拟光标
                if isFocused {
                    cursorView
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isFocused ? Color.themeBackground.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isFocused ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            
            // 2. 透明输入层 (交互)
            // ⚠️ 关键：TextField 的文字完全透明 (opacity 0)，颜色透明
            // 它存在的唯一意义是拦截焦点和键盘事件
            TextField("", text: $text, axis: .vertical)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundColor(.clear) // 文字透明
                .accentColor(.clear)    // 隐藏系统光标
                .textFieldStyle(.plain)
                .lineLimit(nil)
                .lineSpacing(fontSize * 0.3)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .focused($isFocused)
                // 强制水平方向永远不要自作主张折行
                .fixedSize(horizontal: true, vertical: false)
        }
        // 告诉父容器：这个 ZStack 的大小由可见的 Text 决定，TextField 只是一个透明的挂件
        .fixedSize(horizontal: true, vertical: true)
        .onAppear {
            isFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
        .onReceive(timer) { _ in
            blinkCursor.toggle()
        }
    }
    
    /// 虚拟光标视图
    private var cursorView: some View {
        let lines = text.components(separatedBy: .newlines)
        let lastLine = lines.last ?? ""
        let lineHeight = fontSize * 1.3
        
        // 粗略计算光标位置
        // X: padding(8) + 字符估算宽度
        // Y: padding(6) + (行数-1) * 行高
        let cursorX = CGFloat(lastLine.count) * fontSize * 0.6 + 8
        let cursorY = CGFloat(max(0, lines.count - 1)) * lineHeight + 6
        
        return Rectangle()
            .fill(color)
            .frame(width: 2, height: fontSize)
            .opacity(blinkCursor ? 1 : 0)
            .offset(x: cursorX, y: cursorY)
            .animation(.easeInOut(duration: 0.1), value: blinkCursor)
    }
}
