# 截图蒙层不显示问题诊断报告

## 问题现象

- ✅ 屏幕录制权限已授权（"Quite Note Dev" 开关是蓝色）
- ❌ 按 `⌘⇧S` 后屏幕**没有变暗**（没有蒙层）
- ✅ 偶尔出现**蓝色框**（窗口高亮）

---

## 根本原因分析

### 1. **蒙层显示逻辑依赖 `localBoundsList.isEmpty`**

在 `V2WindowHighlightView.swift` 的第 179 行：

```swift
} else if localBoundsList.isEmpty {
    // 无权限或无窗口：主屏幕 0.5，其他屏幕 0.8
    Color.black.opacity(isCurrentlyPrimary ? 0.5 : 0.8)
        .allowsHitTesting(false)
} else {
    // 有权限：窗口区域透明，其他区域根据主屏幕状态显示不同透明度
    Color.black.opacity(isCurrentlyPrimary ? 0.5 : 0.8)
        .mask({
            MultiWindowShape(localWindows: localBoundsList)
                .fill(Color.white)
                .blendMode(.destinationOut)
        })
        .allowsHitTesting(false)
}
```

**关键问题**：
- 如果 `localBoundsList` **不为空**，蒙层使用 `.mask()` 修饰符
- `.mask()` 使用 `.destinationOut` 混合模式，会**挖空**窗口区域
- 但如果窗口坐标转换错误或过滤逻辑太严格，`localBoundsList` 可能为**空数组**
- **空数组 ≠ isEmpty**（Swift 中空数组 `[]` 和 `.isEmpty` 是等价的，但问题可能在其他地方）

### 2. **窗口过滤逻辑可能过于严格**

在 `V2WindowHighlightView.swift` 的第 54-98 行：

```swift
// ⚠️ 先按屏幕过滤，再按应用分组，计算每个应用的包围盒
let windowsOnThisScreen = allWindows.filter { window in
    // 获取窗口中心点（CoreGraphics 坐标）
    let windowCenter = CGPoint(
        x: window.bounds.midX,
        y: window.bounds.midY
    )

    // 判断中心点是否在当前屏幕范围内（CoreGraphics 坐标）
    return cgScreenBounds.contains(windowCenter)
}

// ⚠️ 应用过滤条件
let filtered = windowsOnThisScreen.filter { window in
    // ⚠️ 放宽过滤条件（参考专家建议）
    // 只过滤明显的小窗口（100x50而不是200x200）
    if window.bounds.width < 100 || window.bounds.height < 50 {
        return false
    }

    // 过滤系统窗口（精确匹配而不是contains）
    let systemOwners: Set<String> = ["Window Server", "程序坞", "墙纸", "通知中心", "WindowManager", "Dock"]
    if systemOwners.contains(window.ownerName) {
        return false
    }

    // 过滤壁纸和桌面
    if let name = window.windowName {
        if name.contains("Desktop") || name.contains("Wallpaper") || name.contains("Backdrop") || name.contains("Menubar") {
            return false
        }
    }

    return true
}
```

**可能的问题**：
1. **坐标系统不匹配**：`window.bounds` 使用 CoreGraphics 坐标，`cgScreenBounds` 也使用 CoreGraphics 坐标，但转换可能有bug
2. **屏幕边界判断错误**：多屏幕环境下，屏幕边界计算可能不正确
3. **窗口全部被过滤**：过滤条件可能把所有窗口都过滤掉了

### 3. **面板配置问题**

在 `V2ScreenSelectionController.swift` 的第 185-236 行：

```swift
let panel = NSPanel(
    contentRect: screenFrame,
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)

// 面板配置
panel.level = .floating
panel.backgroundColor = .clear
panel.isOpaque = false
panel.ignoresMouseEvents = false
panel.isMovable = false
panel.hidesOnDeactivate = false
panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
```

**配置看起来正确**，但需要验证：
- 面板是否真的显示在最上层？
- 面板的 frame 是否正确设置为屏幕大小？

### 4. **权限检查时机问题**

在 `V2ScreenSelectionController.swift` 的第 70-76 行：

```swift
// 2. 获取所有窗口信息（使用现有的 WindowInfoService）
switch WindowInfoService.shared.fetchAllWindows() {
case .success(let windows):
    allWindows = windows
case .failure:
    allWindows = []
}
```

