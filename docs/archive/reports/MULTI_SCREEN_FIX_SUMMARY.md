# 多显示器坐标系统问题 - 快速修复指南

**问题**: 三显示器环境下窗口高亮框位置错误、拖拽框不跟随、全屏应用无法选中

---

## 根因分析（3句话）

1. **单屏幕覆盖**: 代码只为鼠标所在屏幕创建覆盖层，导致其他屏幕的窗口高亮框无法显示
2. **坐标混淆**: `CGWindowListCopyWindowInfo` 返回全局坐标，但代码假设单屏幕坐标系
3. **过滤过严**: 全屏应用的窗口层级可能被过滤掉

---

## 解决方案（推荐）

### 方案 A: 多屏幕独立覆盖（推荐）

**核心改动**:
```swift
// 1. 为所有屏幕创建独立面板
for screen in NSScreen.screens {
    let panel = ScreenPanelController(screen: screen, ...)
    panel.show()
}

// 2. 传入正确的屏幕参数
WindowDetectionView(screen: screen, ...)

// 3. 使用全局坐标系
let screen = CoordinateSystem.screenContaining(point: mouseLocation)
```

**优势**:
- ✅ 所有屏幕同时显示覆盖层
- ✅ 窗口高亮框位置正确
- ✅ 拖拽框可以跨越屏幕
- ✅ 符合用户预期（类似 CleanShot X）

---

## 关键代码修改

### 1. 创建 ScreenPanelController（新文件）

**文件**: `Sources/QuiteNote/UI/Screenshot/WindowDetection/ScreenPanelController.swift`

```swift
class ScreenPanelController: NSPanel {
    private let screen: NSScreen

    init(screen: NSScreen, ...) {
        self.screen = screen
        super.init(contentRect: screen.frame, ...)
        setupPanel()
    }

    private func setupPanel() {
        setFrame(screen.frame, display: true)
        // ... 配置面板
    }
}
```

### 2. 修改 WindowDetectionController

**关键改动**:
```swift
// 改为管理多个面板
private var screenPanels: [ScreenPanelController] = []

func show() {
    for screen in NSScreen.screens {
        let panel = ScreenPanelController(screen: screen, ...)
        panel.show()
        screenPanels.append(panel)
    }
}
```

### 3. 修改 WindowDetectionView

**关键改动**:
```swift
// 添加屏幕参数
let screen: NSScreen

init(screen: NSScreen, ...) {
    self.screen = screen
    // ...
}

// 使用正确的屏幕
private func handleGlobalMouseMove(_ event: NSEvent) {
    guard screen.frame.contains(NSEvent.mouseLocation) else {
        return  // 只处理当前屏幕的事件
    }
    // ...
}
```

### 4. 修改 CoordinateSystem

**新增方法**:
```swift
/// 查找包含指定点的屏幕
static func screenContaining(point: CGPoint) -> NSScreen? {
    NSScreen.screens.first { $0.frame.contains(point) }
}
```

### 5. 修改 WindowInfoService

**关键改动**:
```swift
// 放宽尺寸限制
guard width >= 50 || height >= 50 else {
    continue
}

// 查找窗口所在的屏幕
guard let screen = CoordinateSystem.screenContaining(point: window.bounds.origin) else {
    return nil
}

return captureScreen(rect: window.bounds, screen: screen)
```

---

## 测试验证

### 测试环境
- 3 个显示器（水平排列）
- macOS 13.0+

### 关键测试用例

| 测试用例 | 预期结果 |
|---------|---------|
| 多屏幕窗口高亮 | ✅ 所有屏幕的窗口高亮框位置正确 |
| 跨屏幕拖拽 | ✅ 拖拽框和尺寸标签可以跨越屏幕 |
| 全屏应用 | ✅ VS Code 全屏窗口可以正确识别 |

---

## 实施建议

**分阶段实施**:

1. **第一阶段**（核心功能，2-3天）:
   - 实现多屏幕独立覆盖
   - 修复坐标转换逻辑
   - 基本功能测试

2. **第二阶段**（优化，1-2天）:
   - 性能优化
   - 更多测试用例
   - 边界情况处理

3. **第三阶段**（高级功能，可选）:
   - 支持跨屏窗口
   - 配置选项
   - 用户偏好设置

---

## 风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 性能问题 | 中 | 使用懒加载，限制渲染区域 |
| 兼容性 | 低 | 代码改动集中在窗口检测模块 |
| 测试覆盖 | 中 | 在三显示器环境下充分测试 |

---

## 参考资料

- **详细报告**: `MULTI_SCREEN_COORDINATE_RESEARCH.md`
- **参考博客**: [Dealing with multiple screens programming](https://www.thinkandbuild.it/deal-with-multiple-screens-programming/)
- **中文案例**: [多显示器下判断窗口位置 macOS](https://www.logcg.com/en/archives/2771.html)

---

**下一步**: 开始实施第一阶段改动
