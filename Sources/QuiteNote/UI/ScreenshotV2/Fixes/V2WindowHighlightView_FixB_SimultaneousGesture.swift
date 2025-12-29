import SwiftUI

/// 修复方案 B：调整手势组合方式
///
/// 问题分析：
/// - 窗口交互区域的 Color.clear 拦截了鼠标事件
/// - 虽然它只处理 .onHover，但是作为 hit testing 的第一个视图，它阻止了父视图的拖拽手势
///
/// 解决方案：
/// - 在窗口交互区域添加 .simultaneousGesture(DragGesture)
/// - 让窗口区域的拖拽手势与根视图的拖拽手势同时识别
/// - 窗口区域的拖拽手势不做任何处理，只是让事件穿透
///
/// 预期效果：
/// - ✅ 鼠标悬停立即显示蓝色边框
/// - ✅ 拖拽不会误识别为点击
/// - ✅ 点击窗口仍然能正常工作
///
/// 使用方法：
/// 1. 替换 V2WindowHighlightView.swift 中的 buildWindowInteractionArea 方法
/// 2. 重新构建应用
/// 3. 测试悬停、点击、拖拽功能
///
/// 优点：
/// - 最小改动，只修改一个方法
/// - 保持了现有的架构和层级结构
/// - 利用 SwiftUI 的 simultaneousGesture 机制
///
/// 缺点：
/// - 可能存在多个 DragGesture 同时工作，理论上可能影响性能
/// - 需要测试在实际场景中的表现
///
/// 代码位置：
/// 替换 V2WindowHighlightView.swift 的 buildWindowInteractionArea 方法（409-427行）
///
/// 替换代码：
/*
 // ⚠️ 辅助：窗口交互区域（使用 simultaneousGesture 让事件穿透）
 private func buildWindowInteractionArea(for window: WindowInfo, localFrame: CGRect) -> some View {
     Color.clear
         .contentShape(Rectangle())
         .frame(width: localFrame.width, height: localFrame.height)
         .position(x: localFrame.midX, y: localFrame.midY)
         // ⚠️ 关键修复：添加 simultaneousGesture 让拖拽事件穿透到父视图
         .simultaneousGesture(
             DragGesture(minimumDistance: 0)
                 .onChanged { value in
                     // 空实现：让事件继续传递到根视图的 DragGesture
                     print("[EVENT] 窗口区域 DragGesture onChanged - 事件穿透: \(window.displayTitle)")
                 }
                 .onEnded { value in
                     // 空实现：让事件继续传递到根视图的 DragGesture
                     print("[EVENT] 窗口区域 DragGesture onEnded - 事件穿透: \(window.displayTitle)")
                 }
         )
         .onHover { hovering in
             print("[EVENT] onHover 触发 - 窗口: \(window.displayTitle), hovering: \(hovering)")
             if hovering {
                 print("[EVENT] 窗口悬停开始: \(window.displayTitle)")
                 onHoverWindow(window)
                 hoveredWindow = window
             } else if hoveredWindow?.id == window.id {
                 print("[EVENT] 窗口悬停结束: \(window.displayTitle)")
                 onHoverWindow(nil)
                 hoveredWindow = nil
             }
         }
 }
 */

/// 测试验证步骤：
/// 1. 启动应用，触发截图功能
/// 2. 移动鼠标到窗口上，观察是否立即显示蓝色边框
///    - ✅ 应该立即显示边框（onHover 工作）
///    - ✅ 控制台应该输出 "[EVENT] onHover 触发" 日志
/// 3. 点击窗口
///    - ✅ 应该选中窗口（onSelectWindow 被调用）
///    - ✅ 控制台应该输出识别为点击事件的日志
/// 4. 在窗口上按下鼠标并移动
///    - ✅ 应该显示拖拽框（不是点击）
///    - ✅ 控制台应该输出窗口区域的 DragGesture 日志和根视图的 DragGesture 日志
///    - ✅ 最终应该识别为框选事件（distance >= 5）
/// 5. 在空白处按下鼠标并移动
///    - ✅ 应该显示拖拽框
///    - ✅ 应该能正常框选区域

/// 理论基础：
///
/// SwiftUI 的手势识别机制：
/// 1. .gesture() - 子视图手势优先于父视图手势
/// 2. .simultaneousGesture() - 子视图和父视图手势同时识别
/// 3. .highPriorityGesture() - 父视图手势最高优先级
/// 4. .onTapGesture() - 等价于 .gesture(TapGesture())
///
/// 事件传递流程：
/// 1. 用户按下鼠标（在窗口区域）
/// 2. Hit testing 找到窗口交互区域的 Color.clear
/// 3. Color.clear 的 simultaneousGesture(DragGesture) 被触发
/// 4. 同时，根视图的 simultaneousGesture(DragGesture) 也被触发
/// 5. 两个 DragGesture 同时识别移动
/// 6. 用户释放鼠标
/// 7. 根视图的 DragGesture 计算距离，判断是点击还是框选
///
/// 关键点：
/// - simultaneousGesture 确保两个手势都工作
/// - 窗口区域的 DragGesture 不做任何处理，只是让事件"穿透"
/// - 根视图的 DragGesture 负责实际的点击/框选判断
///
/// 为什么这个方案能解决问题？
/// 1. .onHover 仍然工作（Color.clear 接收 hover 事件）
/// 2. 拖拽事件不会丢失（simultaneousGesture 确保根视图接收到事件）
/// 3. 点击判断正确（根视图的 DragGesture 能正确跟踪移动距离）
