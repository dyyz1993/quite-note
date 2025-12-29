import SwiftUI
import AppKit
import OSLog

/// 多窗口形状 - 用于性能优化
/// 一次性渲染所有窗口的形状，避免 ForEach + blendMode 性能瓶颈
struct MultiWindowShape: Shape {
    let localWindows: [CGRect]  // 预先转换好的局部坐标

    func path(in rect: CGRect) -> Path {
        var path = Path()

        for windowBounds in localWindows {
            path.addRect(windowBounds)
        }

        return path
    }
}

/// V2 窗口高亮视图 - 在静态截图上高亮显示窗口
/// 使用 WindowInfoService 获取所有窗口,在显示时过滤当前屏幕
struct V2WindowHighlightView: View {
    let screen: NSScreen
    let snapshot: NSImage
    let allWindows: [WindowInfo]  // 所有全局窗口
    let isPrimary: Bool  // 是否为主屏幕(鼠标所在屏幕)
    let onHoverWindow: (WindowInfo?) -> Void
    let onSelectWindow: (WindowInfo) -> Void
    let onSelectArea: (CGRect, NSScreen) -> Void
    let onCancel: () -> Void

    @State private var hoveredWindow: WindowInfo?
    @State private var dragStartPoint: CGPoint?
    @State private var dragCurrentPoint: CGPoint?

    /// 订阅主屏幕状态变化
    @StateObject private var primaryScreenManager = V2PrimaryScreenStateManager.shared

    /// 动态计算是否是主屏幕（响应鼠标移动）
    private var isCurrentlyPrimary: Bool {
        primaryScreenManager.isPrimary(screen)
    }

    /// 过滤出在当前屏幕上的窗口
    private var windowsOnScreen: [WindowInfo] {
        guard let cgScreenBounds = V2ScreenCaptureService.shared.getScreenBounds(screen) else {
            return []
        }

        print("[V2WindowHighlightView] 屏幕: \(screen.localizedName), 总窗口数: \(allWindows.count)")

        // ⚠️ 先按屏幕过滤，再按应用分组，计算每个应用的包围盒
        let windowsOnThisScreen = allWindows.filter { window in
            // 获取窗口中心点（CoreGraphics 坐标）
            let windowCenter = CGPoint(
                x: window.bounds.midX,
                y: window.bounds.midY
            )

            // 判断中心点是否在当前屏幕范围内（CoreGraphics 坐标）
            return cgScreenBounds.contains(windowCenter)
        }

        print("[V2WindowHighlightView] 屏幕内窗口数: \(windowsOnThisScreen.count)")

        // ⚠️ 不合并窗口，保持原始列表以保留正确的 windowID
        // 这样用户点击后可以正确处理窗口
        // 应用过滤条件
        let filtered = windowsOnThisScreen.filter { window in
            // ⚠️ 放宽过滤条件（参考专家建议）
            // 只过滤明显的小窗口（100x50而不是200x200）
            if window.bounds.width < 100 || window.bounds.height < 50 {
                return false
            }

            // 过滤系统窗口（精确匹配而不是contains）
            let systemOwners: Set<String> = ["Window Server", "程序坞", "墙纸", "通知中心", "WindowManager", "Dock"]
            if systemOwners.contains(window.ownerName) {
                return false
            }

            // 过滤壁纸和桌面
            if let name = window.windowName {
                if name.contains("Desktop") || name.contains("Wallpaper") || name.contains("Backdrop") || name.contains("Menubar") {
                    return false
                }
            }

            return true
        }

        print("[V2WindowHighlightView] 过滤后窗口数: \(filtered.count)")
        for window in filtered {
            print("  - \(window.displayTitle) (\(window.ownerName))")
        }

        return filtered
    }

    /// 遮罩透明度：主屏幕 0.5，其他屏幕 0.8
    /// ⚠️ 修复：初始状态所有屏幕都是 0.8，只有鼠标移动后才动态切换
    private var overlayOpacity: Double {
        // 如果还没有设置主屏幕，返回默认 0.8
        guard primaryScreenManager.primaryScreen != nil else {
            return 0.8
        }
        // 鼠标所在屏幕 0.5，其他屏幕 0.8
        return isCurrentlyPrimary ? 0.5 : 0.8
    }

    /// 计算拖拽选择矩形（带自动吸附功能）
    private var dragRect: CGRect? {
        guard let start = dragStartPoint, let current = dragCurrentPoint else {
            return nil
        }

        let rawRect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

        // 返回原始矩形（吸附逻辑在使用时处理）
        return rawRect
    }

