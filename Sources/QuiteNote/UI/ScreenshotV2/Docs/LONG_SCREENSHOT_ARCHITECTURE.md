# 长截图功能架构文档

> **目的**: 记录长截图功能的完整架构设计、实现细节和技术决策
> **创建日期**: 2026-01-02
> **版本**: 1.0

---

## 目录

1. [功能概述](#功能概述)
2. [架构设计](#架构设计)
3. [组件结构](#组件结构)
4. [状态管理](#状态管理)
5. [交互流程](#交互流程)
6. [关键技术](#关键技术)
7. [技术决策](#技术决策)
8. [代码位置索引](#代码位置索引)

---

## 功能概述

### 功能定义

长截图功能允许用户通过滚动操作自动采集多张截图，并将其垂直拼接为一张长图。

### 核心特性

- ✅ **自动滚动检测**: 监听全局滚动事件，无需手动点击
- ✅ **智能阈值触发**: 每滚动 500px 自动截取一帧
- ✅ **实时预览**: 侧边栏实时显示已采集的帧数和缩略图
- ✅ **自动拼接**: 采集结束自动垂直拼接所有帧
- ✅ **事件穿透**: 选区内滚动事件穿透到底层应用

### 使用场景

1. 浏览器长网页截图
2. 长文档截屏
3. 聊天记录截屏
4. 任何需要滚动才能完整显示的内容

---

## 架构设计

### 设计原则

```
┌─────────────────────────────────────────────────────┐
│  设计原则                                            │
├─────────────────────────────────────────────────────┤
│  1. 最小侵入: 不修改现有截图逻辑                    │
│  2. 独立模块: 所有长截图代码在独立目录              │
│  3. 职责分离: 每个组件只负责一种功能                │
│  4. 状态驱动: 通过状态管理器协调所有组件            │
└─────────────────────────────────────────────────────┘
```

### 整体架构图

```
┌──────────────────────────────────────────────────────┐
│                   V2ScreenshotView                   │
│  (主视图 - 根据模式显示不同的工具栏)                  │
└───────────────┬──────────────────────────────────────┘
                │
       ┌────────┴────────┐
        │                 │
┌───────▼────────┐  ┌────▼──────────────┐
│  普通截图模式    │  │  长截图模式        │
│                │  │                   │
│ V2FloatingToolbar│  │ V2LongScreenshotToolbar│
└────────────────┘  └───────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
┌───────▼────────┐ ┌─────▼──────────┐ ┌──▼────────────┐
│ 滚动检测服务    │ │ 图片拼接服务     │ │ 预览面板      │
└────────────────┘ └──────────────────┘ └───────────────┘
        │                  │
        └──────────┬───────┘
                   ▼
        ┌──────────────────────┐
        │ 状态管理器            │
        │ V2PrimaryScreenStateManager │
        └──────────────────────┘
```

---

## 组件结构

### 目录组织

```
Sources/QuiteNote/UI/ScreenshotV2/
├── LongScreenshot/
│   ├── Controllers/
│   │   └── LongScreenshotFlowController.swift  ✨ 流程控制器
│   ├── Services/
│   │   ├── ScrollDetectionService.swift        ✨ 滚动检测
│   │   └── ImageStitchingService.swift         ✨ 图片拼接
│   ├── Models/
│   │   ├── CaptureConfig.swift                 ⚙️ 配置模型
│   │   └── StitchResult.swift                  📦 结果模型
│   └── Views/
│       ├── LongScreenshotControlPanel.swift    🎛️ 控制面板
│       └── LongScreenshotPreviewPanel.swift   🖼️ 预览面板
├── Views/Toolbar/
│   ├── V2FloatingToolbar.swift                 📦 普通截图工具栏
│   ├── V2AnnotationToolbar.swift               ✏️ 标注工具栏
│   └── V2LongScreenshotToolbar.swift           📜 长截图工具栏 ✨
├── Models/
│   └── V2PrimaryScreenStateManager.swift       🎛️ 状态管理器
└── Controllers/
    └── V2ScreenshotController.swift            🪟 截图控制器
```

### 组件职责

#### 1. 流程控制器 (LongScreenshotFlowController)

**职责**: 协调整个长截图流程的生命周期

**核心方法**:
- `startCapture()`: 开始采集流程
- `stopCapture()`: 停止采集并拼接图片
- `cancelCapture()`: 取消采集，丢弃所有帧

**代码位置**: `LongScreenshot/Controllers/LongScreenshotFlowController.swift`

```swift
// 使用示例
await LongScreenshotFlowController.shared.startCapture(
    selection: selectionRect,
    screen: screen,
    config: .default
) { result in
    switch result {
    case .success(let image):
        // 保存或显示长图
    case .failure(let error):
        // 处理错误
    }
}
```

#### 2. 滚动检测服务 (ScrollDetectionService)

**职责**: 监听全局滚动事件，累计滚动距离，触发截图

**核心特性**:
- 使用 `NSEvent.addGlobalMonitorForEvents` 监听所有应用的滚动
- 累计滚动距离，达到阈值触发回调
- 只在 `isCapturing = true` 时响应

**代码位置**: `LongScreenshot/Services/ScrollDetectionService.swift`

**关键参数**:
- `threshold`: 滚动阈值（默认 500px）
- `selection`: 选区范围
- `screen`: 目标屏幕

#### 3. 图片拼接服务 (ImageStitchingService)

**职责**: 将多张图片垂直拼接为长图

**实现方式**:
- Actor 隔离，确保线程安全
- 计算总画布尺寸
- 逐张绘制到最终画布

**代码位置**: `LongScreenshot/Services/ImageStitchingService.swift`

#### 4. 长截图工具栏 (V2LongScreenshotToolbar)

**职责**: 长截图模式的专用工具栏

**按钮状态**:
- 未采集: `[开始滚动🔴] [取消⚪️]`
- 采集中: `[暂停🟠] [完成🟢] [取消⚪️]`

**代码位置**: `Views/Toolbar/V2LongScreenshotToolbar.swift`

#### 5. 预览面板 (LongScreenshotPreviewPanel)

**职责**: 实时显示已采集的帧数和缩略图

**定位策略**:
1. 优先选区右侧
2. 右侧不足 → 选区左侧
3. 左侧不足 → 选区内部右侧
4. 选区太窄 → 选区内部左侧

**代码位置**: `LongScreenshot/Views/LongScreenshotPreviewPanel.swift`

#### 6. 控制面板 (LongScreenshotControlPanel)

**职责**: 控制采集流程（停止/完成/取消）

**注意**: 当前已简化，主要控制移至工具栏

---

## 状态管理

### 状态枚举

```swift
// V2PrimaryScreenStateManager.swift

@Published var isLongScreenshotMode: Bool = false  // 是否进入长图模式
@Published var isCapturing: Bool = false           // 是否正在采集
@Published var longScreenshotPreviews: [NSImage] = [] // 已采集的帧
```

### 状态转换图

```
[普通截图模式]
       │
       │ 用户点击"长图"按钮
       ▼
[长截图模式] (isLongScreenshotMode = true)
       │
       │ 用户点击"开始滚动"
       ▼
[采集中状态] (isCapturing = true)
       │
       │ 滚动距离 ≥ 500px
       ▼
[自动截图] → 更新预览
       │
       │ 用户点击"暂停"/"完成"/ESC
       ▼
[拼接完成] → 显示长图
       │
       ▼
[返回普通模式]
```

### 状态切换方法

```swift
// 切换到长截图模式
stateManager.setLongScreenshotMode(true)

// 开始采集
await LongScreenshotFlowController.shared.startCapture(...)

// 停止采集
await LongScreenshotFlowController.shared.stopCapture()

// 取消采集
await LongScreenshotFlowController.shared.cancelCapture()

// 重置所有状态
stateManager.reset()
```

---

## 交互流程

### 用户操作流程

```
步骤 1: 用户进入截图模式
    ↓
步骤 2: 框选一个区域
    ↓
步骤 3: 点击"长图"按钮（紫色）
    ↓
步骤 4: 工具栏切换为长图模式
    ↓
步骤 5: 点击"开始滚动"（红色）
    ↓
步骤 6: 预览面板出现（右侧）
    ↓
步骤 7: 在选区内滚动其他应用
    ↓
步骤 8: 每滚动 500px 自动截取一帧
    ↓
步骤 9: 预览面板实时更新帧数
    ↓
步骤 10: 点击"完成"（绿色）
    ↓
步骤 11: 自动拼接所有帧为长图
    ↓
步骤 12: 保存/显示长图
```

### 按钮交互细节

#### "长图"按钮
- **位置**: 标注工具栏右侧
- **颜色**: 紫色 (Color.purple.opacity(0.8))
- **图标**: scroll
- **行为**: 点击后切换到长截图模式

#### "开始滚动"按钮
- **位置**: 长图工具栏中间
- **颜色**: 红色
- **图标**: record.circle
- **行为**:
  1. 启动滚动监听
  2. 显示预览面板
  3. 截取第一帧
  4. 按钮变为"暂停"

#### "暂停"按钮
- **颜色**: 橙色
- **图标**: pause.circle.fill
- **行为**: 停止采集，开始拼接

#### "完成"按钮
- **颜色**: 绿色
- **图标**: checkmark.circle.fill
- **行为**: 停止采集，拼接长图

#### "取消"按钮
- **颜色**: 白色
- **图标**: xmark.circle
- **行为**: 取消采集，丢弃所有帧，返回普通模式

---

## 关键技术

### 1. 事件穿透机制

**问题**: 长截图模式下，用户需要在选区内滚动其他应用（如浏览器）

**解决方案**: 通过 `hitTest` 方法临时忽略鼠标事件

**实现位置**: `V2ScreenshotHostingView.swift`

**工作原理**:
```swift
override func hitTest(_ point: NSPoint) -> NSView? {
    let hitView = super.hitTest(point)
    let stateManager = V2PrimaryScreenStateManager.shared

    if stateManager.isLongScreenshotMode {
        // 转换坐标系：AppKit (左下角) → SwiftUI (左上角)
        let localSwiftUIPoint = CGPoint(x: point.x, y: self.bounds.height - point.y)

        // 判断是否在选区内
        if let selection = stateManager.selectedArea,
           selection.contains(localSwiftUIPoint) {

            // 临时忽略鼠标事件 30ms
            DispatchQueue.main.async {
                self.window?.ignoresMouseEvents = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    self.window?.ignoresMouseEvents = false
                }
            }

            return nil // 穿透到底层应用
        }
    }

    return hitView
}
```

**为什么是 30ms?**
- 足够让当前的鼠标/滚动事件完全穿透
- 不会影响后续的事件处理
- 避免用户感知到延迟

### 2. 窗口级别切换

**普通模式**:
```swift
panel.level = .screenSaver + 1  // 最高级别，抢占焦点
```

**长截图模式**:
```swift
panel.level = .normal  // 普通级别，不抢占焦点
```

**代码位置**: `V2ScreenshotView.swift` (Lines 297-312)

### 3. 全局滚动监听

**为什么使用 `addGlobalMonitorForEvents`?**

- `addLocalMonitorForEvents`: 只能监听本应用的事件
- `addGlobalMonitorForEvents`: 可以监听所有应用的事件 ✅

**关键原因**:
- 用户在选区内滚动的是**其他应用**（如 Safari、Pages）
- 需要监听**系统级**的滚动事件
- `addGlobalMonitorForEvents` 可以监听所有应用的事件

**代码位置**: `ScrollDetectionService.swift`

```swift
scrollEventHandler = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { event in
    guard V2PrimaryScreenStateManager.shared.isCapturing else { return }

    let deltaY = event.scrollingDeltaY
    guard deltaY != 0 else { return }

    self.accumulatedDistance += abs(deltaY)

    if self.accumulatedDistance >= self.threshold {
        self.accumulatedDistance = 0
        onThresholdReached() // 触发截图
    }
}
```

### 4. 智能窗口定位

**预览面板定位算法**:

```swift
// 1. 尝试放在选区右侧
var panelX: CGFloat = selection.maxX + spacing

if panelX + panelWidth > screen.frame.width {
    // 2. 右侧空间不足，尝试左侧
    panelX = selection.minX - panelWidth - spacing

    if panelX < 0 {
        // 3. 左侧也不足，放在选区内部右侧
        panelX = selection.maxX - panelWidth - 10

        if panelX < selection.minX {
            // 4. 选区太窄，放在选区内部左侧
            panelX = selection.minX + 10
        }
    }
}
```

**代码位置**: `LongScreenshotPreviewPanel.swift` (Lines 13-43)

---

## 技术决策

### 决策 1: 为什么使用全局滚动监听?

**背景**: 需要监听其他应用（如浏览器）的滚动事件

**选项对比**:

| 方案 | 优点 | 缺点 | 选择 |
|------|------|------|------|
| addLocalMonitorForEvents | 简单 | 只能监听本应用 | ❌ |
| addGlobalMonitorForEvents | 可监听所有应用 | 需要系统权限 | ✅ |

**结论**: 使用 `addGlobalMonitorForEvents`

### 决策 2: 为什么窗口级别是 .normal?

**背景**: 长图模式下不抢占底层应用的焦点

**选项对比**:

| 级别 | 焦点行为 | 适用场景 | 选择 |
|------|---------|---------|------|
| screenSaver + 1 | 抢占焦点 | 普通截图 | ❌ |
| .normal | 不抢占焦点 | 长截图 | ✅ |

**结论**: 长图模式使用 `.normal`

### 决策 3: 为什么阈值是 500px?

**权衡考虑**:

- 太小 (< 200px): 截图过于频繁，性能问题
- 太大 (> 1000px): 可能漏采内容
- 500px: 约 2-3 次滚轮滚动，频率适中 ✅

**结论**: 默认阈值设为 500px，可配置

### 决策 4: 为什么使用独立的工具栏组件?

**之前的问题**:
- `V2FloatingToolbar` 混合了两种模式
- 职责不清晰，难以维护
- 添加新模式需要修改现有文件

**现在的优势**:
- 每个模式有独立的工具栏
- 职责分离，易于维护
- 添加新模式只需创建新组件

**结论**: 使用独立的 `V2LongScreenshotToolbar`

---

## 代码位置索引

### 核心组件

| 组件 | 文件路径 | 行号参考 |
|------|---------|---------|
| 流程控制器 | `LongScreenshot/Controllers/LongScreenshotFlowController.swift` | 全文 |
| 滚动检测 | `LongScreenshot/Services/ScrollDetectionService.swift` | 全文 |
| 图片拼接 | `LongScreenshot/Services/ImageStitchingService.swift` | 全文 |
| 配置模型 | `LongScreenshot/Models/CaptureConfig.swift` | 全文 |
| 结果模型 | `LongScreenshot/Models/StitchResult.swift` | 全文 |

### UI 组件

| 组件 | 文件路径 | 行号参考 |
|------|---------|---------|
| 长截图工具栏 | `Views/Toolbar/V2LongScreenshotToolbar.swift` | 全文 ✨ |
| 普通截图工具栏 | `Views/Toolbar/V2FloatingToolbar.swift` | 全文 |
| 标注工具栏 | `Views/Toolbar/V2AnnotationToolbar.swift` | 全文 |
| 预览面板 | `LongScreenshot/Views/LongScreenshotPreviewPanel.swift` | 全文 |
| 控制面板 | `LongScreenshot/Views/LongScreenshotControlPanel.swift` | 全文 |

### 状态管理

| 组件 | 文件路径 | 关键行号 |
|------|---------|---------|
| 状态管理器 | `Models/V2PrimaryScreenStateManager.swift` | 26, 145-157 |
| 主视图 | `Views/V2ScreenshotView.swift` | 386-397 (工具栏切换) |
| 截图控制器 | `Controllers/V2ScreenshotController.swift` | 108-123 (面板显示) |

### 事件穿透

| 组件 | 文件路径 | 关键行号 |
|------|---------|---------|
| hitTest 实现 | `Views/Panels/V2ScreenshotHostingView.swift` | 6-57 |
| 窗口级别切换 | `Views/V2ScreenshotView.swift` | 297-312 |

---

## 常见问题排查

### 问题 1: 滚动事件无法穿透

**检查点**:
1. `isLongScreenshotMode` 是否为 `true`?
2. 是否在选区内滚动?
3. `hitTest` 是否返回 `nil`?
4. `ignoresMouseEvents` 是否正确设置?

**调试代码**:
```swift
print("HitTest - Inside: \(isInside), Hit: \(hitView)")
```

### 问题 2: 滚动监听不工作

**检查点**:
1. `isCapturing` 是否为 `true`?
2. 是否使用 `addGlobalMonitorForEvents`?
3. 阈值是否设置合理?

**调试代码**:
```swift
logger.debug("滚动距离: \(deltaY), 累计: \(accumulatedDistance)")
```

### 问题 3: 面板位置错乱

**检查点**:
1. 屏幕边界是否正确计算?
2. 是否考虑了多显示器场景?
3. 面板尺寸是否超出屏幕?

**调试代码**:
```swift
print("Screen: \(screen.frame)")
print("Selection: \(selection)")
print("Panel: \(contentRect)")
```

### 问题 4: 按钮不显示

**检查点**:
1. 是否在长截图模式?
2. `isCapturing` 状态是否正确?
3. 工具栏是否被隐藏?

**调试代码**:
```swift
print("isLongScreenshotMode: \(stateManager.isLongScreenshotMode)")
print("isCapturing: \(stateManager.isCapturing)")
```

---

## 未来扩展

### 可能的改进

1. **可配置阈值**: 让用户自定义滚动阈值
2. **手动添加帧**: 添加"手动截取"按钮
3. **帧删除**: 在预览面板中删除不满意的单帧
4. **水平长图**: 支持横向滚动的长图
5. **GIF 导出**: 将采集的帧导出为 GIF

### 添加新模式

如果需要添加其他模式（如录屏、GIF），只需：

1. 创建新的工具栏组件：
   ```swift
   V2ScreenRecordingToolbar.swift
   VGIFRecordingToolbar.swift
   ```

2. 在 `V2PrimaryScreenStateManager.swift` 中添加状态：
   ```swift
   @Published var isScreenRecordingMode: Bool = false
   @Published var isGIFRecordingMode: Bool = false
   ```

3. 在 `V2ScreenshotView.swift` 中添加分支：
   ```swift
   if primaryScreenManager.isScreenRecordingMode {
       V2ScreenRecordingToolbar(selection: selection, screen: screen)
   } else if primaryScreenManager.isLongScreenshotMode {
       V2LongScreenshotToolbar(selection: selection, screen: screen)
   } else {
       V2FloatingToolbar(selection: selection, screen: screen)
   }
   ```

---

## 总结

### 核心技术点

1. **事件穿透**: `hitTest` + `ignoresMouseEvents` (30ms)
2. **窗口定位**: 智能算法，优先右侧，其次左侧，最后内部
3. **滚动监听**: `addGlobalMonitorForEvents` (系统级)
4. **状态管理**: 通过 `V2PrimaryScreenStateManager` 协调
5. **窗口级别**: 长图模式使用 `.normal`，普通模式使用 `screenSaver + 1`

### 架构优势

✅ **最小侵入**: 不需要重构现有代码
✅ **独立模块**: 长截图逻辑集中在独立目录
✅ **易维护**: 清晰的职责划分
✅ **可扩展**: 预留了配置项和扩展点

### 技术亮点

🌟 **全局滚动监听**: 监听所有应用的滚动事件
🌟 **事件穿透机制**: 临时忽略鼠标事件实现穿透
🌟 **智能窗口定位**: 4层回退算法适应不同场景
🌟 **状态驱动架构**: 通过状态管理器协调所有组件
🌟 **职责分离设计**: 每个组件只负责一种功能

---

**文档版本**: 1.0
**最后更新**: 2026-01-02
**维护者**: Claude Code
