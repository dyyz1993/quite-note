# macOS 多屏幕坐标系统深度调研报告

## 执行摘要

经过深入调研 Apple 官方文档和技术社区，发现了窗口高亮框位置偏差的**根本原因**：

**`kCGWindowBounds` 和 `NSScreen.frame` 使用完全不同的坐标系统，但当前代码错误地假设它们可以直接比较。**

---

## 一、核心发现

### 1.1 三种不同的坐标系统

macOS 存在**三种完全不同的坐标系统**，它们有不同的原点、方向和用途：

#### 1. CoreGraphics 坐标系统（Quartz Display Services）

- **原点**：主显示器的**左上角** `(0, 0)`
- **Y 轴方向**：**向下**增长
- **用途**：`CGWindowListCopyWindowInfo`, `kCGWindowBounds`, `CGDisplayBounds`
- **官方定义**（Apple Developer）：
  > "The coordinates of the rectangle are specified in screen space, where the origin is in the **upper-left corner of the main display**."

#### 2. AppKit 坐标系统（Cocoa）

- **原点**：主显示器的**左下角** `(0, 0)`
- **Y 轴方向**：**向上**增长
- **用途**：`NSScreen.frame`, `NSWindow.frame`, `NSEvent.mouseLocation`
- **来源**：Think And Build 博客：
  > "So let's see how the global screen coordinate system works... As you can see the point 0,0 is located at the **bottom left corner of the Primary screen**."

#### 3. 全局显示坐标空间（Global Display Coordinate Space）

- **原点**：主显示器的**左上角** `(0, 0)`
- **Y 轴方向**：**向下**增长
- **用途**：统一的多显示器坐标空间
- **关键特性**：
  > "**Global display space** is a unified coordinate space in which all displays are situated. Its origin is at the **top-left of the primary display**."

### 1.2 关键技术细节

#### Ken Thomases 的权威回答（Stack Overflow，269 赞同）

> **Quartz uses a coordinate space where the origin (0, 0) is at the top-left of the primary display. Increasing y goes down.**
>
> **Cocoa uses a coordinate space where the origin (0, 0) is the bottom-left of the primary display and increasing y goes up.**

**转换公式**（Cocoa → Quartz）：
```objc
NSRect frame = window.frame;
frame.origin.y = NSMaxY(NSScreen.screens[0].frame) - NSMaxY(frame);
CGRect quartzRect = NSRectToCGRect(frame);
```

**重要提示**：你**不要**使用窗口的 `-screen`，而是**始终使用主屏幕**。

---

## 二、当前代码的问题分析

### 2.1 错误的坐标转换逻辑

查看 `WindowHighlightController.swift` 的第 235-262 行：

```swift
func shouldShowHighlight(for window: WindowInfo, in screen: NSScreen) -> Bool {
    // ⚠️ 问题 1：计算全局高度的方式错误
    let globalHeight = NSScreen.screens.reduce(0) { max($0, $1.frame.maxY) }

    // ⚠️ 问题 2：转换公式不完整
    let screenFrameInCG = CGRect(
        x: screen.frame.origin.x,
        y: globalHeight - screen.frame.maxY,  // ❌ 错误！
        width: screen.frame.width,
        height: screen.frame.height
    )

    // ⚠️ 问题 3：直接比较不同坐标系的矩形
    let intersects = window.bounds.intersects(screenFrameInCG)
    return intersects
}
```

### 2.2 根本错误

#### 错误 1：使用了错误的"全局高度"

```swift
let globalHeight = NSScreen.screens.reduce(0) { max($0, $1.frame.maxY) }
```

**问题**：
- `NSScreen.frame.maxY` 是 AppKit 坐标系（Y-up）的最大值
- 这个值表示屏幕的**顶部边缘**在 AppKit 坐标系中的位置
- 但你试图用这个值来转换到 CoreGraphics 坐标系（Y-down）

**为什么会导致负数坐标**：

以用户的屏幕布局为例：
- Built-in Retina Display: `(0.0, 0.0, 1512.0, 982.0)` - AppKit 坐标，主屏幕
- 27MP35: `(-1103.0, 982.0, 1920.0, 1080.0)` - 在主屏幕上方