    /// 吸附到最近的窗口（使用缓存的坐标映射）
    private func snapToWindow(_ rect: CGRect, localBoundsMap: [UUID: CGRect]) -> CGRect {
        // 找到与拖拽区域重叠最大的窗口
        var bestMatch: UUID?
        var maxOverlap: CGFloat = 0

        for (windowId, localFrame) in localBoundsMap {
            // 计算重叠面积
            let intersection = rect.intersection(localFrame)
            let overlap = intersection.width * intersection.height

            if overlap > maxOverlap {
                maxOverlap = overlap
                bestMatch = windowId
            }
        }

        // 如果重叠面积足够大（超过拖拽区域的 50%），自动吸附
        if let bestMatchId = bestMatch, maxOverlap > (rect.width * rect.height) * 0.5 {
            if let snappedFrame = localBoundsMap[bestMatchId] {
                return snappedFrame
            }
        }

        // 否则返回原始矩形
        return rect
    }

    var body: some View {
        // ⚠️ 简化：提取内容到计算属性
        let content = buildContent()
        return content
    }

    // ⚠️ 拆分：构建主内容
    private func buildContent() -> some View {
        let windowsOnScreen = self.windowsOnScreen
        let localBoundsList = calculateLocalBounds(for: windowsOnScreen)
        let localBoundsMap = createBoundsMap(windows: windowsOnScreen, bounds: localBoundsList)
        let isDragging = dragStartPoint != nil && dragCurrentPoint != nil
        let maskOverlay = buildMaskOverlay(isDragging: isDragging, localBoundsList: localBoundsList)

        return ZStack {
            buildBackgroundLayer()
            buildImageLayer()
            maskOverlay.zIndex(2)
            buildWindowHighlights(windows: windowsOnScreen, boundsMap: localBoundsMap, isDragging: isDragging)
                .zIndex(3)
        }
        .overlay(buildDragRectOverlay(boundsMap: localBoundsMap).zIndex(100))
        .background(Color.clear)
        .contentShape(Rectangle())
        .simultaneousGesture(buildDragGesture())  // ⚠️ 关键：让手势与子视图共存
    }

    // ⚠️ 拆分：背景层
    private func buildBackgroundLayer() -> some View {
        Color.black
            .allowsHitTesting(false)
            .zIndex(0)
    }

    // ⚠️ 拆分：图片层
    private func buildImageLayer() -> some View {
        Image(nsImage: snapshot)
            .resizable()
            .scaledToFill()
            .frame(width: screen.frame.width, height: screen.frame.height)
            .clipped()
            .allowsHitTesting(false)
            .zIndex(1)
    }

    // ⚠️ 拆分：窗口高亮层
    private func buildWindowHighlights(windows: [WindowInfo], boundsMap: [UUID: CGRect], isDragging: Bool) -> some View {
        Group {
            if !isDragging && !boundsMap.isEmpty {
                ForEach(windows, id: \.id) { window in
                    let localFrame = boundsMap[window.id] ?? CGRect.zero
                    let isHovered = hoveredWindow?.id == window.id
                    let isFullyVisible = screen.frame.contains(window.bounds)

                    if isHovered && isFullyVisible {
                        buildWindowHighlight(for: window, localFrame: localFrame)
                    }

                    buildWindowInteractionArea(for: window, localFrame: localFrame)
                        .zIndex(3)
                }
            }
        }
    }

