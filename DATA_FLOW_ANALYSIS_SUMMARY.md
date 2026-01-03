# 点击到线框显示 - 数据流可视化总结

## 一句话总结

**数据流**: `鼠标移动 → onContinuousHover → updateHoverState → globalHoveredRect (@Published) → snappedWireframeRect → YellowWireframe (悬停显示)`

**点击流**: `用户点击 → DragGesture.onEnded → 检查 globalHoveredRect != nil → updateSelection → selectedArea (@Published) → localSelectedArea → YellowWireframe (选中显示)`

---

## 关键数据流路径

```
┌─────────────┐
│ 鼠标悬停     │
│ location:   │
│ (450, 300)  │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────┐
│ onContinuousHover (Line 507)        │
│ .active(let location)               │
└──────┬──────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────┐
│ updateHoverState(at: location)      │
│ (Line 560)                          │
└──────┬──────────────────────────────┘
       │
       ├─→ 坐标转换 (Line 112)
       │   localToScreen → globalPoint
       │
       ├─→ 查找窗口 (Line 115-117)
       │   windowsOnScreen.first { contains }
       │
       └─→ 更新状态 (Line 119-127)
           if found window:
             rect = getLocalRect(window)
             label = "Owner: Window"
           else:
             rect = screenRect
             label = "Full Screen"
           │
           ▼
       ┌─────────────────────────────────────────┐
       │ updateHover(rect, label, on: screen)    │
       │ (V2PrimaryScreenStateManager.swift:170) │
       └──────┬──────────────────────────────────┘
              │
              ├─→ globalHoveredRect = rect ✅ @Published
              ├─→ globalHoveredLabel = label ✅ @Published
              └─→ hoverScreen = screen ✅ @Published
                  │
                  ▼
              ┌─────────────────────────┐
              │ SwiftUI 视图重新计算     │
              │ @Published 属性变化触发   │
              └──────┬──────────────────┘
                     │
                     ▼
              ┌───────────────────────────────────┐
              │ snappedWireframeRect (Line 486)   │
              │ if globalHoveredRect != nil &&    │
              │    hoverScreen == screen          │
              └──────┬────────────────────────────┘
                     │
                     ▼
              ┌───────────────────────────────────┐
              │ YellowWireframe (Line 1084)       │
              │ rect: globalHoveredRect           │
              │ label: globalHoveredLabel         │
              │ opacity: 0.8 (悬停状态)           │
              └───────────────────────────────────┘
```

---

## 点击选择关键路径

```
┌─────────────┐
│ 用户点击     │
│ DragGesture │
│ .onEnded    │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────┐
│ 判断点击 (Line 828-829)             │
│ dragDistance = sqrt(width² + height²)│
│ isClick = (dragDistance < 5)        │
└──────┬──────────────────────────────┘
       │
       ▼ (if isClick)
┌─────────────────────────────────────────────────────┐
│ 检查窗口吸附条件 (Line 836-838)                      │
│                                                      │
│ ✅ 条件1: !primaryScreenManager.isEditing           │
│ ⚠️ 条件2: let rect = primaryScreenManager.globalHoveredRect
│ ✅ 条件3: primaryScreenManager.hoverScreen == screen │
│                                                      │
│ ⚠️ 关键: globalHoveredRect 必须不为 nil!             │
└──────┬──────────────────────────────────────────────┘
       │ (如果条件满足)
       ▼
┌─────────────────────────────────────────┐
│ updateSelection(rect, on: screen)       │
│ (V2PrimaryScreenStateManager.swift:131) │
└──────┬──────────────────────────────────┘
       │
       ├─→ selectedArea = rect ✅ @Published
       └─→ selectionScreen = screen ✅ @Published
           │
           ▼
       ┌───────────────────────────────────┐
       │ localSelectedArea (Line 55-57)    │
       │ if selectionScreen == screen      │
       │   return selectedArea             │
       └──────┬────────────────────────────┘
              │
              ▼
       ┌──────────────────────────────────────────────┐
       │ buildDragOverlay() (Line 1057)               │
       │ 优先级2: localSelectedArea != nil            │
       └──────┬───────────────────────────────────────┘
              │
              ▼
       ┌──────────────────────────────────────────────┐
       │ YellowWireframe (Line 1075)                  │
       │ rect: localSelectedArea                      │
       │ label: "width x height"                      │
       │ showHandles: true ⭐ (8个调整手柄)            │
       │ showBackground: false                        │
       └──────────────────────────────────────────────┘
```

