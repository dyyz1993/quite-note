# 线框不显示问题 - 完整调试方案

## 问题现象
用户点击截图按钮后，移动鼠标悬停在窗口上，黄色线框不显示

## 数据流完整图

```
用户点击截图
  │
  ▼
┌─────────────────────────────────────────┐
│ 步骤1: V2ScreenshotController.show()    │
│ 调用 reset() 重置所有状态                │
└─────────────────────────────────────────┘
  │
  │ 状态: primaryScreen=nil
  │       selectedArea=nil
  │       globalHoveredRect=nil
  │       hoverScreen=nil
  │       isMouseOverUI=false (应该)
  │
  ▼
┌─────────────────────────────────────────┐
│ 步骤2: V2ScreenshotView 初始化           │
│ 为每个屏幕创建视图实例                   │
└─────────────────────────────────────────┘
  │
  │ 状态: isCurrentlyPrimary=false
  │       snappedWireframeRect=nil
  │       localSelectedArea=nil
  │       isReleased=false
  │
  ▼
┌─────────────────────────────────────────┐
│ 步骤3: 鼠标移动触发 onContinuousHover    │
│ buildInteractionLayer()                 │
└─────────────────────────────────────────┘
  │
  ├─→ [🔴 断点1] onContinuousHover 触发？
  │   │
  │   ├─→ ✅ 正常: 频繁触发 .active 事件
  │   └─→ ❌ 异常: 完全不触发
  │       原因: isMouseOverUI=true 阻断
  │
  ├─→ updatePrimaryScreen(screen)
  │   └─ primaryScreen = 当前屏幕
  │
  └─→ updateHoverState(at: location)
       │
       ├─→ [🔴 断点2] 坐标转换成功？
       │   │
       │   ├─→ ✅ 正常: 返回全局坐标
       │   └─→ ❌ 异常: 返回 nil
       │       原因: V2CoordinateMapper bug
       │
       ├─→ [🔴 断点3] 找到窗口？
       │   │
       │   ├─→ ✅ 正常: found != nil
       │   └─→ ❌ 异常: found == nil
       │       原因: windowsOnScreen 为空或 bounds 不匹配
       │
       └─→ primaryScreenManager.updateHover()
           ├─ globalHoveredRect = rect
           ├─ globalHoveredLabel = label
           └─ hoverScreen = screen
  │
  ▼
┌─────────────────────────────────────────┐
│ 步骤4: SwiftUI 刷新                     │
│ @Published 变量变化触发 body 重新计算    │
└─────────────────────────────────────────┘
  │
  ├─→ [🔴 断点4] snappedWireframeRect 计算
  │   │
  │   ├─ 条件1: globalHoveredRect != nil
  │   ├─ 条件2: hoverScreen == screen
  │   │
  │   ├─→ ✅ 正常: 返回 rect
  │   └─→ ❌ 异常: 返回 nil
  │       原因: 条件不满足
  │
  ▼
┌─────────────────────────────────────────┐
│ 步骤5: buildDragOverlay 执行            │
└─────────────────────────────────────────┘
  │
  ├─→ [🔴 断点5] 进入哪个分支？
  │   │
  │   ├─ 分支1: dragStartPoint != nil (拖拽中)
  │   ├─ 分支2: localSelectedArea != nil (已确认)
  │   ├─ 分支3: snappedWireframeRect != nil (悬停) ⬅️ 应该走这里
  │   └─ 分支4: 都不满足 (无显示)
  │
  └─→ [🔴 断点6] 创建 YellowWireframe？
      │
      ├─→ ✅ 正常: 创建线框
      └─→ ❌ 异常: 不创建
          原因: isReleased=true 或 snappedWireframeRect=nil
  │
  ▼
┌─────────────────────────────────────────┐
│ 步骤6: YellowWireframe 渲染             │
│ zIndex(15), 显示在屏幕上                │
└─────────────────────────────────────────┘
```

## 关键变量追踪表