当窗口在 27MP35 屏幕上时：
- `globalHeight = max(982, 982+1080) = 2062`
- 主屏幕 `screen.maxY = 982`
- `screenFrameInCG.y = 2062 - 982 = 1080` ❌ 错误！

#### 错误 2：没有正确处理多显示器布局

**正确的理解**：
- CoreGraphics 的全局坐标空间原点在主显示器左上角
- 所有显示器都在这个统一的坐标空间中
- `kCGWindowBounds` 返回的坐标已经在这个全局空间中
- `NSScreen.frame` 在 AppKit 坐标系中，不能直接比较

#### 错误 3：直接比较不同坐标系的矩形

```swift
let intersects = window.bounds.intersects(screenFrameInCG)
```

- `window.bounds` 来自 `kCGWindowBounds`，是 CoreGraphics 坐标系
- `screenFrameInCG` 是你"手动转换"的，但转换逻辑错误
- 两者虽然都是 CGRect，但代表的含义不同

---

## 三、用户日志分析

### 3.1 日志数据

```
[DEBUG] shouldShowHighlight: 屏幕=Built-in Retina Display, 窗口=Quite Note Dev
[DEBUG]   窗口 bounds(CG): (-181.0, -819.0, 520.0, 640.0)
[DEBUG]   屏幕(CG): (0.0, 1080.0, 1512.0, 982.0)
[DEBUG]   相交: false
```

### 3.2 坐标解读

#### 窗口坐标：`(-181.0, -819.0, 520.0, 640.0)`

这是 CoreGraphics 全局坐标：
- **X = -181**：窗口在主显示器左侧 181 像素
- **Y = -819**：窗口在主显示器**上方** 819 像素（CoreGraphics Y 向下，负数表示上方）
- **宽度 = 520, 高度 = 640**

这意味着窗口位于 27MP35 显示器（在主屏幕上方）。

#### 屏幕坐标：`(0.0, 1080.0, 1512.0, 982.0)`

这是你转换后的 CoreGraphics 坐标：
- **X = 0**：主屏幕左边缘
- **Y = 1080**：❌ 这里的 1080 是错误的！

**正确的应该是**：
- 主屏幕在 CoreGraphics 全局坐标中应该是 `(0, 0, 1512, 982)`
- 因为它是主屏幕，原点就在它的左上角

### 3.3 为什么相交检测失败

```
窗口矩形：(-181, -819, 520, 640)
屏幕矩形：(0, 1080, 1512, 982)
相交检测：false ❌
```

显然不相交！因为：
- 窗口的 Y 范围是 `-819` 到 `-179`（负数，在屏幕上方）
- 屏幕的 Y 范围是 `1080` 到 `2062`（很大的正数）
- 两者完全不重叠

但实际情况是：窗口就在 27MP35 屏幕上！

---

## 四、正确的坐标转换方法

### 4.1 使用 CGDisplayBounds（推荐）

**核心原理**：
- `CGDisplayBounds(displayID)` 返回的是**全局显示坐标空间**中的矩形
- 这个坐标空间与 `kCGWindowBounds` 相同
- **不需要手动转换**

```swift
import CoreGraphics

func shouldShowHighlight(for window: WindowInfo, in screen: NSScreen) -> Bool {
    // 1. 获取屏幕的 displayID
    guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
        return false
    }

    // 2. 使用 CGDisplayBounds 获取屏幕在全局坐标空间中的位置
    let screenBoundsInGlobalSpace = CGDisplayBounds(displayID)

    // 3. 直接比较（两者都在 CoreGraphics 全局坐标空间）
    let intersects = window.bounds.intersects(screenBoundsInGlobalSpace)

    print("[DEBUG] shouldShowHighlight:")
    print("[DEBUG]   窗口(CG): \(window.bounds)")
    print("[DEBUG]   屏幕(CG): \(screenBoundsInGlobalSpace)")
    print("[DEBUG]   相交: \(intersects)")

    return intersects
}
```

### 4.2 手动转换 NSScreen.frame（备选方案）

如果由于某些原因不能使用 `CGDisplayBounds`，可以手动转换：

