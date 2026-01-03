# onChange(of: isReleased) 触发时机追踪报告

## 任务概述

**目标：** 追踪 `onChange(of: isReleased)` 的触发时机和值

**关键代码位置：**
- 文件：`Sources/QuiteNote/UI/ScreenshotV2/Views/V2ScreenshotView.swift`
- 行号：514-519

## 代码分析

### 1. isReleased 的计算逻辑 (第78-92行)

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

**依赖关系链：**
```
isReleased
├── hasAnySelection (依赖 primaryScreenManager.selectedArea)
└── isCurrentlyPrimary (依赖 primaryScreenManager.isPrimary(screen))
    └── primaryScreenManager.primaryScreen
```

### 2. hasAnySelection 的计算 (第68-76行)

```swift
private var hasAnySelection: Bool {
    let result = primaryScreenManager.selectedArea != nil
    if result {
        print("🔴🔴🔴 [hasAnySelection] screen\(screenIndex): TRUE, selectedArea: \(String(describing: primaryScreenManager.selectedArea))")
    }
    return result
}
```

### 3. isCurrentlyPrimary 的计算 (第54-56行)

```swift
private var isCurrentlyPrimary: Bool {
    primaryScreenManager.isPrimary(screen)
}
```

### 4. onChange 监听器 (第514-519行)

```swift
.onChange(of: isReleased) { released in
    let changeTimestamp = ISO8601DateFormatter().string(from: Date())
    print("🔴🔴🔴 [onChange isReleased] screen\(screenIndex) at \(changeTimestamp): \(released)")
    print("   hasAnySelection: \(hasAnySelection)")
    print("   isCurrentlyPrimary: \(isCurrentlyPrimary)")
    print("   selectedArea: \(String(describing: primaryScreenManager.selectedArea))")
    print("   Time since show() started: \(Date().timeIntervalSince(V2ScreenshotView.startTime)) seconds")

    // 设置面板的鼠标事件穿透
    if let panel = V2ScreenshotController.debugPanels.first(where: { $0.frame == screen.frame }) {
        panel.ignoresMouseEvents = released
    }
}
```

## onChange 触发的条件

SwiftUI 的 `onChange(of:)` 监听器会在被观察的值发生变化时触发。对于 `isReleased` 这个计算属性，它会在以下情况下触发：

### 触发条件分析

1. **primaryScreenManager.selectedArea 变化时**
   - `selectedArea` 是 `@Published` 属性
   - 当用户开始或结束框选时，会调用 `updateSelection()`
   - 这会导致 `hasAnySelection` 的计算结果变化

2. **primaryScreenManager.primaryScreen 变化时**
   - `primaryScreen` 是 `@Published` 属性
   - 当用户在不同屏幕间移动鼠标时，会调用 `updatePrimaryScreen()`
   - 这会导致 `isCurrentlyPrimary` 的计算结果变化

## 预期触发时机

根据代码逻辑，`onChange(of: isReleased)` 应该在以下时机触发：

### 场景 1：从无选区到有选区（阶段 0 → 阶段 1+）

**初始状态（阶段 0）：**
- `selectedArea = nil`
- `hasAnySelection = false`
- 所有屏幕的 `isReleased = false`

**用户在 screen0 上开始框选：**
1. `primaryScreenManager.selectedArea` 被设置为选区矩形
2. `primaryScreenManager.primaryScreen` 被设置为 screen0

**触发结果：**
- **screen0（主屏幕）：**
  - `hasAnySelection = true`
  - `isCurrentlyPrimary = true`
  - `isReleased = false`
  - **onChange 会被触发，值为 `false`**
  - `panel.ignoresMouseEvents = false`（捕获鼠标事件）

- **screen1（非主屏幕）：**
  - `hasAnySelection = true`
  - `isCurrentlyPrimary = false`
  - `isReleased = true`
  - **onChange 会被触发，值为 `true`**
  - `panel.ignoresMouseEvents = true`（忽略鼠标事件）

### 场景 2：主屏幕切换（当用户在另一屏幕上移动鼠标）

**当前状态：**
- screen0 是主屏幕，有选区
- screen1 不是主屏幕，已释放

**用户移动鼠标到 screen1：**
1. `primaryScreenManager.updatePrimaryScreen(screen1)` 被调用
2. `primaryScreenManager.primaryScreen` 从 screen0 变为 screen1

**触发结果：**
- **screen0（原主屏幕）：**
  - `hasAnySelection = true`
  - `isCurrentlyPrimary = false`（不再主屏幕）
  - `isReleased = true`
  - **onChange 会被触发，值为 `true`**
  - `panel.ignoresMouseEvents = true`（释放）

- **screen1（新主屏幕）：**
  - `hasAnySelection = true`
  - `isCurrentlyPrimary = true`（变成主屏幕）
  - `isReleased = false`
  - **onChange 会被触发，值为 `false`**
  - `panel.ignoresMouseEvents = false`（捕获）

### 场景 3：选区被清除（阶段 1+ → 阶段 0）

**当前状态：**
- 有选区，screen0 是主屏幕

