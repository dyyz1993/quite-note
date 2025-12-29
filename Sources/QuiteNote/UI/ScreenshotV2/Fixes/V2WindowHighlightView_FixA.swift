import SwiftUI
import AppKit
import OSLog

/// 修复版本 A：简化蒙层显示逻辑
/// 移除复杂的 isCurrentlyPrimary 判断，固定透明度
///
/// 使用方法：将此文件的内容复制到 V2WindowHighlightView.swift 的对应位置
///
/// ⚠️ 这个修复假设问题在于蒙层条件分支判断逻辑有误
///
extension V2WindowHighlightView {

    /// ⚠️ 修复 A：简化的蒙层渲染逻辑
    ///
    /// 修改点：
    /// 1. 移除 isCurrentlyPrimary 的动态判断
    /// 2. 固定蒙层透明度为 0.5（不区分主屏幕和次屏幕）
    /// 3. 简化条件分支逻辑
    static func fixedMaskOverlay(
        isDragging: Bool,
        localBoundsList: [CGRect]
    ) -> some View {
        Group {
            if isDragging {
                // 拖拽时：完全透明
                Color.clear
            } else if localBoundsList.isEmpty {
                // ⚠️ 修复：无窗口时也显示蒙层（固定 0.5 透明度）
                Color.black.opacity(0.5)
                    .allowsHitTesting(false)
            } else {
                // 有窗口：使用 mask 挖空窗口区域（固定 0.5 透明度）
                Color.black.opacity(0.5)
                    .mask({
                        MultiWindowShape(localWindows: localBoundsList)
                            .fill(Color.white)
                            .blendMode(.destinationOut)
                    })
                    .allowsHitTesting(false)
            }
        }
    }
}

/// 在 V2WindowHighlightView.swift 中应用的修复说明
///
/// 步骤 1: 找到第 174-193 行的 maskOverlay 定义
///
/// 原代码：
/// ```swift
/// // ⚠️ 修复1：遮罩层 - 统一逻辑，拖拽时透明，否则根据主屏幕状态显示
/// let maskOverlay = Group {
///     if isDragging {
///         Color.clear
///     } else if localBoundsList.isEmpty {
///         Color.black.opacity(isCurrentlyPrimary ? 0.5 : 0.8)
///             .allowsHitTesting(false)
///     } else {
///         Color.black.opacity(isCurrentlyPrimary ? 0.5 : 0.8)
///             .mask({
///                 MultiWindowShape(localWindows: localBoundsList)
///                     .fill(Color.white)
///                     .blendMode(.destinationOut)
///             })
///             .allowsHitTesting(false)
///     }
/// }
/// ```
///
/// 步骤 2: 替换为简化版本
///
/// ```swift
/// // ⚠️ 修复 A：简化蒙层逻辑，固定透明度
/// let maskOverlay = Group {
///     if isDragging {
///         Color.clear
///     } else if localBoundsList.isEmpty {
///         // 无窗口：显示蒙层
///         Color.black.opacity(0.5)
///             .allowsHitTesting(false)
///     } else {
///         // 有窗口：挖空窗口区域
///         Color.black.opacity(0.5)
///             .mask({
///                 MultiWindowShape(localWindows: localBoundsList)
///                     .fill(Color.white)
///                     .blendMode(.destinationOut)
///             })
///             .allowsHitTesting(false)
///     }
/// }
/// ```
///
/// 步骤 3: 重新编译并测试
/// ```bash
/// ./build-app.sh
/// ```
///
/// 预期结果：
/// - 如果蒙层显示，说明问题是 isCurrentlyPrimary 判断逻辑有误
/// - 如果蒙层仍然不显示，说明问题在其他地方（继续使用方案 B）
///