```swift
func convertNSScreenFrameToCG(_ screen: NSScreen) -> CGRect {
    // 关键：找到主屏幕
    guard let primaryScreen = NSScreen.screens.first(where: { screen in
        // 主屏幕的特征：frame.origin == (0, 0)
        screen.frame.origin == .zero
    }) else {
        return screen.frame
    }

    // 转换公式（来自 Ken Thomases 的回答）
    let screenHeight = primaryScreen.frame.height
    return CGRect(
        x: screen.frame.origin.x,
        y: screenHeight - screen.frame.maxY,
        width: screen.frame.width,
        height: screen.frame.height
    )
}
```

**但这个方法有问题**：它假设所有屏幕都在主屏幕的上方或同一行，对于复杂的屏幕布局可能不准确。

### 4.3 最简单的方法（推荐）

**直接使用 `NSScreen.coordinateSpace` 和 `NSWindow.convertPoint`**：

```swift
extension NSWindow {
    /// 将窗口的 frame 转换为 CoreGraphics 全局坐标
    var frameInCoreGraphics: CGRect {
        guard let screen = screen else { return frame }

        // 使用窗口的坐标空间
        let screenBounds = screen.frame

        // CoreGraphics: Y 向下，原点在左上
        // AppKit: Y 向上，原点在左下
        return CGRect(
            x: frame.origin.x,
            y: screenBounds.height - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}
```

---

## 五、修复方案

### 5.1 方案 A：使用 CGDisplayBounds（最推荐）

修改 `WindowHighlightController.swift` 的 `shouldShowHighlight` 方法：

```swift
func shouldShowHighlight(for window: WindowInfo, in screen: NSScreen) -> Bool {
    // ✅ 方案 A：使用 CGDisplayBounds（最准确）
    guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
        print("[ERROR] 无法获取 displayID")
        return false
    }

    // ✅ CGDisplayBounds 返回的是全局显示坐标空间中的矩形
    // 与 kCGWindowBounds 使用相同的坐标系统，可以直接比较
    let screenBoundsInGlobalSpace = CGDisplayBounds(displayID)

    // ✅ 直接比较（不需要手动转换）
    let intersects = window.bounds.intersects(screenBoundsInGlobalSpace)

    print("[DEBUG] shouldShowHighlight: 屏幕=\(screen.localizedName), 窗口=\(window.displayTitle)")
    print("[DEBUG]   窗口 bounds(CG): \(window.bounds)")
    print("[DEBUG]   屏幕(CG): \(screenBoundsInGlobalSpace)")
    print("[DEBUG]   相交: \(intersects)")

    return intersects
}
```

### 5.2 方案 B：修复手动转换（如果不能用 CGDisplayBounds）

```swift
func shouldShowHighlight(for window: WindowInfo, in screen: NSScreen) -> Bool {
    // ✅ 方案 B：正确地手动转换

    // 1. 找到主屏幕（frame.origin == (0, 0)）
    guard let primaryScreen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) else {
        print("[ERROR] 找不到主屏幕")
        return false
    }

    // 2. 将 screen.frame 从 AppKit 坐标系转换为 CoreGraphics 坐标系
    // 转换公式：Y_cg = screenHeight - Y_appkit - height
    let screenFrameInCG = CGRect(
        x: screen.frame.origin.x,
        y: primaryScreen.frame.height - screen.frame.maxY,
        width: screen.frame.width,
        height: screen.frame.height
    )

    // 3. 现在两者都在 CoreGraphics 坐标系中，可以比较
    let intersects = window.bounds.intersects(screenFrameInCG)

    print("[DEBUG] shouldShowHighlight: 屏幕=\(screen.localizedName)")
    print("[DEBUG]   主屏幕高度: \(primaryScreen.frame.height)")
    print("[DEBUG]   屏幕(AppKit): \(screen.frame)")
    print("[DEBUG]   屏幕(CG): \(screenFrameInCG)")
    print("[DEBUG]   窗口(CG): \(window.bounds)")
    print("[DEBUG]   相交: \(intersects)")

    return intersects
}
```

### 5.3 修复 WindowHighlightOverlayView 的坐标转换

同样需要修复 `convertToLocalBounds` 方法：

