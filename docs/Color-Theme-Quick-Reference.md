# Color Theme Quick Reference

> 颜色主题快速参考指南 - 给 Claude/Trae 使用

---

## 快速查找

### 背景颜色

| 常量 | 用途 | 对应值 |
|-----|------|-------|
| `Color.themeBackground` | 主背景 | gray-900/90 |
| `Color.themeCard` | 卡片背景 | white/5 |
| `Color.themePanel` | 面板背景 | black/20 |
| `Color.themeInput` | 输入框背景 | black/40 |

### 文字颜色

| 常量 | 用途 | 对应值 |
|-----|------|-------|
| `Color.themeTextPrimary` | 主要文字 | gray-200 |
| `Color.themeTextSecondary` | 次要文字 | gray-300 |
| `Color.themeTextTertiary` | 第三级文字 | gray-400 |

### 阴影颜色

| 常量 | 用途 | 对应值 |
|-----|------|-------|
| `Color.themeShadowLight` | 轻阴影 | black.opacity(0.1) |
| `Color.themeShadowMedium` | 中等阴影 | black.opacity(0.2) |
| `Color.themeShadowHeavy` | 重阴影 | black.opacity(0.3) |
| `Color.themeShadowBall` | 浮球阴影 | black.opacity(0.4) |
| `Color.themeShadowBlue` | 蓝色发光 | blue-600.opacity(0.3) |

### 交互状态

| 常量 | 用途 | 对应值 |
|-----|------|-------|
| `Color.themeHoverLight` | 轻微高亮 | white.opacity(0.05) |
| `Color.themeHoverMedium` | 中等高亮 | white.opacity(0.1) |
| `Color.themeSelected` | 选中状态 | blue-600 |
| `Color.themeActive` | 激活状态 | blue-500.opacity(0.2) |
| `Color.themeFocused` | 聚焦状态 | blue-500.opacity(0.3) |

### 状态指示

| 常量 | 用途 | 对应值 |
|-----|------|-------|
| `Color.themeStatusSuccess` | 成功 | green-500 |
| `Color.themeStatusError` | 错误 | red-500 |
| `Color.themeStatusWarning` | 警告 | yellow-500 |
| `Color.themeStatusLoading` | 加载中 | purple-500 |
| `Color.themeStatusPending` | 处理中 | purple-500.opacity(0.7) |

### 边框颜色

| 常量 | 用途 | 对应值 |
|-----|------|-------|
| `Color.themeBorder` | 主边框 | white/10 |
| `Color.themeBorderSubtle` | 次要边框 | white/5 |

---

## 常见用法

### 卡片样式

```swift
.background(Color.themeCard)
.cornerRadius(8)
.overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeBorder, lineWidth: 1))
.shadow(color: Color.themeShadowMedium, radius: 10, x: 0, y: 2)
```

### 按钮悬停

```swift
.background(hovering ? Color.themeHoverMedium : Color.themeHoverLight)
```

### 选中状态

```swift
.background(isSelected ? Color.themeSelected : Color.themeCard)
.overlay(
    RoundedRectangle(cornerRadius: 8)
        .stroke(isSelected ? Color.themeSelected : Color.themeBorder, lineWidth: 1)
)
```

### 输入框聚焦

```swift
.background(Color.themeInput)
.overlay(
    RoundedRectangle(cornerRadius: 4)
        .stroke(isFocused ? Color.themeFocused : Color.themeBorder, lineWidth: 1)
)
```

### 状态指示

```swift
.foregroundColor(status == "success" ? Color.themeStatusSuccess :
                 status == "error" ? Color.themeStatusError :
                 status == "loading" ? Color.themeStatusLoading :
                 Color.themeTextPrimary)
```

---

## 不推荐用法

### ❌ 不要这样用

```swift
// 硬编码 RGB 值
.background(Color(red: 17/255, green: 24/255, blue: 39/255))

// 内联透明度计算
.background(Color.white.opacity(0.05))
.shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 2)

// 使用具体色值而非语义化颜色
.foregroundColor(Color.themeGray200)
```

### ✅ 应该这样用

```swift
// 使用语义化颜色
.background(Color.themeBackground)
.background(Color.themeCard)
.shadow(color: Color.themeShadowMedium, radius: 10, x: 0, y: 2)
.foregroundColor(Color.themeTextPrimary)
```

---

## 添加新颜色

如果需要添加新的颜色常量，按以下优先级：

1. **语义化颜色** - `themeXXX`（如 `themeTooltip`）
2. **状态颜色** - `themeStatusXXX`（如 `themeStatusDisabled`）
3. **具体色阶** - `themeXXX500`（如 `themeOrange500`）

在 `Sources/QuiteNote/UI/Theme/Color+Theme.swift` 中添加，遵循现有结构。
