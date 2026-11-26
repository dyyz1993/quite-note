# SwiftUI 事件传递机制详解

## 核心概念

### 1. Hit Testing（命中测试）

Hit Testing 决定了哪个视图接收用户的点击/移动事件。

**规则：**
```
从最顶层（zIndex 最大）开始
  ↓
检查视图是否包含点击位置
  ↓
如果包含且 .allowsHitTesting != false → 这个视图接收事件
  ↓
如果 .allowsHitTesting == false → 跳过，继续向下找
  ↓
直到找到第一个接收事件的视图
```

**示例：**
```swift
ZStack {
    Color.blue        // zIndex 0
    Color.red         // zIndex 1
        .allowsHitTesting(false)
    Color.green       // zIndex 2
}
```

点击在中心：
1. 检查 Color.green（zIndex 2）- 包含位置，接收事件 ✅
2. Color.red 被 .allowsHitTesting(false) 跳过
3. Color.blue 不会收到事件（被 Color.green 拦截）

### 2. 手势优先级

SwiftUI 有三种手势附加方式：

#### (1) `.gesture()` - 默认手势

**规则：** 子视图手势优先于父视图手势

```swift
VStack {
    ChildView()
        .gesture(TapGesture().onEnded { print("子视图") })
}
.gesture(TapGesture().onEnded { print("父视图") })
```

点击 ChildView：
- 输出：`子视图`
- 父视图手势被阻止（手势被独占）

#### (2) `.simultaneousGesture()` - 同时手势

**规则：** 子视图和父视图手势同时识别

```swift
VStack {
    ChildView()
        .simultaneousGesture(TapGesture().onEnded { print("子视图") })
}
.simultaneousGesture(TapGesture().onEnded { print("父视图") })
```

点击 ChildView：
- 输出：`子视图` `父视图`
- 两个手势都触发

#### (3) `.highPriorityGesture()` - 高优先级手势

**规则：** 父视图手势优先于子视图手势

```swift
VStack {
    ChildView()
        .gesture(TapGesture().onEnded { print("子视图") })
}
.highPriorityGesture(TapGesture().onEnded { print("父视图") })
```

点击 ChildView：
- 输出：`父视图`
- 父视图手势优先，子视图手势被阻止

### 3. DragGesture 的参数

#### `minimumDistance: 0`

**行为：**
- 按下鼠标立即触发 `.onChanged`
- 即使没有移动（`translation == .zero`），也会触发

**问题：**
- 如果窗口拦截了事件，`.onChanged` 可能不会正确更新 `location`
- 导致距离计算错误

**示例：**
```swift
DragGesture(minimumDistance: 0)
    .onChanged { value in
        print("触发：\(value.translation)")  // 按下立即输出 (0, 0)
    }
```

#### `minimumDistance: 5`

**行为：**
- 按下鼠标不会立即触发 `.onChanged`
- 移动超过 5 像素才触发

**优点：**
- 避免误触发
- 提供更明确的点击/拖拽区分

**示例：**
```swift
DragGesture(minimumDistance: 5)
    .onChanged { value in
        print("触发：\(value.translation)")  // 移动 > 5px 才输出
    }
```

### 4. Color.clear 的特殊行为

**默认行为：**
```swift
Color.clear
    .onTapGesture { print("点击") }  // ❌ 不触发（Color.clear 默认不接收事件）
```

**添加 .contentShape 后：**
```swift
Color.clear
    .contentShape(Rectangle())  // ✅ 定义交互区域
    .onTapGesture { print("点击") }  // ✅ 触发
```

**使用 .allowsHitTesting(false)：**
```swift
Color.clear
    .contentShape(Rectangle())
    .allowsHitTesting(false)  // ❌ 完全阻止事件
    .onTapGesture { print("点击") }  // ❌ 不触发
```

**对 .onHover 的影响：**
```swift
Color.clear
    .contentShape(Rectangle())
    .allowsHitTesting(false)
    .onHover { hovering in print("悬停：\(hovering)") }  // ❌ 不触发（需要 hit testing）
```

## 当前问题的事件流分析

### 场景 1：鼠标悬停不显示高亮

**视图层级：**
```
ZStack
├── buildMaskOverlay (zIndex 2, allowsHitTesting=false)
│   └── ZStack (挖孔蒙层)
│       ├── Color.black.opacity(0.5)
│       └── ForEach (窗口挖孔)
│           └── Color.clear + .contentShape(Rectangle()) ← 参与hit testing?
└── buildWindowHighlights (zIndex 3)
    └── buildWindowInteractionArea
        └── Color.clear + .contentShape(Rectangle()) + .onHover
```