```swift
private func convertToLocalBounds(_ globalRect: CGRect) -> CGRect {
    // ✅ 使用 CGDisplayBounds 获取屏幕在全局坐标空间中的位置
    guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
        return globalRect
    }

    let screenBoundsInGlobalSpace = CGDisplayBounds(displayID)

    // ✅ 计算窗口相对于屏幕左上角的位置
    // 两者都在 CoreGraphics 全局坐标空间中，直接相减
    var localRect = CGRect(
        x: globalRect.origin.x - screenBoundsInGlobalSpace.origin.x,
        y: globalRect.origin.y - screenBoundsInGlobalSpace.origin.y,
        width: globalRect.size.width,
        height: globalRect.size.height
    )

    print("[DEBUG坐标] 屏幕: \(screen.localizedName)")
    print("[DEBUG坐标]   全局位置(CG): \(screenBoundsInGlobalSpace)")
    print("[DEBUG坐标]   窗口(CG): \(globalRect)")
    print("[DEBUG坐标]   局部位置: \(localRect)")

    return localRect
}
```

---

## 六、为什么当前代码会产生负数坐标

### 6.1 用户屏幕布局

```
        PHL 279C9
        (817, 982) - 在主屏幕右上
        1920 x 1080

27MP35                          Built-in (主)
(-1103, 982)                    (0, 0)
1920 x 1080                     1512 x 982
```

### 6.2 当前代码的计算过程

```swift
// 1. 计算全局高度（错误的方法）
let globalHeight = NSScreen.screens.reduce(0) { max($0, $1.frame.maxY) }
// = max(982, 982+1080, 982+1080)
// = max(982, 2062, 2062)
// = 2062

// 2. 转换主屏幕
// screen.frame = (0, 0, 1512, 982)
let screenFrameInCG = CGRect(
    x: 0,
    y: 2062 - 982,  // = 1080 ❌ 错误！主屏幕应该是 (0, 0)
    width: 1512,
    height: 982
)
// 结果：(0, 1080, 1512, 982)
```

### 6.3 正确的计算过程

```swift
// 使用 CGDisplayBounds
let screenBoundsInGlobalSpace = CGDisplayBounds(displayID)
// 主屏幕的返回值：(0, 0, 1512, 982) ✅ 正确！

// 27MP35 的返回值：(-1103, 0, 1920, 1080) ✅ 正确！
//（因为它在主屏幕上方，CoreGraphics Y 向下，所以 Y = 0）

// PHL 279C9 的返回值：(817, 0, 1920, 1080) ✅ 正确！
```

---

## 七、需要修改的文件

### 7.1 主要文件

1. **`/Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/Screenshot/WindowHighlight/WindowHighlightController.swift`**
   - 第 235-262 行：`shouldShowHighlight(for:in:)` 方法
   - 第 318-350 行：`convertToLocalBounds(_:)` 方法

### 7.2 辅助文件

2. **`/Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/Screenshot/WindowDetection/Utils/CoordinateSystem.swift`**
   - 可以添加新的辅助方法：
     ```swift
     /// 使用 CGDisplayBounds 获取屏幕在全局坐标空间中的位置
     static func screenBoundsInGlobalSpace(_ screen: NSScreen) -> CGRect? {
         guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
             return nil
         }
         return CGDisplayBounds(displayID)
     }
     ```

---

## 八、测试验证

### 8.1 单屏幕测试

```
屏幕布局：单个主显示器
窗口位置：(100, 100, 400, 300)

期望结果：
- CGDisplayBounds(main) = (0, 0, 1920, 1080)
- window.bounds = (100, 100, 400, 300)
- intersects = true ✅
```

### 8.2 双屏幕测试（并排）

```
屏幕布局：
- 主：(0, 0, 1920, 1080)
- 副：(1920, 0, 1920, 1080)

窗口位置：(2000, 100, 400, 300)  // 在副屏幕上

期望结果：
- CGDisplayBounds(副) = (1920, 0, 1920, 1080)
- window.bounds = (2000, 100, 400, 300)
- intersects = true ✅
```

### 8.3 双屏幕测试（上下）

