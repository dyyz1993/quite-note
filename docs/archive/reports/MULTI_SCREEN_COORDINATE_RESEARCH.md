# 多显示器环境下坐标系统问题深度调研报告

**日期**: 2025-12-27
**问题编号**: Multi-Screen Coordinate System Issues
**调研范围**: 三显示器环境下的窗口检测、坐标转换、全屏应用支持

---

## 目录

1. [问题根因分析](#1-问题根因分析)
2. [macOS 多显示器坐标系统详解](#2-macos-多显示器坐标系统详解)
3. [当前代码问题诊断](#3-当前代码问题诊断)
4. [参考项目案例分析](#4-参考项目案例分析)
5. [完整修复方案](#5-完整修复方案)
6. [测试验证方法](#6-测试验证方法)

---

## 1. 问题根因分析

### 1.1 用户报告的问题

在三显示器环境下，用户遇到以下三个核心问题：

#### 问题 1: 窗口高亮框位置错误
- **现象**: 鼠标在第一个屏幕，但高亮框出现在右边（可能是在其他屏幕上）
- **影响**: 无法正确识别用户想要截图的窗口
- **严重程度**: 高（影响核心功能）

#### 问题 2: 拖拽框尺寸标签不跟随
- **现象**: 拖拽框选的尺寸标签只停留在一个屏幕，不会跑到其他屏幕
- **影响**: 跨屏幕拖拽时无法看到实时尺寸
- **严重程度**: 中（影响用户体验）

#### 问题 3: VS Code 全屏窗口无法选中
- **现象**: 某些全屏应用（如 VS Code 全屏模式）无法被窗口识别选中
- **影响**: 无法截图全屏应用
- **严重程度**: 高（限制功能覆盖范围）

### 1.2 根本原因

经过深入调研，发现以下根本原因：

#### 原因 1: 单屏幕覆盖策略
```swift
// WindowDetectionController.swift:68-76
let targetScreen = NSScreen.screens.first { screen in
    screen.frame.contains(NSEvent.mouseLocation)
} ?? NSScreen.main
```

**问题**:
- 只为鼠标所在屏幕创建 NSPanel
- 其他屏幕上的窗口高亮框无法显示
- 拖拽操作跨越屏幕时，尺寸标签无法跟随

#### 原因 2: 坐标系统混淆
```swift
// CoordinateSystem.swift:75-88
static func screenToLocal(
    _ screenPoint: CGPoint,
    windowFrame: CGRect,
    screen: NSScreen
) -> CGPoint {
    let windowFrameCG = appKitToCoreGraphics(windowFrame, screenHeight: screen.frame.height)
    return CGPoint(
        x: screenPoint.x - windowFrameCG.origin.x,
        y: screenPoint.y - windowFrameCG.origin.y
    )
}
```

**问题**:
- `CGWindowListCopyWindowInfo` 返回的 bounds 是**全局坐标系**
- 但代码假设窗口在单屏幕坐标系中
- 导致多屏幕下坐标转换错误

#### 原因 3: 窗口层级过滤过严
```swift
// WindowInfoService.swift:69
windows.sort { $0.layer > $1.layer }
```

**问题**:
- 全屏应用可能使用不同的窗口层级
- 当前代码可能过滤掉了某些全屏窗口

---

## 2. macOS 多显示器坐标系统详解

### 2.1 全局统一坐标系

**核心概念**: macOS 使用**全局统一坐标系**管理所有显示器，而非每个屏幕独立坐标系。

#### 坐标系统特性

1. **原点位置**: 主屏幕（包含菜单栏的屏幕）左上角为 (0, 0)
2. **Y 轴方向**: CoreGraphics 中 Y 轴向下增长，AppKit 中 Y 轴向上增长
3. **屏幕定位**: 其他屏幕相对于主屏幕定位，可能出现负坐标

#### 示例配置

```
三显示器水平排列：

┌─────────────┬─────────────┬─────────────┐
│   左屏      │   主屏      │   右屏      │
│ (-1920,0)   │   (0,0)     │  (1920,0)   │
│  1920×1080  │  1920×1080  │  1920×1080  │
└─────────────┴─────────────┴─────────────┘

全局坐标系范围：
左屏: x ∈ [-1920, 0],    y ∈ [0, 1080]
主屏: x ∈ [0, 1920],     y ∈ [0, 1080]
右屏: x ∈ [1920, 3840],  y ∈ [0, 1080]

全局原点 (0, 0) 在主屏幕左上角
```

### 2.2 NSScreen API 详解

#### 关键属性

```swift
// NSScreen.screens: 所有屏幕的数组
let screens = NSScreen.screens  // [NSScreen]

// NSScreen.main: 主屏幕（包含菜单栏）
let mainScreen = NSScreen.main  // NSScreen?

// 每个屏幕的 frame（全局坐标系）
let screenFrame = screen.frame  // CGRect(x, y, width, height)

// 每个屏幕的 visibleFrame（全局坐标系，排除 Dock 和菜单栏）
let visibleFrame = screen.visibleFrame  // CGRect
```

#### 重要区别

| 属性 | 含义 | 坐标系 | 用途 |
|------|------|--------|------|
| `NSScreen.main` | 包含菜单栏的屏幕 | - | 原点参考 |
| `NSScreen.screens[0]` | 不一定等于 main | - | 不可依赖 |
| `screen.frame` | 屏幕的全局位置 | 全局 | 坐标转换 |
| `screen.visibleFrame` | 可用区域 | 全局 | 窗口定位 |

### 2.3 CGWindowListCopyWindowInfo 的行为

#### 返回的窗口信息

```swift
let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)

// 每个窗口的字典包含：
kCGWindowBounds: CGRect      // ⚠️ 全局坐标系中的窗口位置
kCGWindowNumber: Int         // 窗口 ID
kCGWindowOwnerName: String   // 应用名称
kCGWindowLayer: Int          // 窗口层级
kCGWindowAlpha: Double       // 透明度
kCGWindowIsOnscreen: Bool    // 是否在屏幕上
```

#### 关键发现

1. **窗口边界**: `kCGWindowBounds` 是在**全局坐标系**中的绝对位置
2. **跨屏窗口**: 窗口可能跨越多个屏幕（虽然罕见）
3. **全屏应用**: 全屏应用的窗口占据整个屏幕的 `visibleFrame`

### 2.4 坐标系统转换

#### 三种坐标系统

1. **CoreGraphics 坐标系**（屏幕坐标）
   - 原点: 左上角
   - Y 轴: 向下增长
   - 用途: `CGWindowListCopyWindowInfo`

2. **AppKit 坐标系**（窗口坐标）
   - 原点: 左下角
   - Y 轴: 向上增长
   - 用途: `NSEvent.mouseLocation`, `NSWindow.frame`

3. **SwiftUI 坐标系**（视图坐标）
   - 原点: 左上角
   - Y 轴: 向下增长
   - 用途: SwiftUI 视图

#### 转换公式

```swift
// AppKit → CoreGraphics
func appKitToCoreGraphics(_ point: CGPoint, screenHeight: CGFloat) -> CGPoint {
    CGPoint(x: point.x, y: screenHeight - point.y)
}

// CoreGraphics → AppKit
func coreGraphicsToAppKit(_ point: CGPoint, screenHeight: CGFloat) -> CGPoint {
    CGPoint(x: point.x, y: screenHeight - point.y)
}

// ⚠️ 多屏幕下的正确做法
func getScreenContaining(point: CGPoint) -> NSScreen? {
    NSScreen.screens.first { $0.frame.contains(point) }
}
```

---

## 3. 当前代码问题诊断

### 3.1 WindowDetectionController.swift

#### 问题 1: 只覆盖鼠标所在屏幕

**位置**: Line 68-76

```swift
let targetScreen = NSScreen.screens.first { screen in
    screen.frame.contains(NSEvent.mouseLocation)
} ?? NSScreen.main

guard let screen = targetScreen else {
    print("[ERROR] WindowDetectionController: No screen found")
    return
}
let screenFrame = screen.frame
```

**问题**:
- 只为鼠标所在屏幕创建 NSPanel
- 其他屏幕上的窗口高亮框无法显示

**影响**:
- 问题 1: 窗口高亮框位置错误
- 问题 2: 拖拽框尺寸标签不跟随

#### 问题 2: 使用 NSScreen.main 而非实际屏幕

**位置**: Line 235, 258, 294

```swift
guard let screen = NSScreen.main else { return }
```

**问题**:
- 多屏幕环境下，`NSScreen.main` 不等于鼠标所在屏幕
- 导致坐标转换错误

### 3.2 WindowDetectionView.swift

#### 问题 1: windowFrame 使用单屏幕坐标系

**位置**: Line 310-320

```swift
private func captureWindowFrame() {
    if let screen = NSScreen.main {
        windowFrame = screen.frame
        print("[DEBUG WindowDetectionView] 使用屏幕框架: \(windowFrame)")
    }
}
```

**问题**:
- `windowFrame` 应该是**全局坐标系**中的所有屏幕联合区域
- 而不是单个屏幕的 frame

**影响**:
- 多屏幕下坐标转换错误
- 窗口高亮框位置错误

#### 问题 2: 鼠标事件处理未区分屏幕

**位置**: Line 233-254

```swift
private func handleGlobalMouseMove(_ event: NSEvent) {
    guard let screen = NSScreen.main else { return }

    let mouseLocation = NSEvent.mouseLocation
    let mouseCG = CoordinateSystem.appKitToCoreGraphics(mouseLocation, screenHeight: screen.frame.height)
    let localPoint = CoordinateSystem.screenToLocal(mouseCG, windowFrame: windowFrame, screen: screen)
    // ...
}
```

**问题**:
- 使用 `NSScreen.main` 而非鼠标所在屏幕
- 未处理鼠标跨越屏幕的情况

### 3.3 CoordinateSystem.swift

#### 问题 1: 转换假设单屏幕

**位置**: Line 75-88

```swift
static func screenToLocal(
    _ screenPoint: CGPoint,
    windowFrame: CGRect,
    screen: NSScreen
) -> CGPoint {
    let windowFrameCG = appKitToCoreGraphics(windowFrame, screenHeight: screen.frame.height)
    return CGPoint(
        x: screenPoint.x - windowFrameCG.origin.x,
        y: screenPoint.y - windowFrameCG.origin.y
    )
}
```

**问题**:
- 假设 `windowFrame` 在单屏幕坐标系中
- 实际上应该处理全局坐标系

### 3.4 WindowInfoService.swift

#### 问题 1: 可能过滤全屏窗口

**位置**: Line 49-52

```swift
// 过滤掉太小的窗口（可能是窗口部件）
guard width >= 100 || height >= 100 else {
    continue
}
```

**问题**:
- 某些全屏应用可能创建多个小窗口
- 过严的尺寸过滤可能误杀窗口

#### 问题 2: 未检查窗口与屏幕的交集

**位置**: Line 102-108

```swift
let found = windowList.first { window in
    let contains = window.isVisible && window.contains(point)
    if contains {
        print("[DEBUG WindowInfoService] 命中窗口: \(window.displayTitle), bounds: \(window.bounds)")
    }
    return contains
}
```

**问题**:
- `window.contains(point)` 只检查点是否在窗口内
- 未考虑窗口可能跨越多个屏幕

---

## 4. 参考项目案例分析

### 4.1 CleanShot X（商业产品）

**实现策略**（通过 YouTube 演示分析）:
- 为**所有屏幕**创建覆盖层
- 使用半透明黑色遮罩
- 窗口高亮框根据窗口实际位置渲染（支持跨屏）

**用户体验**:
- 所有屏幕同时变暗
- 可以在任意屏幕选择窗口
- 拖拽框可以跨越屏幕

### 4.2 Screenshot-bar（开源替代）

**GitHub**: 不在搜索结果中，但参考类似项目

**常见实现模式**:
```swift
// 为每个屏幕创建独立窗口
for screen in NSScreen.screens {
    let panel = NSPanel(...)
    panel.setFrame(screen.frame, display: true)
    panel.orderFront(nil)
    panels.append(panel)
}
```

**优势**:
- 简单直接
- 每个屏幕独立渲染
- 性能较好

### 4.3 多显示器博客文章

**参考**: [Dealing with multiple screens programming](https://www.thinkandbuild.it/deal-with-multiple-screens-programming/)

**关键发现**:
1. 全局坐标系从主屏幕开始
2. 其他屏幕相对于主屏幕定位
3. 需要遍历所有屏幕找到包含点的屏幕

**参考代码**:
```swift
var currentScreen = NSScreen.main
for scr in NSScreen.screens {
    if scr.frame.contains(location) {
        currentScreen = scr
        break
    }
}
```

### 4.4 中文博客案例

**参考**: [多显示器下判断窗口位置 macOS](https://www.logcg.com/en/archives/2771.html)

**关键发现**:
1. 全屏应用下 `NSScreen.main` 返回的是主屏幕，而非应用所在屏幕
2. 需要遍历所有屏幕找到窗口实际位置

**解决方案**:
```swift
var currentScreen = NSScreen.main
for scr in NSScreen.screens {
    if scr.frame.contains(location) {
        currentScreen = scr
        break
    }
}
```

---

## 5. 完整修复方案

### 5.1 架构设计建议

#### 推荐方案: 多屏幕独立覆盖

**架构图**:
```
WindowDetectionController (协调器)
    ├── ScreenPanelController (屏幕 1)
    │   ├── NSPanel (覆盖屏幕 1)
    │   └── WindowDetectionView (SwiftUI)
    ├── ScreenPanelController (屏幕 2)
    │   ├── NSPanel (覆盖屏幕 2)
    │   └── WindowDetectionView (SwiftUI)
    └── ScreenPanelController (屏幕 3)
        ├── NSPanel (覆盖屏幕 3)
        └── WindowDetectionView (SwiftUI)
```

**优势**:
1. 所有屏幕同时显示覆盖层
2. 窗口高亮框可以正确显示在任意屏幕
3. 拖拽框可以跨越屏幕（因为每个屏幕都有独立覆盖层）
4. 符合用户预期（类似 CleanShot X）

**实现复杂度**: 中等

### 5.2 具体修复方案

#### 方案 A: 多屏幕独立覆盖（推荐）

**核心改动**:

1. **修改 WindowDetectionController**
   - 为所有屏幕创建 NSPanel
   - 统一管理多个面板的生命周期
   - 协调跨屏幕的鼠标事件

2. **修改 WindowDetectionView**
   - 添加屏幕参数，知道自己在哪个屏幕
   - 使用正确的屏幕进行坐标转换
   - 只处理本屏幕内的窗口高亮

3. **修改 CoordinateSystem**
   - 支持全局坐标系
   - 添加屏幕查找方法
   - 修正坐标转换逻辑

4. **修改 WindowInfoService**
   - 支持跨屏窗口检测
   - 改进全屏窗口识别
   - 优化窗口层级过滤

#### 方案 B: 单屏幕智能切换（简化版）

**核心改动**:
- 只覆盖鼠标所在屏幕
- 当鼠标跨越屏幕时，动态切换覆盖层
- 优点: 实现简单
- 缺点: 用户体验不如方案 A

**推荐**: 方案 A（多屏幕独立覆盖）

### 5.3 代码实现

#### 文件 1: 创建 ScreenPanelController.swift

**新文件**: `/Sources/QuiteNote/UI/Screenshot/WindowDetection/ScreenPanelController.swift`

```swift
import AppKit
import SwiftUI

/// 单个屏幕的面板控制器
class ScreenPanelController: NSPanel {
    private let screen: NSScreen
    private var hostingController: NSHostingController<WindowDetectionView>?
    private let onWindowSelected: (WindowInfo, CGRect) -> Void
    private let onAreaSelected: (CGRect) -> Void
    private let onFullscreen: () -> Void
    private let onCancel: () -> Void

    init(
        screen: NSScreen,
        onWindowSelected: @escaping (WindowInfo, CGRect) -> Void,
        onAreaSelected: @escaping (CGRect) -> Void,
        onFullscreen: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.screen = screen
        self.onWindowSelected = onWindowSelected
        self.onAreaSelected = onAreaSelected
        self.onFullscreen = onFullscreen
        self.onCancel = onCancel

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        setupPanel()
    }

    private func setupPanel() {
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        ignoresMouseEvents = false
        isMovable = false
        hidesOnDeactivate = false
        collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]

        // 创建 SwiftUI 视图
        let view = WindowDetectionView(
            screen: screen,  // ⚠️ 传入屏幕参数
            onWindowSelected: onWindowSelected,
            onAreaSelected: onAreaSelected,
            onFullscreen: onFullscreen,
            onCancel: onCancel
        )

        hostingController = NSHostingController(rootView: view)
        hostingController?.view.frame = screen.frame
        contentViewController = hostingController
        setFrame(screen.frame, display: false)
    }

    func show() {
        setFrame(screen.frame, display: false)
        orderFrontRegardless()
    }

    override func close() {
        super.close()
        hostingController = nil
    }
}
```

#### 文件 2: 修改 WindowDetectionController.swift

**修改**: `/Sources/QuiteNote/UI/Screenshot/WindowDetection/WindowDetectionController.swift`

```swift
class WindowDetectionController: NSObject {
    // 回调
    private var onSelectionComplete: ((NSImage, CGRect) -> Void)?
    private var onCancel: (() -> Void)?

    // 通知模式
    private var notificationName: Notification.Name?

    // ⚠️ 改为管理多个面板
    private var screenPanels: [ScreenPanelController] = []

    // 私有初始化器
    private override init() {
        super.init()
    }

    /// 创建窗口识别控制器的工厂方法（通知模式）
    static func createWithNotification(notificationName: Notification.Name) -> WindowDetectionController {
        let controller = WindowDetectionController()
        controller.notificationName = notificationName
        return controller
    }

    /// 显示窗口识别面板
    func show() {
        print("[DEBUG] ===== WindowDetectionController.show() START =====")

        // ⚠️ 为所有屏幕创建面板
        for screen in NSScreen.screens {
            let panel = ScreenPanelController(
                screen: screen,
                onWindowSelected: { [weak self] window, rect in
                    self?.handleWindowSelected(window, rect: rect)
                },
                onAreaSelected: { [weak self] rect in
                    self?.handleAreaSelected(rect)
                },
                onFullscreen: { [weak self] in
                    self?.handleFullscreen()
                },
                onCancel: { [weak self] in
                    self?.handleCancel()
                }
            )
            panel.show()
            screenPanels.append(panel)
        }

        NSApp.activate(ignoringOtherApps: true)

        print("[DEBUG] ===== WindowDetectionController.show() END =====")
        print("[DEBUG] 创建了 \(screenPanels.count) 个屏幕面板")
    }

    // MARK: - 事件处理

    private func handleWindowSelected(_ window: WindowInfo, rect: CGRect) {
        guard let image = WindowInfoService.shared.captureWindow(window) else {
            print("[WindowDetection] Failed to capture window")
            return
        }

        close()
        notifySelectionComplete(image: image, rect: rect)
    }

    private func handleAreaSelected(_ rect: CGRect) {
        // ⚠️ 需要将局部坐标转换为全局坐标
        guard let image = WindowInfoService.shared.captureScreen(rect: rect) else {
            print("[WindowDetection] Failed to capture area")
            return
        }

        close()
        notifySelectionComplete(image: image, rect: rect)
    }

    private func handleFullscreen() {
        // ⚠️ 截取所有屏幕
        let images = screenPanels.compactMap { panel in
            WindowInfoService.shared.captureFullScreen(screen: panel.screen)
        }

        if let firstImage = images.first {
            close()
            notifySelectionComplete(image: firstImage, rect: .zero)
        }
    }

    private func handleCancel() {
        close()
        notifyCancelled()
    }

    // MARK: - 结果通知

    private func notifySelectionComplete(image: NSImage, rect: CGRect) {
        if let notificationName = notificationName {
            NotificationCenter.default.post(
                name: notificationName,
                object: self,
                userInfo: ["image": image, "rect": rect]
            )
        } else {
            onSelectionComplete?(image, rect)
        }
    }

    private func notifyCancelled() {
        if let notificationName = notificationName {
            NotificationCenter.default.post(
                name: notificationName,
                object: self,
                userInfo: ["cancelled": true]
            )
        } else {
            onCancel?()
        }
    }

    /// 关闭所有面板
    override func close() {
        screenPanels.forEach { $0.close() }
        screenPanels.removeAll()
    }
}
```

#### 文件 3: 修改 WindowDetectionView.swift

**修改**: `/Sources/QuiteNote/UI/Screenshot/WindowDetection/WindowDetectionView.swift`

```swift
struct WindowDetectionView: View {
    // ⚠️ 添加屏幕参数
    let screen: NSScreen
    let onWindowSelected: (WindowInfo, CGRect) -> Void
    let onAreaSelected: (CGRect) -> Void
    let onFullscreen: () -> Void
    let onCancel: () -> Void

    // 状态
    @State private var windows: [WindowInfo] = []
    @State private var highlightedWindow: WindowInfo?
    @State private var mouseLocation: CGPoint = .zero
    @State private var isDragging = false
    @State private var dragStartPoint: CGPoint = .zero
    @State private var selectionRect: CGRect = .zero
    @State private var showExitConfirm = false
    @State private var exitConfirmTimer: Timer?
    @State private var windowFrame: CGRect = .zero

    // 全局鼠标跟踪
    @State private var globalMonitor: Any?
    @State private var localMonitor: Any?

    // 服务
    private let windowService = WindowInfoService.shared

    init(
        screen: NSScreen,  // ⚠️ 新增参数
        onWindowSelected: @escaping (WindowInfo, CGRect) -> Void,
        onAreaSelected: @escaping (CGRect) -> Void,
        onFullscreen: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.screen = screen
        self.onWindowSelected = onWindowSelected
        self.onAreaSelected = onAreaSelected
        self.onFullscreen = onFullscreen
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            // 半透明遮罩层
            Color.black.opacity(0.2)
                .ignoresSafeArea(.all)

            // 背景点击处理
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 1) {
                    handleBackgroundTap()
                }

            // ⚠️ 传入屏幕参数
            WindowHighlightOverlay(
                window: highlightedWindow,
                screen: screen,  // ⚠️ 新增
                windowFrame: windowFrame
            )
            .animation(.easeInOut(duration: 0.15), value: highlightedWindow?.bounds)

            // 框选拖拽层
            SelectionDragLayer(
                selectionRect: $selectionRect,
                isDragging: isDragging,
                animation: .easeInOut(duration: 0.1)
            )

            // 底部提示栏
            VStack {
                Spacer()

                VStack(spacing: 8) {
                    hintPanel

                    if let window = highlightedWindow {
                        windowInfoPanel(for: window)
                    }
                }
                .padding(.bottom, 40)
            }

            // 退出确认提示
            if showExitConfirm {
                exitConfirmView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.all)
        .onAppear {
            print("[DEBUG WindowDetectionView] onAppear 被调用，屏幕: \(screen.localizedName ?? "Unknown")")
            setupWindowDetection()
            setupCursor()
            setupGlobalMouseTracking()
            captureWindowFrame()
            print("[DEBUG WindowDetectionView] onAppear 完成，找到 \(windows.count) 个窗口")
        }
        .onDisappear {
            print("[DEBUG WindowDetectionView] onDisappear 被调用")
            cleanupCursor()
            removeGlobalMouseTracking()
        }
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    handleDragChanged(value)
                }
                .onEnded { value in
                    handleDragEnded(value)
                }
        )
        .overlay {
            keyboardHandler
        }
    }

    // MARK: - 设置

    private func setupWindowDetection() {
        print("[DEBUG WindowDetectionView] setupWindowDetection 开始")
        switch windowService.fetchAllWindows() {
        case .success(let windowList):
            // ⚠️ 过滤出与当前屏幕相交的窗口
            windows = windowList.filter { window in
                window.bounds.intersects(screen.frame)
            }
            print("[DEBUG WindowDetectionView] 成功获取 \(windows.count) 个窗口（屏幕: \(screen.localizedName ?? "Unknown")）")
        case .failure(let error):
            print("[WindowDetection] Failed to fetch windows: \(error.localizedDescription)")
        }
    }

    // ⚠️ 修改：使用当前屏幕而非 NSScreen.main
    private func setupGlobalMouseTracking() {
        print("[DEBUG WindowDetectionView] setupGlobalMouseTracking 被调用")
        removeGlobalMouseTracking()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { event in
            self.handleGlobalMouseMove(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            self.handleLocalMouseMove(event)
            return event
        }

        print("[DEBUG WindowDetectionView] 全局鼠标监听已设置")
    }

    private func removeGlobalMouseTracking() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    // ⚠️ 修改：使用当前屏幕
    private func handleGlobalMouseMove(_ event: NSEvent) {
        // 1. 获取鼠标在屏幕上的位置（AppKit 坐标系）
        let mouseLocation = NSEvent.mouseLocation

        // 2. 检查鼠标是否在当前屏幕
        guard screen.frame.contains(mouseLocation) else {
            return
        }

        // 3. 转换为 CoreGraphics 坐标系
        let mouseCG = CoordinateSystem.appKitToCoreGraphics(mouseLocation, screenHeight: screen.frame.height)

        // 4. 转换为窗口局部坐标（SwiftUI 坐标系）
        let localPoint = CoordinateSystem.screenToLocal(mouseCG, windowFrame: windowFrame, screen: screen)

        DispatchQueue.main.async {
            self.mouseLocation = localPoint
            if !self.isDragging {
                self.updateHighlightedWindow(at: localPoint)
            }
        }
    }

    // ⚠️ 修改：使用当前屏幕
    private func handleLocalMouseMove(_ event: NSEvent) {
        let location = event.locationInWindow
        let mouseCG = CoordinateSystem.appKitToCoreGraphics(location, screenHeight: screen.frame.height)
        let localPoint = CoordinateSystem.screenToLocal(mouseCG, windowFrame: windowFrame, screen: screen)

        DispatchQueue.main.async {
            self.mouseLocation = localPoint
            if !self.isDragging {
                self.updateHighlightedWindow(at: localPoint)
            }
        }
    }

    // ⚠️ 修改：使用当前屏幕
    private func updateHighlightedWindow(at point: CGPoint) {
        print("[DEBUG WindowDetectionView] 鼠标位置（窗口局部坐标）: \(point)")

        // ⚠️ 使用当前屏幕而非 NSScreen.main
        let screenPoint = CoordinateSystem.localToScreen(point, windowFrame: windowFrame, screen: screen)
        print("[DEBUG WindowDetectionView] 鼠标位置（屏幕坐标 CG）: \(screenPoint)")

        let found = windowService.findWindow(at: screenPoint, in: windows)
        print("[DEBUG WindowDetectionView] 找到窗口: \(found?.displayTitle ?? "nil"), bounds: \(found?.bounds ?? .zero)")
        highlightedWindow = found
    }

    // ⚠️ 修改：使用当前屏幕
    private func captureWindowFrame() {
        windowFrame = screen.frame
        print("[DEBUG WindowDetectionView] 使用屏幕框架: \(windowFrame)")
    }

    // ... 其他方法保持不变 ...
}
```

#### 文件 4: 修改 WindowHighlightOverlay.swift

**修改**: `/Sources/QuiteNote/UI/Screenshot/WindowDetection/Views/WindowHighlightOverlay.swift`

```swift
struct WindowHighlightOverlay: View {
    let window: WindowInfo?
    let screen: NSScreen  // ⚠️ 新增
    let windowFrame: CGRect
    let animation: Animation?

    init(window: WindowInfo?, screen: NSScreen, animation: Animation? = .easeInOut(duration: 0.15), windowFrame: CGRect = .zero) {
        self.window = window
        self.screen = screen
        self.animation = animation
        self.windowFrame = windowFrame
    }

    var body: some View {
        if let window = window {
            // ⚠️ 检查窗口是否与当前屏幕相交
            let intersection = window.bounds.intersection(screen.frame)

            guard !intersection.isNull else {
                return Color.clear
            }

            // ⚠️ 转换为局部坐标
            let localBounds = CoordinateSystem.screenToLocal(
                intersection,
                windowFrame: windowFrame,
                screen: screen
            )

            // 渲染高亮框
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: localBounds.width, height: localBounds.height)

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue, lineWidth: 4)

                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white, lineWidth: 2)
                }
            }
            .frame(width: localBounds.width, height: localBounds.height)
            .position(x: localBounds.midX, y: localBounds.midY)
        } else {
            Color.clear
        }
    }
}
```

#### 文件 5: 修改 CoordinateSystem.swift

**修改**: `/Sources/QuiteNote/UI/Screenshot/WindowDetection/Utils/CoordinateSystem.swift`

```swift
struct CoordinateSystem {

    // MARK: - 新增：屏幕查找方法

    /// 查找包含指定点的屏幕
    /// - Parameter point: 全局坐标系中的点
    /// - Returns: 包含该点的屏幕，如果没有则返回 nil
    static func screenContaining(point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.contains(point)
        }
    }

    // MARK: - 点转换

    /// 将 AppKit 坐标（Y 向上）转换为 CoreGraphics 坐标（Y 向下）
    static func appKitToCoreGraphics(_ point: CGPoint, screenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: screenHeight - point.y)
    }

    /// 将 CoreGraphics 坐标（Y 向下）转换为 AppKit 坐标（Y 向上）
    static func coreGraphicsToAppKit(_ point: CGPoint, screenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: screenHeight - point.y)
    }

    // MARK: - 屏幕坐标 <-> 窗口局部坐标

    /// 将屏幕坐标（CoreGraphics）转换为窗口局部坐标（SwiftUI）
    /// - Parameters:
    ///   - screenPoint: 屏幕坐标点（CoreGraphics 坐标系）
    ///   - windowFrame: 窗口的屏幕框架（AppKit 坐标系）
    ///   - screen: 屏幕
    /// - Returns: 窗口局部坐标点（SwiftUI 坐标系）
    static func screenToLocal(
        _ screenPoint: CGPoint,
        windowFrame: CGRect,
        screen: NSScreen
    ) -> CGPoint {
        let windowFrameCG = appKitToCoreGraphics(windowFrame, screenHeight: screen.frame.height)
        return CGPoint(
            x: screenPoint.x - windowFrameCG.origin.x,
            y: screenPoint.y - windowFrameCG.origin.y
        )
    }

    /// 将窗口局部坐标（SwiftUI）转换为屏幕坐标（CoreGraphics）
    static func localToScreen(
        _ localPoint: CGPoint,
        windowFrame: CGRect,
        screen: NSScreen
    ) -> CGPoint {
        let windowFrameCG = appKitToCoreGraphics(windowFrame, screenHeight: screen.frame.height)
        return CGPoint(
            x: localPoint.x + windowFrameCG.origin.x,
            y: localPoint.y + windowFrameCG.origin.y
        )
    }

    // MARK: - 辅助方法

    /// 获取鼠标在屏幕上的位置（CoreGraphics 坐标系）
    static func mouseLocationInCoreGraphics() -> CGPoint {
        let mouseLocation = NSEvent.mouseLocation

        // ⚠️ 查找鼠标所在屏幕
        guard let screen = screenContaining(point: mouseLocation) else {
            return mouseLocation
        }

        return appKitToCoreGraphics(mouseLocation, screenHeight: screen.frame.height)
    }
}
```

#### 文件 6: 修改 WindowInfoService.swift

**修改**: `/Sources/QuiteNote/System/Services/WindowInfoService.swift`

```swift
class WindowInfoService {
    static let shared = WindowInfoService()

    private init() {}

    // MARK: - 获取窗口列表

    func fetchAllWindows() -> Result<[WindowInfo], WindowInfoError> {
        guard CGPreflightScreenCaptureAccess() else {
            return .failure(.screenCaptureAccessRequired)
        }

        guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: AnyObject]] else {
            return .failure(.noWindowsFound)
        }

        var windows: [WindowInfo] = []

        for windowInfo in windowList {
            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: AnyObject],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let width = boundsDict["Width"] as? CGFloat,
                  let height = boundsDict["Height"] as? CGFloat,
                  width > 0 && height > 0 else {
                continue
            }

            let bounds = CGRect(x: x, y: y, width: width, height: height)

            let windowNumber = windowInfo[kCGWindowNumber as String] as? Int ?? 0
            let ownerName = windowInfo[kCGWindowOwnerName as String] as? String ?? "Unknown"
            let windowName = windowInfo[kCGWindowName as String] as? String
            let layer = windowInfo[kCGWindowLayer as String] as? Int ?? 0
            let alpha = windowInfo[kCGWindowAlpha as String] as? Double ?? 1.0
            let isOnscreen = windowInfo[kCGWindowIsOnscreen as String] as? Bool ?? true

            // ⚠️ 改进：放宽尺寸限制，支持更多窗口类型
            guard width >= 50 || height >= 50 else {
                continue
            }

            // ⚠️ 改进：不严格过滤窗口层级，支持全屏应用
            // 保留所有可见窗口，由调用者决定是否过滤

            let window = WindowInfo(
                windowNumber: windowNumber,
                windowID: CGWindowID(windowNumber),
                bounds: bounds,
                ownerName: ownerName,
                windowName: windowName,
                layer: layer,
                alpha: alpha,
                isOnscreen: isOnscreen
            )

            windows.append(window)
        }

        // 按层级排序（高层级在前）
        windows.sort { $0.layer > $1.layer }

        return .success(windows)
    }

    // MARK: - 窗口命中检测

    func findWindow(at point: CGPoint, in windows: [WindowInfo]? = nil) -> WindowInfo? {
        print("[DEBUG WindowInfoService] findWindow 被调用，point: \(point)")
        let windowList: [WindowInfo]

        if let windows = windows {
            windowList = windows
            print("[DEBUG WindowInfoService] 使用传入的窗口列表，数量: \(windows.count)")
        } else {
            switch fetchAllWindows() {
            case .success(let list):
                windowList = list
                print("[DEBUG WindowInfoService] 自动获取窗口列表，数量: \(list.count)")
            case .failure(let error):
                print("[DEBUG WindowInfoService] 获取窗口列表失败: \(error)")
                return nil
            }
        }

        // ⚠️ 改进：查找命中点且可见的窗口
        let found = windowList.first { window in
            let contains = window.isVisible && window.bounds.contains(point)
            if contains {
                print("[DEBUG WindowInfoService] 命中窗口: \(window.displayTitle), bounds: \(window.bounds)")
            }
            return contains
        }

        print("[DEBUG WindowInfoService] 最终结果: \(found?.displayTitle ?? "nil")")
        return found
    }

    // MARK: - 屏幕截图

    func captureScreen(rect: CGRect, screen: NSScreen? = nil) -> NSImage? {
        let targetScreen = screen ?? NSScreen.main
        guard let targetScreen = targetScreen else {
            return nil
        }

        let displayID = targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID

        // ⚠️ 修复：确保 rect 在屏幕范围内
        let screenFrame = targetScreen.frame
        let clippedRect = rect.intersection(screenFrame)

        guard !clippedRect.isNull,
              let cgImage = CGDisplayCreateImage(displayID, rect: clippedRect) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: clippedRect.size)
    }

    func captureWindow(_ window: WindowInfo) -> NSImage? {
        print("[DEBUG WindowInfoService] captureWindow 被调用")
        print("[DEBUG WindowInfoService] 窗口 bounds（全局坐标）: \(window.bounds)")
        print("[DEBUG WindowInfoService] 窗口尺寸: \(window.bounds.width) x \(window.bounds.height)")

        // ⚠️ 修复：查找窗口所在的屏幕
        guard let screen = CoordinateSystem.screenContaining(point: window.bounds.origin) else {
            print("[DEBUG WindowInfoService] ⚠️ 无法找到窗口所在的屏幕")
            return nil
        }

        let image = captureScreen(rect: window.bounds, screen: screen)

        if let image = image {
            print("[DEBUG WindowInfoService] 截图成功，图片尺寸: \(image.size)")
        } else {
            print("[DEBUG WindowInfoService] ⚠️ 截图失败")
        }

        return image
    }

    func captureFullScreen(screen: NSScreen? = nil) -> NSImage? {
        let targetScreen = screen ?? NSScreen.main
        guard let targetScreen = targetScreen else {
            return nil
        }

        return captureScreen(rect: targetScreen.frame, screen: targetScreen)
    }

    // MARK: - 坐标转换

    func screenToImageRect(_ screenRect: CGRect, imageSize: CGSize, screenSize: CGSize) -> CGRect {
        let scaleX = imageSize.width / screenSize.width
        let scaleY = imageSize.height / screenSize.height

        return CGRect(
            x: screenRect.origin.x * scaleX,
            y: screenRect.origin.y * scaleY,
            width: screenRect.size.width * scaleX,
            height: screenRect.size.height * scaleY
        )
    }

    var mainScreenSize: CGSize {
        return NSScreen.main?.frame.size ?? .zero
    }

    var mainScreenFrame: CGRect {
        return NSScreen.main?.frame ?? .zero
    }
}
```

---

## 6. 测试验证方法

### 6.1 测试环境配置

**硬件要求**:
- 3 个显示器（推荐 1920×1080 或更高分辨率）
- 显示器排列方式：水平排列（左-中-右）

**软件要求**:
- macOS 13.0+
- Xcode 15+

### 6.2 测试用例

#### 测试用例 1: 单屏幕窗口高亮

**步骤**:
1. 在主屏幕打开一个窗口（如 Finder）
2. 触发截图模式
3. 移动鼠标到该窗口

**预期结果**:
- ✅ 窗口高亮框正确显示
- ✅ 高亮框位置与窗口位置完全重合
- ✅ 窗口信息正确显示

#### 测试用例 2: 多屏幕窗口高亮

**步骤**:
1. 在左屏、主屏、右屏各打开一个窗口
2. 触发截图模式
3. 依次将鼠标移动到每个屏幕的窗口上

**预期结果**:
- ✅ 所有屏幕同时显示半透明遮罩
- ✅ 每个屏幕的窗口高亮框位置正确
- ✅ 鼠标移动到哪个屏幕，该屏幕的窗口高亮

#### 测试用例 3: 跨屏幕拖拽

**步骤**:
1. 触发截图模式
2. 在左屏开始拖拽
3. 拖拽到主屏和右屏

**预期结果**:
- ✅ 拖拽框可以跨越屏幕
- ✅ 尺寸标签跟随鼠标移动
- ✅ 尺寸标签始终可见

#### 测试用例 4: 全屏应用截图

**步骤**:
1. 在右屏打开 VS Code
2. 进入全屏模式（Command + Control + F）
3. 触发截图模式
4. 移动鼠标到右屏的 VS Code 窗口

**预期结果**:
- ✅ VS Code 全屏窗口可以被识别
- ✅ 高亮框正确显示在右屏
- ✅ 点击可以正确截取全屏窗口

#### 测试用例 5: 跨屏窗口（罕见情况）

**步骤**:
1. 手动调整窗口位置，使其跨越两个屏幕
2. 触发截图模式
3. 移动鼠标到该窗口

**预期结果**:
- ✅ 窗口在两个屏幕都显示高亮框
- ✅ 高亮框位置正确
- ✅ 点击可以正确截取窗口

### 6.3 调试方法

#### 启用详细日志

在 `WindowDetectionView.swift` 中添加：

```swift
.onAppear {
    print("[DEBUG] 屏幕数量: \(NSScreen.screens.count)")
    for (index, screen) in NSScreen.screens.enumerated() {
        print("[DEBUG] 屏幕 \(index): \(screen.localizedName ?? "Unknown"), frame: \(screen.frame)")
    }
}
```

#### 可视化坐标系统

在 `WindowHighlightOverlay.swift` 中添加调试视图：

```swift
// 显示窗口边界
Text("x: \(Int(window.bounds.minX)), y: \(Int(window.bounds.minY))")
    .font(.system(size: 10))
    .foregroundColor(.red)
    .position(x: localBounds.minX, y: localBounds.minY)
```

### 6.4 性能测试

**测试指标**:
- 面板创建时间（应 < 100ms）
- 鼠标移动响应延迟（应 < 16ms，即 60fps）
- 内存占用（应 < 50MB）

**测试方法**:
```swift
let start = CFAbsoluteTimeGetCurrent()
// ... 操作 ...
let duration = CFAbsoluteTimeGetCurrent() - start
print("[PERF] 操作耗时: \(duration * 1000)ms")
```

---

## 7. 总结与建议

### 7.1 核心问题

1. **单屏幕覆盖**: 只覆盖鼠标所在屏幕，导致其他屏幕的窗口高亮框无法显示
2. **坐标转换错误**: 混淆了全局坐标系和局部坐标系
3. **全屏应用支持不足**: 窗口层级过滤过严，无法识别全屏应用

### 7.2 解决方案

**推荐方案**: 多屏幕独立覆盖

**核心改动**:
1. 为所有屏幕创建独立的 NSPanel
2. 使用全局坐标系处理窗口位置
3. 改进全屏应用识别逻辑

**预期效果**:
- ✅ 所有屏幕同时显示覆盖层
- ✅ 窗口高亮框位置正确
- ✅ 拖拽框可以跨越屏幕
- ✅ 全屏应用可以正常识别和截图

### 7.3 实施建议

**分阶段实施**:

1. **第一阶段**（核心功能）:
   - 实现多屏幕独立覆盖
   - 修复坐标转换逻辑
   - 测试基本功能

2. **第二阶段**（优化改进）:
   - 优化性能
   - 添加更多测试用例
   - 改进用户体验

3. **第三阶段**（高级功能）:
   - 支持跨屏窗口
   - 支持多屏幕全屏截图
   - 添加配置选项

**风险评估**:
- 低风险: 代码改动集中在窗口检测模块
- 中等复杂度: 需要处理多个面板的协调
- 可测试性: 在三显示器环境下可以充分测试

---

## 附录

### A. 参考资料链接

1. [Dealing with multiple screens programming](https://www.thinkandbuild.it/deal-with-multiple-screens-programming/)
2. [多显示器下判断窗口位置 macOS](https://www.logcg.com/en/archives/2771.html)
3. [Determine which display a window is on in macOS](https://stackoverflow.com/questions/40881963/determine-which-display-a-window-is-on-in-macos)
4. [Apple: NSScreen Documentation](https://developer.apple.com/documentation/appkit/nsscreen)
5. [Apple: Coordinate Spaces and Transformations](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/CapturingScreenContents/CapturingScreenContents.html)

### B. 相关文件清单

```
/Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/Screenshot/WindowDetection/
├── WindowDetectionController.swift         ⚠️ 需要修改
├── WindowDetectionView.swift              ⚠️ 需要修改
├── Views/
│   ├── WindowHighlightOverlay.swift       ⚠️ 需要修改
│   └── SelectionDragLayer.swift
├── Utils/
│   └── CoordinateSystem.swift             ⚠️ 需要修改
└── Models/
    └── WindowInfo.swift

/Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/System/Services/
└── WindowInfoService.swift                 ⚠️ 需要修改
```

### C. 术语表

| 术语 | 英文 | 说明 |
|------|------|------|
| 全局坐标系 | Global Coordinate System | macOS 中所有显示器共享的统一坐标系 |
| 局部坐标系 | Local Coordinate System | 相对于特定屏幕或窗口的坐标系 |
| 主屏幕 | Primary Screen | 包含菜单栏的屏幕 |
| 主窗口屏幕 | Main Screen | 包含当前 key window 的屏幕 |
| CoreGraphics 坐标系 | CoreGraphics Coordinate System | 原点在左上角，Y 轴向下 |
| AppKit 坐标系 | AppKit Coordinate System | 原点在左下角，Y 轴向上 |
| SwiftUI 坐标系 | SwiftUI Coordinate System | 原点在左上角，Y 轴向下 |
| NSPanel | NSPanel | AppKit 中用于浮动面板的窗口类 |

---

**文档版本**: 1.0
**最后更新**: 2025-12-27
**作者**: Claude Code
**审核状态**: 待审核