**关键问题**：
- 如果 `fetchAllWindows()` 返回 `.failure`（权限被拒绝），`allWindows` 会被设为 `[]`
- **但用户说权限已经授权了**，所以问题不在这里
- 但**可能在其他地方权限检查失败**，比如 `CGPreflightScreenCaptureAccess()` 返回 `false`

---

## 诊断步骤

### 步骤 1: 检查日志输出

运行应用并按 `⌘⇧S`，查看控制台输出：

```bash
# 应该看到这些日志
[V2CaptureController] ========== 开始 V2 静态截图流程 ==========
[V2ScreenCaptureService] ========== 屏幕信息 ==========
[V2ScreenSelectionController] 显示屏幕/窗口选择界面
[V2WindowHighlightView] 屏幕: XXX, 总窗口数: XXX
[V2WindowHighlightView] 屏幕内窗口数: XXX
[V2WindowHighlightView] 过滤后窗口数: XXX
```

**关键问题**：
- 如果 "过滤后窗口数" 是 **0**，说明所有窗口都被过滤了
- 如果 "屏幕内窗口数" 是 **0**，说明坐标转换有问题
- 如果 "总窗口数" 是 **0**，说明权限检查失败

### 步骤 2: 验证权限

在 `V2ScreenCaptureService.swift` 的 `captureScreenSync` 方法中添加日志：

```swift
private func captureScreenSync(_ screen: NSScreen) -> NSImage? {
    // ⚠️ 添加权限检查
    let hasPermission = CGPreflightScreenCaptureAccess()
    print("[V2ScreenCaptureService] 权限检查: \(hasPermission)")

    guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
        logger.error("无法获取 Display ID for \(screen.localizedName)")
        return nil
    }

    // 使用 CGDisplayCreateImage 截图
    guard let cgImage = CGDisplayCreateImage(displayID) else {
        logger.error("CGDisplayCreateImage 失败 for display \(displayID)")
        return nil
    }

    // 转换为 NSImage
    return NSImage(cgImage: cgImage, size: screen.frame.size)
}
```

### 步骤 3: 验证蒙层渲染

在 `V2WindowHighlightView.swift` 的 `body` 计算属性中添加日志：

```swift
var body: some View {
    // 性能优化：一次性计算所有需要的值，避免重复计算
    let windowsOnScreen = self.windowsOnScreen

    // ⚠️ 添加调试日志
    print("[V2WindowHighlightView] body 被调用")
    print("  windowsOnScreen.count: \(windowsOnScreen.count)")
    print("  localBoundsList.isEmpty: \(localBoundsList.isEmpty)")
    print("  isCurrentlyPrimary: \(isCurrentlyPrimary)")

    // ...
}
```

---

## 最小化测试代码

创建一个最简单的蒙层测试，排除窗口识别逻辑的影响：

```swift
import AppKit
import SwiftUI

class SimpleMaskTest {
    func showMask() {
        guard let screen = NSScreen.main else { return }

        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false

        let view = NSView(frame: screen.frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor

        panel.contentView = view
        panel.orderFrontRegardless()

        print("[SimpleMaskTest] 蒙层应该显示在屏幕上")
        print("  按 ESC 关闭")

        // 5秒后自动关闭
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            panel.close()
        }
    }
}
```

**测试步骤**：
1. 在 `startV2Screenshot()` 方法开头调用 `SimpleMaskTest().showMask()`
2. 运行应用并按 `⌘⇧S`
3. 如果蒙层显示，说明权限和面板配置都没问题
4. 如果蒙层不显示，说明权限或面板配置有问题

---

## 修复方案

### 方案 A: 快速修复（最小改动）

**假设**：问题是 `localBoundsList.isEmpty` 判断逻辑有误，导致蒙层条件分支不正确。

**修复**：在 `V2WindowHighlightView.swift` 的第 179 行，修改蒙层逻辑：

```swift
// ⚠️ 修复：简化逻辑，总是显示蒙层
let maskOverlay = Group {
    if isDragging {
        // 拖拽时：完全透明
        Color.clear
    } else if localBoundsList.isEmpty {
        // 无窗口：显示纯黑色蒙层
        Color.black.opacity(0.5)
            .allowsHitTesting(false)
    } else {
        // 有窗口：使用 mask 挖空窗口区域
        Color.black.opacity(0.5)
            .mask({
                MultiWindowShape(localWindows: localBoundsList)
                    .fill(Color.white)
                    .blendMode(.destinationOut)
            })
            .allowsHitTesting(false)
    }
}
```

