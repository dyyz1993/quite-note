# V2ScreenshotDebugView 重构测试指南

## 测试用例列表

### 自动化测试 (Cases 1-8)

| Case | 测试内容 | 验证点 |
|------|----------|--------|
| Case 1 | 基础UI组件 | InvertedRectangle, VisualEffectView, LayerLabel 可创建 |
| Case 2 | Magnifier组件 | MagnifierView, AnnotationMagnifierPreview 可创建 |
| Case 3 | Toolbar组件 | ToolbarButton, V2FloatingToolbar, V2CaptureStopToolbar 可创建 |
| Case 4 | Panels类 | V2TextInputPanel, V2LongScreenshotControlPanel, V2ScreenshotHostingView 可创建 |
| Case 5 | Overlays组件 | YellowWireframe, V2LongScreenshotPreview 可创建 |
| Case 6 | Models | SelectionHandle 所有位置可计算 |
| Case 7 | Controller | V2ScreenshotDebugController 静态属性可访问 |
| Case 8 | 主视图创建 | V2ScreenshotDebugView 可创建并渲染 |

### 手动测试 (Case 9)

| 步骤 | 操作 | 预期结果 |
|------|------|----------|
| 1 | 运行应用，按 `⌥⌘R` 触发调试截图 | 调试窗口显示 |
| 2 | 移动鼠标悬停窗口 | 显示黄色高亮框 |
| 3 | 拖拽选区 | 选区跟随鼠标，显示尺寸标签 |
| 4 | 点击窗口选中 | 选区固定，显示工具栏 |
| 5 | 点击工具栏"编辑"按钮 | 进入编辑模式，显示标注工具 |
| 6 | 绘制线条/形状 | 标注正确显示 |
| 7 | 点击"长图"按钮 | 进入长图模式 |
| 8 | 点击"开始滚动" | 显示控制面板 |
| 9 | 点击"完成并保存" | 截图保存到剪贴板，窗口关闭 |

## 运行测试

### 方式1: 在代码中调用
```swift
// 在 MainApp.swift 或调试入口
RunRefactoringTests.runAll()
```

### 方式2: 直接调用
```swift
RefactoringTestCases.runAllTests()
```

## 组件依赖关系图

```
V2ScreenshotDebugView (主视图)
├─ 使用: YellowWireframe (Overlays/)
├─ 使用: MagnifierView (Magnifier/)
├─ 使用: V2FloatingToolbar (Toolbar/)
├─ 使用: LayerLabel (Foundation/)
└─ 调用: V2ScreenshotDebugController (Controllers/)
   ├─ 使用: V2ScreenshotHostingView (Panels/)
   ├─ 使用: V2TextInputPanel (Panels/)
   └─ 使用: V2LongScreenshotControlPanel (Panels/)
      └─ 使用: V2CaptureStopToolbarView (Toolbar/)
```

## 修改的文件清单

### 新建文件 (15个)
- `Components/Foundation/InvertedRectangle.swift`
- `Components/Foundation/VisualEffectView.swift`
- `Components/Foundation/LayerLabel.swift`
- `Models/SelectionHandle.swift`
- `Controllers/V2ScreenshotDebugController.swift`
- `Views/Magnifier/MagnifierView.swift`
- `Views/Magnifier/AnnotationMagnifierPreview.swift`
- `Views/Toolbar/ToolbarButton.swift`
- `Views/Toolbar/V2FloatingToolbar.swift`
- `Views/Toolbar/V2CaptureStopToolbar.swift`
- `Views/Toolbar/V2CaptureStopToolbarView.swift`
- `Views/Panels/V2ScreenshotHostingView.swift`
- `Views/Panels/V2LongScreenshotControlPanel.swift`
- `Views/Panels/V2TextInputPanel.swift`
- `Views/Overlays/YellowWireframe.swift`
- `Views/Overlays/V2LongScreenshotPreview.swift`

### 修改文件 (1个)
- `Views/V2ScreenshotDebugView.swift` (2402行 → 1413行)

### 备份文件
- `Views/V2ScreenshotDebugView.swift.backup` (原始文件)

### 新增测试文件 (2个)
- `Testing/RefactoringTestCases.swift`
- `Testing/RunRefactoringTests.swift`

## 验证命令

```bash
# 编译验证
swift build -c release

# 查看文件行数
wc -l Sources/QuiteNote/UI/ScreenshotV2/Views/V2ScreenshotDebugView.swift

# 运行应用测试
./.build/arm64-apple-macosx/release/QuiteNote
```