| 步骤 | primaryScreen | selectedArea | globalHoveredRect | hoverScreen | isCurrentlyPrimary | snappedWireframeRect |
|------|---------------|--------------|-------------------|-------------|-------------------|---------------------|
| 1. 点击截图 | nil | nil | nil | nil | false | nil |
| 2. 初始化 | nil | nil | nil | nil | false | nil |
| 3. 鼠标移动 | Screen A | nil | nil | nil | false | nil |
| 3.5. updatePrimary | Screen A ✅ | nil | nil | nil | **true** ✅ | nil |
| 4. updateHover | Screen A | nil | **rect A** ✅ | **Screen A** ✅ | true | **rect A** ✅ |
| 5. SwiftUI刷新 | Screen A | nil | rect A | Screen A | true | rect A |
| 6. buildDrag | Screen A | nil | rect A | Screen A | true | rect A |
| 7. YellowWire | Screen A | nil | rect A | Screen A | true | rect A |

## 6个关键断点验证

### 断点1：onContinuousHover 是否触发？

**位置：** `V2ScreenshotView.swift:508`

**添加代码：**
```swift
.onContinuousHover { phase in
    // 🔴 [断点1] 验证 onContinuousHover 是否触发
    print("🔍 [B1] onContinuousHover - screen\(screenIndex), phase: \(phase), isMouseOverUI: \(primaryScreenManager.isMouseOverUI)")

    if primaryScreenManager.isMouseOverUI {
        print("⚠️⚠️⚠️ [B1-ERROR] onContinuousHover 被 isMouseOverUI 阻断！")
        print("   isMouseOverUI: \(primaryScreenManager.isMouseOverUI)")
        print("   这就是线框不显示的原因！")
        return
    }

    // ... 原有代码
}
```

**预期结果：**
- ✅ 正常：鼠标移动时频繁打印 "🔍 [B1] onContinuousHover"
- ❌ 异常：完全不打印，或打印 "⚠️⚠️⚠️ [B1-ERROR]"

**失败原因：**
1. isMouseOverUI 残留为 true（调试面板 hover 状态未清除）
2. allowsHitTesting 被设置为 false
3. 层级被遮挡

---

### 断点2：坐标转换是否成功？

**位置：** `V2ScreenshotView.swift:110`

**添加代码：**
```swift
private func updateHoverState(at location: CGPoint) {
    // 🔴 [断点2] 验证坐标转换
    print("🔍 [B2] updateHoverState - screen\(screenIndex), location: \(location)")

    guard let globalPoint = V2CoordinateMapper.localToScreen(point: location, on: screen) else {
        print("⚠️⚠️⚠️ [B2-ERROR] 坐标转换失败！")
        print("   location: \(location)")
        print("   screen: \(screen)")
        return
    }

    print("🔍 [B2.1] 坐标转换成功: \(location) -> \(globalPoint)")

    // ... 原有代码
}
```

**预期结果：**
- ✅ 正常：打印坐标转换成功
- ❌ 异常：打印 "坐标转换失败"

**失败原因：**
1. V2CoordinateMapper.localToScreen 实现有 bug
2. screen 参数错误
3. 坐标系配置问题

---

### 断点3：是否找到窗口？

**位置：** `V2ScreenshotView.swift:110`

**添加代码：**
```swift
private func updateHoverState(at location: CGPoint) {
    // ... 前面的代码

    // 🔴 [断点3] 验证窗口查找
    print("🔍 [B3.1] windowsOnScreen.count: \(windowsOnScreen.count)")

    if windowsOnScreen.isEmpty {
        print("⚠️⚠️⚠️ [B3-ERROR] windowsOnScreen 为空！")
    }

    let found = windowsOnScreen.first { window in
        window.bounds.contains(globalPoint)
    }

    if let window = found {
        print("🔍 [B3.2] 找到窗口: \(window.ownerName): \(window.windowName ?? "无标题")")
        let rect = getLocalRect(for: window)
        print("🔍 [B3.3] 窗口 rect: \(rect)")

        primaryScreenManager.updateHover(rect, label: "\(window.ownerName)", on: screen)
        print("✅ [B3.4] updateHover 完成")
    } else {
        print("🔍 [B3.5] 未找到窗口，使用全屏")
        let screenRect = CGRect(origin: .zero, size: screen.frame.size)
        primaryScreenManager.updateHover(screenRect, label: "Full Screen", on: screen)
    }
}
```

**预期结果：**
- ✅ 正常：打印 "找到窗口" 或 "使用全屏"
- ❌ 异常：windowsOnScreen 为空

