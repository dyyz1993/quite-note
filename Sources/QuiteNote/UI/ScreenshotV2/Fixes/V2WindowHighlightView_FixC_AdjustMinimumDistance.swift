import SwiftUI

/// 修复方案 C：调整 DragGesture 的 minimumDistance
///
/// 问题分析：
/// - DragGesture(minimumDistance: 0) 太敏感
/// - 按下鼠标立即开始跟踪，任何微小的移动都会被识别为拖拽
/// - 但是由于窗口交互区域的 Color.clear 拦截了事件，导致根视图的 DragGesture 无法正确跟踪
/// - 结果：移动距离计算错误，拖拽被识别为点击
///
/// 解决方案：
/// - 将根视图的 DragGesture 的 minimumDistance 从 0 改为 5
/// - 减少 DragGesture 的敏感度，避免误触发
/// - 同时调整点击/框选的判断阈值，从 5 改为 10
///
/// 预期效果：
/// - ✅ 鼠标悬停显示蓝色边框（需要配合方案 A 或 B）
/// - ✅ 小幅移动（< 5像素）不会触发拖拽，减少误判
/// - ✅ 明显的拖拽（>= 10像素）能正确识别为框选
///
/// 使用方法：
/// 1. 替换 V2WindowHighlightView.swift 中的 buildDragGesture 方法
/// 2. 重新构建应用
/// 3. 测试点击和拖拽功能
///
/// 优点：
/// - 简单直接，只修改一个方法的参数
/// - 减少了 DragGesture 的误触发
/// - 提高了点击/框选判断的准确性
///
/// 缺点：
/// - 不解决悬停不显示的问题（需要配合其他方案）
/// - 用户需要移动超过 5 像素才会开始跟踪拖拽
/// - 可能影响用户体验（需要更明确的拖拽动作）
///
/// 代码位置：
/// 替换 V2WindowHighlightView.swift 的 buildDragGesture 方法（222-260行）
///
/// 替换代码：
/*
 // ⚠️ 拖拽手势（调整 minimumDistance，减少误触发）
 private func buildDragGesture() -> some Gesture {
     DragGesture(minimumDistance: 5)  // ⚠️ 修改：从 0 改为 5，减少敏感度
         .onChanged { value in
             // 开始拖拽
             if dragStartPoint == nil {
                 dragStartPoint = value.startLocation
                 print("[EVENT] DragGesture onChanged - 开始拖拽: \(value.startLocation)")
             }
             dragCurrentPoint = value.location
             let distance = dragStartPoint.map { start in
                 sqrt(pow(value.location.x - start.x, 2) + pow(value.location.y - start.y, 2))
             } ?? 0
             print("[EVENT] DragGesture onChanged - 移动到: \(value.location), 距离: \(distance)")
         }
         .onEnded { value in
             guard let start = dragStartPoint, let end = dragCurrentPoint else {
                 print("[EVENT] DragGesture onEnded - 无起点或终点，忽略")
                 dragStartPoint = nil
                 dragCurrentPoint = nil
                 return
             }

             let distance = sqrt(pow(end.x - start.x, 2) + pow(end.y - start.y, 2))
             print("[EVENT] DragGesture onEnded - 总距离: \(distance)")

             // ⚠️ 修改：从 5 改为 10，提高判断阈值
             if distance < 10 {
                 // 距离 < 10：认为是点击
                 print("[EVENT] 识别为点击事件，距离: \(distance)")
                 handleTap(at: start)
             } else {
                 // 距离 >= 10：认为是框选
                 print("[EVENT] 识别为框选事件，距离: \(distance)")
                 handleDragSelection(start: start, end: end)
             }

             dragStartPoint = nil
             dragCurrentPoint = nil
         }
 }
 */

/// 测试验证步骤：
/// 1. 启动应用，触发截图功能
/// 2. 点击窗口（不移动）
///    - ✅ 应该选中窗口（识别为点击）
///    - ✅ 控制台应该输出 "识别为点击事件"
/// 3. 点击窗口并轻微移动（< 5 像素）
///    - ✅ 不应该触发 DragGesture（因为 minimumDistance: 5）
///    - ✅ 释放后应该识别为点击
/// 4. 点击窗口并明显移动（>= 10 像素）
///    - ✅ 应该触发 DragGesture（移动超过 5 像素）
///    - ✅ 应该显示拖拽框
///    - ✅ 释放后应该识别为框选（距离 >= 10）
/// 5. 在空白处测试相同操作
///    - ✅ 行为应该一致

/// 理论基础：
///
/// DragGesture(minimumDistance: d) 的行为：
/// - minimumDistance: 0 - 按下立即开始跟踪，任何移动都会触发 onChanged
/// - minimumDistance: 5 - 移动超过 5 像素才开始跟踪，小于 5 像素的移动不会触发
///
/// 为什么 minimumDistance: 0 有问题？
/// 1. 按下鼠标立即触发 onChanged
/// 2. 此时 startLocation == location（没有移动）
/// 3. 但是由于窗口交互区域的 Color.clear 拦截了事件
/// 4. 导致 onChanged 不能正确触发，或者 location 不更新
/// 5. 结果 distance 计算错误（< 5），被识别为点击
///
/// 为什么 minimumDistance: 5 能改善？
/// 1. 按下鼠标不会立即触发 onChanged
/// 2. 只有移动超过 5 像素才会触发
/// 3. 如果移动 < 5 像素，不会触发 onChanged，直接进入 onEnded
/// 4. 在 onEnded 中计算距离，如果 < 10，识别为点击
/// 5. 如果移动 >= 5 像素，触发 onChanged，开始跟踪
/// 6. 继续移动 >= 10 像素，释放后识别为框选
///
/// 关键改进：
/// - 减少了 DragGesture 的误触发
/// - 提供了更明确的点击/框选判断
/// - 降低了事件拦截的影响（因为只有明确的拖拽才会触发）
///
/// 注意事项：
/// - 这个方案单独使用时，不能解决悬停不显示的问题
/// - 建议配合方案 A（移除窗口交互区域）或方案 B（simultaneousGesture）使用
/// - 最佳组合：方案 B + 方案 C

/// 推荐组合：
///
/// 组合 1：方案 B（SimultaneousGesture）+ 方案 C（Adjust MinimumDistance）
/// - 使用 simultaneousGesture 让事件穿透
/// - 调整 minimumDistance 减少误触发
/// - 同时解决悬停和拖拽问题
///
/// 组合 2：方案 A（使用 .mask()）+ 方案 C（Adjust MinimumDistance）
/// - 使用 .mask() 替代 ZStack 挖孔
/// - 调整 minimumDistance 减少误触发
/// - 同时解决悬停和拖拽问题
///
/// 组合 3：单独使用方案 C（Adjust MinimumDistance）
/// - 只解决拖拽误识别问题
/// - 不解决悬停问题
/// - 最小改动，快速修复
