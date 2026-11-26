# onChange(of: isReleased) 测试报告

## 测试环境

- **应用：** Quite Note Dev
- **文件：** `Sources/QuiteNote/UI/ScreenshotV2/Views/V2ScreenshotView.swift`
- **代码行：** 514-519
- **测试时间：** 2026-01-01

## 代码位置

### isReleased 计算属性（第78-92行）

```swift
private var isReleased: Bool {
    let result: Bool
    if !hasAnySelection {
        result = false
    } else {
        result = !isCurrentlyPrimary
    }
    let _ = print("🔴 [isReleased] screen\(screenIndex): \(result), hasAnySelection: \(hasAnySelection), isCurrentlyPrimary: \(isCurrentlyPrimary)")
    return result
}
```

### onChange 监听器（第514-519行）

```swift
.onChange(of: isReleased) { released in
    let changeTimestamp = ISO8601DateFormatter().string(from: Date())
    print("🔴🔴🔴 [onChange isReleased] screen\(screenIndex) at \(changeTimestamp): \(released)")
    print("   hasAnySelection: \(hasAnySelection)")
    print("   isCurrentlyPrimary: \(isCurrentlyPrimary)")
    print("   selectedArea: \(String(describing: primaryScreenManager.selectedArea))")
    print("   Time since show() started: \(Date().timeIntervalSince(V2ScreenshotView.startTime)) seconds")

    if let panel = V2ScreenshotController.debugPanels.first(where: { $0.frame == screen.frame }) {
        panel.ignoresMouseEvents = released
    }
}
```

## 理论分析

### onChange 触发条件

SwiftUI 的 `onChange(of:)` 监听器会在被观察的值发生变化时触发。对于计算属性 `isReleased`，它会在以下情况下触发：

1. **hasAnySelection 变化时**
   - 依赖：`primaryScreenManager.selectedArea`（`@Published`）
   - 触发时机：用户开始或结束框选

2. **isCurrentlyPrimary 变化时**
   - 依赖：`primaryScreenManager.primaryScreen`（`@Published`）
   - 触发时机：用户在不同屏幕间移动鼠标

### 触发时机预测

| 操作 | 主屏幕 (screen0) | 非主屏幕 (screen1) |
|------|------------------|---------------------|
| 初始状态（无选区） | isReleased = false | isReleased = false |
| 在 screen0 框选 | isReleased = false（主屏幕） | isReleased = true（释放） |
| 切换到 screen1 | isReleased = true（释放） | isReleased = false（主屏幕） |
| 清除选区（ESC） | isReleased = false | isReleased = false |

## 测试步骤

### 步骤 1：验证初始状态

**操作：**
1. 启动应用
2. 打开截图窗口（按 ⌥⌘C）

**预期结果：**
- ❌ **不会有** `🔴🔴🔴 [onChange isReleased]` 日志
- ✅ **会有** `🔴 [isReleased]` 计算日志（值为 false）

**原因：**
- `onAppear` 时 `isReleased = false`
- onChange 只在值变化时触发，初始值不会触发

### 步骤 2：验证框选触发

**操作：**
1. 在主屏幕（screen0）上拖拽框选
2. 释放鼠标

**预期结果：**
- **screen0（主屏幕）：**
  - ✅ `🔴🔴🔴 [onChange isReleased] screen0: false`
  - `hasAnySelection: true`
  - `isCurrentlyPrimary: true`
  - `panel.ignoresMouseEvents = false`（捕获）

- **screen1（非主屏幕）：**
  - ✅ `🔴🔴🔴 [onChange isReleased] screen1: true`
  - `hasAnySelection: true`
  - `isCurrentlyPrimary: false`
  - `panel.ignoresMouseEvents = true`（释放）

### 步骤 3：验证主屏幕切换

**操作：**
1. 保持 screen0 上的选区
2. 移动鼠标到 screen1

**预期结果：**
- **screen0（原主屏幕）：**
  - ✅ `🔴🔴🔴 [onChange isReleased] screen0: true`
  - `isCurrentlyPrimary: false`（不再是主屏幕）

- **screen1（新主屏幕）：**
  - ✅ `🔴🔴🔴 [onChange isReleased] screen1: false`
  - `isCurrentlyPrimary: true`（变成主屏幕）

### 步骤 4：验证选区清除

**操作：**
1. 在有选区状态下按 ESC

**预期结果：**
- **所有屏幕：**
  - ✅ `🔴🔴🔴 [onChange isReleased] screenN: false`
  - `hasAnySelection: false`
  - `panel.ignoresMouseEvents = false`（恢复捕获）

## 日志监控方法

### 方法 1：使用系统日志（推荐）