**失败原因：**
1. 窗口过滤逻辑过于严格
2. 窗口 bounds 计算错误
3. globalPoint 不在任何一个窗口内

---

### 断点4：snappedWireframeRect 计算结果？

**位置：** `V2ScreenshotView.swift:485`

**添加代码：**
```swift
private var snappedWireframeRect: CGRect? {
    // 🔴 [断点4] 验证计算逻辑
    print("🔍 [B4] snappedWireframeRect getter - screen\(screenIndex)")
    print("   globalHoveredRect: \(String(describing: primaryScreenManager.globalHoveredRect))")
    print("   hoverScreen: \(String(describing: primaryScreenManager.hoverScreen?.localizedName))")
    print("   current screen: \(screen.localizedName)")
    print("   hoverScreen == screen: \(primaryScreenManager.hoverScreen == screen)")

    if let rect = primaryScreenManager.globalHoveredRect,
       primaryScreenManager.hoverScreen == screen {
        print("✅ [B4.1] 条件满足，返回 rect: \(rect)")

        let screenRect = CGRect(origin: .zero, size: screen.frame.size)
        if abs(rect.width - screenRect.width) < 1 &&
           abs(rect.height - screenRect.height) < 1 {
            let insetRect = rect.insetBy(dx: 8, dy: 8)
            print("✅ [B4.2] 全屏内缩: \(insetRect)")
            return insetRect
        }

        return rect
    }

    print("❌ [B4.3] 条件不满足，返回 nil")
    if primaryScreenManager.globalHoveredRect == nil {
        print("   原因: globalHoveredRect == nil")
    }
    if primaryScreenManager.hoverScreen != screen {
        print("   原因: hoverScreen != screen")
    }
    return nil
}
```

**预期结果：**
- ✅ 正常：打印 "条件满足，返回 rect"
- ❌ 异常：打印 "条件不满足，返回 nil"

**失败原因：**
1. globalHoveredRect 为 nil（updateHoverState 没执行或失败）
2. hoverScreen 与当前屏幕不匹配（多屏幕问题）

---

### 断点5：buildDragOverlay 进入哪个分支？

**位置：** `V2ScreenshotView.swift:1060`

**添加代码：**
```swift
private func buildDragOverlay() -> some View {
    // 🔴 [断点5] 验证分支判断
    print("🔍 [B5] buildDragOverlay - screen\(screenIndex)")
    print("   dragStartPoint: \(String(describing: dragStartPoint))")
    print("   localSelectedArea: \(String(describing: localSelectedArea))")
    print("   snappedWireframeRect: \(String(describing: snappedWireframeRect))")
    print("   isReleased: \(isReleased)")

    ZStack(alignment: .topLeading) {
        if let start = dragStartPoint, let current = dragCurrentPoint {
            print("✅ [B5.1] 进入分支1: 拖拽中")
            // ... 原有代码
        } else if let rect = localSelectedArea {
            print("✅ [B5.2] 进入分支2: 已确认选区")
            // ... 原有代码
        } else if let rect = snappedWireframeRect {
            print("✅ [B5.3] 进入分支3: 悬停预览, rect: \(rect)")
            if !isReleased {
                print("✅ [B5.4] 创建 YellowWireframe")
                YellowWireframe(rect: rect, ...)
            } else {
                print("❌ [B5.5] isReleased=true，不创建线框")
            }
        } else {
            print("❌❌❌ [B5.6] 所有分支都不满足，不显示任何线框")
        }
    }
}
```

**预期结果：**
- ✅ 正常：打印 "进入分支3: 悬停预览" 和 "创建 YellowWireframe"
- ❌ 异常：打印 "所有分支都不满足"

**失败原因：**
1. snappedWireframeRect 为 nil
2. isReleased 为 true
3. 优先级问题（进入了其他分支）

---

### 断点6：YellowWireframe 是否创建？

**这个断点其实就是断点5的一部分**

但可以额外在 YellowWireframe 组件内部添加验证：

```swift
init(rect: CGRect, ...) {
    // 🔴 [断点6] 验证 YellowWireframe 初始化
    print("🔍 [B6] YellowWireframe.init - rect: \(rect)")
    self.rect = rect
    // ...
}
```

## 最可能的3个问题（按概率排序）

