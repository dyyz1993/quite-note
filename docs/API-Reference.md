# API 参考文档

## 概述

本文档提供了主题系统和组件的完整 API 参考。

**源文件**: `/Users/xuyingzhou/Project/study-mac-app/quite-note/note.jsx`

**版本**: v1.0

---

## 目录

1. [Color API](#color-api)
2. [Font API](#font-api)
3. [Spacing API](#spacing-api)
4. [Shape API](#shape-api)
5. [Animation API](#animation-api)
6. [View Extensions](#view-extensions)
7. [Components](#components)
8. [Enums](#enums)
9. [Structs](#structs)

---

## Color API

### 主题颜色

#### Gray Scale

```swift
extension Color {
    static let themeGray900: Color // #111827 (bg-gray-900)
    static let themeGray800: Color // #1F2937 (bg-gray-800)
    static let themeGray700: Color // #374151 (bg-gray-700)
    static let themeGray600: Color // #4B5563 (bg-gray-600)
    static let themeGray500: Color // #6B7280 (text-gray-500)
    static let themeGray400: Color // #9CA3AF (text-gray-400)
    static let themeGray300: Color // #D1D5DB (text-gray-300)
    static let themeGray200: Color // #E5E7EB (text-gray-200)
    static let themeGray100: Color // #F3F4F6 (bg-gray-100)
}
```

**用法示例:**

```swift
Color.themeGray900 // 主背景色
Color.themeGray200 // 主要文本色
Color.themeGray400 // 次要文本色
```

#### Blue Scale (AI/交互色)

```swift
extension Color {
    static let themeBlue600: Color // #2563EB (bg-blue-600)
    static let themeBlue500: Color // #3B82F6 (blue-500)
    static let themeBlue400: Color // #60A5FA (blue-400)
    static let themeBlue300: Color // #93C5FD (blue-300)
}
```

**用法示例:**

```swift
Color.themeBlue500 // 主色调
Color.themeBlue400 // 悬停色
```

#### Purple Scale (AI 总结)

```swift
extension Color {
    static let themePurple600: Color // #9333EA (purple-600)
    static let themePurple500: Color // #A855F7 (purple-500)
    static let themePurple400: Color // #C084FC (purple-400)
    static let themePurple300: Color // #D8B4FE (purple-300)
}
```

**用法示例:**

```swift
Color.themePurple500 // AI 总结色
Color.themePurple300 // AI 激活色
```

#### Green Scale (成功/确认)

```swift
extension Color {
    static let themeGreen600: Color // #16A34A (green-600)
    static let themeGreen500: Color // #22C55E (green-500)
    static let themeGreen400: Color // #4ADE80 (green-400)
    static let themeGreen300: Color // #84FFAD (green-300)
}
```

**用法示例:**

```swift
Color.themeGreen500 // 成功状态
Color.themeGreen300 // 成功激活
```

#### Red Scale (错误/删除)

```swift
extension Color {
    static let themeRed600: Color // #B91C1C (red-600)
    static let themeRed500: Color // #EF4444 (red-500)
    static let themeRed400: Color // #F87171 (red-400)
    static let themeRed300: Color // #FEACAC (red-300)
}
```

**用法示例:**

```swift
Color.themeRed500 // 错误状态
Color.themeRed300 // 错误激活
```

#### Yellow Scale (警告/硬件)

```swift
extension Color {
    static let themeYellow600: Color // #B45309 (yellow-600)
    static let themeYellow500: Color // #EAB308 (yellow-500)
    static let themeYellow400: Color // #FACC15 (yellow-400)
    static let themeYellow300: Color // #FDE68A (yellow-300)
}
```

**用法示例:**

```swift
Color.themeYellow500 // 警告状态
Color.themeYellow300 // 警告激活
```

#### 透明色

```swift
extension Color {
    static let themeWhite5: Color   // bg-white/5 (2% 透明)
    static let themeWhite10: Color  // bg-white/10 (4% 透明)
    static let themeWhite20: Color  // bg-white/20 (8% 透明)
    static let themeWhite30: Color  // bg-white/30 (12% 透明)
    static let themeWhite50: Color  // bg-white/50 (20% 透明)
    static let themeWhite80: Color  // bg-white/80 (32% 透明)
    static let themeWhite90: Color  // bg-white/90 (36% 透明)

    static let themeBlack20: Color  // bg-black/20 (20% 透明)
    static let themeBlack30: Color  // bg-black/30 (30% 透明)
    static let themeBlack40: Color  // bg-black/40 (40% 透明)
    static let themeBlack50: Color  // bg-black/50 (50% 透明)
}
```

**用法示例:**

```swift
Color.themeWhite20 // 悬停背景
Color.themeBlack40 // 输入框背景
```

#### 语义色

```swift
extension Color {
    static let themeBackground: Color   // themeGray900
    static let themeCard: Color         // themeWhite5
    static let themeBorder: Color       // themeWhite10
    static let themeItem: Color         // themeWhite5
    static let themeHover: Color        // themeWhite20
    static let themeInput: Color        // themeBlack40
    static let themePanel: Color        // themeBlack20
    static let themeTextPrimary: Color  // themeGray200
    static let themeTextSecondary: Color // themeGray400
    static let themeTextTertiary: Color // themeGray500
}
```

**用法示例:**

```swift
Color.themeBackground // 主背景
Color.themeCard       // 卡片背景
Color.themeTextPrimary // 主要文本
```

### 颜色方法

#### withAlpha

```swift
func withAlpha(_ alpha: Double) -> Color
```

**参数:**
- `alpha`: 透明度值 (0.0-1.0)

**返回值:** 应用了透明度的颜色

**用法示例:**

```swift
Color.themeBlue500.withAlpha(0.5) // 50% 透明度的蓝色
```

#### fromTailwindAlpha

```swift
static func fromTailwindAlpha(colorName: String, alpha: Int) -> Color
```

**参数:**
- `colorName`: "white" 或 "black"
- `alpha`: 5, 10, 20, 50, 80, 90 等

**返回值:** 转换后的颜色

**用法示例:**

```swift
Color.fromTailwindAlpha(colorName: "white", alpha: 20) // bg-white/20
```

#### fromTailwindColorWithAlpha

```swift
static func fromTailwindColorWithAlpha(baseColor: String, alpha: Int) -> Color
```

**参数:**
- `baseColor`: "gray-900", "blue-500" 等
- `alpha`: 50, 80, 90 等

**返回值:** 转换后的颜色

**用法示例:**

```swift
Color.fromTailwindColorWithAlpha(baseColor: "gray-900", alpha: 90) // bg-gray-900/90
```

#### fromHex

```swift
static func fromHex(_ hex: String) -> Color
```

**参数:**
- `hex`: 十六进制颜色字符串，如 "#FF0000" 或 "FF0000"

**返回值:** 转换后的颜色

**用法示例:**

```swift
Color.fromHex("#FF0000") // 红色
Color.fromHex("00FF00")  // 绿色
```

#### fromHex (with alpha)

```swift
static func fromHex(_ hex: String, alpha: Double) -> Color
```

**参数:**
- `hex`: 十六进制颜色字符串
- `alpha`: 透明度值 (0.0-1.0)

**返回值:** 转换后的颜色

**用法示例:**

```swift
Color.fromHex("#FF0000", alpha: 0.5) // 50% 透明度的红色
```

---

## Font API

### 字体大小

```swift
extension Font {
    static let themeH1: Font           // 16px, font-semibold (text-base)
    static let themeH2: Font           // 14px, font-semibold (text-sm)
    static let themeBody: Font         // 14px, normal (text-sm, default)
    static let themeCaption: Font      // 12px, normal (text-xs)
    static let themeCaptionSmall: Font // 10px, normal (text-[10px])
    static let themeCaptionTiny: Font  // 8px, normal (text-[8px])
}
```

**用法示例:**

```swift
.font(.themeH1)           // 大标题
.font(.themeBody)         // 正文
.font(.themeCaptionSmall) // 小标签
```

### 字体族

```swift
extension Font {
    static let themeSans: Font    // 系统无衬线字体 (font-sans)
    static let themeMono: Font    // 等宽字体 (font-mono)
}
```

**用法示例:**

```swift
.font(.themeSans) // 默认字体族
.font(.themeMono) // 代码字体
```

### 字重

```swift
extension Font {
    static let themeWeightLight: Font     // font-light (300)
    static let themeWeightNormal: Font    // normal (400, default)
    static let themeWeightMedium: Font    // font-medium (500)
    static let themeWeightSemibold: Font  // font-semibold (600)
    static let themeWeightBold: Font      // font-bold (700)
}
```

**用法示例:**

```swift
.font(.themeWeightBold)     // 粗体
.font(.themeWeightLight)    // 细体
```

### 字间距

```swift
extension Font {
    static let themeTrackingNormal: Font // 默认字间距
    static let themeTrackingWide: Font   // 宽字间距 (需手动调整)
}
```

**用法示例:**

```swift
.font(.themeTrackingNormal) // 正常字间距
```

### 字体方法

#### weight

```swift
func weight(_ weight: Font.Weight) -> Font
```

**参数:**
- `weight`: 字体权重

**返回值:** 应用了字重的字体

**用法示例:**

```swift
.font(.themeBody.weight(.bold)) // 正文字体 + 粗体
```

#### monospace

```swift
func monospace(_ size: CGFloat? = nil) -> Font
```

**参数:**
- `size`: 字体大小 (可选)

**返回值:** 等宽字体

**用法示例:**

```swift
.font(.monospace())        // 默认等宽字体
.font(.monospace(12))      // 12px 等宽字体
```

#### uppercase

```swift
func uppercase(_ text: String) -> Text
```

**参数:**
- `text`: 要转换的文本

**返回值:** 转换后的 Text

**用法示例:**

```swift
Text("hello").uppercase("hello world") // "HELLO WORLD"
```

---

## Spacing API

### Spacing 枚举

```swift
enum ThemeSpacing: CGFloat {
    case px0   = 0     // 0px
    case px1   = 4     // 4px
    case px2   = 8     // 8px
    case px3   = 12    // 12px
    case px4   = 16    // 16px
    case px5   = 20    // 20px
    case px6   = 24    // 24px
    case px8   = 32    // 32px
    case px10  = 40    // 40px
    case px12  = 48    // 48px
    case px16  = 64    // 64px
    case px20  = 80    // 80px
    case px24  = 96    // 96px
    case px32  = 128   // 128px

    var rawValue: CGFloat { get }
}
```

**用法示例:**

```swift
ThemeSpacing.p4.rawValue  // 16px
ThemeSpacing.w16.rawValue // 64px
```

### 常用间距值

```swift
extension ThemeSpacing {
    static let p2: ThemeSpacing   // px8 (8px)
    static let p3: ThemeSpacing   // px12 (12px)
    static let p4: ThemeSpacing   // px16 (16px)
    static let p6: ThemeSpacing   // px24 (24px)
    static let p8: ThemeSpacing   // px32 (32px)
    static let p10: ThemeSpacing  // px40 (40px)
    static let p12: ThemeSpacing  // px48 (48px)
    static let p16: ThemeSpacing  // px64 (64px)

    static let w16: ThemeSpacing  // px64 (64px, 宽度)
    static let h12: ThemeSpacing  // px48 (48px, 高度)
    static let h8: ThemeSpacing   // px32 (32px, 高度)
    static let h1: ThemeSpacing   // px4 (4px, 高度)

    static let border1: CGFloat   // 1px
    static let border2: CGFloat   // 2px
}
```

**用法示例:**

```swift
ThemeSpacing.p4  // 16px 内边距
ThemeSpacing.w16 // 64px 宽度
ThemeSpacing.h12 // 48px 高度
```

### View Extensions

#### padding

```swift
func padding(_ spacing: ThemeSpacing) -> some View
```

**参数:**
- `spacing`: ThemeSpacing 值

**返回值:** 应用了间距的视图

**用法示例:**

```swift
.padding(.p4) // 16px 内边距
```

#### padding (多参数)

```swift
func padding(_ top: CGFloat, _ leading: CGFloat, _ bottom: CGFloat, _ trailing: CGFloat) -> some View
```

**参数:**
- `top`: 顶部间距
- `leading`: 左侧间距
- `bottom`: 底部间距
- `trailing`: 右侧间距

**返回值:** 应用了间距的视图

**用法示例:**

```swift
.padding(16, 12, 16, 12) // 上右下左间距
```

#### margin

```swift
func margin(_ top: CGFloat, _ leading: CGFloat, _ bottom: CGFloat, _ trailing: CGFloat) -> some View
```

**参数:**
- `top`: 顶部外边距
- `leading`: 左侧外边距
- `bottom`: 底部外边距
- `trailing`: 右侧外边距

**返回值:** 应用了外边距的视图

**用法示例:**

```swift
.margin(8, 8, 8, 8) // 外边距
```

#### frame

```swift
func frame(width: ThemeSpacing? = nil, height: ThemeSpacing? = nil) -> some View
```

**参数:**
- `width`: 宽度 (可选)
- `height`: 高度 (可选)

**返回值:** 应用了尺寸的视图

**用法示例:**

```swift
.frame(width: .w16, height: .h12) // 64x48 尺寸
```

#### frame (size)

```swift
func frame(size: CGSize) -> some View
```

**参数:**
- `size`: CGSize 尺寸

**返回值:** 应用了尺寸的视图

**用法示例:**

```swift
.frame(size: CGSize(width: 100, height: 50))
```

#### frame (square)

```swift
func frame(square size: CGFloat) -> some View
```

**参数:**
- `size`: 正方形边长

**返回值:** 应用了正方形尺寸的视图

**用法示例:**

```swift
.frame(square: 50) // 50x50 正方形
```

#### minWidth

```swift
func minWidth(_ width: ThemeSpacing) -> some View
```

**参数:**
- `width`: 最小宽度

**返回值:** 应用了最小宽度的视图

**用法示例:**

```swift
.minWidth(.w16) // 最小宽度 64px
```

#### minHeight

```swift
func minHeight(_ height: ThemeSpacing) -> some View
```

**参数:**
- `height`: 最小高度

**返回值:** 应用了最小高度的视图

**用法示例:**

```swift
.minHeight(.h12) // 最小高度 48px
```

#### maxWidth

```swift
func maxWidth(_ width: ThemeSpacing) -> some View
```

**参数:**
- `width`: 最大宽度

**返回值:** 应用了最大宽度的视图

**用法示例:**

```swift
.maxWidth(.w32) // 最大宽度 128px
```

#### maxHeight

```swift
func maxHeight(_ height: ThemeSpacing) -> some View
```

**参数:**
- `height`: 最大高度

**返回值:** 应用了最大高度的视图

**用法示例:**

```swift
.maxHeight(.h24) // 最大高度 96px
```

#### spacing

```swift
func spacing(_ spacing: ThemeSpacing) -> some View
```

**参数:**
- `spacing`: 间距值

**返回值:** 应用了间距的视图

**用法示例:**

```swift
.spacing(.p4) // 16px 间距
```

#### verticalSpacing

```swift
func verticalSpacing(_ spacing: ThemeSpacing) -> some View
```

**参数:**
- `spacing`: 垂直间距

**返回值:** 应用了垂直间距的视图

**用法示例:**

```swift
.verticalSpacing(.p4) // 垂直 16px 间距
```

#### horizontalSpacing

```swift
func horizontalSpacing(_ spacing: ThemeSpacing) -> some View
```

**参数:**
- `spacing`: 水平间距

**返回值:** 应用了水平间距的视图

**用法示例:**

```swift
.horizontalSpacing(.p4) // 水平 16px 间距
```

### Spacing 结构体

#### vertical

```swift
static func vertical(_ height: ThemeSpacing) -> some View
```

**参数:**
- `height`: 间距高度

**返回值:** 垂直间距视图

**用法示例:**

```swift
Spacing.vertical(.p4) // 16px 垂直间距
```

#### horizontal

```swift
static func horizontal(_ width: ThemeSpacing) -> some View
```

**参数:**
- `width`: 间距宽度

**返回值:** 水平间距视图

**用法示例:**

```swift
Spacing.horizontal(.p4) // 16px 水平间距
```

#### fixed

```swift
static func fixed(_ size: ThemeSpacing) -> some View
```

**参数:**
- `size`: 间距尺寸

**返回值:** 固定尺寸间距视图

**用法示例:**

```swift
Spacing.fixed(.p4) // 16x16 固定间距
```

---

## Shape API

### ThemeRadius 枚举

```swift
enum ThemeRadius: CGFloat {
    case none = 0       // 0px (rounded-none)
    case sm   = 2       // 2px (rounded-sm)
    case base = 4       // 4px (rounded)
    case md   = 6       // 6px (rounded-md)
    case lg   = 8       // 8px (rounded-lg)
    case xl   = 12      // 12px (rounded-xl)
    case `2xl` = 16     // 16px (rounded-2xl)
    case `3xl` = 24     // 24px (rounded-3xl)
    case full  = 9999   // 圆形 (rounded-full)
}
```

**用法示例:**

```swift
ThemeRadius.lg.rawValue  // 8px
ThemeRadius.full.rawValue // 圆形
```

### ThemeBorder 结构体

```swift
struct ThemeBorder {
    let width: CGFloat
    let color: Color

    static let thin: ThemeBorder   // width: 4px, color: themeBorder
    static let medium: ThemeBorder // width: 6px, color: themeBorder
    static let thick: ThemeBorder  // width: 8px, color: themeBorder
}
```

**用法示例:**

```swift
ThemeBorder.medium // 中等边框
```

### View Extensions

#### cornerRadius

```swift
func cornerRadius(_ radius: ThemeRadius) -> some View
```

**参数:**
- `radius`: 圆角半径

**返回值:** 应用了圆角的视图

**用法示例:**

```swift
.cornerRadius(.lg) // 8px 圆角
```

#### border (ThemeBorder)

```swift
func border(_ border: ThemeBorder) -> some View
```

**参数:**
- `border`: ThemeBorder 定义

**返回值:** 应用了边框的视图

**用法示例:**

```swift
.border(ThemeBorder.medium) // 中等边框
```

#### border (width + color)

```swift
func border(width: CGFloat = 4, color: Color = .themeBorder) -> some View
```

**参数:**
- `width`: 边框宽度 (默认 4px)
- `color`: 边框颜色 (默认 themeBorder)

**返回值:** 应用了边框的视图

**用法示例:**

```swift
.border(width: 2, color: .themeBlue500) // 2px 蓝色边框
```

#### shadow

```swift
func shadow(color: Color = .black, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View
```

**参数:**
- `color`: 阴影颜色 (默认 black)
- `radius`: 阴影模糊半径
- `x`: 水平偏移 (默认 0)
- `y`: 垂直偏移 (默认 0)

**返回值:** 应用了阴影的视图

**用法示例:**

```swift
.shadow(color: .black, radius: 20, x: 0, y: 4) // 黑色阴影
```

#### insetShadow

```swift
func insetShadow(color: Color = .black, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View
```

**参数:**
- `color`: 内阴影颜色 (默认 black)
- `radius`: 阴影模糊半径
- `x`: 水平偏移 (默认 0)
- `y`: 垂直偏移 (默认 0)

**返回值:** 应用了内阴影的视图

**用法示例:**

```swift
.insetShadow(color: .white, radius: 10) // 白色内阴影
```

#### clipRounded

```swift
func clipRounded(radius: ThemeRadius = .base) -> some View
```

**参数:**
- `radius`: 圆角半径 (默认 base)

**返回值:** 裁剪为圆角矩形的视图

**用法示例:**

```swift
.clipRounded(radius: .lg) // 裁剪为大圆角
```

#### clipCircle

```swift
func clipCircle() -> some View
```

**返回值:** 裁剪为圆形的视图

**用法示例:**

```swift
.clipCircle() // 裁剪为圆形
```

#### cardStyle

```swift
func cardStyle(cornerRadius: ThemeRadius = .lg, shadow: Bool = true) -> some View
```

**参数:**
- `cornerRadius`: 圆角半径 (默认 lg)
- `shadow`: 是否添加阴影 (默认 true)

**返回值:** 卡片样式视图

**用法示例:**

```swift
.cardStyle() // 默认卡片样式
```

#### buttonStyle

```swift
func buttonStyle(
    cornerRadius: ThemeRadius = .md,
    background: Color = .themeItem,
    shadow: Bool = true
) -> some View
```

**参数:**
- `cornerRadius`: 圆角半径 (默认 md)
- `background`: 背景色 (默认 themeItem)
- `shadow`: 是否添加阴影 (默认 true)

**返回值:** 按钮样式视图

**用法示例:**

```swift
.buttonStyle() // 默认按钮样式
```

#### inputStyle

```swift
func inputStyle(
    cornerRadius: ThemeRadius = .base,
    background: Color = .themeInput
) -> some View
```

**参数:**
- `cornerRadius`: 圆角半径 (默认 base)
- `background`: 背景色 (默认 themeInput)

**返回值:** 输入框样式视图

**用法示例:**

```swift
.inputStyle() // 默认输入框样式
```

#### panelStyle

```swift
func panelStyle(
    cornerRadius: ThemeRadius = .`2xl`,
    shadow: Bool = true
) -> some View
```

**参数:**
- `cornerRadius`: 圆角半径 (默认 2xl)
- `shadow`: 是否添加阴影 (默认 true)

**返回值:** 面板样式视图

**用法示例:**

```swift
.panelStyle() // 默认面板样式
```

### ThemeShapes 结构体

#### roundedRectangle

```swift
static func roundedRectangle(cornerRadius: ThemeRadius = .lg) -> RoundedRectangle
```

**参数:**
- `cornerRadius`: 圆角半径 (默认 lg)

**返回值:** 圆角矩形

**用法示例:**

```swift
ThemeShapes.roundedRectangle() // 圆角矩形
```

#### capsule

```swift
static func capsule() -> Capsule
```

**返回值:** 胶囊形状

**用法示例:**

```swift
ThemeShapes.capsule() // 胶囊形状
```

#### circle

```swift
static func circle() -> Circle
```

**返回值:** 圆形

**用法示例:**

```swift
ThemeShapes.circle() // 圆形
```

### Border 结构体

#### top

```swift
static func top(width: CGFloat = 4, color: Color = .themeBorder) -> some View
```

**参数:**
- `width`: 边框宽度 (默认 4px)
- `color`: 边框颜色 (默认 themeBorder)

**返回值:** 顶部边框视图

**用法示例:**

```swift
Border.top() // 顶部边框
```

#### bottom

```swift
static func bottom(width: CGFloat = 4, color: Color = .themeBorder) -> some View
```

**参数:**
- `width`: 边框宽度 (默认 4px)
- `color`: 边框颜色 (默认 themeBorder)

**返回值:** 底部边框视图

**用法示例:**

```swift
Border.bottom() // 底部边框
```

#### left

```swift
static func left(width: CGFloat = 4, color: Color = .themeBorder) -> some View
```

**参数:**
- `width`: 边框宽度 (默认 4px)
- `color`: 边框颜色 (默认 themeBorder)

**返回值:** 左侧边框视图

**用法示例:**

```swift
Border.left() // 左侧边框
```

#### right

```swift
static func right(width: CGFloat = 4, color: Color = .themeBorder) -> some View
```

**参数:**
- `width`: 边框宽度 (默认 4px)
- `color`: 边框颜色 (默认 themeBorder)

**返回值:** 右侧边框视图

**用法示例:**

```swift
Border.right() // 右侧边框
```

---

## Animation API

### ThemeDuration 枚举

```swift
enum ThemeDuration: Double {
    case `100` = 0.1      // 100ms
    case `200` = 0.2      // 200ms
    case `300` = 0.3      // 300ms
    case `500` = 0.5      // 500ms
    case `1000` = 1.0     // 1000ms
}
```

**用法示例:**

```swift
ThemeDuration.`300`.rawValue // 0.3 秒
```

### Animation Extensions

```swift
extension Animation {
    static let easeIn: Animation          // 300ms easeIn
    static let easeOut: Animation         // 300ms easeOut
    static let easeInOut: Animation       // 300ms easeInOut
    static let spring: Animation          // spring(response:0.3,dampingFraction:0.7)
    static let customBezier: Animation    // timingCurve(0.34,1.56,0.64,1.0, duration:0.5)
    static let pulse: Animation           // 1.5s 脉冲动画
    static let spin: Animation            // 1.0s 旋转动画
    static let toast: Animation           // 300ms toast 动画
    static let fade: Animation            // 200ms 淡入淡出
    static let slide: Animation           // 300ms 滑动
    static let scale: Animation           // spring 缩放
}
```

**用法示例:**

```swift
.animation(.easeOut, value: isExpanded)
.animation(.spring, value: scale)
```

### AnyTransition Extensions

```swift
extension AnyTransition {
    static let slideRight: AnyTransition  // 从右侧滑入
    static let slideLeft: AnyTransition   // 从左侧滑入
    static let slideTop: AnyTransition    // 从顶部滑入
    static let slideBottom: AnyTransition // 从底部滑入

    static let toastIn: AnyTransition     // Toast 进入
    static let toastOut: AnyTransition    // Toast 离开

    static let settingsIn: AnyTransition  // 设置面板进入
    static let settingsOut: AnyTransition // 设置面板离开

    static let expand: AnyTransition      // 展开过渡
    static let collapse: AnyTransition    // 折叠过渡
}
```

**用法示例:**

```swift
.transition(.slideRight)
.transition(.toastIn)
```

### View Extensions

#### animateIn

```swift
func animateIn(duration: ThemeDuration = .`300`, curve: Animation = .easeOut) -> some View
```

**参数:**
- `duration`: 动画时长 (默认 300ms)
- `curve`: 动画曲线 (默认 easeOut)

**返回值:** 应用了进入动画的视图

**用法示例:**

```swift
.animateIn() // 默认进入动画
.animateIn(duration: .`500`, curve: .customBezier) // 自定义动画
```

#### animateInOut

```swift
func animateInOut(duration: ThemeDuration = .`300`) -> some View
```

**参数:**
- `duration`: 动画时长 (默认 300ms)

**返回值:** 应用了进出动画的视图

**用法示例:**

```swift
.animateInOut() // 默认进出动画
```

#### animateSpring

```swift
func animateSpring(response: Double = 0.3, dampingFraction: Double = 0.7) -> some View
```

**参数:**
- `response`: 响应时间 (默认 0.3)
- `dampingFraction`: 阻尼系数 (默认 0.7)

**返回值:** 应用了弹性动画的视图

**用法示例:**

```swift
.animateSpring() // 默认弹性动画
.animateSpring(response: 0.2, dampingFraction: 0.8) // 自定义弹性
```

#### animateBezier

```swift
func animateBezier(c1x: Double, c1y: Double, c2x: Double, c2y: Double, duration: ThemeDuration = .`500`) -> some View
```

**参数:**
- `c1x`: 第一个控制点 x
- `c1y`: 第一个控制点 y
- `c2x`: 第二个控制点 x
- `c2y`: 第二个控制点 y
- `duration`: 动画时长 (默认 500ms)

**返回值:** 应用了贝塞尔动画的视图

**用法示例:**

```swift
.animateBezier(c1x: 0.34, c1y: 1.56, c2x: 0.64, c2y: 1.0) // 自定义贝塞尔
```

#### animatePulse

```swift
func animatePulse(duration: Double = 1.5) -> some View
```

**参数:**
- `duration`: 脉冲周期 (默认 1.5s)

**返回值:** 应用了脉冲动画的视图

**用法示例:**

```swift
.animatePulse() // 默认脉冲
```

#### animateSpin

```swift
func animateSpin(duration: Double = 1.0) -> some View
```

**参数:**
- `duration`: 旋转周期 (默认 1.0s)

**返回值:** 应用了旋转动画的视图

**用法示例:**

```swift
.animateSpin() // 默认旋转
```

#### animateToast

```swift
func animateToast() -> some View
```

**返回值:** 应用了 Toast 动画的视图

**用法示例:**

```swift
.animateToast() // Toast 动画
```

#### animateFade

```swift
func animateFade() -> some View
```

**返回值:** 应用了淡入淡出动画的视图

**用法示例:**

```swift
.animateFade() // 淡入淡出
```

#### animateSlide

```swift
func animateSlide() -> some View
```

**返回值:** 应用了滑动动画的视图

**用法示例:**

```swift
.animateSlide() // 滑动动画
```

#### animateScale

```swift
func animateScale() -> some View
```

**返回值:** 应用了缩放动画的视图

**用法示例:**

```swift
.animateScale() // 缩放动画
```

### Transition Extensions

#### transitionSlideRight

```swift
func transitionSlideRight() -> some View
```

**返回值:** 应用了右侧滑入过渡的视图

**用法示例:**

```swift
.transitionSlideRight() // 右侧滑入
```

#### transitionSlideLeft

```swift
func transitionSlideLeft() -> some View
```

**返回值:** 应用了左侧滑入过渡的视图

**用法示例:**

```swift
.transitionSlideLeft() // 左侧滑入
```

#### transitionSlideTop

```swift
func transitionSlideTop() -> some View
```

**返回值:** 应用了顶部滑入过渡的视图

**用法示例:**

```swift
.transitionSlideTop() // 顶部滑入
```

#### transitionSlideBottom

```swift
func transitionSlideBottom() -> some View
```

**返回值:** 应用了底部滑入过渡的视图

**用法示例:**

```swift
.transitionSlideBottom() // 底部滑入
```

#### transitionToastIn

```swift
func transitionToastIn() -> some View
```

**返回值:** 应用了 Toast 进入过渡的视图

**用法示例:**

```swift
.transitionToastIn() // Toast 进入
```

#### transitionToastOut

```swift
func transitionToastOut() -> some View
```

**返回值:** 应用了 Toast 离开过渡的视图

**用法示例:**

```swift
.transitionToastOut() // Toast 离开
```

#### transitionSettingsIn

```swift
func transitionSettingsIn() -> some View
```

**返回值:** 应用了设置面板进入过渡的视图

**用法示例:**

```swift
.transitionSettingsIn() // 设置面板进入
```

#### transitionSettingsOut

```swift
func transitionSettingsOut() -> some View
```

**返回值:** 应用了设置面板离开过渡的视图

**用法示例:**

```swift
.transitionSettingsOut() // 设置面板离开
```

#### transitionExpand

```swift
func transitionExpand() -> some View
```

**返回值:** 应用了展开过渡的视图

**用法示例:**

```swift
.transitionExpand() // 展开过渡
```

#### transitionCollapse

```swift
func transitionCollapse() -> some View
```

**返回值:** 应用了折叠过渡的视图

**用法示例:**

```swift
.transitionCollapse() // 折叠过渡
```

### AnimationUtils 结构体

#### delayed

```swift
static func delayed(delay: Double, animation: Animation) -> Animation
```

**参数:**
- `delay`: 延迟时间 (秒)
- `animation`: 原始动画

**返回值:** 带延迟的动画

**用法示例:**

```swift
AnimationUtils.delayed(delay: 0.5, animation: .easeOut) // 延迟 0.5 秒
```

#### repeated

```swift
static func repeated(count: Int, autoreverses: Bool = false, animation: Animation) -> Animation
```

**参数:**
- `count`: 重复次数
- `autoreverses`: 是否自动反向 (默认 false)
- `animation`: 原始动画

**返回值:** 重复动画

**用法示例:**

```swift
AnimationUtils.repeated(count: 3, autoreverses: true, animation: .pulse) // 重复 3 次
```

#### infinite

```swift
static func infinite(autoreverses: Bool = false, animation: Animation) -> Animation
```

**参数:**
- `autoreverses`: 是否自动反向 (默认 false)
- `animation`: 原始动画

**返回值:** 无限动画

**用法示例:**

```swift
AnimationUtils.infinite(animation: .spin) // 无限旋转
```

#### combined

```swift
static func combined(transition1: AnyTransition, transition2: AnyTransition) -> AnyTransition
```

**参数:**
- `transition1`: 第一个过渡
- `transition2`: 第二个过渡

**返回值:** 组合过渡

**用法示例:**

```swift
AnimationUtils.combined(transition1: .slideRight, transition2: .opacity) // 组合过渡
```

### AnimationPresets 结构体

```swift
struct AnimationPresets {
    static let toast: Animation           // Toast 动画
    static let buttonPress: Animation      // 按钮按下动画
    static let cardHover: Animation        // 卡片悬停动画
    static let settingsPanel: Animation    // 设置面板动画
    static let recordCardExpand: Animation // 记录卡片展开动画
    static let loadingSpinner: Animation   // 加载旋转动画
    static let successPulse: Animation     // 成功脉冲动画

    static func errorShake() -> Animation  // 错误抖动动画
}
```

**用法示例:**

```swift
.animation(AnimationPresets.toast, value: showToast)
.animation(AnimationPresets.errorShake(), value: showError)
```

---

## View Extensions

### 通用方法

#### textCase

```swift
func textCase(_ caseType: TextCase) -> some View
```

**参数:**
- `caseType`: 文本大小写类型

**返回值:** 应用了文本大小写的视图

**用法示例:**

```swift
Text("hello").textCase(.uppercase) // "HELLO"
```

#### kerning

```swift
func kerning(_ value: CGFloat) -> some View
```

**参数:**
- `value`: 字间距值

**返回值:** 应用了字间距的视图

**用法示例:**

```swift
Text("HELLO").kerning(2) // 字间距 2px
```

#### fontWeight

```swift
func fontWeight(_ weight: Font.Weight) -> some View
```

**参数:**
- `weight`: 字体权重

**返回值:** 应用了字重的视图

**用法示例:**

```swift
.fontWeight(.bold) // 粗体
```

#### monospace

```swift
func monospace(_ size: CGFloat? = nil) -> some View
```

**参数:**
- `size`: 字体大小 (可选)

**返回值:** 应用了等宽字体的视图

**用法示例:**

```swift
.monospace() // 等宽字体
.monospace(12) // 12px 等宽字体
```

#### pointingHandCursor

```swift
func pointingHandCursor() -> some View
```

**返回值:** 应用了手型光标的视图

**用法示例:**

```swift
.pointingHandCursor() // 手型光标
```

### VStack Extensions

#### init (spacing)

```swift
init(spacing: ThemeSpacing, @ViewBuilder content: () -> Content)
```

**参数:**
- `spacing`: 间距值
- `content`: 视图内容

**用法示例:**

```swift
VStack(spacing: .p4) {
    Text("Item 1")
    Text("Item 2")
}
```

### HStack Extensions

#### init (spacing)

```swift
init(spacing: ThemeSpacing, @ViewBuilder content: () -> Content)
```

**参数:**
- `spacing`: 间距值
- `content`: 视图内容

**用法示例:**

```swift
HStack(spacing: .p4) {
    Text("Item 1")
    Text("Item 2")
}
```

### ZStack Extensions

#### init (spacing)

```swift
init(spacing: ThemeSpacing, @ViewBuilder content: () -> Content)
```

**参数:**
- `spacing`: 间距值
- `content`: 视图内容

**用法示例:**

```swift
ZStack(spacing: .p4) {
    Text("Item 1")
    Text("Item 2")
}
```

---

## Components

### RecordCard

完整的 RecordCard 组件 API。

**文件**: `Sources/QuiteNote/UI/Components/RecordCard.swift`

#### 属性

```swift
let record: Record              // 记录数据
@Binding var expandedId: UUID?  // 展开的记录 ID
let store: RecordStore          // 记录存储
@State private var hovering: Bool // 是否悬停
```

#### 方法

```swift
private var displayTitle: String                    // 显示标题
private var statusIconLucide: IconName              // 状态图标
private var statusColor: Color                      // 状态颜色
private var statusText: String                      // 状态文本
private var cardHeader: (Bool) -> some View         // 卡片头部视图
private var cardExpandedContent: some View          // 展开内容视图
```

#### 用法示例

```swift
RecordCard(
    record: record,
    expandedId: $expandedId,
    store: store
)
```

### SettingsPanel

完整的 SettingsPanel 组件 API。

**文件**: `Sources/QuiteNote/UI/Components/SettingsPanel.swift`

#### 属性

```swift
@Environment(\.dismiss) var dismiss    // 关闭环境变量
@StateObject var store: RecordStore    // 记录存储
@StateObject var bluetooth: BluetoothManager // 蓝牙管理器
@State private var settingsTab: String // 当前标签
@State private var editConfig          // 编辑配置
```

#### 方法

```swift
private var headerView: some View           // 头部视图
private var tabView: some View              // 标签视图
private var contentView: some View          // 内容视图
private var footerView: some View           // 底部视图
private var aiSettingsView: some View       // AI 设置视图
private var historySettingsView: some View  // 历史设置视图
private var bluetoothSettingsView: some View // 蓝牙设置视图
private var windowSettingsView: some View   // 窗口设置视图
```

#### 用法示例

```swift
SettingsPanel(
    store: store,
    bluetooth: bluetooth
)
```

### ToastView

Toast 提示视图组件。

**文件**: 待实现

#### 属性

```swift
let message: String        // 消息文本
let type: ToastType        // 消息类型
```

#### 用法示例

```swift
ToastView(
    message: "操作成功！",
    type: .success
)
```

### HeatmapView

热力图组件。

**文件**: 待实现

#### 属性

```swift
@ObservedObject var viewModel: HeatmapViewModel // 视图模型
```

#### 用法示例

```swift
HeatmapView(vm: heatmapVM)
```

### IconButton

图标按钮组件。

#### 属性

```swift
let icon: IconName        // 图标名称
let color: Color          // 图标颜色
let action: () -> Void    // 点击动作
```

#### 用法示例

```swift
IconButton(
    icon: .star,
    color: .themeYellow,
    action: { /* 点击逻辑 */ }
)
```

---

## Enums

### TextCase

文本大小写枚举。

```swift
enum TextCase {
    case normal
    case uppercase
    case lowercase

    func apply(to text: String) -> String
}
```

**用法示例:**

```swift
TextCase.uppercase.apply(to: "hello") // "HELLO"
```

### ThemeSpacing

间距枚举。

```swift
enum ThemeSpacing: CGFloat {
    case px0, px1, px2, px3, px4, px5, px6, px8, px10, px12, px16, px20, px24, px32
}
```

**用法示例:**

```swift
ThemeSpacing.p4 // 16px
```

### ThemeRadius

圆角枚举。

```swift
enum ThemeRadius: CGFloat {
    case none, sm, base, md, lg, xl, `2xl`, `3xl`, full
}
```

**用法示例:**

```swift
ThemeRadius.lg // 8px
```

### ThemeDuration

动画时长枚举。

```swift
enum ThemeDuration: Double {
    case `100`, `200`, `300`, `500`, `1000`
}
```

**用法示例:**

```swift
ThemeDuration.`300` // 0.3 秒
```

---

## Structs

### ThemeBorder

边框定义结构体。

```swift
struct ThemeBorder {
    let width: CGFloat
    let color: Color

    static let thin: ThemeBorder
    static let medium: ThemeBorder
    static let thick: ThemeBorder
}
```

**用法示例:**

```swift
ThemeBorder.medium // 中等边框
```

### ThemeShapes

形状工具结构体。

```swift
struct ThemeShapes {
    static func roundedRectangle(cornerRadius: ThemeRadius = .lg) -> RoundedRectangle
    static func capsule() -> Capsule
    static func circle() -> Circle
}
```

**用法示例:**

```swift
ThemeShapes.roundedRectangle() // 圆角矩形
```

### Border

边框工具结构体。

```swift
struct Border {
    static func top(width: CGFloat = 4, color: Color = .themeBorder) -> some View
    static func bottom(width: CGFloat = 4, color: Color = .themeBorder) -> some View
    static func left(width: CGFloat = 4, color: Color = .themeBorder) -> some View
    static func right(width: CGFloat = 4, color: Color = .themeBorder) -> some View
}
```

**用法示例:**

```swift
Border.top() // 顶部边框
```

### Spacing

间距工具结构体。

```swift
struct Spacing {
    static func vertical(_ height: ThemeSpacing) -> some View
    static func horizontal(_ width: ThemeSpacing) -> some View
    static func fixed(_ size: ThemeSpacing) -> some View
}
```

**用法示例:**

```swift
Spacing.vertical(.p4) // 16px 垂直间距
```

### AnimationUtils

动画工具结构体。

```swift
struct AnimationUtils {
    static func delayed(delay: Double, animation: Animation) -> Animation
    static func repeated(count: Int, autoreverses: Bool = false, animation: Animation) -> Animation
    static func infinite(autoreverses: Bool = false, animation: Animation) -> Animation
    static func combined(transition1: AnyTransition, transition2: AnyTransition) -> AnyTransition
}
```

**用法示例:**

```swift
AnimationUtils.delayed(delay: 0.5, animation: .easeOut) // 延迟动画
```

### AnimationPresets

动画预设结构体。

```swift
struct AnimationPresets {
    static let toast: Animation
    static let buttonPress: Animation
    static let cardHover: Animation
    static let settingsPanel: Animation
    static let recordCardExpand: Animation
    static let loadingSpinner: Animation
    static let successPulse: Animation
    static func errorShake() -> Animation
}
```

**用法示例:**

```swift
AnimationPresets.toast // Toast 动画预设
```

---

## 类型别名

### IconName

图标名称类型别名（来自 Lucide 图标库）。

```swift
typealias IconName = LucideIconName // 假设的类型
```

**用法示例:**

```swift
let icon: IconName = .sparkles
```

---

## 常量

### 主题常量

```swift
let THEME_VERSION = "1.0.0"        // 主题版本
let THEME_AUTHOR = "Claude AI"     // 主题作者
let THEME_LICENSE = "MIT"          // 主题许可证
```

---

## 错误处理

### 可能的错误

1. **颜色值错误**: 确保 RGBA 值在 0.0-1.0 范围内
2. **间距值错误**: 确保 ThemeSpacing 值为正数
3. **动画时长错误**: 确保 ThemeDuration 值为正数
4. **圆角值错误**: 确保 ThemeRadius 值非负

### 错误处理建议

```swift
// 颜色验证
guard red >= 0.0 && red <= 1.0 else {
    print("红色值必须在 0.0-1.0 之间")
    return Color.red
}

// 间距验证
guard spacing.rawValue > 0 else {
    print("间距值必须大于 0")
    return ThemeSpacing.p4
}
```

---

## 版本历史

### v1.0 (2024-12-05)

- 初始版本
- 完整的颜色、字体、间距、形状、动画 API
- RecordCard 和 SettingsPanel 组件
- 完整的文档和示例

---

## 贡献指南

### 添加新的 API

1. 在相应的扩展文件中添加新方法
2. 添加详细的文档注释
3. 添加使用示例
4. 更新本 API 文档

### 修改现有 API

1. 确保向后兼容
2. 更新文档
3. 添加迁移指南（如果需要）
4. 更新测试

---

## 许可证

MIT License

Copyright (c) 2024 Claude AI

详情请查看 LICENSE 文件。

---

**文档版本**: v1.0

**最后更新**: 2024-12-05

**维护者**: Claude AI