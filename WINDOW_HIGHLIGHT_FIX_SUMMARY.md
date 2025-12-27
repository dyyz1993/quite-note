# 窗口高亮显示修复 - 快速指南

## 问题

窗口高亮不显示，原因是**坐标系混淆**。

## 根本原因

- `CGWindowListCopyWindowInfo` 返回**全局屏幕坐标**（原点在主屏幕左上角）
- SwiftUI ZStack 使用**窗口局部坐标**（原点在视图左上角）
- 代码直接混用两种坐标系，导致高亮框显示在错误位置

## 修复内容

### 1. WindowHighlightOverlay.swift

**新增**：
- `windowFrame: CGRect` 参数（遮罩窗口的屏幕位置）
- `convertScreenToLocal()` 方法（坐标转换）

**改动**：
```swift
// 使用转换后的局部坐标显示高亮
let localBounds = convertScreenToLocal(window.bounds)
Rectangle().path(in: localBounds).stroke(Color.blue, lineWidth: 4)
```

### 2. WindowDetectionView.swift

**新增**：
- `@State private var windowFrame: CGRect` 状态
- `captureWindowFrame()` 方法（获取窗口屏幕框架）
- `convertWindowToScreen()` 方法（坐标转换）

**改动**：
```swift
// 传递 windowFrame 给高亮层
WindowHighlightOverlay(window: highlightedWindow, windowFrame: windowFrame)

// 查找窗口时转换坐标
let screenPoint = convertWindowToScreen(point)
let found = windowService.findWindow(at: screenPoint, in: windows)
```

## 坐标转换公式

```
// 显示高亮：屏幕 → 局部
local = screen - windowOrigin

// 查找窗口：局部 → 屏幕
screen = local + windowOrigin
```

## 验证

1. 运行应用
2. 进入截图模式（步骤 0）
3. 移动鼠标到窗口上
4. 应该看到蓝色高亮边框

## 调试日志

```
[DEBUG WindowDetectionView] 窗口框架: (0.0, 0.0, 1920.0, 1080.0)
[DEBUG WindowDetectionView] 鼠标位置（窗口坐标）: (345.5, 278.0)
[DEBUG WindowDetectionView] 鼠标位置（屏幕坐标）: (345.5, 278.0)
[DEBUG WindowDetectionView] 找到窗口: Safari - Browser
```

## 状态

✅ 代码已修复
✅ 编译成功
⏳ 待测试验证