### 🎯 问题1：isMouseOverUI 状态残留（90%）

**症状：**
- onContinuousHover 完全不触发
- 控制台打印 "⚠️⚠️⚠️ [B1-ERROR] onContinuousHover 被 isMouseOverUI 阻断"

**原因：**
- 调试面板（V2DebugOverlayView）的 hover 状态没有正确清除
- 鼠标从调试面板移开时，onPanelHover(false) 没有触发
- 或触发了但时序有问题

**修复方案：**
```swift
// 方案A：在 onContinuousHover 开始时强制重置
.onContinuousHover { phase in
    // ✨ 修复：鼠标移动时，强制重置 isMouseOverUI
    // 因为鼠标移动到 InteractionLayer 时，肯定不在 UI 上
    if case .active(_) = phase {
        primaryScreenManager.isMouseOverUI = false
    }

    if primaryScreenManager.isMouseOverUI {
        return
    }
    // ...
}

// 方案B：改用局部状态，而不是全局状态
// 不在 primaryScreenManager 中存储 isMouseOverUI
// 而是在每个需要的地方局部判断

// 方案C：在 onContinuousHover .active 时设置
.onContinuousHover { phase in
    switch phase {
    case .active(let location):
        // ✨ 鼠标在 InteractionLayer 上，肯定不在 UI 上
        primaryScreenManager.isMouseOverUI = false
        // ...
    case .ended:
        // ...
    }
}
```

---

### 🎯 问题2：windowsOnScreen 为空（5%）

**症状：**
- 控制台打印 "⚠️⚠️⚠️ [B3-ERROR] windowsOnScreen 为空"
- updateHoverState 总是走 "使用全屏" 分支

**原因：**
- 窗口过滤逻辑过于严格（line 87-107）
- WindowInfoService.shared.fetchAllWindows() 返回空
- 坐标系转换导致窗口 bounds 不在屏幕内

**修复方案：**
```swift
// 检查窗口过滤条件
private var windowsOnScreen: [WindowInfo] {
    // ...
    return allWindows.filter { window in
        // 1. 必须与当前屏幕相交
        guard window.bounds.intersects(screenBounds) else {
            print("❌ 窗口 \(window.ownerName) 不与屏幕相交")
            return false
        }

        // 2. 排除过小的窗口
        let rect = getLocalRect(for: window)
        if rect.width < 100 || rect.height < 100 {
            print("❌ 窗口 \(window.ownerName) 太小: \(rect.size)")
            return false
        }

        // 3. 排除系统背景
        if isSystemBackground(window) {
            print("❌ 窗口 \(window.ownerName) 是系统背景")
            return false
        }

        print("✅ 窗口 \(window.ownerName) 通过过滤")
        return true
    }
}
```

---

### 🎯 问题3：坐标转换失败（5%）

**症状：**
- 控制台打印 "⚠️⚠️⚠️ [B2-ERROR] 坐标转换失败"
- updateHoverState 提前返回

**原因：**
- V2CoordinateMapper.localToScreen 实现有 bug
- screen 参数错误
- 坐标系配置问题

**修复方案：**
```swift
// 检查 V2CoordinateMapper 实现
guard let globalPoint = V2CoordinateMapper.localToScreen(point: location, on: screen) else {
    print("⚠️ 坐标转换失败:")
    print("   location: \(location)")
    print("   screen.frame: \(screen.frame)")
    print("   screen.visibleFrame: \(screen.visibleFrame)")
    return
}
```

## 验证步骤

### 第1步：添加所有断点代码

将上述6个断点的验证代码添加到对应位置

### 第2步：运行并观察日志

1. 点击截图按钮
2. 移动鼠标到窗口上
3. 观察控制台日志

### 第3步：分析日志

根据日志输出，定位到具体哪个断点失败：
- 如果断点1失败 → isMouseOverUI 问题
- 如果断点2失败 → 坐标转换问题
- 如果断点3失败 → 窗口过滤问题
- 如果断点4失败 → hoverScreen 不匹配
- 如果断点5失败 → snappedWireframeRect 为 nil
- 如果断点6失败 → YellowWireframe 创建问题

### 第4步：应用对应的修复方案

根据失败的断点，应用对应的修复代码

### 第5步：验证修复

重复步骤2，确认线框正常显示