**关键改动**：
- 移除 `isCurrentlyPrimary` 的判断，暂时简化逻辑
- 固定透明度为 0.5，不区分主屏幕和次屏幕

### 方案 B: 中等修复（调试日志）

**假设**：问题是窗口过滤逻辑太严格或坐标转换错误。

**修复**：
1. 在 `V2WindowHighlightView.swift` 的 `windowsOnScreen` 计算属性中添加详细日志
2. 临时放宽过滤条件，保留所有窗口
3. 在 `body` 中添加蒙层显示状态的日志

**具体修改**：

```swift
/// 过滤出在当前屏幕上的窗口
private var windowsOnScreen: [WindowInfo] {
    guard let cgScreenBounds = V2ScreenCaptureService.shared.getScreenBounds(screen) else {
        print("[V2WindowHighlightView] ⚠️ 无法获取屏幕边界")
        return []
    }

    print("[V2WindowHighlightView] 屏幕: \(screen.localizedName), 总窗口数: \(allWindows.count)")
    print("[V2WindowHighlightView] 屏幕边界(CG): \(cgScreenBounds)")

    // ⚠️ 临时修复：不过滤任何窗口，保留所有窗口
    let windowsOnThisScreen = allWindows.filter { window in
        let windowCenter = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
        let contains = cgScreenBounds.contains(windowCenter)
        if !contains {
            print("  ❌ 窗口 \(window.displayTitle) 不在屏幕内，中心点: \(windowCenter)")
        }
        return contains
    }

    print("[V2WindowHighlightView] 屏幕内窗口数: \(windowsOnThisScreen.count)")

    // ⚠️ 临时修复：只过滤明显的小窗口
    let filtered = windowsOnThisScreen.filter { window in
        if window.bounds.width < 10 || window.bounds.height < 10 {
            print("  ❌ 过滤小窗口: \(window.displayTitle), 尺寸: \(window.bounds.width) x \(window.bounds.height)")
            return false
        }
        return true
    }

    print("[V2WindowHighlightView] 过滤后窗口数: \(filtered.count)")
    for window in filtered {
        print("  ✓ \(window.displayTitle) (\(window.ownerName)), bounds: \(window.bounds)")
    }

    return filtered
}
```

### 方案 C: 根本修复（重构坐标系统）

**假设**：问题是多屏幕坐标系统不一致，CoreGraphics 坐标和 AppKit 坐标混淆。

**修复**：
1. 统一使用 CoreGraphics 坐标（全局坐标）
2. 在显示视图时再转换为局部坐标
3. 添加详细的坐标转换日志

**这个方案需要更多时间，建议先尝试方案 A 或 B。**

---

## 测试验证

### 验证步骤

1. **应用快速修复（方案 A）**
   - 重新编译应用：`./build-app.sh`
   - 运行应用并按 `⌘⇧S`
   - 检查屏幕是否变暗

2. **查看日志**
   - 打开 Console.app，过滤 "Quite Note"
   - 查找 `[V2WindowHighlightView]` 和 `[V2ScreenCaptureService]` 日志
   - 检查 "过滤后窗口数" 是否 > 0

3. **多屏幕测试**
   - 如果有多个显示器，测试鼠标移动到不同屏幕
   - 检查蒙层是否正确切换

4. **降级测试**
   - 如果修复后仍然无效，运行 `SimpleMaskTest` 测试
   - 如果简单蒙层也不显示，说明是权限或面板配置问题
   - 如果简单蒙层显示，说明是窗口识别逻辑问题

---

## 下一步行动

1. ✅ 先应用 **方案 A**（快速修复），验证蒙层是否显示
2. 如果方案 A 无效，应用 **方案 B**（添加调试日志），分析根本原因
3. 根据日志输出，决定是否需要 **方案 C**（重构坐标系统）
4. 如果简单蒙层测试也失败，检查系统权限设置

---

## 需要用户提供的信息

1. 运行应用后，Console.app 中的完整日志输出
2. 是否有多个显示器？
3. "Quite Note Dev" 在屏幕录制权限中是否真的开启了？
4. 尝试关闭权限开关，等待 2 秒，再重新开启，重启应用，问题是否解决？