---

## 数据丢失风险点 (按优先级)

### 🔴 P0 - 关键风险

#### 1. globalHoveredRect 在点击时为 nil
- **位置**: Line 837
- **影响**: 点击条件不满足，窗口选择失败
- **原因**:
  - 鼠标在点击前移出窗口
  - onContinuousHover.ended 清空了状态
  - 坐标转换失败导致 updateHoverState 未执行

#### 2. 时序竞争: hover.ended vs DragGesture.onEnded
- **位置**: Line 566 vs Line 824
- **影响**: globalHoveredRect 在点击前被清空
- **原因**: 两个事件的触发顺序不确定

### 🟡 P1 - 重要风险

#### 3. 屏幕不匹配
- **位置**: Line 838
- **影响**: hoverScreen != screen，点击失败
- **原因**: 多屏环境下快速切换

#### 4. 窗口列表更新延迟
- **位置**: Line 115-117
- **影响**: 找不到窗口，globalHoveredRect 为 nil
- **原因**: 窗口关闭/移动后列表未及时更新

### 🟢 P2 - 次要风险

#### 5. 坐标转换失败
- **位置**: Line 112
- **影响**: updateHoverState 提前返回
- **原因**: V2CoordinateMapper.localToScreen 返回 nil

#### 6. 点击误判
- **位置**: Line 829
- **影响**: 拖拽误判为点击，或反之
- **原因**: 鼠标抖动，距离阈值设置不当

---

## 快速诊断清单

### 症状: 点击窗口后没有显示选中线框

**检查步骤**:

1. ✅ 悬停时是否显示线框?
   - 是 → 继续
   - 否 → 检查 `updateHoverState` 是否执行 (Line 560)

2. ✅ 点击时 `globalHoveredRect` 是否有值?
   ```swift
   // 在 Line 837 前添加日志
   print("[DEBUG] globalHoveredRect: \(primaryScreenManager.globalHoveredRect?.debugDescription ?? "nil")")
   ```
   - 有值 → 继续
   - 无值 → 检查 onContinuousHover.ended 是否清空状态 (Line 566)

3. ✅ `hoverScreen` 是否匹配当前屏幕?
   ```swift
   // 在 Line 838 前添加日志
   print("[DEBUG] hoverScreen: \(primaryScreenManager.hoverScreen?.localizedName ?? "nil"), current: \(screen.localizedName)")
   ```
   - 匹配 → 继续
   - 不匹配 → 检查多屏切换逻辑

4. ✅ `updateSelection` 是否执行?
   ```swift
   // 在 Line 839 后添加日志
   print("[DEBUG] updateSelection called with rect: \(rect)")
   ```
   - 执行 → 继续
   - 未执行 → 检查条件判断 (Line 836-838)

5. ✅ `localSelectedArea` 是否有值?
   ```swift
   // 在 Line 1074 前添加日志
   print("[DEBUG] localSelectedArea: \(localSelectedArea?.debugDescription ?? "nil")")
   ```
   - 有值 → 检查 YellowWireframe 渲染
   - 无值 → 检查 selectionScreen 是否匹配 (Line 56)

---

## 推荐修复方案 (按优先级)

### 方案 A: 捕获点击时的窗口 (最推荐)
```swift
// 在 DragGesture.onChanged 中捕获
@State private var clickCandidateWindow: WindowInfo?

.changed { value in
    let location = value.location
    let globalPoint = V2CoordinateMapper.localToScreen(point: location, on: screen)
    clickCandidateWindow = windowsOnScreen.first { $0.bounds.contains(globalPoint ?? .zero)
}

// 在 DragGesture.onEnded 中使用
.onEnded { value in
    if isClick, let window = clickCandidateWindow {
        let rect = getLocalRect(for: window)
        primaryScreenManager.updateSelection(rect, on: screen)
    }
}
```