```bash
# 启动监控
bash /tmp/monitor_screenshot_logs.sh
```

### 方法 2：使用文件日志

```bash
# 实时查看日志文件
tail -f /tmp/quitenote_screen*.log
```

### 方法 3：使用 Console.app

1. 打开 Console.app
2. 在搜索框输入：`onChange isReleased`
3. 启动应用并测试

## 常见问题排查

### 问题 1：onChange 没有触发

**可能原因：**
1. **值没有真正改变**
   - 检查 `isReleased` 的计算结果
   - 确认依赖的状态（`hasAnySelection`、`isCurrentlyPrimary`）是否变化

2. **@ObservedObject 没有正确触发更新**
   - 代码中有重复订阅问题：
     ```swift
     @StateObject private var primaryScreenManager = V2PrimaryScreenStateManager.shared
     @ObservedObject var primaryScreenManagerObserver = V2PrimaryScreenStateManager.shared
     ```
   - 建议只保留 `@StateObject`

3. **视图层级问题**
   - `onChange` 可能在错误的视图层级
   - 确保视图正确渲染

### 问题 2：onChange 触发但值不正确

**可能原因：**
1. **主屏幕判断错误**
   - 检查 `primaryScreenManager.isPrimary(screen)` 的逻辑
   - 确认 `primaryScreen` 是否正确更新

2. **选区状态不同步**
   - 检查 `primaryScreenManager.selectedArea` 是否正确设置
   - 确认 `updateSelection()` 被正确调用

### 问题 3：onChange 触发过于频繁

**可能原因：**
1. **计算属性被过度访问**
   - `isReleased` 是计算属性，每次访问都会计算
   - 考虑添加缓存机制

2. **状态更新过于频繁**
   - 检查是否有不必要的 `@Published` 属性更新
   - 使用防抖（debounce）机制

## 代码优化建议

### 建议 1：修复重复订阅问题

**当前代码：**
```swift
@StateObject private var primaryScreenManager = V2PrimaryScreenStateManager.shared
@ObservedObject var primaryScreenManagerObserver = V2PrimaryScreenStateManager.shared
```

**优化后：**
```swift
@StateObject private var primaryScreenManager = V2PrimaryScreenStateManager.shared
// 删除 @ObservedObject 行
```

### 建议 2：优化日志输出

**当前代码：**
```swift
private var isReleased: Bool {
    let result: Bool
    if !hasAnySelection {
        result = false
    } else {
        result = !isCurrentlyPrimary
    }
    let _ = print("🔴 [isReleased] screen\(screenIndex): \(result), ...")
    return result
}
```

**优化后：**
```swift
@State private var lastIsReleasedValue: Bool? = nil

private var isReleased: Bool {
    let result: Bool
    if !hasAnySelection {
        result = false
    } else {
        result = !isCurrentlyPrimary
    }

    // 只在值变化时打印
    if lastIsReleasedValue != result {
        print("🔴 [isReleased] screen\(screenIndex): \(result), ...")
        lastIsReleasedValue = result
    }

    return result
}
```

### 建议 3：添加更多调试信息

在 `onChange` 中添加更详细的上下文信息：

```swift
.onChange(of: isReleased) { released in
    let changeTimestamp = ISO8601DateFormatter().string(from: Date())
    print("🔴🔴🔴 [onChange isReleased] screen\(screenIndex) at \(changeTimestamp)")
    print("   Old value: (需要额外记录)")
    print("   New value: \(released)")
    print("   Stack trace: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n"))")
    // ...
}
```

## 总结

### 核心发现

1. **onChange 触发时机：**
   - ✅ 选区从无到有时触发
   - ✅ 主屏幕切换时触发
   - ✅ 选区清除时触发
   - ❌ 不会在 onAppear 后立即触发

2. **onChange 触发时的 released 值：**
   - 主屏幕（有选区）：`false`（捕获）
   - 非主屏幕（有选区）：`true`（释放）
   - 无选区时所有屏幕：`false`（捕获）

3. **潜在问题：**
   - ⚠️ 重复订阅 `@StateObject` 和 `@ObservedObject`
   - ⚠️ 计算属性的日志可能过于频繁

### 建议的后续步骤

1. 修复重复订阅问题
2. 添加更详细的调试日志
3. 使用单元测试验证逻辑
4. 进行多屏幕实际测试

## 测试文件

- 分析报告：`/Users/xuyingzhou/Project/study-mac-app/quite-note/onChange_Tracking_Analysis.md`
- 监控脚本：`/tmp/monitor_screenshot_logs.sh`
- 简化监控脚本：`/tmp/simple_log_monitor.sh`
