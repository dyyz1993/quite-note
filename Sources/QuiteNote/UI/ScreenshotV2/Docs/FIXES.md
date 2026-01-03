# V2 多屏幕修复说明

## 🔧 修复的关键问题

### 问题 1: 坐标系混乱

#### 错误的做法:
```swift
let screenBounds = CGDisplayBounds(displayID)  // CoreGraphics 坐标系
let panel = NSPanel(contentRect: screenBounds, ...)  // ❌ 错误!
```

#### 正确的做法:
```swift
let screenFrame = screen.frame  // AppKit 坐标系
let panel = NSPanel(contentRect: screenFrame, ...)  // ✅ 正确!
```

**原因**: NSPanel 使用 AppKit 坐标系(左下角原点),而 CGDisplayBounds 返回 CoreGraphics 坐标系(左上角原点)。

### 问题 2: 面板 level 不一致

#### 旧代码:
```swift
panel.level = .screenSaver  // 太高,可能导致事件异常
```

#### 修复后:
```swift
panel.level = .floating  // 与 WindowDetectionController 一致
```

### 问题 3: collectionBehavior 不完整

#### 旧代码:
```swift
panel.collectionBehavior = [.fullScreenAuxiliary, .stationary]
```

#### 修复后:
```swift
panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
// 与 WindowDetectionController 完全一致
```

## 📊 对比表

| 特性 | 错误实现 | 正确实现 | WindowDetectionController |
|------|---------|---------|---------------------------|
| 面板坐标 | CGDisplayBounds | screen.frame | screen.frame |
| Level | .screenSaver | .floating | .floating |
| collectionBehavior | [.fullScreenAuxiliary, .stationary] | [.fullScreenAuxiliary, .canJoinAllSpaces] | [.fullScreenAuxiliary, .canJoinAllSpaces] |
| 鼠标事件 | 主屏幕接收 | 主屏幕接收 | 主屏幕接收 |
| 次要屏幕 | ignoresMouseEvents=true | ignoresMouseEvents=true | ignoresMouseEvents=true |

### 问题 4: 长图模式下的事件穿透与 UI 遮挡

#### 挑战:
在长图模式下，需要用户能够操作选区内的网页进行滚动，但选区外的 UI（如工具栏、背景蒙层）会遮挡操作。

#### 修复方案:
1. **动态 `isCapturing` 状态**: 当用户点击“开始滚动”后，全局状态 `isCapturing` 设为 `true`，立即隐藏背景截图和暗色蒙层。
2. **智能 `hitTest` 穿透**: 选区内部区域在采集状态下不响应任何鼠标事件，让点击和滚动事件穿透到系统底层应用。
3. **侧边控制面板**: 将预览和控制按钮从选区上方/下方移至**独立侧边窗口**，避免遮挡滚动路径，并实现智能左右避让。

## ✅ 现在的行为

```
触发截图
  ↓
V2CaptureController.startCapture()
  ↓
V2ScreenCaptureService.captureAllScreens()
  - 捕获所有屏幕的静态截图
  ↓
V2ScreenSelectionController
  - 为每个屏幕创建 NSPanel
  - 每个 panel 使用 screen.frame (正确!)
  - panel level = .floating
  - 次要屏幕 ignoresMouseEvents = true
  ↓
每个屏幕显示:
  - 静态截图背景
  - 窗口边框高亮
  - 可以交互(主屏幕)或只显示(次要屏幕)
```

## 🎯 测试建议

### 测试场景:
1. **双屏并排**: 主屏 + 副屏
2. **三屏**: 主屏 + 2个副屏
3. **不同分辨率**: 1920x1080 + 2560x1440
4. **竖屏**: 横屏 + 竖屏组合

### 预期行为:
- ✅ 每个屏幕都显示静态截图
- ✅ 每个屏幕都高亮窗口边框
- ✅ 只有主屏幕接收鼠标点击
- ✅ 坐标转换正确

### 调试命令:
```swift
// 打印所有屏幕信息
V2ScreenCaptureService.shared.printAllScreensInfo()

// 打印坐标信息
V2CoordinateMapper.debugPrintCoordinates()
```

## 🔍 关键差异对比

### WindowDetectionController (旧系统,动态)
```swift
// 透明覆盖层
backgroundColor = .clear
level = .floating
targetScreen = 鼠标所在的屏幕
createPanelsForAllScreens()
```

### V2ScreenSelectionController (新系统,静态)
```swift
// 静态截图背景
backgroundColor = .clear
level = .floating  // ✅ 已修复
为每个屏幕创建面板
  - 每个面板使用 screen.frame  // ✅ 已修复
  - 次要屏幕 ignoresMouseEvents = true
```

**关键区别**: 显示内容不同,但面板配置完全一致!