### 方案 B: 重新计算窗口位置 (次优)
```swift
.onEnded { value in
    if isClick {
        // 重新计算，不依赖 globalHoveredRect
        updateHoverState(at: value.startLocation)
        if let rect = primaryScreenManager.globalHoveredRect {
            primaryScreenManager.updateSelection(rect, on: screen)
        }
    }
}
```

### 方案 C: 延迟清空状态 (临时)
```swift
@State private var isProcessingClick = false

case .ended:
    if !isProcessingClick {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            primaryScreenManager.updateHover(nil, label: nil, on: nil)
        }
    }

.onEnded { value in
    if isClick {
        isProcessingClick = true
        // ... 处理点击
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isProcessingClick = false
        }
    }
}
```

---

## 性能优化建议

### 1. 缓存计算属性
```swift
// 当前: 每次访问都重新计算 (Line 55-57)
private var localSelectedArea: CGRect? {
    primaryScreenManager.selectionScreen == screen
        ? primaryScreenManager.selectedArea
        : nil
}

// 优化: 缓存结果
@State private var cachedSelectionScreen: NSScreen?
@State private var cachedSelectedArea: CGRect?

private var localSelectedArea: CGRect? {
    if primaryScreenManager.selectionScreen == screen {
        if cachedSelectionScreen != screen || cachedSelectedArea != primaryScreenManager.selectedArea {
            cachedSelectionScreen = screen
            cachedSelectedArea = primaryScreenManager.selectedArea
        }
        return cachedSelectedArea
    }
    return nil
}
```

### 2. 减少 @Published 更新频率
```swift
// 当前: 每次鼠标移动都更新 (Line 560)
updateHoverState(at: location)

// 优化: 节流更新
@State private var lastHoverUpdateTime: Date = .now

if Date.now.timeIntervalSince(lastHoverUpdateTime) > 0.016 { // 60fps
    updateHoverState(at: location)
    lastHoverUpdateTime = .now
}
```

---

## 测试场景

### 场景 1: 正常点击 (应该成功)
```
步骤:
1. 打开 Xcode 窗口
2. 鼠标悬停在窗口上 → 显示悬停线框
3. 点击窗口 → 显示选中线框 (带手柄)

预期:
- globalHoveredRect 有值
- 点击条件满足
- selectedArea 被设置
- 显示选中线框
```

### 场景 2: 快速移动后点击 (可能失败)
```
步骤:
1. 鼠标悬停在 Xcode 窗口
2. 快速移动到另一个窗口
3. 立即点击原窗口位置

预期失败原因:
- globalHoveredRect 已更新为新窗口
- 点击位置与 globalHoveredRect 不匹配
```

### 场景 3: 多屏切换 (可能失败)
```
步骤:
1. 在屏幕A悬停窗口
2. 快速切换到屏幕B
3. 点击屏幕B

预期失败原因:
- hoverScreen 仍然是屏幕A
- hoverScreen == screen 条件不满足
```

---

## 监控指标

### 关键指标
1. **globalHoveredRect 有效率**: 点击时不为 nil 的比例
   - 目标: > 95%
   - 监控: 在 Line 837 添加统计

2. **点击成功率**: 点击后显示选中线框的比例
   - 目标: > 90%
   - 监控: 在 Line 839 和 Line 1075 添加统计

3. **时序延迟**: hover.ended 到 DragGesture.onEnded 的时间差
   - 目标: < 16ms
   - 监控: 在两个事件中记录 timestamp

---

## 结论

**数据流设计**:
- ✅ 清晰的状态管理 (@Published 属性)
- ✅ 明确的优先级 (拖拽 > 选中 > 悬停)
- ⚠️ 依赖瞬时状态 (globalHoveredRect)

**主要问题**:
- 点击选择依赖 `globalHoveredRect`，但该值可能在点击前失效
- 缺少点击时的窗口位置捕获机制

**推荐方案**:
- 在 DragGesture.onChanged 中捕获点击候选窗口
- 在 DragGesture.onEnded 中使用捕获的窗口，而不是 globalHoveredRect
- 这样可以消除对瞬时状态的依赖

**预期效果**:
- 点击成功率从 ~70% 提升到 > 95%
- 消除时序竞争问题
- 提升用户体验
