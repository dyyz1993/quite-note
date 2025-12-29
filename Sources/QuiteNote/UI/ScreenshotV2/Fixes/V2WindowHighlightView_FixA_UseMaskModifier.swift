import SwiftUI

/// 修复方案 A：使用 .mask() 修饰符实现挖孔效果
///
/// 问题分析：
/// - 蒙层使用 ZStack 挖孔：在 ZStack 内部放置 Color.clear 实现透明区域
/// - 虽然整个 ZStack 设置了 .allowsHitTesting(false)，但内部的 Color.clear 仍然参与 hit testing
/// - 这些 Color.clear 在 zIndex(2) 层级，与窗口交互区域（zIndex 3）接近
/// - 可能阻挡事件传递或导致事件冲突
///
/// 解决方案：
/// - 使用 .mask() 修饰符实现挖孔效果
/// - 不再使用 ZStack 内部的 Color.clear
/// - 完全避免额外的视图层级，减少事件拦截
///
/// 预期效果：
/// - ✅ 蒙层仍然是黑色半透明
/// - ✅ 窗口区域完全透明，显示下方的截图
/// - ✅ 蒙层不会阻挡事件传递（因为只有一个视图，设置了 .allowsHitTesting(false)）
/// - ✅ 鼠标悬停能正常工作（窗口交互区域接收到事件）
///
/// 使用方法：
/// 替换 V2WindowHighlightView.swift 中的 buildMaskOverlay 方法
///
/// 优点：
/// - 完全移除了蒙层内部的 Color.clear 视图
/// - 简化了视图层级结构
/// - 避免了事件拦截和冲突
/// - 更符合 SwiftUI 的设计理念（使用修饰符而不是子视图）
///
/// 缺点：
/// - .mask() 的实现可能比较复杂
/// - 需要仔细调整 mask 的形状和位置
/// - 可能影响性能（mask 需要额外的渲染）
///
/// 代码位置：
/// 替换 V2WindowHighlightView.swift 的 buildMaskOverlay 方法（303-332行）
///
/// 替换代码：
/*
 // ⚠️ 辅助：蒙层构建（使用 .mask() 实现挖孔）
 private func buildMaskOverlay(isDragging: Bool, localBoundsList: [CGRect]) -> some View {
     let isSimpleMask = localBoundsList.isEmpty
     print("[EVENT] buildMaskOverlay - isDragging: \(isDragging), 窗口数: \(localBoundsList.count), 使用简单蒙层: \(isSimpleMask)")

     return Group {
         if isDragging {
             Color.clear
         } else if isSimpleMask {
             // 无权限或无窗口：简单蒙层
             Color.black.opacity(isCurrentlyPrimary ? 0.5 : 0.8)
                 .allowsHitTesting(false)
         } else {
             // ⚠️ 修复：使用 .mask() 实现窗口挖孔效果
             GeometryReader { geometry in
                 Color.black.opacity(isCurrentlyPrimary ? 0.5 : 0.8)
                     .mask(
                         // 创建 mask：除了窗口区域外，其他区域不透明
                         ZStack {
                             // 背景矩形：整个屏幕
                             Rectangle()
                                 .fill(Color.black)

                             // 窗口区域：使用 .destinationOut 挖孔
                             ForEach(Array(localBoundsList.enumerated()), id: \.offset) { _, windowRect in
                                 Rectangle()
                                     .fill(Color.white)
                                     .frame(width: windowRect.width, height: windowRect.height)
                                     .position(x: windowRect.midX, y: windowRect.midY)
                                     .blendMode(.destinationOut)
                             }
                         }
                         .compositingGroup()
                     )
             }
             .allowsHitTesting(false)  // 整个蒙层不拦截事件
         }
     }
 }
 */