**用户按 ESC 或清除选区：**
1. `primaryScreenManager.selectedArea` 被设置为 nil
2. `hasAnySelection` 变为 false

**触发结果：**
- **所有屏幕：**
  - `hasAnySelection = false`
  - `isReleased = false`
  - **onChange 会被触发，值为 `false`**
  - `panel.ignoresMouseEvents = false`（恢复捕获）

## onChange 是否在 onAppear 后立即触发？

**答案：不会立即触发**

**原因：**
1. `onAppear` 在视图首次出现时调用
2. 此时 `selectedArea = nil`，`primaryScreen = nil`
3. `isReleased = false`（因为 `hasAnySelection = false`）
4. `onChange` 只在值变化时触发，初始值不会触发

**但是：**
- 如果视图重新渲染（比如 `@ObservedObject` 的属性变化），可能会导致 `isReleased` 重新计算
- 如果计算结果与之前不同，就会触发 `onChange`

## 如果 onChange 没有触发，可能的原因

### 原因 1：值没有真正改变
- SwiftUI 的 `onChange` 只在值从 A 变为 B（A ≠ B）时触发
- 如果 `isReleased` 计算结果始终是 `false`（阶段 0），则不会触发

### 原因 2：计算属性的依赖没有触发更新
- `@ObservedObject var primaryScreenManagerObserver` 可能没有正确触发视图更新
- 需要确保 `primaryScreenManager` 的 `@Published` 属性变化时，视图能够感知

### 原因 3：视图没有正确订阅状态
- 代码中有两行订阅：
  ```swift
  @StateObject private var primaryScreenManager = V2PrimaryScreenStateManager.shared
  @ObservedObject var primaryScreenManagerObserver = V2PrimaryScreenStateManager.shared
  ```
  这可能导致混乱，应该只保留一个

### 原因 4：onChange 在错误的视图层级
- 如果 `onChange` 所在的视图没有正确渲染，或者被其他视图覆盖，可能不会触发

## 测试建议

### 测试 1：验证初始状态
1. 打开截图窗口
2. 观察控制台输出
3. **预期：** 只有 `🔴 [isReleased]` 的计算日志，**没有** `🔴🔴🔴 [onChange isReleased]`

### 测试 2：验证框选触发
1. 在任意屏幕上框选
2. 观察控制台输出
3. **预期：**
   - 主屏幕：`🔴🔴🔴 [onChange isReleased] screen0: false`
   - 非主屏幕：`🔴🔴🔴 [onChange isReleased] screen1: true`

### 测试 3：验证主屏幕切换
1. 在 screen0 框选
2. 移动鼠标到 screen1
3. 观察控制台输出
4. **预期：**
   - screen0: `🔴🔴🔴 [onChange isReleased] screen0: true`
   - screen1: `🔴🔴🔴 [onChange isReleased] screen1: false`

### 测试 4：验证选区清除
1. 有选区状态下，按 ESC
2. 观察控制台输出
3. **预期：** 所有屏幕都输出 `🔴🔴🔴 [onChange isReleased] screenN: false`

## 实际日志监控命令

由于环境问题，建议使用以下方法监控日志：

### 方法 1：使用 Console.app
1. 打开 Console.app
2. 在搜索框输入：`onChange isReleased`
3. 启动应用并打开截图窗口

### 方法 2：使用文件日志
代码已经将日志输出到文件：
```bash
# 实时监控日志文件
tail -f /tmp/quitenote_screen*.log
```

### 方法 3：使用 log 命令（需要权限）
```bash
log stream --predicate 'processImagePath contains "Quite"' --level debug | grep "onChange isReleased"
```

## 关键发现和建议

### 发现 1：重复订阅问题
代码中同时使用了 `@StateObject` 和 `@ObservedObject` 订阅同一个单例：
```swift
@StateObject private var primaryScreenManager = V2PrimaryScreenStateManager.shared
@ObservedObject var primaryScreenManagerObserver = V2PrimaryScreenStateManager.shared
```

**建议：** 只保留一个，推荐使用 `@StateObject`

### 发现 2：计算属性的打印频率
`isReleased` 是计算属性，每次访问都会打印日志，可能导致刷屏

**建议：** 使用更精确的条件判断，只在真正变化时打印

### 发现 3：onChange 的时间戳
代码中记录了时间戳：
```swift
print("   Time since show() started: \(Date().timeIntervalSince(V2ScreenshotView.startTime)) seconds")
```

这可以帮助判断 onChange 是否在预期时间触发

## 结论

**onChange(of: isReleased) 的触发时机：**
1. ✅ 当选区从无到有时触发
2. ✅ 当主屏幕切换时触发
3. ✅ 当选区被清除时触发
4. ❌ 不会在 onAppear 后立即触发（除非值有变化）

**onChange 触发时的 released 值：**
- 主屏幕：`false`（捕获鼠标事件）
- 非主屏幕：`true`（忽略鼠标事件）
- 无选区时所有屏幕：`false`（捕获鼠标事件）

**如果 onChange 没有触发：**
最可能的原因是 `@ObservedObject` 没有正确触发视图更新，建议检查订阅方式