    // ⚠️ 拖拽手势（同时处理点击和框选）
    private func buildDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 5)  // ⚠️ 修复：从 0 改为 5，避免误触
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

                if distance < 10 {
                    // ⚠️ 距离 < 10：认为是点击（从 5 改为 10）
                    print("[EVENT] 识别为点击事件，距离: \(distance)")
                    handleTap(at: start)
                } else {
                    // ⚠️ 距离 >= 10：认为是框选（从 5 改为 10）
                    print("[EVENT] 识别为框选事件，距离: \(distance)")
                    handleDragSelection(start: start, end: end)
                }

                dragStartPoint = nil
                dragCurrentPoint = nil
            }
    }

    // ⚠️ 处理点击事件
    private func handleTap(at location: CGPoint) {
        let localBoundsList = calculateLocalBounds(for: windowsOnScreen)
        let localBoundsMap = createBoundsMap(windows: windowsOnScreen, bounds: localBoundsList)

        // 检查是否点击在窗口内
        for window in windowsOnScreen {
            if let localFrame = localBoundsMap[window.id] {
                if localFrame.contains(location) {
                    print("[V2WindowHighlightView] 点击窗口: \(window.displayTitle)")
                    onSelectWindow(window)
                    return
                }
            }
        }

        // 点击空白处：截取整个屏幕
        print("[V2WindowHighlightView] 点击空白处，截取全屏")
        onSelectArea(screen.frame, screen)
    }

    // ⚠️ 处理框选事件
    private func handleDragSelection(start: CGPoint, end: CGPoint) {
        let localBoundsList = calculateLocalBounds(for: windowsOnScreen)
        let localBoundsMap = createBoundsMap(windows: windowsOnScreen, bounds: localBoundsList)

        let rawRect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        let snappedRect = snapToWindow(rawRect, localBoundsMap: localBoundsMap)
        if snappedRect.width > 20 && snappedRect.height > 20 {
            print("[V2WindowHighlightView] 框选完成: \(Int(snappedRect.width)) × \(Int(snappedRect.height))")
            onSelectArea(snappedRect, screen)
        }
    }

    // ⚠️ 辅助：蒙层构建
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
                // ⚠️ 修复：使用 mask 实现真正的窗口挖孔效果
                Color.black.opacity(isCurrentlyPrimary ? 0.4 : 0.7)
                    .mask(
                        ZStack {
                            Rectangle().fill(Color.white)
                            
                            ForEach(Array(localBoundsList.enumerated()), id: \.offset) { _, windowRect in
                                Rectangle()
                                    .fill(Color.black)
                                    .frame(width: windowRect.width, height: windowRect.height)
                                    .position(x: windowRect.midX, y: windowRect.midY)
                                    .blendMode(.destinationOut)
                            }
                        }
                        .compositingGroup()
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    // ⚠️ 辅助：拖拽框构建
    private func buildDragRectOverlay(boundsMap: [UUID: CGRect]) -> some View {
        Group {
            if let rawRect = dragRect {
                let snappedRect = snapToWindow(rawRect, localBoundsMap: boundsMap)
                let inset: CGFloat = 2
                let borderFrame = CGRect(
                    x: snappedRect.minX + inset,
                    y: snappedRect.minY + inset,
                    width: snappedRect.width - inset * 2,
                    height: snappedRect.height - inset * 2
                )

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue, lineWidth: 2)
                        .frame(width: borderFrame.width, height: borderFrame.height)
                        .position(x: borderFrame.midX, y: borderFrame.midY)

                    Text("\(Int(snappedRect.width)) × \(Int(snappedRect.height))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(4)
                        .position(x: snappedRect.midX, y: snappedRect.minY - 16)
                }
                .allowsHitTesting(false)
            }
        }
    }

    // ⚠️ 辅助：窗口高亮边框
    private func buildWindowHighlight(for window: WindowInfo, localFrame: CGRect) -> some View {
        let inset: CGFloat = 2
        let borderFrame = CGRect(
            x: localFrame.minX + inset,
            y: localFrame.minY + inset,
            width: localFrame.width - inset * 2,
            height: localFrame.height - inset * 2
        )

        return ZStack {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, dash: [10, 6]))
                .frame(width: borderFrame.width, height: borderFrame.height)
                .position(x: borderFrame.midX, y: borderFrame.midY)

            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white, lineWidth: 2)
                .frame(width: borderFrame.width, height: borderFrame.height)
                .position(x: borderFrame.midX, y: borderFrame.midY)

            VStack(alignment: .leading, spacing: 4) {
                Text(window.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                HStack(spacing: 8) {
                    Text("✓ 点击选择")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.8))

                    Text("ESC 取消")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.75)))
            .position(x: localFrame.midX, y: localFrame.minY - 30)
        }
        .allowsHitTesting(false)
    }

    // ⚠️ 辅助：窗口交互区域（只保留悬停，点击由拖拽手势处理）
    private func buildWindowInteractionArea(for window: WindowInfo, localFrame: CGRect) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: localFrame.width, height: localFrame.height)
            .position(x: localFrame.midX, y: localFrame.midY)
            // ⚠️ 移除 onTapGesture，点击由根视图的拖拽手势统一处理
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

    // ⚠️ 辅助：计算局部坐标
    private func calculateLocalBounds(for windows: [WindowInfo]) -> [CGRect] {
        windows.compactMap { window in
            V2CoordinateMapper.screenToLocal(rect: window.bounds, on: screen)
        }
    }

    // ⚠️ 辅助：创建坐标映射
    private func createBoundsMap(windows: [WindowInfo], bounds: [CGRect]) -> [UUID: CGRect] {
        Dictionary(uniqueKeysWithValues: zip(windows.map { $0.id }, bounds))
    }
}

/// 窗口高亮矩形 - 只在悬停时显示边框，窗口区域保持透明
struct V2WindowHighlightRectangle: View {
    let frame: CGRect
    let title: String
    let isHovered: Bool

    var body: some View {
        ZStack {
            // ⚠️ 关键：完全透明，不填充任何背景，显示下方的静态截图

            if isHovered {
                // 白色边框
                Rectangle()
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: frame.width, height: frame.height)

                // 标题标签
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.7))
                    )
                    .position(x: frame.midX, y: frame.minY - 12)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }
}

#Preview {
    V2WindowHighlightView(
        screen: NSScreen.main!,
        snapshot: NSImage(size: NSScreen.main!.frame.size),
        allWindows: [],
        isPrimary: true,
        onHoverWindow: { _ in },
        onSelectWindow: { _ in },
        onSelectArea: { _, _ in },
        onCancel: {}
    )
}