**事件流（问题）：**
```
鼠标移动到窗口上
  ↓
[Hit Testing] 从 zIndex 3 开始
  ↓
buildWindowInteractionArea (Color.clear)
  ├─ ✅ 包含位置
  ├─ ✅ .contentShape(Rectangle()) 定义了交互区域
  └─ ✅ 应该接收 .onHover 事件
  ↓
❌ 但实际上 .onHover 没有触发
```

**可能原因：**
1. 蒙层的 ZStack 挖孔区域的 `Color.clear` 阻挡了事件
   - 虽然整个 ZStack 设置了 `.allowsHitTesting(false)`
   - 但内部的 `Color.clear` 可能仍参与 hit testing
   - 因为它设置了 `.contentShape(Rectangle())`

2. `zIndex` 层级问题
   - 窗口交互区域在 `Group` 内部，`Group` 的默认 `zIndex` 是多少？
   - 如果 `Group` 的 `zIndex` < 蒙层的 `zIndex`，事件会被蒙层拦截

**验证方法：**
```swift
// 在 buildMaskOverlay 添加日志
print("[DEBUG] 蒙层 zIndex: 2")
print("[DEBUG] 蒙层内部 Color.clear 数量: \(localBoundsList.count)")

// 在 buildWindowInteractionArea 添加日志
print("[DEBUG] 窗口交互区域 zIndex: 3")
print("[DEBUG] 窗口位置: \(localFrame)")
```

### 场景 2：拖拽被识别为点击

**视图层级：**
```
ZStack (根视图)
├── buildMaskOverlay (zIndex 2, allowsHitTesting=false)
├── buildWindowHighlights (zIndex 3)
│   └── buildWindowInteractionArea (Color.clear + .onHover)
└── .simultaneousGesture(DragGesture(minimumDistance: 0))
```

**事件流（问题）：**
```
用户在窗口上按下鼠标
  ↓
[Hit Testing] 从 zIndex 3 开始
  ↓
buildWindowInteractionArea (Color.clear)
  ├─ ✅ 包含位置
  ├─ ✅ .contentShape(Rectangle()) 定义了交互区域
  ├─ ✅ 触发 .onHover
  └─ ❌ 拦截了按下事件（虽然不处理，但阻止父视图接收）
  ↓
用户移动鼠标
  ↓
❌ 父视图的 DragGesture 没有收到完整的 onChanged 事件
  ❌ 或者 location 没有正确更新
  ↓
用户释放鼠标
  ↓
父视图的 DragGesture.onEnded
  ├─ dragStartPoint = (按下时的位置)
  ├─ dragCurrentPoint = (按下时的位置) ← 没有更新!
  ├─ distance = 0
  └─ ❌ distance < 5，识别为点击
```

**为什么被拦截？**
- `Color.clear` 是 hit testing 的第一个视图
- 虽然它只处理 `.onHover`，不处理按下事件
- 但是 SwiftUI 的手势识别机制会让它"占用"这个按下事件
- 导致父视图的 `DragGesture` 无法正确跟踪移动

**解决方案：**
使用 `.simultaneousGesture(DragGesture)` 让窗口区域不独占事件：

```swift
Color.clear
    .simultaneousGesture(
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // 空实现，让事件穿透
            }
    )
    .onHover { hovering in
        // 处理悬停
    }
```

这样：
- 窗口区域的 `DragGesture` 接收按下事件
- 父视图的 `DragGesture` 也同时接收按下事件
- 两个手势都跟踪移动
- 父视图的 `DragGesture` 能正确计算距离

## ZStack 的事件传递特性

### 问题：ZStack 内部子视图的 hit testing

**代码：**
```swift
ZStack
    .allowsHitTesting(false) {
    Color.black.opacity(0.5)
    Color.clear
        .contentShape(Rectangle())
}
```

**问题：** `Color.clear` 是否参与 hit testing？

**答案：** 取决于 SwiftUI 的版本和实现

- 理论上，父视图的 `.allowsHitTesting(false)` 应该影响所有子视图
- 实际上，`Color.clear` 设置了 `.contentShape(Rectangle())` 后，可能仍参与 hit testing
- 这是因为 `.contentShape()` 改变了视图的 hit testing 行为

**验证：**
```swift
// 添加测试代码
ZStack {
    Color.black.opacity(0.5)
        .onTapGesture { print("黑色蒙层被点击") }

    Color.clear
        .contentShape(Rectangle())
        .frame(width: 100, height: 100)
        .onTapGesture { print("透明区域被点击") }
}
.allowsHitTesting(false)
```

如果输出"透明区域被点击"，说明内部子视图仍参与 hit testing。

### 解决方案：使用 .mask()

