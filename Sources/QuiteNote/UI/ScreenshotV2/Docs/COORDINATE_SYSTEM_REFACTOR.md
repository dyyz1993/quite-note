# V2 坐标系统重构 - 架构设计文档

## 📋 概述

本次重构解决了 SwiftUI 截图功能中长期存在的坐标系统混乱问题，通过引入 `V2CoordinateSpace` 统一坐标管理框架，实现了渲染与定位的职责分离。

**重构日期：** 2026-01-01
**重构范围：** V2ScreenshotV2 模块的坐标系统
**核心理念：** 明确职责边界，统一坐标转换，提高可维护性

---

## 🎯 解决的问题

### 问题 1：渲染与定位职责混淆

**之前的代码：**
```swift
// YellowWireframe 同时负责渲染和定位
struct YellowWireframe: View {
    let rect: CGRect  // 包含位置和尺寸

    var body: some View {
        GeometryReader { _ in  // 仅用于坐标隔离
            ZStack { ... }
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)  // ❌ 定位职责
        }
    }
}
```

**问题：**
- `YellowWireframe` 既要渲染样式，又要处理绝对定位
- 移除 `GeometryReader` 会导致坐标偏移，因为它提供了隐式的坐标隔离层
- 职责不清晰，难以测试和复用

**重构后：**
```swift
// YellowWireframe 只负责渲染
struct YellowWireframe: View {
    let size: CGSize  // 只包含尺寸

    var body: some View {
        ZStack { ... }
        .frame(width: size.width, height: size.height)
        // ✅ 无 .offset()，定位由调用者控制
    }
}

// 调用者负责定位
YellowWireframe.from(rect, label: "100x100")
    .frame(width: rect.width, height: rect.height)
    .offset(x: rect.minX, y: rect.minY)  // ✅ 定位职责清晰
```

---

### 问题 2：坐标转换逻辑分散

**之前的架构：**
```
V2ScreenshotView (计算本地坐标)
    │
    ├─ localSelectedArea: CGRect?
    │
    ├─ V2CoordinateMapper.localToScreen()  // 转换工具
    │
    └─ YellowWireframe 内部 .offset()     // 又一次偏移
```

**问题：**
- 坐标转换发生在多个地方，难以追踪
- `V2CoordinateMapper` 和 `.offset()` 的语义不清晰
- 缺少统一的坐标空间命名

**重构后：**
```
V2CoordinateSpace (统一坐标管理)
    │
    ├─ .screen() - 屏幕全局坐标
    ├─ .window() - 窗口坐标
    └─ .view() - 视图本地坐标
         │
         ├─ convert(_:to:) - 统一转换接口
         └─ anchorPosition(for:) - 定位辅助

调用者
    │
    ├─ YellowWireframe.from(rect)  // 提取尺寸
    └─ .frame().offset()           // 明确定位
```

---

## 🏗️ 新架构设计

### 1. V2CoordinateSpace 枚举

**职责：**
- 定义明确的坐标空间类型
- 提供统一的坐标转换接口
- 支持调试和日志记录

**核心 API：**
```swift
enum V2CoordinateSpace {
    case screen(NSScreen)      // 屏幕全局坐标
    case window                // 窗口坐标
    case view                  // 视图本地坐标

    // 坐标转换
    func convert(_ point: CGPoint, to targetSpace: V2CoordinateSpace) -> CGPoint?
    func convert(_ rect: CGRect, to targetSpace: V2CoordinateSpace) -> CGRect?

    // 定位辅助
    func anchorPosition(for rect: CGRect) -> CGPoint
    func centerPosition(for rect: CGRect) -> CGPoint
}
```

**设计理念：**
- 使用枚举而非结构体，确保类型安全
- 每个坐标空间都是显式的，避免隐式转换
- 提供调试辅助方法，便于排查问题

---

### 2. YellowWireframe 重构

**职责：**
- ✅ 渲染黄色边框
- ✅ 渲染 8 个调整手柄
- ✅ 渲染尺寸标签
- ❌ **不处理** 绝对定位

