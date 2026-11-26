# Quite Note 截图功能 (V2) 架构文档

本文档详细描述了 Quite Note 截图功能（V2/Debug 模式）的设计架构、文件层级及核心逻辑，旨在为后续开发或技术参考提供指导。

## 1. 核心设计思想

截图功能采用**多层级叠加 (Layered Overlay)** 和**全局状态管理 (Global State Management)** 的架构：
- **Layered Overlay**: 每个屏幕被划分为 5 个逻辑层，独立处理背景、蒙层、交互、选区和调试信息。
- **Global State**: 使用单例 `V2PrimaryScreenStateManager` 同步多屏幕间的鼠标位置、悬停窗口和选区状态，确保跨屏幕操作的连贯性。

---

## 2. 文件层级结构

截图功能的核心代码位于 `Sources/QuiteNote/UI/ScreenshotV2/` 目录下：

### 核心视图 (Views)
- **[V2ScreenshotDebugView.swift](file:///Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/ScreenshotV2/Views/V2ScreenshotDebugView.swift)**: 
  - **核心入口**：截图交互的主视图。
  - **职责**：处理 5 层渲染逻辑、放大镜、色值获取、鼠标光标切换、吸附逻辑。
  - **内部组件**：`MagnifierView` (放大镜), `YellowWireframe` (黄色选区框), `LayerLabel` (层级标签)。

### 控制器 (Controllers)
- **[V2ScreenshotDebugController.swift](file:///Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/ScreenshotV2/Views/V2ScreenshotDebugView.swift)** (位于 View 文件底部):
  - **职责**：管理 `NSPanel` 窗口的生命周期（创建、显示、关闭），获取屏幕原始截图，初始化视图。
- **[V2CaptureController.swift](file:///Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/ScreenshotV2/Controllers/V2CaptureController.swift)**:
  - **职责**：协调正式截图流程与调试流程的切换和清理。

### 模型与状态 (Models)
- **[V2PrimaryScreenStateManager.swift](file:///Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/ScreenshotV2/Models/V2PrimaryScreenStateManager.swift)**:
  - **职责**：全局单例，存储 `primaryScreen` (当前活动屏幕), `selectedArea` (选区矩形), `globalHoveredRect` (当前吸附的窗口矩形) 等。

### 服务 (Services)
- **[V2CoordinateMapper.swift](file:///Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/ScreenshotV2/Services/V2CoordinateMapper.swift)**:
  - **职责**：处理逻辑坐标 (SwiftUI) 与全局屏幕坐标 (AppKit) 之间的转换。
- **[V2ScreenCaptureService.swift](file:///Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/ScreenshotV2/Services/V2ScreenCaptureService.swift)**:
  - **职责**：底层屏幕采集、窗口列表获取 (`WindowInfoService`)。

---

## 3. 五层渲染架构 (Layered Architecture)

每个屏幕视图 (`V2ScreenshotDebugView`) 内部由以下 5 个逻辑层级组成，通过 `ZStack` 堆叠：

```text
┌─────────────────────────────────────────────────────────────────┐
│ [Layer 5] Debug & Info Layer (最顶层)                            │
│ ├─ MagnifierView (放大镜: 仅 Phase 0/0.5, 3x, 十字准星)          │
│ ├─ V2FloatingToolbar (浮动工具栏: 编辑/撤销/完成)                 │
│ └─ DebugPanel & Logs (调试信息)                                 │
├─────────────────────────────────────────────────────────────────┤
│ [Layer 4.5] Annotation Layer (标注层: 仅编辑模式)                 │
│ └─ Canvas (渲染绘图路径 drawingPaths & currentPath)             │
├─────────────────────────────────────────────────────────────────┤
│ [Layer 4] Drag/Selection Layer (选区层)                          │
│ └─ YellowWireframe (8个手柄: 仅非编辑模式, 虚线边框)              │
├─────────────────────────────────────────────────────────────────┤
│ [Layer 3] Window Interaction (交互层)                            │
│ ├─ MouseMoved: 更新主屏幕/鼠标位置/层级标签                       │
│ └─ TapGesture: 窗口吸附/清除选区/点击工具栏切换编辑状态            │
├─────────────────────────────────────────────────────────────────┤
│ [Layer 2] Mask Overlay (蒙层层)                                  │
│ └─ Color.black (0.3~0.6) + Mask (挖孔逻辑: 跟随鼠标或选区)        │
├─────────────────────────────────────────────────────────────────┤
│ [Layer 1] Background Layer (最底层)                              │
│ └─ NSImage (原始全屏截图: 纯净, 供裁剪使用)                      │
└─────────────────────────────────────────────────────────────────┘
```

### 层级职责详细说明：

1.  **Layer 1: Background Layer (背景层)**
    - **职责**：显示进入截图模式瞬间采集的 `snapshot`。
    - **特点**：它是纯净的，不包含任何 UI。保存截图时直接从这一层裁剪。
    - **文件**：[V2ScreenshotDebugView.swift](file:///Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/ScreenshotV2/Views/V2ScreenshotDebugView.swift) (Line 258)

2.  **Layer 2: Mask Overlay (蒙层层)**
    - **职责**：营造“暗场”效果，并通过 `blendMode` 实现高亮的“挖孔”。
    - **特点**：亮度会根据是否是活动屏幕自动切换（0.2 vs 0.5）。
    - **文件**：[V2ScreenshotDebugView.swift](file:///Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/ScreenshotV2/Views/V2ScreenshotDebugView.swift) (Line 733: `buildMaskOverlay`)

3.  **Layer 3: Window Interaction (交互层)**
    - **职责**：捕获所有鼠标事件的核心层。
    - **特点**：处理 `onContinuousHover`（更新坐标/层级）和 `onTapGesture`（吸附/清理）。
    - **文件**：[V2ScreenshotDebugView.swift](file:///Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/ScreenshotV2/Views/V2ScreenshotDebugView.swift) (Line 526: `buildInteractionLayer`)

4.  **Layer 4: Drag/Selection Layer (选区层)**
    - **职责**：渲染黄色选区框和 8 个缩放手柄。
    - **特点**：**编辑模式下 8 个点会自动消失**，且禁用拖拽移动，防止误触。
    - **文件**：[V2ScreenshotDebugView.swift](file:///Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/ScreenshotV2/Views/V2ScreenshotDebugView.swift) (Line 826: `buildDragOverlay`)

4.5 **Layer 4.5: Annotation Layer (标注层)**
    - **职责**：在选区内绘制标注内容。
    - **特点**：使用 `Canvas` 渲染，仅在 `isEditing` 为 true 时拦截拖拽事件用于绘图。
    - **文件**：[V2ScreenshotDebugView.swift](file:///Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/ScreenshotV2/Views/V2ScreenshotDebugView.swift) (Line 792: `buildAnnotationLayer`)

5.  **Layer 5: Debug & Info Layer (调试层)**
    - **职责**：辅助工具渲染层。
    - **特点**：放大镜（Layer 5）被设置为 `allowsHitTesting(false)`，确保不干扰 Layer 3 的事件捕获。
    - **文件**：[V2ScreenshotDebugView.swift](file:///Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/ScreenshotV2/Views/V2ScreenshotDebugView.swift) (Line 369: `buildDebugOverlay`)

---

### 4. 关键层级设计决策

#### 为什么 Layer 4.5 (标注层) 位于 Layer 3 & 4 之上？
1. **视觉优先 (Visual Priority)**: 确保用户绘制的内容（线条、箭头等）始终覆盖在选区边框和手柄（Layer 4）之上，避免 UI 元素遮挡标注内容。
2. **逻辑解耦 (Decoupling)**: Layer 3 作为“事件引擎”拦截所有手势，根据状态将坐标分发给 Layer 4 (选区) 或 Layer 4.5 (标注)。这种设计让渲染层（4.5）保持纯粹，不处理交互逻辑。
3. **性能考虑**: 标注内容随用户操作频繁更新，将其放在较高的视觉层级有助于 SwiftUI 更高效地处理层级合成。

#### 扩展场景：长图截取模式 (Long Screenshot Mode)

在长图截取模式下，为了实现“一边滚动一边预览”的专业体验，系统引入了**侧边控制面板架构**：

- **Layer 1 & 2 (背景/蒙层)**: 临时隐藏。通过 `stateManager.isCapturing` 状态控制，当用户开始滚动采集时，背景截图和暗色蒙层会消失，露出底层的真实窗口。
- **Layer 3 (交互层)**: **局部事件穿透**。选区内部区域不再拦截点击（通过 `V2ScreenshotHostingView` 的 `hitTest` 逻辑），允许用户直接操作下方的网页/文档进行滚动。
- **Layer 4 (选区层)**: 保持活跃。作为录制范围的视觉指引，虚线框始终可见。
- **Layer 5 (控制与预览层)**: 核心区域。引入了独立的 `V2LongScreenshotControlPanel` (NSPanel)：
    - **侧边栏布局**：整合了实时滚动预览和操作按钮，采用 180x460px 的纵向布局。
    - **智能定位**：优先吸附在选区**右侧**，若空间不足自动翻转至**左侧**，且始终保持与选区**垂直居中**。
    - **实时预览**：内部包含一个 `ScrollView`，实时拼接并展示已采集的图片片段。
    - **状态指示**：带有红色呼吸灯动画，明确指示当前的采集状态。

---

### 5. 涉及文件清单 (Full File List)

| 模块 | 文件路径 | 核心功能 |
| :--- | :--- | :--- |
| **视图** | `Views/V2ScreenshotDebugView.swift` | 5层渲染、放大镜、工具栏、所有交互逻辑 |
| **状态** | `Models/V2PrimaryScreenStateManager.swift` | 跨屏幕同步 `isEditing`, `selectedArea`, `paths` |
| **控制器** | `Controllers/V2ScreenshotDebugController.swift` | 管理 NSPanel 生命周期, 预取纯净截图 |
| **服务** | `Services/WindowInfoService.swift` | 获取桌面所有窗口的 Rect 用于吸附 |
| **坐标** | `Services/V2CoordinateMapper.swift` | SwiftUI (Top-Left) 与 AppKit (Bottom-Left) 转换 |
| **正式版** | `Controllers/V2CaptureController.swift` | 协调正式流程与调试流程的资源切换 |

---

## 4. 关键技术实现

### 4.1 Retina 高清支持
为了防止截图模糊，我们在裁剪和显示时做了特殊处理：
- **采集**：使用 `CGDisplayCreateImage` 获取原始像素，并显式设置 `NSImage.size` 为屏幕逻辑尺寸。
- **保存**：利用 `screen.backingScaleFactor` 将逻辑选区矩形映射回像素坐标，通过 `CGImage.cropping(to:)` 从原始图像裁剪。
- **标注合成**：在保存前，使用 `NSImage.lockFocus()` 将标注路径通过 `Core Graphics` 渲染到裁剪后的图像上，确保标注也是高清的。

### 4.2 智能工具栏定位
工具栏会根据选区位置自动计算最佳显示位置：
1. 优先尝试显示在选区**下方**。
2. 如果下方空间不足，尝试显示在选区**上方**。
3. 如果上方空间也不足（如全屏选区），则显示在选区**内部底部**。

### 4.3 屏幕释放逻辑
当用户在一个屏幕上（如 Screen A）完成选区后：
- `primaryScreenManager.selectionScreen` 被赋值为 Screen A。
- Screen B 的 `isReleased` 计算属性变为 `true`。
- Screen B 的 `body` 立即卸载所有 UI 层级，并调用 `panel.ignoresMouseEvents = true`，让鼠标可以穿透到系统底层。

### 4.3 放大镜与取色
- **原理**：实时获取鼠标位置，通过对原始图片进行 `offset` 和 `scale` 变换实现放大。
- **取色**：通过 `dataProvider` 读取 `CGImage` 在特定像素坐标的 RGBA 值，并转换为 HEX 字符串展示。
