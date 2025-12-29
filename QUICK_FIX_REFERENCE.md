# 截图蒙层问题 - 快速修复参考卡

## 🚀 快速开始（3分钟）

```bash
cd /Users/xuyingzhou/Project/study-mac-app/quite-note
./test-screenshot-darkness.sh
# 然后按 ⌘⇧S 测试
```

---

## 🔍 问题诊断

### 现象
- ❌ 按 `⌘⇧S` 后屏幕没有变暗（没有蒙层）
- ✅ 偶尔出现蓝色框（窗口高亮）

### 可能原因
1. **蒙层显示条件判断问题**（60%）- `isCurrentlyPrimary` 动态判断有误
2. **窗口过滤逻辑过于严格**（30%）- 所有窗口都被过滤了
3. **权限或面板配置问题**（10%）- `CGPreflightScreenCaptureAccess()` 返回 false

---

## ⚡️ 快速修复（方案 A）

### 修改文件
`V2WindowHighlightView.swift`（第 174-193 行）

### 核心改动
```swift
// 原代码
Color.black.opacity(isCurrentlyPrimary ? 0.5 : 0.8)

// 修复后
Color.black.opacity(0.5)
```

### 完整代码
```swift
let maskOverlay = Group {
    if isDragging {
        Color.clear
    } else if localBoundsList.isEmpty {
        Color.black.opacity(0.5)
            .allowsHitTesting(false)
    } else {
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

### 测试
```bash
./build-app.sh
open "Quite Note Dev.app"
# 按 ⌘⇧S 测试
```

---

## 🔧 调试修复（方案 B）

### 适用场景
方案 A 无效时使用

### 修改位置
`V2WindowHighlightView.swift`（第 46-99 行）

### 核心改动
```swift
private var windowsOnScreen: [WindowInfo] {
    // ⚠️ 放宽过滤条件（10x10 而不是 100x50）
    let filtered = windowsOnThisScreen.filter { window in
        if window.bounds.width < 10 || window.bounds.height < 10 {
            print("  ❌ 过滤掉: '\(window.displayTitle)' - 尺寸太小")
            return false
        }

        print("  ✓ 通过过滤: '\(window.displayTitle)'")
        return true
    }

    return filtered
}
```

### 查看日志
```bash
# 打开 Console.app，过滤 "Quite Note"
# 查找 "[V2WindowHighlightView] 过滤后窗口数: X"
```

---

## 🔧 权限重置（方案 C）

### 适用场景
简单蒙层测试也看不到时使用

### 操作
```bash
# 1. 关闭应用
killall Quite\ Note\ Dev

# 2. 重置权限
tccutil reset ScreenCapture com.quitenote.app.dev

# 3. 重新授权
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

# 4. 重启应用
./build-app.sh
open "Quite Note Dev.app"
```

---

## 📊 判断标准

### 简单蒙层测试
- ✅ **看到蒙层** → 权限正常，继续方案 A
- ❌ **看不到蒙层** → 权限问题，使用方案 C

### 窗口识别蒙层
- ✅ **看到蒙层** → 问题解决！
- ❌ **看不到蒙层** → 继续方案 B

### 日志分析
- "总窗口数" = 0 → 权限检查失败
- "屏幕内窗口数" = 0 → 坐标转换问题
- "过滤后窗口数" = 0 → 过滤条件太严格

---

## 📁 相关文件

### 诊断工具
- `SimpleMaskTest.swift` - 简单蒙层测试
- `test-screenshot-darkness.sh` - 自动化测试脚本

### 修复方案
- `V2WindowHighlightView_FixA.swift` - 快速修复代码
- `V2WindowHighlightView_FixB.swift` - 调试修复代码

### 文档
- `SCREENSHOT_DARKNESS_SUMMARY.md` - 完整报告
- `SCREENSHOT_FIX_GUIDE.md` - 详细指南
- `SCREENSHOT_DARKNESS_DEBUG_REPORT.md` - 问题分析

---

## 🆘 需要反馈

如果所有方案都无效，请提供：

1. **Console.app 的完整日志**
   - 从 "开始 V2 静态截图流程" 到结束
   - 包含 `[V2WindowHighlightView]` 和 `[SimpleMaskTest]` 的所有日志

2. **测试结果**
   - 简单蒙层测试是否显示？
   - 窗口识别蒙层是否显示？

3. **环境信息**
   - 屏幕配置（有几个显示器？分辨率？）
   - 权限状态截图
   - macOS 版本：`sw_vers`

---

## ✅ 成功标准

- ✅ 屏幕变暗（显示蒙层）
- ✅ 窗口区域透明（显示下方窗口）
- ✅ 非窗口区域半透明黑色
- ✅ 鼠标悬停显示蓝色高亮框
- ✅ 多屏幕切换流畅

---

**最后更新**: 2025-12-28
**预计修复时间**: 5-30 分钟
