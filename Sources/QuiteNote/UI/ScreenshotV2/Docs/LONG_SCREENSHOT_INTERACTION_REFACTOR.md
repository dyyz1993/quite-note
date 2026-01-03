# 长截图交互流程文档

> **目的**: 描述长截图功能的完整交互流程和重构方案
> **创建日期**: 2026-01-02
> **版本**: 2.0 (重构版)

---

## 目录

1. [当前问题分析](#当前问题分析)
2. [完整的用户交互流程](#完整的用户交互流程)
3. [技术架构详解](#技术架构详解)
4. [重构方案](#重构方案)
5. [实现细节](#实现细节)

---

## 当前问题分析

### 问题 1: 滚动事件无法穿透 ❌

**现象**: 在长截图模式下，用户在选区内滚动，底层应用（如浏览器）不响应

**根本原因**:
```
┌─────────────────────────────────────────────────────┐
│  事件传播机制                                       │
├─────────────────────────────────────────────────────┤
│  鼠标点击事件:                                       │
│    → hitTest → 返回接收事件的视图                    │
│    → 可以通过返回 nil 实现穿透                       │
│                                                      │
│  滚动事件: ⚠️ 关键区别                              │
│    → 不走 hitTest                                    │
│    → 走响应链 (responder chain)                      │
│    → NSHostingView 会拦截所有滚动事件                │
│    → hitTest 返回 nil 无效 ❌                       │
└─────────────────────────────────────────────────────┘
```

**当前错误实现**:
```swift
// ❌ 这对滚动事件无效
override func hitTest(_ point: NSPoint) -> NSView? {
    if shouldPenetrate {
        self.window?.ignoresMouseEvents = true  // 这会让点击也穿透
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            self.window?.ignoresMouseEvents = false
        }
        return nil
    }
    return hitView
}
```

**问题**:
1. `hitTest` 只影响鼠标点击，不影响滚动事件
2. `ignoresMouseEvents = true` 会让所有事件都穿透，包括工具栏按钮
3. 没有办法让滚动穿透但点击工具栏按钮

---

## 完整的用户交互流程

### 流程图

```
┌───────────────────────────────────────────────────────────────┐
│                    长截图完整交互流程                          │
└───────────────────────────────────────────────────────────────┘

步骤 1: 进入截图模式
    用户按下快捷键或点击菜单
    ↓
    出现全屏透明覆盖层
    鼠标变为十字光标
    ↓

步骤 2: 框选区域
    用户按下鼠标并拖拽
    ↓
    实时显示选区矩形（黄色线框）
    ↓
    用户释放鼠标
    ↓
    选区确定，显示标注工具栏

步骤 3: 切换到长截图模式
    用户点击"长图"按钮（紫色）
    ↓
    主窗口关闭
    ↓
    创建独立的长截图面板
    ↓
    显示长截图专用工具栏
    ↓
    【关键】设置 window.ignoresMouseEvents = true
    （此时滚动事件已经可以穿透）

步骤 4: 开始滚动采集
    用户点击"开始滚动"按钮（红色）
    ↓
    【关键】鼠标必须悬停在工具栏上才能点击
    （因为 ignoresMouseEvents = true）
    ↓
    截取第一帧
    ↓
    显示预览面板（右侧）
    ↓
    启动全局滚动监听

步骤 5: 滚动并自动采集
    用户在选区内滚动底层应用（如浏览器）
    ↓
    【关键】滚动事件穿透到底层应用，内容滚动
    ↓
    ScrollDetectionService 检测到滚动事件
    ↓
    累计滚动距离
    ↓
    达到阈值（500px）
    ↓
    自动截取新帧
    ↓
    预览面板更新帧数

步骤 6: 完成采集
    用户点击"完成"按钮（绿色）
    ↓
    【关键】鼠标必须悬停在工具栏上才能点击
    ↓
    停止滚动监听
    ↓
    关闭独立面板
    ↓
    执行图片拼接
    ↓
    保存长图到桌面
    ↓
    使用系统默认查看器打开
```

### 关键交互节点

#### 节点 1: 点击"开始滚动"按钮

**问题**: `ignoresMouseEvents = true` 时无法点击按钮

**解决方案**:
```
使用 NSTrackingArea 检测鼠标悬停

鼠标不在工具栏上:
    window.ignoresMouseEvents = true  → 滚动穿透 ✅

鼠标进入工具栏:
    NSTrackingArea 检测到 → mouseEntered
    window.ignoresMouseEvents = false  → 可以点击 ✅

鼠标离开工具栏:
    NSTrackingArea 检测到 → mouseExited
    window.ignoresMouseEvents = true  → 恢复穿透 ✅
```

#### 节点 2: 选区内滚动

**期望行为**: 底层应用滚动，长截图自动采集

**实现机制**:
```
1. ignoresMouseEvents = true
   ↓
2. 滚动事件穿透 NSHostingView
   ↓
3. 底层应用（如浏览器）接收滚动事件
   ↓
4. NSEvent.addGlobalMonitorForEvents 监听到滚动
   ↓
5. 累计距离，达到阈值触发截图
```

---

## 技术架构详解

### 事件穿透机制对比

| 方案 | 滚动穿透 | 按钮可点击 | 实现难度 | 推荐度 |
|------|---------|-----------|---------|--------|
| ❌ hitTest 返回 nil | ❌ 无效 | ✅ 可用 | 简单 | ❌ 不推荐 |
| ✅ ignoresMouseEvents | ✅ 有效 | ❌ 不可点击 | 简单 | ⚠️ 需配合 |
| ✅ ignoresMouseEvents + NSTrackingArea | ✅ 有效 | ✅ 可用 | 中等 | ✅ 强烈推荐 |
| ⚠️ CGEventTap 转发 | ✅ 有效 | ✅ 可用 | 复杂 | ⚠️ 过度工程 |

### 推荐方案架构

```
┌─────────────────────────────────────────────────────┐
│  LongScreenshotContentView (SwiftUI)               │
│                                                     │
│  ZStack:                                            │
│    1. Color.clear (背景，穿透)                      │
│    2. YellowWireframe (线框)                        │
│    3. V2LongScreenshotToolbarRepresentable         │
│       ↓                                             │
│    ┌─────────────────────────────────────────┐      │
│    │ V2LongScreenshotToolbarWrapper (NSView) │      │
│    │                                          │      │
│    │  + NSTrackingArea (鼠标悬停检测)         │      │
│    │    - mouseEntered:                        │      │
│    │        window?.ignoresMouseEvents = false│      │
│    │    - mouseExited:                         │      │
│    │        window?.ignoresMouseEvents = true │      │
│    │                                          │      │
│    │  + NSHostingController                    │      │
│    │    → V2LongScreenshotToolbar (SwiftUI)   │      │
│    └─────────────────────────────────────────┘      │
│                                                     │
│    4. LongScreenshotPreviewPanelView               │
└─────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────┐
│  NSPanel                                            │
│                                                     │
│  属性:                                              │
│    - level: .floating                               │
│    - ignoresMouseEvents: true (初始)               │
│    - styleMask: [.borderless, .nonactivatingPanel] │
│    - collectionBehavior: [.canJoinAllSpaces]        │
└─────────────────────────────────────────────────────┘
```

### 关键技术点

#### 1. NSPanel 配置

```swift
let panel = NSPanel(
    contentRect: screen.frame,
    styleMask: [.borderless, .nonactivatingPanel],  // ⚠️ 关键
    backing: .buffered,
    defer: false
)

panel.level = .floating
panel.ignoresMouseEvents = true  // ⚠️ 关键：允许滚动穿透
panel.becomesKeyOnlyIfNeeded = false
panel.canHide = false
panel.hidesOnDeactivate = false
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
```

**为什么这样配置**:
- `.nonactivatingPanel`: 不激活底层应用
- `.floating`: 适中层级，可见但不抢占
- `ignoresMouseEvents = true`: 滚动穿透
- `.canJoinAllSpaces`: 支持全屏应用

#### 2. NSTrackingArea 配置

```swift
let trackingArea = NSTrackingArea(
    rect: bounds,
    options: [
        .mouseEnteredAndExited,  // 监听进入/离开
        .activeAlways,           // 始终激活
        .inVisibleRect           // 在可见区域内
    ],
    owner: self,
    userInfo: nil
)
addTrackingArea(trackingArea)
```

**为什么这样配置**:
- `.mouseEnteredAndExited`: 需要检测悬停
- `.activeAlways`: 即使不是 key window 也响应
- `.inVisibleRect`: 只在可见区域触发

#### 3. 坐标系统

```
全局坐标系 (多显示器)
    ┌─────────────────────────────────┐
    │ Screen 0: (0, 0) - (1920, 1080) │
    │ Screen 1: (1920, 0) - (3840, 1080) │
    └─────────────────────────────────┘

本地坐标系 (Panel 内部)
    ┌─────────────────────────────────┐
    │ Panel: (0, 0) - (1920, 1080)    │
    │                                 │
    │  Selection (全局坐标):          │
    │    x: 2000, y: 100              │
    │                                 │
    │  Selection (本地坐标):          │
    │    x: 80, y: 100                 │
    │    (2000 - 1920 = 80)           │
    └─────────────────────────────────┘

转换公式:
localX = globalX - screenFrame.minX
localY = globalY - screenFrame.minY
```

---

## 重构方案

### 重构目标

1. ✅ 滚动事件能够穿透到底层应用
2. ✅ 工具栏按钮仍然可以点击
3. ✅ 保持代码清晰可维护

### 重构步骤

#### 步骤 1: 创建 NSView 包装器

**文件**: `V2LongScreenshotToolbarWrapper.swift`

```swift
class V2LongScreenshotToolbarWrapper: NSView {
    override func mouseEntered(with event: NSEvent) {
        window?.ignoresMouseEvents = false  // 临时启用事件接收
    }

    override func mouseExited(with event: NSEvent) {
        if stateManager.isLongScreenshotMode {
            window?.ignoresMouseEvents = true  // 恢复事件穿透
        }
    }
}
```

#### 步骤 2: 创建 SwiftUI 包装器

**文件**: `V2LongScreenshotToolbarWrapper.swift`

```swift
struct V2LongScreenshotToolbarRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> V2LongScreenshotToolbarWrapper {
        return V2LongScreenshotToolbarWrapper(toolbar: toolbar, frame: frame)
    }
}
```

#### 步骤 3: 更新长截图视图

**文件**: `LongScreenshotContentView.swift`

```swift
V2LongScreenshotToolbarRepresentable(
    selection: selection,
    screen: screen,
    screenFrame: screen.frame
)
```

#### 步骤 4: 设置初始状态

**文件**: `LongScreenshotFlowController.swift`

```swift
func startCapture(...) {
    // ...
    independentPanel?.ignoresMouseEvents = true  // 默认穿透
}
```

### 修改文件清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `V2LongScreenshotToolbarWrapper.swift` | 新建 | NSView 包装器 |
| `LongScreenshotContentView.swift` | 修改 | 使用 Representable |
| `LongScreenshotFlowController.swift` | 修改 | 设置 ignoresMouseEvents |
| `V2ScreenshotHostingView.swift` | 可选 | 移除旧的 hitTest 逻辑 |

---

## 实现细节

### 完整的交互时序

```
用户点击"开始滚动"

时序 1: 鼠标进入工具栏
    ↓
    NSTrackingArea 检测到
    ↓
    V2LongScreenshotToolbarWrapper.mouseEntered()
    ↓
    window.ignoresMouseEvents = false
    ↓
    用户点击按钮 ✅

时序 2: 点击"开始滚动"按钮
    ↓
    LongScreenshotFlowController.startCapture()
    ↓
    independentPanel?.ignoresMouseEvents = true
    ↓
    预览面板显示

时序 3: 用户在选区内滚动
    ↓
    window.ignoresMouseEvents = true
    ↓
    滚动事件穿透 NSHostingView ✅
    ↓
    底层应用接收滚动事件 ✅
    ↓
    ScrollDetectionService 监听到滚动
    ↓
    累计距离达到阈值
    ↓
    自动截取新帧

时序 4: 用户点击"完成"
    ↓
    鼠标进入工具栏
    ↓
    window.ignoresMouseEvents = false
    ↓
    点击按钮 ✅
    ↓
    停止采集，拼接图片
```

### 边界情况处理

#### 情况 1: 鼠标在选区外

```
鼠标位置: 选区外
    ↓
window.ignoresMouseEvents = true
    ↓
滚动事件穿透 ✅
点击事件穿透 ✅
```

#### 情况 2: 鼠标在工具栏上

```
鼠标位置: 工具栏上
    ↓
NSTrackingArea 检测到
    ↓
window.ignoresMouseEvents = false
    ↓
滚动事件被拦截 ❌ (这是期望的)
点击按钮正常 ✅
```

#### 情况 3: 鼠标在线框上

```
鼠标位置: 线框上
    ↓
window.ignoresMouseEvents = true
    ↓
线框 .allowsHitTesting(false)
    ↓
所有事件穿透 ✅
```

### 性能考虑

| 操作 | 频率 | 性能影响 |
|------|------|---------|
| mouseEntered/mouseExited | 鼠标移动时 | 低 (系统优化) |
| ignoresMouseEvents 切换 | 悬停变化时 | 低 (简单的布尔值) |
| hitTest | 每次鼠标事件 | 中 (但已优化) |
| 全局滚动监听 | 滚动时 | 低 (仅计数) |

---

## 调试指南

### 日志输出

```swift
// V2LongScreenshotToolbarWrapper.swift
override func mouseEntered(with event: NSEvent) {
    print("🖱️ 鼠标进入工具栏 - 事件接收已启用")
    window?.ignoresMouseEvents = false
}

override func mouseExited(with event: NSEvent) {
    print("🖱️ 鼠标离开工具栏 - 事件穿透已恢复")
    window?.ignoresMouseEvents = true
}
```

### 测试检查清单

- [ ] 启动长截图模式
- [ ] 鼠标悬停在工具栏上能看到日志
- [ ] 点击"开始滚动"按钮有效
- [ ] 在选区内滚动，底层应用响应
- [ ] ScrollDetectionService 输出滚动日志
- [ ] 预览面板显示帧数增加
- [ ] 点击"完成"按钮有效
- [ ] 长图生成并打开

### 常见问题

**Q: 为什么滚动时工具栏还在？**
A: 因为工具栏使用了 NSViewRepresentable，直接添加到面板的视图中，不受 ignoresMouseEvents 影响。

**Q: 为什么鼠标必须悬停才能点击？**
A: 因为 `ignoresMouseEvents = true` 时，所有事件都穿透。通过 NSTrackingArea 检测悬停，临时启用事件接收。

**Q: 能否让选区内的点击也穿透？**
A: 可以，但需要修改 hitTest 逻辑。当前实现只处理滚动穿透。

---

## 总结

### 核心解决方案

```
问题: 滚动事件无法穿透

原因: NSHostingView 拦截滚动事件，hitTest 对滚动无效

方案:
    1. window.ignoresMouseEvents = true (默认)
    2. NSTrackingArea 检测工具栏悬停
    3. 悬停时临时设置 ignoresMouseEvents = false
    4. 离开后恢复 ignoresMouseEvents = true

效果:
    ✅ 滚动事件穿透
    ✅ 工具栏可点击
    ✅ 实现简单
    ✅ 性能良好
```

### 技术亮点

🌟 **NSTrackingArea**: 精确检测鼠标悬停
🌟 **ignoresMouseEvents**: 可靠的事件穿透
🌟 **NSViewRepresentable**: 无缝集成 SwiftUI
🌟 **坐标转换**: 支持多显示器

### 参考

- [ScrollSnap - 开源滚动截图工具](https://github.com/Brkgng/ScrollSnap)
- [Apple - NSTrackingArea](https://developer.apple.com/documentation/appkit/nstrackingarea)
- [Apple - ignoresMouseEvents](https://developer.apple.com/documentation/appkit/nswindow/1419050-ignoremouseevents)

---

**文档版本**: 2.0
**最后更新**: 2026-01-02
**维护者**: Claude Code