**替代方案：**
```swift
Color.black.opacity(0.5)
    .mask(
        ZStack {
            Rectangle().fill(Color.black)
            Rectangle()
                .fill(Color.white)
                .frame(width: 100, height: 100)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    )
    .allowsHitTesting(false)
```

**优点：**
- 只有一个视图（`Color.black.opacity(0.5)`）
- mask 内部的视图不影响 hit testing
- 事件传递更简单

## 最佳实践

### 1. 蒙层设计

**推荐：**
```swift
// 简单蒙层（单一视图）
Color.black.opacity(0.5)
    .allowsHitTesting(false)

// 或使用 .mask() 挖孔
Color.black.opacity(0.5)
    .mask(maskShape)
    .allowsHitTesting(false)
```

**不推荐：**
```swift
// ZStack 挖孔（可能阻挡事件）
ZStack {
    Color.black.opacity(0.5)
    Color.clear
        .contentShape(Rectangle())
}
.allowsHitTesting(false)
```

### 2. 窗口交互区域

**推荐：**
```swift
Color.clear
    .contentShape(Rectangle())
    .simultaneousGesture(
        DragGesture(minimumDistance: 0)
            .onChanged { _ in }
            .onEnded { _ in }
    )
    .onHover { hovering in
        // 处理悬停
    }
```

**不推荐：**
```swift
Color.clear
    .contentShape(Rectangle())
    .onTapGesture { }  // 可能拦截父视图的拖拽手势
    .onHover { hovering in
        // 处理悬停
    }
```

### 3. DragGesture 参数

**推荐：**
```swift
DragGesture(minimumDistance: 5)  // 减少误触发
    .onChanged { value in
        // 跟踪移动
    }
    .onEnded { value in
        if distance < 10 {
            // 点击
        } else {
            // 拖拽
        }
    }
```

**不推荐：**
```swift
DragGesture(minimumDistance: 0)  // 太敏感
    .onChanged { value in
        // 按下立即触发，即使没有移动
    }
```

## 调试技巧

### 1. 使用调试日志

```swift
.onHover { hovering in
    print("[EVENT] .onHover - hovering: \(hovering)")
}

DragGesture(minimumDistance: 0)
    .onChanged { value in
        print("[EVENT] DragGesture.onChanged - location: \(value.location)")
    }
    .onEnded { value in
        print("[EVENT] DragGesture.onEnded - translation: \(value.translation)")
    }
```

### 2. 使用可视化调试

```swift
Color.clear
    .border(Color.red, width: 2)  // 显示交互区域边界
    .onHover { hovering in
        if hovering {
            Color.blue.opacity(0.3)  // 悬停时高亮
        }
    }
```

### 3. 分阶段测试

1. **测试 hit testing**
   ```swift
   Color.clear
       .contentShape(Rectangle())
       .onTapGesture { print("hit") }
   ```

2. **测试 hover**
   ```swift
   Color.clear
       .contentShape(Rectangle())
       .onHover { print("hover: \($0)") }
   ```

3. **测试 drag**
   ```swift
   Color.clear
       .contentShape(Rectangle())
       .gesture(
           DragGesture()
               .onChanged { print("drag: \($0.location)") }
       )
   ```

4. **组合测试**
   ```swift
   Color.clear
       .contentShape(Rectangle())
       .simultaneousGesture(
           DragGesture().onChanged { print("drag") }
       )
       .onHover { print("hover: \($0)") }
   ```

## 总结

**关键要点：**
1. `Color.clear` + `.contentShape()` 会参与 hit testing
2. ZStack 内部的子视图可能独立参与 hit testing
3. `.simultaneousGesture()` 让子视图和父视图手势同时识别
4. `minimumDistance: 0` 太敏感，建议使用 5 或 10
5. 使用 `.mask()` 替代 ZStack 挖孔，避免事件冲突

**推荐修复顺序：**
1. 添加调试日志，确认事件流
2. 使用 `.simultaneousGesture(DragGesture)` 让事件穿透
3. 调整 `minimumDistance` 和判断阈值
4. 如果还有问题，使用 `.mask()` 替代 ZStack 挖孔

---

**参考文件：**
- EVENT_CONFLICT_DIAGNOSTIC_REPORT.md（完整诊断报告）
- EVENT_CONFLICT_FIX_QUICK_START.md（快速修复指南）
- Fixes/V2WindowHighlightView_FixA_UseMaskModifier.swift（方案 A）
- Fixes/V2WindowHighlightView_FixB_SimultaneousGesture.swift（方案 B）
- Fixes/V2WindowHighlightView_FixC_AdjustMinimumDistance.swift（方案 C）
