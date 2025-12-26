项目的主题是 Quite Note，一个基于 SwiftUI 的 macOS 应用，用于记录和管理个人或团队的任务、事件、笔记等。
UI theme 主题

动效主题 /Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/Theme/Animation+Theme.swift
颜色主题 /Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/Theme/Color+Theme.swift
字体主题 /Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/Theme/Font+Theme.swift
形状主题 /Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/Theme/Shape+Theme.swift
间距主题 /Users/xuyingzhou/Project/study-mac-app/quite-note/Sources/QuiteNote/UI/Theme/Spacing+Theme.swift

统一在这里实现，需要的可以直接引用，缺失的可以在主题文件里面拓展，严禁在项目代码里面直接实现。

---

## 颜色使用规范

### 基本规则

1. **主题文件位置**: `Sources/QuiteNote/UI/Theme/Color+Theme.swift`
2. **严禁硬编码**: 禁止在视图代码中直接使用 RGB 值（如 `Color(red: 17/255, green: 24/255, blue: 39/255)`）
3. **严禁内联透明度**: 禁止在视图代码中直接使用 `.opacity()` 计算透明度（如 `Color.white.opacity(0.05)`）
4. **优先语义化**: 优先使用语义化颜色（如 `themeBackground`, `themeTextPrimary`）而非具体色值
5. **集中管理**: 所有颜色定义必须在 `Color+Theme.swift` 中

### 可用的颜色类型

#### 语义化颜色（优先使用）

```swift
// 背景颜色
Color.themeBackground      // 主背景 (bg-gray-900/90)
Color.themeCard            // 卡片背景 (bg-white/5)
Color.themePanel           // 面板背景 (bg-black/20)
Color.themeInput           // 输入框背景 (bg-black/40)

// 文字颜色
Color.themeTextPrimary     // 主要文字 (text-gray-200)
Color.themeTextSecondary   // 次要文字 (text-gray-300)
Color.themeTextTertiary    // 第三级文字 (text-gray-400)

// 边框颜色
Color.themeBorder          // 主边框 (border-white/10)
Color.themeBorderSubtle    // 次要边框 (border-white/5)
```

#### 阴影颜色

```swift
Color.themeShadowLight     // 轻阴影 (black.opacity(0.1))
Color.themeShadowMedium    // 中等阴影 (black.opacity(0.2))
Color.themeShadowHeavy     // 重阴影 (black.opacity(0.3))
Color.themeShadowBall      // 浮球阴影 (black.opacity(0.4))
Color.themeShadowBlue      // 蓝色发光 (blue-600.opacity(0.3))
Color.themeShadowPurple    // 紫色发光 (purple-500.opacity(0.3))
```

#### 交互状态颜色

```swift
Color.themeHoverLight      // 轻微高亮 (white.opacity(0.05))
Color.themeHoverMedium     // 中等高亮 (white.opacity(0.1))
Color.themeHoverStrong     // 强烈高亮 (white.opacity(0.15))
Color.themeSelected        // 选中状态 (blue-600)
Color.themeActive          // 激活状态 (blue-500.opacity(0.2))
Color.themeFocused         // 聚焦状态 (blue-500.opacity(0.3))
```

#### 状态指示颜色

```swift
Color.themeStatusIdle      // 空闲 (blue-400.opacity(0.7))
Color.themeStatusLoading   // 加载中 (purple-500)
Color.themeStatusSuccess   // 成功 (green-500)
Color.themeStatusWarning   // 警告 (yellow-500)
Color.themeStatusError     // 错误 (red-500)
Color.themeStatusPending   // 处理中 (purple-500.opacity(0.7))
```

### 正确用法示例

```swift
// ✅ 背景颜色
.background(Color.themeBackground)
.background(Color.themeCard)

// ✅ 阴影
.shadow(color: Color.themeShadowMedium, radius: 10, x: 0, y: 2)

// ✅ 悬停状态
.background(hovering ? Color.themeHoverMedium : Color.clear)

// ✅ 边框
.overlay(RoundedRectangle().stroke(Color.themeBorder, lineWidth: 1))

// ✅ 状态指示
.foregroundColor(Color.themeStatusSuccess)
```

### 错误用法示例

```swift
// ❌ 硬编码 RGB 值
.background(Color(red: 17/255, green: 24/255, blue: 39/255))

// ❌ 内联透明度计算
.background(Color.white.opacity(0.05))
.shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 2)

// ❌ 使用具体色值而非语义化颜色
.foregroundColor(Color.themeGray200)  // 应使用 Color.themeTextPrimary
```

### 如果缺少颜色常量

如果在 `Color+Theme.swift` 中找不到需要的颜色常量：

1. 检查是否可以通过组合现有颜色实现
2. 如果确实需要新颜色，在 `Color+Theme.swift` 中按以下顺序添加：
   - 优先添加语义化颜色（如 `themeXXX`）
   - 其次添加状态颜色（如 `themeStatusXXX`）
   - 最后添加具体色阶颜色（如 `themeXXX500`）
3. 添加时遵循现有命名规范和代码组织结构
4. 添加清晰的注释说明用途

### 特殊情况

**NSColor 类型**: 当与 AppKit 交互需要使用 `NSColor` 时，允许硬编码 RGB 值，但必须添加注释说明对应的 SwiftUI 颜色：

```swift
// 注意：这里使用 NSColor 因为 SelectableTextView 需要
// 对应 SwiftUI: Color.themePurple400
NSColor(red: 192/255, green: 132/255, blue: 252/255, alpha: 0.8)
```

**动态透明度**: 如果需要动态调整透明度，使用基础颜色 + `.opacity()`：

```swift
.foregroundColor(Color.themeBlue500.opacity(isActive ? 1.0 : 0.5))
```

---

## 其他主题使用规范

### 动画主题

```swift
// 使用预定义的动画时长
.animation(.easeOut(duration: ThemeDuration._300.rawValue), value: someValue)

// 使用预定义的动画曲线
.animation(.spring, value: someValue)
.animation(.customBezier, value: someValue)
```

### 字体主题

```swift
// 使用预定义的字体样式
.font(.themeH1)      // 标题 H1
.font(.themeH2)      // 标题 H2
.font(.themeBody)    // 正文
.font(.themeCaption) // 说明文字
```

### 形状主题

```swift
// 使用预定义的圆角
.cornerRadius(ThemeRadius.lg.rawValue)  // 8px
.cornerRadius(ThemeRadius.xl.rawValue)  // 12px

// 使用预定义的样式
.cardStyle()        // 卡片样式
.buttonStyle()      // 按钮样式
.inputStyle()       // 输入框样式
.panelStyle()       // 面板样式
```

### 间距主题

```swift
// 使用预定义的间距值
.padding(ThemeSpacing.px4.rawValue)  // 16px
.padding(ThemeSpacing.px6.rawValue)  // 24px
```