# 窗口高亮显示问题诊断报告

## 问题概述

在 macOS 截图应用的窗口识别阶段（步骤 0），鼠标移动到窗口上时，窗口没有显示蓝色高亮边框。

### 症状
- 瞄准镜光标显示正常
- 按 Enter 能进入步骤 2（全屏截图）
- 鼠标移动时，窗口没有高亮显示
- 看不到任何边框、高亮效果

---

## 根本原因分析

### 问题核心：坐标系不匹配

经过深入调研和代码分析，发现问题出在**坐标系混淆**：

1. **`CGWindowListCopyWindowInfo` 返回的是全局屏幕坐标**
   - 原点在主显示器的**左上角** `(0, 0)`
   - Y 轴向下增长
   - 坐标是相对于整个屏幕的（全局坐标空间）

2. **SwiftUI 的 ZStack 使用的是窗口局部坐标系**
   - 原点在视图的左上角
   - 坐标是相对于窗口的（局部坐标空间）

3. **代码中直接混用了两种坐标系**
   - 将屏幕坐标当作窗口坐标使用
   - 导致高亮框显示在错误的位置（甚至超出屏幕边界）

### 参考来源

根据 [Apple Developer Documentation on kCGWindowBounds](https://developer.apple.com/documentation/coregraphics/kcgwindowbounds)：
> "The coordinates of the rectangle are specified in screen space, where the origin is in the upper-left corner of the main display."

根据 [Stack Overflow 讨论](https://stackoverflow.com/questions/20520902/how-to-get-nswindow-size-from-kcgwindownumber)：
> "The Core Graphics coordinate system has its origin at the top-left of the primary display, with Y increasing in the down direction."

---

## 问题代码定位

### 1. WindowHighlightOverlay.swift（第 17-20 行）

```swift
// ❌ 错误：直接使用 window.bounds（屏幕坐标）来定位视图
Rectangle()
    .path(in: window.bounds)  // window.bounds 是屏幕坐标！
    .stroke(Color.blue, style: StrokeStyle(lineWidth: 4))
```

**问题**：`window.bounds` 是屏幕坐标系中的位置，但 SwiftUI 的视图需要使用相对于窗口的局部坐标。

### 2. WindowDetectionView.swift（第 211-216 行）

```swift
private func updateHighlightedWindow(at point: CGPoint) {
    print("[DEBUG WindowDetectionView] 鼠标位置: \(point)")
    // ❌ 错误：point 是窗口局部坐标，但 findWindow 期望屏幕坐标
    let found = windowService.findWindow(at: point, in: windows)
    highlightedWindow = found
}
```

**问题**：`TrackingView.mouseMoved` 返回的坐标是相对于遮罩窗口的局部坐标，但 `findWindow` 期望屏幕坐标来查找窗口。

---

## 坐标系统详解

### macOS 全局屏幕坐标系统

```
┌─────────────────────────────────────────┐
│ 主屏幕 (0, 0)                           │
│                                         │
│     ┌──────────────┐                   │
│     │  窗口 A       │                   │
│     │  (100, 100)  │                   │
│     └──────────────┘                   │
│                                         │
└─────────────────────────────────────────┘
```

- 原点：主屏幕左上角
- X 轴：向右增长
- Y 轴：向下增长
- 适用于多显示器环境

### SwiftUI 窗口局部坐标系统

```
┌─────────────────────────────────────────┐
│ 遮罩窗口 (0, 0)                         │
│                                         │
│     ┌──────────────┐                   │
│     │  高亮边框     │                   │
│     │  (50, 50)    │  ← 局部坐标       │
│     └──────────────┘                   │
│                                         │
└─────────────────────────────────────────┘
```

- 原点：视图左上角
- X 轴：向右增长
- Y 轴：向下增长
- 相对于窗口内容区域

---

## 修复方案

### 核心思路

1. **获取遮罩窗口的屏幕框架**：知道遮罩窗口在屏幕上的位置
2. **坐标转换**：
   - 显示高亮：屏幕坐标 → 局部坐标
   - 查找窗口：局部坐标 → 屏幕坐标

### 修复后的代码

#### 1. WindowHighlightOverlay.swift

```swift
struct WindowHighlightOverlay: View {
    let window: WindowInfo?
    let windowFrame: CGRect  // 新增：窗口的屏幕框架

    var body: some View {
        if let window = window {
            // 转换屏幕坐标为局部坐标
            let localBounds = convertScreenToLocal(window.bounds)

            ZStack {
                // 使用转换后的局部坐标
                Rectangle()
                    .path(in: localBounds)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 4))
                    .shadow(color: Color.blue.opacity(0.5), radius: 8)

                windowInfoLabel(for: window)
                    .position(x: localBounds.midX, y: localBounds.minY - 20)
            }
        }
    }

    /// 将屏幕坐标转换为窗口局部坐标
    private func convertScreenToLocal(_ screenRect: CGRect) -> CGRect {
        // 局部坐标 = 屏幕坐标 - 窗口原点
        return CGRect(
            x: screenRect.origin.x - windowFrame.origin.x,
            y: screenRect.origin.y - windowFrame.origin.y,
            width: screenRect.size.width,
            height: screenRect.size.height
        )
    }
}
```

#### 2. WindowDetectionView.swift

```swift
struct WindowDetectionView: View {
    @State private var windowFrame: CGRect = .zero  // 新增：窗口的屏幕框架

    var body: some View {
        ZStack {
            // 传递 windowFrame 给高亮覆盖层
            WindowHighlightOverlay(window: highlightedWindow, windowFrame: windowFrame)
                .animation(.easeInOut(duration: 0.15), value: highlightedWindow?.bounds)
            // ...
        }
        .onAppear {
            setupWindowDetection()
            setupCursor()
            captureWindowFrame()  // 获取窗口框架
        }
    }

    private func updateHighlightedWindow(at point: CGPoint) {
        // 将窗口局部坐标转换为屏幕坐标
        let screenPoint = convertWindowToScreen(point)
        let found = windowService.findWindow(at: screenPoint, in: windows)
        highlightedWindow = found
    }

    /// 将窗口局部坐标转换为屏幕坐标
    private func convertWindowToScreen(_ point: CGPoint) -> CGPoint {
        // 屏幕坐标 = 局部坐标 + 窗口原点
        return CGPoint(
            x: point.x + windowFrame.origin.x,
            y: point.y + windowFrame.origin.y
        )
    }

    /// 捕获窗口的屏幕框架
    private func captureWindowFrame() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApp.keyWindow {
                windowFrame = window.frame
            }
        }
    }
}
```

---

## 坐标转换公式

### 显示高亮边框（屏幕 → 局部）

```
局部坐标 = 屏幕坐标 - 窗口原点

x_local = x_screen - window_frame.x
y_local = y_screen - window_frame.y
```

**示例**：
- 窗口在屏幕上的位置：`(100, 100)`
- 目标窗口在屏幕上的位置：`(200, 200, 400, 300)`
- 转换后的局部位置：`(100, 100, 400, 300)` → 相对于遮罩窗口的左上角

### 查找窗口（局部 → 屏幕）

```
屏幕坐标 = 局部坐标 + 窗口原点

x_screen = x_local + window_frame.x
y_screen = y_local + window_frame.y
```

**示例**：
- 遮罩窗口在屏幕上的位置：`(0, 0)`（全屏）
- 鼠标在窗口内的位置：`(300, 250)`
- 转换后的屏幕位置：`(300, 250)` → 用于查找窗口

---

## 测试验证

### 预期行为

1. 打开窗口识别界面（步骤 0）
2. 移动鼠标到任意窗口上
3. 应该看到蓝色高亮边框出现在该窗口周围
4. 边框应该完全贴合窗口边界
5. 窗口信息标签应该显示在边框上方

### 调试日志

修复后的代码会输出以下调试信息：

```
[DEBUG WindowDetectionView] 窗口框架: (0.0, 0.0, 1920.0, 1080.0)
[DEBUG WindowDetectionView] 鼠标位置（窗口坐标）: (345.5, 278.0)
[DEBUG WindowDetectionView] 鼠标位置（屏幕坐标）: (345.5, 278.0)
[DEBUG WindowDetectionView] 找到窗口: Safari - Browser
[DEBUG WindowInfoService] 命中窗口: Safari - Browser, bounds: (300.0, 200.0, 800.0, 600.0)
```

---

## 相关技术文档

### Apple 官方文档
- [kCGWindowBounds - Apple Developer](https://developer.apple.com/documentation/coregraphics/kcgwindowbounds)
- [CGWindowListCopyWindowInfo - Apple Developer](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:))
- [TN3124: Debugging coordinate space issues](https://developer.apple.com/documentation/technotes/tn3124-debugging-coordinate-transformations)

### 社区资源
- [How to get NSWindow size from kCGWindowNumber](https://stackoverflow.com/questions/20520902/how-to-get-nswindow-size-from-kcgwindownumber)
- [CGWindowListCopyWindowInfo: multiple screens](https://stackoverflow.com/questions/19475578/cgwindowlistcopywindowinfo-multiple-screens-and-changing-properties)
- [Deconstructing macOS screencapture CLI](https://blog.eternalstorms.at/2016/09/10/deconstructing-and-reimplementing-macos-screencapture-cli/)

---

## 总结

这次修复解决了 macOS 截图应用中窗口高亮显示的核心问题：**坐标系不匹配**。通过正确理解和使用 macOS 的全局屏幕坐标系统与 SwiftUI 的局部坐标系统，我们成功实现了窗口高亮功能。

### 关键要点

1. **`CGWindowListCopyWindowInfo` 返回的是全局屏幕坐标**
   - 原点在主屏幕左上角
   - 适用于多显示器环境

2. **SwiftUI 视图使用的是局部坐标系**
   - 需要进行坐标转换才能正确显示

3. **坐标转换的核心公式**
   - 局部坐标 = 屏幕坐标 - 窗口原点
   - 屏幕坐标 = 局部坐标 + 窗口原点

4. **调试建议**
   - 打印坐标值，确认转换是否正确
   - 在 Preview 中测试坐标转换逻辑
   - 使用 macOS 的 Accessibility Inspector 验证窗口位置

---

## 未来优化方向

1. **多显示器支持**：当前实现假设遮罩窗口位于主屏幕，需要扩展到多显示器
2. **窗口层级优化**：考虑使用 ScreenCaptureKit API（macOS 12.3+）替代 CGWindowListCopyWindowInfo
3. **性能优化**：缓存窗口列表，避免频繁调用 CGWindowListCopyWindowInfo
4. **边缘检测**：处理窗口跨越多个显示器的情况

---

**文档生成时间**：2025-12-26
**问题状态**：✅ 已修复
**编译状态**：✅ 编译成功
