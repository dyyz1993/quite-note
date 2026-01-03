# 长截图功能（LongScreenshot）

## 概述

这是长截图功能的独立模块实现，采用方案 D：自动检测滚动距离。通过监听全局滚动事件，在达到指定阈值时自动截图并拼接为长图。

## 架构

```
LongScreenshot/
├── Controllers/
│   └── LongScreenshotFlowController.swift   # 流程控制器（核心协调器）
├── Views/
│   ├── LongScreenshotPreviewPanel.swift     # 预览面板（显示已采集帧）
│   └── LongScreenshotControlPanel.swift      # 控制面板（开始/停止/完成/取消）
├── Services/
│   ├── ScrollDetectionService.swift         # 滚动检测服务
│   └── ImageStitchingService.swift          # 图像拼接服务
└── Models/
    ├── CaptureConfig.swift                   # 捕获配置
    └── StitchResult.swift                    # 拼接结果
```

## 核心组件

### 1. ScrollDetectionService（滚动检测服务）

**职责**：监听全局滚动事件并累计滚动距离

**关键特性**：
- 使用 `NSEvent.addLocalMonitorForEvents(matching: .scrollWheel)` 监听滚动
- 累计垂直滚动距离
- 达到阈值时触发回调
- 返回 event 让事件传播到底层应用（确保滚动能正常工作）

**使用方式**：
```swift
let service = ScrollDetectionService()
service.startMonitoring(
    selection: selection,
    screen: screen,
    threshold: 500,
    onThresholdReached: {
        // 截取新帧
    }
)
```

### 2. ImageStitchingService（图像拼接服务）

**职责**：将多张图片垂直拼接为长图

**关键特性**：
- 使用 Actor 确保线程安全
- 计算最终画布尺寸
- 简单的垂直拼接（从上到下）
- 使用 `NSImage.lockFocus()` 绘制

**使用方式**：
```swift
let service = ImageStitchingService.shared
let longImage = await service.stitch(images)
```

### 3. LongScreenshotFlowController（流程控制器）

**职责**：管理长截图的完整流程

**关键特性**：
- 单例模式
- 协调滚动检测和图像拼接
- 处理开始、停止、取消
- 自动裁剪到选区
- 保存到剪贴板

**使用方式**：
```swift
LongScreenshotFlowController.shared.startCapture(
    selection: selection,
    screen: screen,
    config: .default
) { result in
    switch result {
    case .success(let image):
        // 保存到剪贴板
    case .failure(let error):
        // 处理错误
    }
}
```

### 4. LongScreenshotPreviewPanel（预览面板）

**职责**：显示已采集的帧数和预览

**关键特性**：
- 独立的 NSPanel
- 位置：选区右侧
- 尺寸：180px 宽，300px 高
- 显示帧数统计
- 显示最新几帧的缩略图

### 5. LongScreenshotControlPanel（控制面板）

**职责**：显示操作按钮

**关键特性**：
- 独立的 NSPanel
- 位置：选区下方
- 包含按钮：[停止] [完成] [取消]
- 停止：停止捕获并拼接
- 完成：停止捕获并拼接（同停止）
- 取消：取消捕获，丢弃所有帧

## 数据流

```
用户点击"开始滚动"
    ↓
显示预览面板和控制面板
    ↓
截取第一帧
    ↓
启动滚动检测
    ↓
用户在选区内滚动
    ↓
累计滚动距离达到阈值（500px）
    ↓
自动截取新帧
    ↓
更新预览面板
    ↓
用户点击"完成"或"停止"
    ↓
停止滚动检测
    ↓
拼接所有帧为长图
    ↓
保存到剪贴板
    ↓
关闭所有面板
```

## 配置

**CaptureConfig**：
- `scrollThreshold`: 滚动距离阈值（默认 500px）
- `autoDetectEnabled`: 是否启用自动检测（默认 true）
- `maxFrames`: 最大捕获帧数（默认 50）

## 事件穿透

长截图模式下的交互流程：
1. 用户选区后点击"长图"进入长图模式
2. 点击"开始滚动"启动捕获
3. 预览面板和控制面板显示
4. 主调试窗口设置 `ignoresMouseEvents = true`
5. 用户可以滚动选区内的应用
6. 滚动事件通过 `ScrollDetectionService` 监听
7. 返回 event 让事件传播到底层应用
8. 达到阈值时自动截图

## 状态管理

复用现有的 `V2PrimaryScreenStateManager`：
- `isCapturing`: 是否正在捕获
- `isLongScreenshotMode`: 是否处于长图模式
- `longScreenshotPreviews`: 已采集的帧列表

## 错误处理

**LongScreenshotError**：
- `noFrames`: 没有捕获到任何帧
- `cancelled`: 用户取消操作
- `stitchFailed`: 拼接失败

## 测试建议

1. **滚动检测测试**：
   - 在 Safari 或 Chrome 中打开长网页
   - 选区后进入长图模式
   - 滚动并观察预览面板帧数增加

2. **图像拼接测试**：
   - 滚动采集多帧后点击"完成"
   - 检查剪贴板中的长图
   - 验证图片垂直拼接正确

3. **边界测试**：
   - 测试最大帧数限制（50帧）
   - 测试取消操作
   - 测试 ESC 键退出

4. **事件穿透测试**：
   - 确保滚动操作能正常工作
   - 确保底层应用能响应滚动事件

## 已知问题

1. **简单拼接**：当前实现不做重叠去除，只是简单的垂直拼接
2. **性能**：大量帧可能导致内存压力
3. **Retina 适配**：需要正确处理高 DPI 屏幕

## 未来改进

1. 添加智能重叠检测和去除
2. 支持手动标记拼接点
3. 添加进度条显示
4. 支持导出到文件
5. 支持水平滚动

## 依赖

- `V2ScreenshotController.captureScreen()`: 屏幕截图
- `V2PrimaryScreenStateManager`: 状态管理
- `V2ScreenshotHostingView`: 事件穿透机制
- `VisualEffectView`: UI 组件

## 注意事项

1. 最小侵入原则：所有新增代码都在 `LongScreenshot/` 目录
2. 复用现有状态管理器
3. 保持事件穿透机制正常工作
4. 及时释放资源，避免内存泄漏