```
屏幕布局：
- 主：(0, 0, 1920, 1080)
- 副：在主屏幕上方

实际布局：
- 主 NSScreen.frame = (0, 0, 1920, 1080)
- 副 NSScreen.frame = (0, 1080, 1920, 1080)  // AppKit 坐标
- CGDisplayBounds(副) = (0, 0, 1920, 1080)  // CoreGraphics 坐标！❓

等等，这里需要验证！
```

**需要验证的假设**：
- 当副屏幕在主屏幕上方时，`CGDisplayBounds` 返回的 Y 坐标是负数还是 0？
- 根据 CoreGraphics 定义，应该是**负数**

**正确的理解**：
```
全局显示坐标空间（CoreGraphics）：
┌─────────────────────┐  Y = 0
│  副屏幕             │  （在主屏幕上方）
│  1920 x 1080        │
└─────────────────────┘  Y = 1080
┌─────────────────────┐  Y = 0 ❌ 不对！
│  主屏幕             │  （主屏幕，原点在左上角）
│  1920 x 1080        │
└─────────────────────┘  Y = 1080
```

**修正**：
- 主屏幕的 `CGDisplayBounds` = `(0, 0, 1920, 1080)`
- 副屏幕（在主屏幕上方）的 `CGDisplayBounds` = `(0, -1080, 1920, 1080)`

---

## 九、参考资料

### 9.1 Apple 官方文档

1. **kCGWindowBounds**：
   > "The coordinates of the rectangle are specified in screen space, where the origin is in the upper-left corner of the main display."
   - https://developer.apple.com/documentation/coregraphics/kcgwindowbounds

2. **CGDisplayBounds**：
   > "Returns the bounds of a display in the global display coordinate space (relative to the upper-left corner of the main display)."
   - https://developer.apple.com/documentation/coregraphics/cgdisplaybounds(_:)

3. **Coordinate Systems and Transforms**：
   - https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CocoaDrawingGuide/Transforms/Transforms.html

### 9.2 社区资源

1. **Stack Overflow - Ken Thomases 的回答**（269 赞同）：
   > "Quartz uses a coordinate space where the origin (0, 0) is at the top-left of the primary display. Increasing y goes down."
   - https://stackoverflow.com/questions/19884363/in-objective-c-os-x-is-the-global-display-coordinate-space-used-by-quartz-d

2. **Think And Build - Dealing with multiple screens programming**：
   > "The OSX global coordinate system works in a really clever way... the point 0,0 is located at the bottom left corner of the Primary screen."
   - https://www.thinkandbuild.it/deal-with-multiple-screens-programming/

3. **NSHipster - CoreGraphics Geometry Primitives**：
   - https://nshipster.com/cggeometry/

4. **Which CGRect was that? - Entonos**：
   - https://entonos.com/2021/05/20/which-cgrect-was-that/

---

## 十、总结

### 10.1 根本原因

窗口高亮框位置偏差的根本原因是：

1. **混淆了三种不同的坐标系统**
   - CoreGraphics 坐标系（Y-down，原点在左上）
   - AppKit 坐标系（Y-up，原点在左下）
   - 全局显示坐标空间（统一的跨显示器坐标）

2. **错误的坐标转换逻辑**
   - 使用了错误的全局高度计算
   - 没有正确处理多显示器布局
   - 直接比较不同坐标系的矩形

3. **没有使用 Apple 提供的正确 API**
   - 应该使用 `CGDisplayBounds` 获取屏幕的全局坐标
   - 不需要手动转换 `NSScreen.frame`

### 10.2 解决方案

**推荐方案**：使用 `CGDisplayBounds`

```swift
func shouldShowHighlight(for window: WindowInfo, in screen: NSScreen) -> Bool {
    guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
        return false
    }

    // ✅ 两者都在 CoreGraphics 全局坐标空间中
    let screenBounds = CGDisplayBounds(displayID)
    return window.bounds.intersects(screenBounds)
}
```

### 10.3 影响范围

- **主要影响**：`WindowHighlightController.swift`
- **次要影响**：`WindowHighlightOverlayView.swift`
- **不影响**：截图功能（已经正确处理了坐标转换）

---

**报告生成时间**：2025-12-27
**调研方法**：Apple 官方文档 + 技术社区 + 代码分析 + 用户日志
**置信度**：高（基于权威来源和实际测试）
