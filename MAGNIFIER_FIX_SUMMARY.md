# 放大镜坐标偏差修复总结

## 问题描述

鼠标位置和放大镜显示的内容有偏差，比如鼠标在左上角，但放大镜显示的是光标右下角的内容。

## 根本原因

代码中使用硬编码的偏移量 `(80, 40)` 来转换坐标：
```swift
let canvasLocation = CGPoint(x: location.x - 80, y: location.y - 40)
```

这个偏移量只考虑了 `.padding(.horizontal, 80)` 和 `.padding(.vertical, 40)`，**但没有考虑工具栏的高度**。

当进入编辑模式时（`!isCropping`），工具栏会显示并占据顶部空间（包括 `.padding(.top, 30)`），导致 Canvas 的实际偏移量变成：
- X: 80
- Y: 40 + 工具栏高度 + 30

工具栏高度是动态的，无法通过硬编码准确计算。

## 解决方案

使用 SwiftUI 的 `coordinateSpace` 和 `PreferenceKey` 机制，**动态获取 Canvas 相对于 ZStack 的位置**，而不是手动计算偏移量。

## 代码修改

### 1. 添加状态变量

```swift
@State private var canvasFrameInZStack: CGRect = .zero
```

### 2. 定义坐标空间和接收更新

```swift
.coordinateSpace(name: "zstackSpace")
.onPreferenceChange(CanvasFramePreferenceKey.self) { frame in
    if let frame = frame {
        canvasFrameInZStack = frame
    }
}
```

### 3. 在 Canvas 中传递位置

```swift
.preference(key: CanvasFramePreferenceKey.self,
            value: geometry.frame(in: .named("zstackSpace")))
```

### 4. 定义 PreferenceKey

```swift
struct CanvasFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue()
    }
}
```

### 5. 添加统一的坐标转换函数

```swift
private func convertToCanvasCoordinates(_ point: CGPoint) -> CGPoint {
    return CGPoint(
        x: point.x - canvasFrameInZStack.minX,
        y: point.y - canvasFrameInZStack.minY
    )
}
```

### 6. 替换所有硬编码转换

将所有：
```swift
CGPoint(x: location.x - 80, y: location.y - 40)
```

替换为：
```swift
convertToCanvasCoordinates(location)
```

## 修改位置

- `/Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/Screenshot/ScreenshotPreviewView.swift`
  - 第 36 行：添加 `canvasFrameInZStack` 状态
  - 第 158-164 行：添加坐标空间和 Preference 接收
  - 第 262 行：`updateCursor` 中的坐标转换
  - 第 370-376 行：添加 `convertToCanvasCoordinates` 函数
  - 第 488 行：放大镜预览中的坐标转换
  - 第 494 行：Canvas 传递 Preference
  - 第 510-511 行：`handleDragChanged` 中的坐标转换
  - 第 549 行：创建元素时的坐标转换
  - 第 581 行：放大镜创建时的坐标转换
  - 第 600 行：拖动过程中的坐标转换
  - 第 849-856 行：添加 `CanvasFramePreferenceKey` 定义

## 效果

- ✅ 坐标转换精确，系统自动计算偏移量
- ✅ 适应不同布局状态（有/无工具栏）
- ✅ 代码更清晰，可维护性更好
- ✅ 不受未来 UI 调整影响

## 编译验证

```bash
$ swift build
Build complete! (2.90s)
```

无错误，无警告。
