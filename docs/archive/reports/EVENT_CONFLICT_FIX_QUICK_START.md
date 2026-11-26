# 快速修复指南

## 问题摘要

1. **鼠标悬停不显示高亮** - 必须点击窗口才显示蓝色边框
2. **拖拽被识别为点击** - 按下移动鼠标时，应该是框选，但被识别为点击

## 最快修复方案（5 分钟）

### 方案：组合方案 B + C

**核心改动：**
1. 在窗口交互区域添加 `simultaneousGesture`
2. 调整 `DragGesture` 的 `minimumDistance` 和判断阈值

### 步骤 1：修改 buildWindowInteractionArea

打开文件：`Sources/QuiteNote/UI/ScreenshotV2/Views/V2WindowHighlightView.swift`

找到方法 `buildWindowInteractionArea`（第 409-427 行），替换为：

```swift
// ⚠️ 辅助：窗口交互区域（使用 simultaneousGesture 让事件穿透）
private func buildWindowInteractionArea(for window: WindowInfo, localFrame: CGRect) -> some View {
    Color.clear
        .contentShape(Rectangle())
        .frame(width: localFrame.width, height: localFrame.height)
        .position(x: localFrame.midX, y: localFrame.midY)
        // ⚠️ 关键修复：添加 simultaneousGesture 让拖拽事件穿透到父视图
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // 空实现：让事件继续传递到根视图的 DragGesture
                    print("[EVENT] 窗口区域 DragGesture onChanged - 事件穿透: \(window.displayTitle)")
                }
                .onEnded { value in
                    // 空实现：让事件继续传递到根视图的 DragGesture
                    print("[EVENT] 窗口区域 DragGesture onEnded - 事件穿透: \(window.displayTitle)")
                }
        )
        .onHover { hovering in
            print("[EVENT] onHover 触发 - 窗口: \(window.displayTitle), hovering: \(hovering)")
            if hovering {
                print("[EVENT] 窗口悬停开始: \(window.displayTitle)")
                onHoverWindow(window)
                hoveredWindow = window
            } else if hoveredWindow?.id == window.id {
                print("[EVENT] 窗口悬停结束: \(window.displayTitle)")
                onHoverWindow(nil)
                hoveredWindow = nil
            }
        }
}
```

### 步骤 2：修改 buildDragGesture

找到方法 `buildDragGesture`（第 222-260 行），替换为：

```swift
// ⚠️ 拖拽手势（调整 minimumDistance，减少误触发）
private func buildDragGesture() -> some Gesture {
    DragGesture(minimumDistance: 5)  // ⚠️ 修改：从 0 改为 5，减少敏感度
        .onChanged { value in
            // 开始拖拽
            if dragStartPoint == nil {
                dragStartPoint = value.startLocation
                print("[EVENT] DragGesture onChanged - 开始拖拽: \(value.startLocation)")
            }
            dragCurrentPoint = value.location
            let distance = dragStartPoint.map { start in
                sqrt(pow(value.location.x - start.x, 2) + pow(value.location.y - start.y, 2))
            } ?? 0
            print("[EVENT] DragGesture onChanged - 移动到: \(value.location), 距离: \(distance)")
        }
        .onEnded { value in
            guard let start = dragStartPoint, let end = dragCurrentPoint else {
                print("[EVENT] DragGesture onEnded - 无起点或终点，忽略")
                dragStartPoint = nil
                dragCurrentPoint = nil
                return
            }

            let distance = sqrt(pow(end.x - start.x, 2) + pow(end.y - start.y, 2))
            print("[EVENT] DragGesture onEnded - 总距离: \(distance)")

            // ⚠️ 修改：从 5 改为 10，提高判断阈值
            if distance < 10 {
                // 距离 < 10：认为是点击
                print("[EVENT] 识别为点击事件，距离: \(distance)")
                handleTap(at: start)
            } else {
                // 距离 >= 10：认为是框选
                print("[EVENT] 识别为框选事件，距离: \(distance)")
                handleDragSelection(start: start, end: end)
            }

            dragStartPoint = nil
            dragCurrentPoint = nil
        }
}
```

### 步骤 3：构建和测试

```bash
# 构建应用
./build-app.sh

# 运行应用
open build/QuiteNote.app
```

### 步骤 4：验证修复

1. **测试悬停**
   - ✅ 移动鼠标到窗口上，立即显示蓝色边框
   - ✅ 控制台输出：`[EVENT] onHover 触发`

2. **测试点击**
   - ✅ 点击窗口（不移动），选中窗口
   - ✅ 控制台输出：`[EVENT] 识别为点击事件`

3. **测试拖拽**
   - ✅ 在窗口上按下并移动（> 10 像素），显示拖拽框
   - ✅ 控制台输出：`[EVENT] 识别为框选事件`

4. **测试空白区域**
   - ✅ 在空白处拖拽，正常框选

## 如果还有问题

### 问题 1：悬停仍然不工作

**可能原因：** 蒙层的 ZStack 挖孔区域阻挡了事件

**解决方案：** 使用方案 A（.mask()）

参考文件：`Sources/QuiteNote/UI/ScreenshotV2/Fixes/V2WindowHighlightView_FixA_UseMaskModifier.swift`

### 问题 2：拖拽仍然误识别为点击

**可能原因：** `minimumDistance: 5` 仍然太敏感

**解决方案：** 进一步调整参数

```swift
DragGesture(minimumDistance: 10)  // 提高到 10

// 判断阈值也相应提高
if distance < 15 {
    // 点击
} else {
    // 框选
}
```

### 问题 3：性能问题

**可能原因：** 多个 DragGesture 同时工作

**解决方案：**
- 移除窗口区域的 `simultaneousGesture`
- 改用方案 A（.mask()）

## 回滚方案

如果修复后问题更严重，可以快速回滚：

```bash
# 查看修改
git diff Sources/QuiteNote/UI/ScreenshotV2/Views/V2WindowHighlightView.swift

# 回滚修改
git checkout Sources/QuiteNote/UI/ScreenshotV2/Views/V2WindowHighlightView.swift

# 重新构建
./build-app.sh
```

## 调试日志说明

添加的调试日志会输出以下信息：

- `[EVENT] onHover 触发` - 鼠标悬停触发
- `[EVENT] DragGesture onChanged` - 拖拽移动
- `[EVENT] DragGesture onEnded` - 拖拽结束
- `[EVENT] 识别为点击/框选事件` - 事件识别结果

**使用技巧：**
1. 打开终端，运行应用查看日志
2. 执行各种操作（悬停、点击、拖拽）
3. 观察日志输出，确认事件流
4. 如果某个事件没有触发，说明被拦截了

## 下一步

修复成功后：
1. 移除调试日志（或改为 Logger）
2. 进行完整的功能测试
3. 提交代码

参考文件：`EVENT_CONFLICT_DIAGNOSTIC_REPORT.md`（完整诊断报告）