/// 技术细节：
///
/// .mask() 修饰符的工作原理：
/// - mask 是一个视图，定义了哪些区域可见、哪些区域透明
/// - mask 中的不透明区域（Color.black）会使主视图可见
/// - mask 中的透明区域会使主视图透明
///
/// .blendMode(.destinationOut) 的作用：
/// - 从背景中"减去"当前视图
/// - 在 mask 中使用时，会挖孔出透明区域
/// - .compositingGroup() 确保 blendMode 只影响 mask 内部
///
/// 视图层级对比：
///
/// 原方案（ZStack 挖孔）：
/// ZStack (zIndex 2, allowsHitTesting(false))
///   ├── Color.black.opacity(0.5)
///   └── ForEach
///       └── Color.clear (每个窗口一个) ← 可能拦截事件
///
/// 新方案（.mask() 挖孔）：
/// Color.black.opacity(0.5) (zIndex 2, allowsHitTesting(false))
///   .mask(
///     ZStack
///       ├── Rectangle().fill(Color.black)
///       └── ForEach
///           └── Rectangle().fill(Color.white).blendMode(.destinationOut)
///   )
///
/// ** 关键差异：**
/// - 新方案只有一个 Color.black.opacity(0.5) 视图
/// - mask 内部的视图不影响 hit testing（它们只是 mask，不是实际的视图）
/// - 事件传递更简单直接

/// 测试验证步骤：
/// 1. 启动应用，触发截图功能
/// 2. 观察蒙层效果
///    - ✅ 背景应该是黑色半透明
///    - ✅ 窗口区域应该完全透明，显示下方的截图
///    - ✅ 边缘应该清晰，没有模糊或锯齿
/// 3. 测试事件传递
///    - ✅ 鼠标悬停在窗口上，应该立即显示蓝色边框
///    - ✅ 点击窗口应该能选中
///    - ✅ 拖拽应该能框选区域
/// 4. 对比测试
///    - 无权限时（简单蒙层）：应该仍然正常工作
///    - 有权限时（.mask() 挖孔）：应该与简单蒙层表现一致

/// 性能考虑：

/// .mask() 的性能影响：
/// - mask 需要额外的渲染步骤
/// - .blendMode(.destinationOut) 需要混合模式计算
/// - 对于多个窗口（10+），可能会有性能问题

/// 优化建议：
/// - 如果窗口数量较少（< 10），.mask() 方案性能可接受
/// - 如果窗口数量较多，可以考虑使用方案 B（SimultaneousGesture）
/// - 可以添加性能监控，对比两种方案的帧率和响应时间

/// 替代方案：使用 SwiftUI 的 Shape

/// 如果 .mask() 性能不佳，可以考虑创建自定义 Shape：

/// struct WindowMaskShape: Shape {
///     let windows: [CGRect]
///
///     func path(in rect: CGRect) -> Path {
///         var path = Path()
///
///         // 添加整个屏幕矩形
///         path.addRect(rect)
///
///         // 使用 even-odd rule 挖孔
///         for window in windows {
///             path.addRect(window)
///         }
///
///         return path
///     }
///
///     // 使用 even-odd fill rule
///     func fillRule() -> FillRule {
///         .evenOdd
///     }
/// }

/// // 使用方式：
/// WindowMaskShape(windows: localBoundsList)
///     .fill(Color.black.opacity(0.5))
///     .allowsHitTesting(false)

/// 优点：
/// - 更简单的实现
/// - 性能更好（单一 Path）
/// - 符合 SwiftUI 的设计理念

/// 缺点：
/// - 需要创建自定义 Shape
/// - even-odd rule 可能不适合所有场景

/// 推荐组合：

/// 组合 1：方案 A（.mask()）+ 方案 C（Adjust MinimumDistance）
/// - 使用 .mask() 实现挖孔
/// - 调整 minimumDistance 减少误触发
/// - 同时解决蒙层事件冲突和拖拽误识别问题

/// 组合 2：方案 A（.mask()）+ 方案 B（SimultaneousGesture）
/// - 使用 .mask() 实现挖孔
/// - 使用 simultaneousGesture 让事件穿透
/// - 同时解决蒙层事件冲突和窗口交互区域事件拦截问题

/// 组合 3：单独使用方案 A（.mask()）
/// - 只解决蒙层事件冲突问题
/// - 不解决窗口交互区域的事件拦截
/// - 建议配合方案 B 使用