**核心改动：**
```swift
// 之前
let rect: CGRect  // 包含位置 (x, y) 和尺寸 (width, height)

// 重构后
let size: CGSize  // 只包含尺寸，位置由调用者控制
```

**便利方法：**
```swift
extension YellowWireframe {
    /// 从 CGRect 创建（兼容旧代码）
    static func from(_ rect: CGRect, label: String?, ...) -> YellowWireframe {
        return YellowWireframe(size: rect.size, label: label, ...)
    }
}
```

**使用示例：**
```swift
// 方式1：使用 .position() 定位（推荐）
YellowWireframe(size: rect.size, label: "100x100")
    .position(x: rect.midX, y: rect.midY)

// 方式2：使用 .frame() + .offset() 定位
YellowWireframe.from(rect, label: "100x100")
    .frame(width: rect.width, height: rect.height)
    .offset(x: rect.minX, y: rect.minY)
```

---

### 3. 调用者职责明确

**V2ScreenshotView 中的使用：**
```swift
// ✅ 拖拽中的临时选区
YellowWireframe.from(rect, label: "\(Int(rect.width)) x \(Int(rect.height))", ...)
    .frame(width: rect.width, height: rect.height)
    .offset(x: rect.minX, y: rect.minY)

// ✅ 已确认的选区
YellowWireframe.from(localSelectedArea, label: "..., showHandles: true)
    .frame(width: rect.width, height: rect.height)
    .offset(x: rect.minX, y: rect.minY)

// ✅ 悬停预览
YellowWireframe.from(snappedWireframeRect, label: globalHoveredLabel, ...)
    .frame(width: rect.width, height: rect.height)
    .offset(x: rect.minX, y: rect.minY)
```

**优势：**
- 定位逻辑集中在调用者，易于维护
- `YellowWireframe` 可独立测试
- 不同的定位方式（`.position()` vs `.offset()`）可以灵活选择

---

## 📊 架构对比

### 重构前

| 层级 | 组件 | 职责 | 问题 |
|------|------|------|------|
| UI | YellowWireframe | 渲染 + 定位 | 职责混淆 |
| 工具 | V2CoordinateMapper | 坐标转换 | 与 UI 职责重叠 |
| UI | V2ScreenshotView | 逻辑控制 | 坐标计算分散 |

### 重构后

| 层级 | 组件 | 职责 | 优势 |
|------|------|------|------|
| 架构 | V2CoordinateSpace | 坐标空间定义 | 类型安全，统一管理 |
| UI | YellowWireframe | 纯渲染 | 职责单一，可复用 |
| 工具 | V2CoordinateMapper | 底层转换 | 与 UI 解耦 |
| UI | V2ScreenshotView | 逻辑 + 定位 | 控制集中 |

---

## 🔍 技术细节

### 为什么移除 GeometryReader 会导致偏移？

**GeometryReader 的双重作用：**
1. **官方作用：** 获取父视图的几何信息
2. **隐式作用：** 创建独立的坐标空间，隔离父视图布局

**之前的代码依赖：**
```swift
GeometryReader { _ in  // ← 参数被忽略（用 _ ）
    ZStack { ... }
    .offset(x: rect.minX, y: rect.minY)
}
// ↑ GeometryReader 提供了坐标隔离层
```

**移除后的影响：**
- `.offset()` 的参考坐标系发生变化
- 导致线框位置偏移

**重构后的解决方案：**
- `YellowWireframe` 不再使用 `GeometryReader`
- 定位由调用者通过 `.frame() + .offset()` 显式控制
- 语义更清晰，不再依赖隐式行为

---

### SwiftUI 的坐标转换陷阱

#### 问题：`.offset()` vs `.position()`

```swift
// .offset() - 相对偏移
MyView()
    .offset(x: 10, y: 10)
    // 视图向右下移动，但保留原始布局空间

// .position() - 绝对定位
MyView()
    .position(x: 50, y: 50)
    // 视图中心放在 (50, 50)，忽略原始布局空间
```

**我们的选择：**
- 使用 `.frame() + .offset()` 组合
- `.frame()` 设置尺寸
- `.offset()` 设置位置
- 语义清晰，易于理解

