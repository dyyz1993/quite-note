# 截图V2 代码骨架文档

> **生成时间**: 2026-01-01
> **目的**: 在重构前沉淀代码架构，为"先删后加"提供参考

---

## 目录

1. [流程图](#1-流程图)
2. [视图层级](#2-视图层级)
3. [分支逻辑](#3-分支逻辑)
4. [变量监听](#4-变量监听)
5. [数据流向](#5-数据流向)
6. [删除检查清单](#6-删除检查清单)

---

## 1. 流程图

### 1.1 用户交互流程（启动截图）

```
用户点击截图按钮
    ↓ (ScreenshotService.swift)
触发 V2ScreenshotController.show()
    ↓ (V2ScreenshotController.swift:18)
V2PrimaryScreenStateManager.shared.reset()
    ├── 清除所有 @Published 变量
    ├── 清空标注元素 (elements = [])
    └── 清空选区 (selectedArea = nil)
    ↓ (V2ScreenshotController.swift:23-44)
WindowInfoService.shared.fetchAllWindows()
    ├── 获取所有窗口信息
    ├── 过滤掉自身窗口 (Quite Note)
    ├── 过滤掉系统背景 (Window Server, Dock, Finder wallpaper)
    └── 返回 [WindowInfo] 列表（按 Z-order 排序）
    ↓ (V2ScreenshotController.swift:46-86)
for each screen in NSScreen.screens
    ├── captureScreen(screen) → 截取屏幕快照
    ├── 创建 V2ScreenshotView(screen, snapshot, allWindows)
    ├── 创建 V2TextInputPanel (NSPanel)
    ├── 设置窗口属性
    │   ├── level = .screenSaver (最高层级)
    │   ├── ignoresMouseEvents = false
    │   └── acceptsMouseMovedEvents = true
    ├── 创建 V2ScreenshotHostingView (SwiftUI → AppKit 桥接)
    └── panel.makeKeyAndOrderFront(nil)
    ↓ (V2ScreenshotView.swift:449-459)
onAppear
    ├── 延迟激活 Panel (becomeKey)
    └── 监听 "SaveScreenshot" 通知
    ↓
显示截图窗口（多屏同步）
```

---

### 1.2 窗口选择流程（鼠标悬停）

```
鼠标在屏幕上移动
    ↓ (V2ScreenshotView.swift:515-576)
buildInteractionLayer().onContinuousHover
    ↓
.onContinuousHover { phase in
    case .active(let location):
        ↓ (Line 521-523)
        重置 isMouseOverUI = false
        ↓ (Line 532-536)
        记录 hasMouseMoved = true
        ↓ (Line 539-541)
        primaryScreenManager.updatePrimaryScreen(screen)
        ↓ (Line 544)
        mouseLocation = location
        ↓ (Line 558)
        updateCursor(at: location)
        ↓ (Line 561)
        updateHoverState(at: location)
            ↓ (V2ScreenshotView.swift:110-128)
            updateHoverState(at location)
                ├── V2CoordinateMapper.localToScreen(point, screen) → 转换为全局坐标
                ├── windowsOnScreen.first { $0.bounds.contains(point) }
                ├── if 找到窗口:
                │   ├── getLocalRect(for: window) → 转换为局部坐标
                │   └── primaryScreenManager.updateHover(rect, label, on: screen)
                └── if 未找到:
                    ├── screenRect = CGRect(origin: .zero, size: screen.frame.size)
                    └── primaryScreenManager.updateHover(screenRect, "Full Screen", screen)
        ↓
更新 globalHoveredRect (全局状态)
    ↓ (V2ScreenshotView.swift:1109-1115)
buildDragOverlay
    ├── if snappedWireframeRect != nil:
    │   └── YellowWireframe(rect, label, isDashed: true, opacity: 0.8)
    └── .animation(.easeOut(duration: 0.15), value: rect)
        ↓
显示黄色线框（带动画）
```

---

### 1.3 选区创建流程（拖拽框选）

```
用户按下鼠标并拖拽
    ↓ (V2ScreenshotView.swift:584-831)
DragGesture(minimumDistance: 0)
    ↓
.onChanged { value in
    ↓ (Line 589-591)
    确保当前屏幕是主屏幕
    ↓ (Line 594)
    mouseLocation = value.startLocation
    ↓ (Line 597)
    updateHoverState(at: value.startLocation)
    ↓ (Line 601-604)
    重置 isMouseOverUI = false
    ↓ (Line 607-617)
    if editingTextId != nil:
        ├── if 点击选区外: finishTextEdit()
        └── else: return (让 TextField 接收)
    ↓ (Line 620-622)
    if isMouseOverUI: return (不处理 UI 上的拖拽)
    ↓ (Line 624)
    if isReleased: return
    ↓ (Line 626-768) 🔥 阶段 2: 编辑模式
    if isEditing && localSelectedArea != nil:
        ├── if selectedTool == .cursor: 元素移动逻辑
        ├── else: 绘图逻辑
        └── return
    ↓ (Line 771-819) 🔥 阶段 1: 选区调整
    if localSelectedArea != nil:
        ├── if isEditing || isLongScreenshotMode: return
        ├── if !isMovingSelection && activeHandle == nil:
        │   ├── if 点中手柄: activeHandle = handle
        │   ├── else if 点中选区内: isMovingSelection = true
        │   └── else: 开始新的框选 (dragStartPoint = startLocation)
        └── 执行调整大小或移动
    ↓ (Line 821-831) 🔥 阶段 0: 新选区创建
    else:
        ├── dragStartPoint = value.startLocation
        └── dragCurrentPoint = value.location
    ↓
.onEnded { value in
    ↓ (Line 837-838)
    计算拖拽距离
    ↓ (Line 841)
    if 拖拽距离 < 5 (判定为点击):
        ↓ (Line 844-856) 🔥 点击吸附选择
        if !isEditing && globalHoveredRect != nil:
            ├── updatePrimaryScreen(screen)
            ├── updateSelection(rect, screen)
            ├── 清空 dragStartPoint, dragCurrentPoint
            └── return
        ↓ (Line 859-877) 🔥 编辑模式点击
        if isEditing && selectedTool == .cursor:
            ├── 查找点击位置的元素
            ├── if 文本元素: editingTextId = element.id
            └── selectedElementId = element.id
        ↓ (Line 881-896) 🔥 放大镜工具点击
        if isEditing && selectedTool == .magnifier:
            ├── 创建 DrawingElement(tool: .magnifier)
            └── 添加到 elements
        ↓ (Line 900-915) 🔥 文本工具点击
        if isEditing && selectedTool == .text:
            ├── 创建 DrawingElement(tool: .text)
            └── editingTextId = element.id
        ↓ (Line 918-925) 🔥 点击选区外
        if localSelectedArea != nil && !contains(clickLocation):
            ├── updateSelection(nil, nil)
            └── setEditing(false)
        └── return
    ↓ (Line 934-950) 🔥 拖拽结束处理
    if isEditing:
        ├── if isDraggingElement: 重置拖拽状态
        └── if currentElement != nil: addElement(currentElement)
    ↓ (Line 952-958) 🔥 选区调整结束
    if isMovingSelection || activeHandle != nil:
        ├── isMovingSelection = false
        └── activeHandle = nil
    ↓ (Line 960-974) 🔥 新选区确认
    if dragStartPoint != nil:
        ├── 计算矩形 (min(start.x, end.x)...)
        ├── if rect.width > 5 && rect.height > 5:
        │   └── updateSelection(rect, screen)
        └── dragStartPoint = nil
    ↓
选区创建完成
```

---

### 1.4 多屏协调流程

```
用户移动鼠标到另一个屏幕
    ↓ (V2ScreenshotView.swift:539-541)
primaryScreenManager.updatePrimaryScreen(newScreen)
    ↓ (V2PrimaryScreenStateManager.swift:126-128)
primaryScreen = newScreen
    ↓
所有 V2ScreenshotView 重新计算 isCurrentlyPrimary
    ↓ (V2ScreenshotView.swift:45-47)
var isCurrentlyPrimary: Bool {
    primaryScreenManager.isPrimary(screen)
}
    ↓
其他屏幕触发 isReleased = true
    ↓ (V2ScreenshotView.swift:67-72)
var isReleased: Bool {
    guard hasAnySelection else { return false }
    return !isCurrentlyPrimary
}
    ↓ (V2ScreenshotView.swift:271-273)
if isReleased:
    └── Color.clear (完全不渲染)
    ↓ (V2ScreenshotView.swift:468-480)
.onChange(of: isReleased) { released in
    ├── panel.ignoresMouseEvents = released
    └── released ? "Screen released" : "Screen reclaimed"
    ↓
非主屏幕释放（允许鼠标穿透）
```

---

### 1.5 标注系统流程（编辑模式）

```
用户点击工具栏的编辑按钮
    ↓ (V2FloatingToolbar.swift)
V2FloatingToolbar.onEdit
    ↓
primaryScreenManager.setEditing(true)
    ↓ (V2PrimaryScreenStateManager.swift:137-142)
setEditing(_ editing: Bool)
    ├── isEditing = editing
    └── if editing: isLongScreenshotMode = false
    ↓ (V2ScreenshotView.swift:1026-1067)
buildAnnotationLayer
    ├── V2AnnotationCanvas(
    │   stateManager: primaryScreenManager,
    │   canvasSize: screenSize,
    │   baseImage: snapshot
    │ )
    │   .zIndex(20)
    ↓
渲染标注层 (zIndex=20)
    ├── if magnifierPreviewPosition != nil:
    │   └── AnnotationMagnifierPreview (zIndex=25)
    └── V2AnnotationTextEditorView (zIndex=30)
    ↓ (V2ScreenshotView.swift:742-768)
用户选择工具并绘制
    ↓
DragGesture.onChanged (阶段 2)
    ├── if selectedTool == .cursor: 元素选择/移动
    ├── if selectedTool == .magnifier: 点击创建
    ├── if selectedTool == .text: 点击创建
    └── else: 绘制路径
        ├── currentElement = DrawingElement(...)
        └── currentElement.points.append(location)
    ↓ (V2ScreenshotView.swift:945-948)
DragGesture.onEnded
    └── addElement(currentElement)
    ↓ (V2PrimaryScreenStateManager.swift:184-189)
addElement(_ element)
    ├── elements.append(element)
    └── if element.tool == .steps: stepCounter += 1
    ↓
标注元素已保存
```

---

### 1.6 保存剪贴板流程

```
用户点击工具栏的保存按钮
    ↓ (V2FloatingToolbar.swift)
发送 "SaveScreenshot" 通知
    ↓ (V2ScreenshotView.swift:462-466)
NotificationCenter.default.addObserver
    ↓
saveToClipboard(rect: selection)
    ↓ (V2ScreenshotView.swift:202-266)
    ├── (Line 206) scale = screen.backingScaleFactor
    ├── (Line 209-214) pixelRect = rect * scale
    ├── (Line 217-221) 裁剪 CGImage
    ├── (Line 224) finalImage = NSImage(cgImage: croppedCGImage)
    ↓ (Line 227-255) 🔥 渲染标注层
    if !elements.isEmpty:
        ├── exportCanvas = V2AnnotationCanvas(isExporting: true)
        ├── renderer = ImageRenderer(content: exportCanvas)
        ├── renderer.scale = scale
        ├── annotationImage = renderer.nsImage
        ├── croppedAnnotationImage = annotationImage.cropping(to: pixelRect)
        └── finalImage.draw(croppedAnnotationImage) (叠加)
    ↓ (Line 258-260)
    pasteboard.writeObjects([finalImage])
    ↓ (Line 265)
    V2ScreenshotController.close()
    ↓
截图已保存到剪贴板
```

---

## 2. 视图层级

### 2.1 ZStack 完整层级结构

```
V2ScreenshotView (ZStack)
│
├── 🔴 Layer 0: 彻底释放层
│   └── if isReleased: Color.clear (完全透明，不渲染任何内容)
│
├── 🔵 Layer 1: 背景层 (始终显示)
│   └── Image(nsImage: snapshot)
│       ├── .resizable()
│       ├── .scaledToFill()
│       └── .frame(width: screen.width, height: screen.height)
│
├── ⚫️ Layer 2: 蒙层层 (挖孔效果)
│   └── if !isLongScreenshotMode:
│       └── V2MaskOverlayView(
│           isReleased, screenSize,
│           dragStartPoint, dragCurrentPoint,
│           localSelectedArea, isCurrentlyPrimary,
│           hasPrimaryScreen
│       )
│
├── 🔴 Layer 3: 交互层 (处理鼠标事件)
│   └── buildInteractionLayer()
│       ├── Color.white.opacity(0.0001) (透明热区)
│       ├── .onContinuousHover { ... }
│       └── .simultaneousGesture(DragGesture)
│
├── 🟡 Layer 4: 框选层 (显示黄色线框)
│   └── buildDragOverlay()
│       ├── zIndex(15)
│       ├── if dragStartPoint != nil: 正在拖拽的临时选区
│       ├── if localSelectedArea != nil: 已确认的选区 + 手柄
│       └── if snappedWireframeRect != nil: 悬停预览
│
├── 🟢 Layer 4.5: 标注层 (编辑模式)
│   └── if !isLongScreenshotMode && isEditing:
│       └── buildAnnotationLayer()
│           ├── V2AnnotationCanvas (zIndex=20)
│           ├── AnnotationMagnifierPreview (zIndex=25)
│           └── V2AnnotationTextEditorView (zIndex=30)
│
├── 🟣 Layer 5: 调试信息层 (最顶层)
│   └── if !isCapturing:
│       └── V2DebugOverlayView(
│           screen, screenIndex,
│           isCurrentlyPrimary, logEntries,
│           windowsOnScreen, currentLayerName, currentLayerLevel,
│           onClose, onBack, onPanelHover, onCloseButtonHover
│       )
│
├── 📸 Layer 5.1: 长图滚动预览
│   └── if isLongScreenshotMode && localSelectedArea != nil && !isCapturing:
│       └── V2LongScreenshotPreview(selection, screen)
│
├── 🛠️ Layer 5.2: 截图工具栏
│   └── if localSelectedArea != nil && !isCapturing:
│       └── V2FloatingToolbar(selection, screen)
│           ├── zIndex(1000) (最顶层)
│           └── 保存、编辑、长图、取消等按钮
│
└── 🏷️ Layer 5.3: 层级标签 (调试用)
    └── if !isCapturing:
        └── VStack (Layer 1-5 的标签列表)
```

### 2.2 zIndex 值分布

| 层级 | zIndex | 显示条件 |
|------|--------|----------|
| 框选层 | 15 | 始终 |
| 标注层 | 20 | isEditing && !isLongScreenshotMode |
| 放大镜预览 | 25 | isEditing && magnifierPreviewPosition != nil |
| 文本编辑器 | 30 | isEditing && editingTextId != nil |
| 工具栏 | 1000 | localSelectedArea != nil && !isCapturing |

---

## 3. 分支逻辑

### 3.1 DragGesture.onChanged 的主要分支

```swift
DragGesture(minimumDistance: 0)
    .onChanged { value in

        // ✅ 分支 1: 主屏幕检查 (Line 589-591)
        if !isCurrentlyPrimary {
            primaryScreenManager.updatePrimaryScreen(screen)
        }

        // ✅ 分支 2: 文本编辑中 (Line 607-617)
        if editingTextId != nil {
            if let selection = localSelectedArea, !selection.contains(value.startLocation) {
                finishTextEdit()
            } else {
                return // 点击选区内，让 TextField 接收
            }
        }

        // ✅ 分支 3: 鼠标在 UI 上 (Line 620-622)
        if isMouseOverUI && !isDraggingElement && !isMovingSelection && activeHandle == nil {
            return
        }

        // ✅ 分支 4: 屏幕已释放 (Line 624)
        if isReleased { return }

        // ✅ 分支 5: 阶段 2 - 编辑模式 (Line 629-768)
        if isEditing, let selection = localSelectedArea {
            if selectedTool == .cursor {
                // 5.1: 选择工具 → 移动元素
            } else {
                // 5.2: 绘图工具 → 创建路径
            }
            return
        }

        // ✅ 分支 6: 阶段 1 - 选区调整 (Line 774-819)
        if let currentSelection = localSelectedArea {
            if isEditing || isLongScreenshotMode { return }
            // 6.1: 检查手柄 → 调整大小
            // 6.2: 检查选区内 → 移动选区
            // 6.3: 点击外部 → 开始新框选
            return
        }

        // ✅ 分支 7: 阶段 0 - 新选区创建 (Line 825-831)
        if dragStartPoint == nil {
            dragStartPoint = value.startLocation
        }
        dragCurrentPoint = value.location
    }
```

### 3.2 DragGesture.onEnded 的主要分支

```swift
.onEnded { value in

    // ✅ 分支 1: 点击检测 (Line 837)
    let dragDistance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
    let isClick = dragDistance < 5

    if isClick {
        // 1.1: 窗口吸附选择 (Line 844-856)
        if !isEditing && globalHoveredRect != nil {
            updateSelection(rect, screen)
            return
        }

        // 1.2: 编辑模式 - 选择元素 (Line 859-878)
        if isEditing && selectedTool == .cursor {
            selectedElementId = hitElement.id
            return
        }

        // 1.3: 编辑模式 - 放大镜工具 (Line 881-896)
        if isEditing && selectedTool == .magnifier {
            addElement(magnifierElement)
            return
        }

        // 1.4: 编辑模式 - 文本工具 (Line 900-915)
        if isEditing && selectedTool == .text {
            addElement(textElement)
            editingTextId = element.id
            return
        }

        // 1.5: 点击选区外 (Line 918-925)
        if localSelectedArea != nil && !contains(clickLocation) {
            updateSelection(nil, nil)
            return
        }

        return
    }

    // ✅ 分支 2: 拖拽结束 - 编辑模式 (Line 935-949)
    if isEditing {
        if isDraggingElement {
            isDraggingElement = false
            return
        }
        if currentElement != nil {
            addElement(currentElement)
        }
        return
    }

    // ✅ 分支 3: 拖拽结束 - 选区调整 (Line 952-958)
    if isMovingSelection || activeHandle != nil {
        isMovingSelection = false
        activeHandle = nil
        return
    }

    // ✅ 分支 4: 拖拽结束 - 新选区确认 (Line 960-974)
    if dragStartPoint != nil {
        let rect = CGRect(...)
        if rect.width > 5 && rect.height > 5 {
            updateSelection(rect, screen)
        }
        dragStartPoint = nil
    }
}
```

### 3.3 V2ScreenshotView 状态判断分支

```swift
// ✅ 分支 1: 是否是主屏幕
var isCurrentlyPrimary: Bool {
    primaryScreenManager.isPrimary(screen)
}

// ✅ 分支 2: 屏幕是否释放
var isReleased: Bool {
    guard hasAnySelection else { return false }
    return !isCurrentlyPrimary
}

// ✅ 分支 3: 局部选区
var localSelectedArea: CGRect? {
    primaryScreenManager.selectionScreen == screen
        ? primaryScreenManager.selectedArea
        : nil
}

// ✅ 分支 4: 是否有选区
var hasAnySelection: Bool {
    primaryScreenManager.selectedArea != nil
}

// ✅ 分支 5: 当前屏幕上的窗口
var windowsOnScreen: [WindowInfo] {
    allWindows.filter { window in
        // 1. 与屏幕相交
        guard window.bounds.intersects(screenBounds) else { return false }
        // 2. 排除过小的窗口
        let rect = getLocalRect(for: window)
        if rect.width < 100 || rect.height < 100 { return false }
        // 3. 排除系统背景
        return !isSystemBackground(window)
    }
}
```

---

## 4. 变量监听

### 4.1 V2PrimaryScreenStateManager (@Published 变量)

| 变量名 | 类型 | 初始值 | 用途 | 使用位置 |
|--------|------|--------|------|----------|
| `primaryScreen` | NSScreen? | nil | 当前主屏幕 | V2ScreenshotView.isCurrentlyPrimary |
| `selectedArea` | CGRect? | nil | 全局选区 | V2ScreenshotView.localSelectedArea |
| `selectionScreen` | NSScreen? | nil | 选区所在屏幕 | V2ScreenshotView.localSelectedArea |
| `isEditing` | Bool | false | 编辑模式 | buildAnnotationLayer, 工具栏显示 |
| `isLongScreenshotMode` | Bool | false | 长图模式 | V2MaskOverlayView 隐藏 |
| `isCapturing` | Bool | false | 采集中 | 隐藏 UI |
| `longScreenshotPreviews` | [NSImage] | [] | 长图预览列表 | V2LongScreenshotPreview |
| `elements` | [DrawingElement] | [] | 标注元素 | V2AnnotationCanvas |
| `currentElement` | DrawingElement? | nil | 当前绘制的元素 | DragGesture.onChanged |
| `selectedTool` | AnnotationTool | .cursor | 选中的工具 | 工具栏高亮, 光标显示 |
| `selectedColor` | Color | .red | 选中的颜色 | 创建元素时使用 |
| `lineWidth` | CGFloat | 4.0 | 线条宽度 | 创建元素时使用 |
| `fontSize` | CGFloat | 20.0 | 字体大小 | 创建元素时使用 |
| `stepCounter` | Int | 1 | 步骤计数 | steps 工具 |
| `selectedElementId` | UUID? | nil | 选中的元素 ID | 元素高亮显示 |
| `editingTextId` | UUID? | nil | 正在编辑的文本 | V2AnnotationTextEditorView |
| `magnifierPreviewPosition` | CGPoint? | nil | 放大镜预览位置 | AnnotationMagnifierPreview |
| `magnifierFollowMouse` | Bool | true | 放大镜跟随鼠标 | AnnotationMagnifierPreview |
| `isMouseOverUI` | Bool | false | 鼠标悬停在 UI 上 | DragGesture 拦截 |
| `drawingPaths` | [DrawingPath] | [] | 旧版绘图路径 | 兼容保留 |
| `globalHoveredRect` | CGRect? | nil | 全局悬停矩形 | buildDragOverlay |
| `globalHoveredLabel` | String? | nil | 全局悬停标签 | YellowWireframe 显示 |
| `hoverScreen` | NSScreen? | nil | 悬停所在屏幕 | 确保唯一显示 |

### 4.2 V2ScreenshotView (@State 变量)

| 变量名 | 类型 | 初始值 | 用途 | 更新时机 |
|--------|------|--------|------|----------|
| `dragStartPoint` | CGPoint? | nil | 拖拽起点 | DragGesture.onChanged (Phase 0) |
| `dragCurrentPoint` | CGPoint? | nil | 拖拽终点 | DragGesture.onChanged (Phase 0) |
| `isDraggingElement` | Bool | false | 是否拖拽元素中 | DragGesture.onChanged (Phase 2) |
| `initialElementPoints` | [CGPoint] | [] | 元素初始位置 | 元素拖拽开始 |
| `initialMagnifierOffset` | CGSize | .zero | 放大镜初始偏移 | 放大镜拖拽开始 |
| `magnifierDragTarget` | MagnifierDragTarget? | nil | 放大镜拖拽目标 | 放大镜拖拽开始 |
| `initialSelectionForMove` | CGRect? | nil | 选区初始位置 | 选区移动/调整开始 |
| `isMovingSelection` | Bool | false | 是否移动选区中 | 选区移动开始 |
| `activeHandle` | SelectionHandle? | nil | 激活的手柄 | 选区调整开始 |
| `currentCursor` | NSCursor | .arrow | 当前光标 | updateCursor |
| `logEntries` | [String] | [] | 日志条目 | addLog |
| `currentLayerName` | String | "None" | 当前层级名 | onContinuousHover |
| `currentLayerLevel` | Int | 0 | 当前层级值 | onContinuousHover |
| `mouseLocation` | CGPoint | .zero | 鼠标位置 | onContinuousHover |
| `hasMouseMoved` | Bool | false | 鼠标是否移动过 | onContinuousHover (首次) |

### 4.3 .onChange 监听器

| 监听位置 | 监听变量 | 触发操作 | 代码行 |
|----------|----------|----------|--------|
| V2ScreenshotView.body | `isReleased` | panel.ignoresMouseEvents = released | 468-480 |
| V2ScreenshotView.body | `isLongScreenshotMode` | 调整 window level | 297-312 |
| V2ScreenshotView.body | `isLongScreenshotMode` | allowsHitTesting | 296 |

---

## 5. 数据流向

### 5.1 全局状态流向

```
V2PrimaryScreenStateManager (单例)
│
├── primaryScreen
│   └── 被使用: V2ScreenshotView.isCurrentlyPrimary (所有屏幕)
│
├── selectedArea + selectionScreen
│   └── 被使用: V2ScreenshotView.localSelectedArea (只有对应屏幕才有值)
│
├── globalHoveredRect + globalHoveredLabel + hoverScreen
│   └── 被使用: V2ScreenshotView.snappedWireframeRect (只有对应屏幕才显示)
│
├── isEditing
│   ├── 被使用: buildAnnotationLayer (控制是否显示标注层)
│   ├── 被使用: V2MaskOverlayView (控制是否隐藏)
│   └── 被使用: V2FloatingToolbar (控制按钮状态)
│
├── isLongScreenshotMode
│   ├── 被使用: V2MaskOverlayView (隐藏蒙层)
│   ├── 被使用: buildAnnotationLayer (隐藏标注)
│   └── 被使用: V2LongScreenshotPreview (显示预览)
│
├── isCapturing
│   ├── 被使用: V2DebugOverlayView (隐藏调试信息)
│   ├── 被使用: V2FloatingToolbar (隐藏工具栏)
│   └── 被使用: MagnifierView (隐藏放大镜)
│
└── elements + currentElement + selectedElementId + editingTextId
    ├── 被使用: V2AnnotationCanvas (渲染所有元素)
    ├── 被使用: AnnotationMagnifierPreview (显示放大镜)
    └── 被使用: V2AnnotationTextEditorView (编辑文本)
```

### 5.2 屏幕坐标转换

```
AppKit 全局坐标 (CGWindowListCopyWindowInfo)
    │
    ↓ V2CoordinateMapper.localToScreen(point, on: screen)
    │   └── 将 SwiftUI 局部坐标 → AppKit 全局坐标
    │
    ↓ 用于: 查找窗口 (window.bounds.contains(point))
    │
    ↓ V2CoordinateMapper.screenToLocal(rect, on: screen)
    │   └── 将 AppKit 全局坐标 → SwiftUI 局部坐标
    │
    ↓ 用于: 显示线框 (YellowWireframe)
    │
SwiftUI 局部坐标 (CGPoint, CGRect)
```

### 5.3 鼠标事件流向

```
鼠标移动
    ↓
NSPanel (acceptsMouseMovedEvents = true)
    ↓
V2ScreenshotHostingView (AppKit → SwiftUI 桥接)
    ↓
V2ScreenshotView.buildInteractionLayer()
    ↓
Color.white.opacity(0.0001).onContinuousHover
    ↓
updateHoverState(at: location)
    ├── localToScreen → 全局坐标
    ├── 查找窗口
    └── screenToLocal → 局部坐标
    ↓
primaryScreenManager.updateHover(rect, label, screen)
    ↓
@Published globalHoveredRect 更新
    ↓
V2ScreenshotView.snappedWireframeRect 计算
    ↓
YellowWireframe 显示
```

---

## 6. 删除检查清单

### 6.1 可以删除的功能（对应流程/层级）

| 功能 | 对应流程 | 对应层级 | 删除原因 |
|------|----------|----------|----------|
| 长图模式 | 1.5 | Layer 2, 4.5, 5.1 | 用户需求不明确，简化功能 |
| 标注系统 | 1.5 | Layer 4.5 | 过于复杂，保留截图核心功能 |
| 调试信息层 | - | Layer 5 | 仅用于开发，不影响用户功能 |
| 层级标签 | - | Layer 5.3 | 调试用，可删除 |
| 放大镜预览 | 1.2, 1.5 | Layer 0, 4.5 | 非核心功能，简化交互 |
| 文本编辑 | 1.5 | Layer 4.5 | 标注系统的一部分 |
| 步骤标注 | 1.5 | Layer 4.5 | 标注系统的一部分 |
| 马赛克 | 1.5 | Layer 4.5 | 标注系统的一部分 |
| 聚光灯 | 1.5 | Layer 4.5 | 标注系统的一部分 |

### 6.2 保留的核心功能

| 功能 | 对应流程 | 对应层级 | 保留原因 |
|------|----------|----------|----------|
| 多屏支持 | 1.4 | - | 核心功能，必须保留 |
| 窗口选择 | 1.2 | Layer 3, 4 | 核心功能，必须保留 |
| 选区创建 | 1.3 | Layer 3, 4 | 核心功能，必须保留 |
| 选区调整 | 1.3 | Layer 3, 4 | 核心功能，必须保留 |
| 保存剪贴板 | 1.6 | - | 核心功能，必须保留 |
| 悬停预览 | 1.2 | Layer 4 | 核心功能，必须保留 |

### 6.3 简化后的视图层级

```
V2ScreenshotView (ZStack)
│
├── Layer 1: 背景层 (Image)
├── Layer 2: 蒙层层 (V2MaskOverlayView)
├── Layer 3: 交互层 (Color + DragGesture)
└── Layer 4: 框选层 (YellowWireframe)
```

### 6.4 简化后的状态管理

```
V2PrimaryScreenStateManager
│
├── primaryScreen: NSScreen?
├── selectedArea: CGRect?
├── selectionScreen: NSScreen?
├── globalHoveredRect: CGRect?
├── globalHoveredLabel: String?
└── hoverScreen: NSScreen?
```

---

## 附录：关键文件位置

| 文件 | 位置 | 核心职责 |
|------|------|----------|
| V2ScreenshotController | `Controllers/V2ScreenshotController.swift:13` | 入口，创建窗口 |
| V2ScreenshotView | `Views/V2ScreenshotView.swift:268` | 主视图，ZStack 层级 |
| V2PrimaryScreenStateManager | `Models/V2PrimaryScreenStateManager.swift:13` | 全局状态管理 |
| V2MaskOverlayView | `Views/Overlays/MaskOverlayView.swift` | 蒙层（挖孔效果） |
| YellowWireframe | `Views/Overlays/YellowWireframe.swift` | 黄色线框 |
| V2AnnotationCanvas | `Views/V2AnnotationCanvas.swift` | 标注画布 |
| V2FloatingToolbar | `Views/Toolbar/V2FloatingToolbar.swift` | 工具栏 |
| V2CoordinateMapper | `Services/V2CoordinateMapper.swift` | 坐标转换 |
| V2ScreenCaptureService | `Services/V2ScreenCaptureService.swift` | 截屏服务 |

---

## 总结

本文档记录了截图V2的完整代码骨架，包括：
- 6 个主要流程的详细步骤
- ZStack 的 5 层层级结构
- 3 个主要分支逻辑（DragGesture）
- 24 个 @Published 变量和 14 个 @State 变量
- 完整的数据流向（全局状态、坐标转换、鼠标事件）
- 删除检查清单（标注系统、长图模式等）

**重构建议**：
1. 先删除 Layer 4.5（标注层）和相关状态
2. 再删除 Layer 5.1（长图预览）和相关状态
3. 保留 Layer 1-4（核心截图功能）
4. 简化 V2PrimaryScreenStateManager，只保留 6 个核心变量
5. 简化 DragGesture 分支，只保留阶段 0 和 1