---

## 📈 性能影响

### 内存占用
- **之前：** `YellowWireframe` 包含 `GeometryReader`，额外的测量开销
- **现在：** 纯渲染组件，无额外开销

### 渲染性能
- **之前：** 坐标转换在组件内部，每次渲染都计算
- **现在：** 坐标转换在调用者，可缓存和优化

### 代码可维护性
- **之前：** 修改定位逻辑需要改动 `YellowWireframe`
- **现在：** 修改定位逻辑只需改动调用者

---

## 🚀 未来优化方向

### 短期（已完成）
- ✅ 创建 `V2CoordinateSpace` 统一坐标管理
- ✅ 重构 `YellowWireframe` 分离渲染和定位
- ✅ 更新所有调用点使用新 API
- ✅ 添加便利方法兼容旧代码

### 中期（建议）
- 🔄 扩展 `V2CoordinateSpace.convert()` 支持更多坐标空间
- 🔄 添加坐标转换缓存机制
- 🔄 创建 `V2PositionableWireframe` 协议，统一所有线框的定位方式

### 长期（愿景）
- 🎯 建立完整的坐标转换测试套件
- 🎯 实现坐标转换的可视化调试工具
- 🎯 将 `V2CoordinateSpace` 推广到整个项目

---

## 📚 最佳实践

### 1. 渲染组件的设计原则

```swift
// ✅ 好的设计：职责单一
struct MyComponent: View {
    let size: CGSize  // 只包含尺寸
    // 渲染逻辑...
}

// ❌ 不好的设计：职责混乱
struct MyComponent: View {
    let frame: CGRect  // 包含位置
    var body: some View {
        // 渲染逻辑...
            .offset(x: frame.minX, y: frame.minY)  // 定位逻辑
    }
}
```

### 2. 坐标转换的使用

```swift
// ✅ 使用统一的坐标空间
let screenSpace = V2CoordinateSpace.screen(screen)
let viewSpace = V2CoordinateSpace.view
let convertedPoint = screenSpace.convert(point, to: viewSpace)

// ❌ 避免直接计算偏移
let convertedPoint = CGPoint(
    x: point.x - screen.frame.origin.x,
    y: point.y - screen.frame.origin.y
)
```

### 3. 定位方式的选择

```swift
// ✅ 使用 .frame() + .offset() 明确定位
MyComponent(size: size)
    .frame(width: size.width, height: size.height)
    .offset(x: rect.minX, y: rect.minY)

// ⚠️ 使用 .position() 时注意坐标中心
MyComponent(size: size)
    .position(x: rect.midX, y: rect.midY)  // 中心点定位
```

---

## 🔗 相关文档

- `V2CoordinateSpace.swift` - 坐标空间管理实现
- `YellowWireframe.swift` - 线框组件实现
- `V2ScreenshotView.swift` - 截图视图（调用者）
- `DEBUG_WIREFRAME_ISSUE.md` - 线框问题调试记录

---

## ✅ 总结

本次重构通过引入 `V2CoordinateSpace` 统一坐标管理框架，解决了 SwiftUI 截图功能中长期存在的坐标系统混乱问题。核心改进包括：

1. **职责分离：** `YellowWireframe` 只负责渲染，定位由调用者控制
2. **统一管理：** `V2CoordinateSpace` 提供类型安全的坐标转换
3. **语义清晰：** 使用 `.frame() + .offset()` 明确表达定位意图
4. **易于维护：** 坐标转换逻辑集中，不再分散

**架构改进效果：**
- ✅ 移除了对 `GeometryReader` 隐式行为的依赖
- ✅ 提高了代码可测试性和可复用性
- ✅ 降低了未来修改的维护成本
- ✅ 为多屏幕支持奠定了坚实基础

**关键经验：**
> SwiftUI 的坐标系统比 AppKit 更复杂，需要显式的架构设计来管理。不要依赖隐式的布局行为（如 `GeometryReader` 的坐标隔离），而应该建立明确的坐标空间和转换接口。
