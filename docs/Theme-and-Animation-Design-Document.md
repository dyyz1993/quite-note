# QuiteNote 主题和动效设计文档

> 版本：1.0
> 日期：2025-12-09
> 作者：Claude Code

## 文档修订记录

| 版本 | 修订日期 | 修订内容 | 修订人 |
|------|----------|----------|--------|
| 1.0 | 2025-12-09 | 初始版本 | Claude Code |

---

## 目录

1. [设计概述](#1-设计概述)
2. [设计原则](#2-设计原则)
3. [主题系统架构](#3-主题系统架构)
4. [颜色系统](#4-颜色系统)
5. [字体系统](#5-字体系统)
6. [间距系统](#6-间距系统)
7. [形状系统](#7-形状系统)
8. [动画系统](#8-动画系统)
9. [组件设计规范](#9-组件设计规范)
10. [动效设计指南](#10-动效设计指南)
11. [响应式设计](#11-响应式设计)
12. [可访问性设计](#12-可访问性设计)
13. [主题切换机制](#13-主题切换机制)
14. [实现指南](#14-实现指南)
15. [最佳实践](#15-最佳实践)
16. [附录](#16-附录)

---

## 1. 设计概述

### 1.1 设计目标

QuiteNote 的主题和动效设计旨在提供一个现代化、优雅且高度一致的用户界面体验。设计遵循 macOS 设计规范，同时融入独特的视觉语言和动效表达。

### 1.2 设计特色

- **科技感与优雅并存**：深色背景搭配高亮色彩，营造科技氛围
- **流畅的动效体验**：精心设计的过渡动画，提升用户感知
- **模块化主题系统**：完整的主题架构，便于维护和扩展
- **响应式交互**：智能的交互反馈，增强用户参与感

### 1.3 设计约束

- 仅支持 macOS 12.0 及以上版本
- 遵循 SwiftUI 设计范式
- 支持深色主题（当前）
- 适配多种屏幕尺寸

---

## 2. 设计原则

### 2.1 一致性 (Consistency)

**目标**：确保界面元素在视觉和交互上保持一致

**实现方式**：
- 统一的颜色命名和使用规范
- 标准化的组件尺寸和间距
- 一致的动效时长和缓动函数
- 相同场景使用相同的交互模式

**示例**：
```swift
// ✅ 正确：使用主题颜色
Color.themePrimary
// ❌ 错误：硬编码颜色
Color(red: 0.235, green: 0.510, blue: 0.969)
```

### 2.2 可读性 (Readability)

**目标**：确保内容清晰易读，信息层次分明

**实现方式**：
- 合理的字体大小和行高
- 足够的对比度（符合 WCAG AA 标准）
- 清晰的视觉层次结构
- 适当的留白和间距

**规范**：
- 主文本：14pt，对比度 ≥ 4.5:1
- 次要文本：12pt，对比度 ≥ 3:1
- 辅助文本：10pt，对比度 ≥ 3:1

### 2.3 可访问性 (Accessibility)

**目标**：确保所有用户都能正常使用应用

**实现方式**：
- 支持键盘导航
- 提供足够的点击区域（最小 44x44pt）
- 支持动态字体大小
- 提供语义化的标签

**要求**：
- 所有交互元素支持 Tab 导航
- 重要操作提供触觉反馈
- 支持 VoiceOver

### 2.4 性能优先 (Performance First)

**目标**：在保证视觉效果的同时，优先考虑性能

**实现方式**：
- 使用轻量级动画（避免复杂路径动画）
- 合理使用视图缓存
- 优化图片和图标资源
- 减少不必要的视图更新

---

## 3. 主题系统架构

### 3.1 系统概览

主题系统采用分层架构，包含以下层次：

```
┌─────────────────────────────────────┐
│        应用层 (App Layer)           │
│  - 视图和组件使用主题 API           │
└─────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────┐
│     主题扩展 (Theme Extensions)     │
│  - View 扩展方法                    │
│  - 便捷的样式应用                   │
└─────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────┐
│    主题枚举 (Theme Enums)           │
│  - Color, Font, Spacing, Radius     │
│  - Animation                        │
└─────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────┐
│      基础值 (Base Values)           │
│  - 硬编码的颜色、尺寸、动画值        │
│  - 从 note.jsx 提取                 │
└─────────────────────────────────────┘
```

### 3.2 主题文件组织

```
Sources/QuiteNote/UI/Theme/
├── Color+Theme.swift        # 颜色主题系统
├── Font+Theme.swift         # 字体主题系统
├── Spacing+Theme.swift      # 间距主题系统
├── Shape+Theme.swift        # 形状主题系统
├── Animation+Theme.swift    # 动画主题系统
└── ThemeExtensions.swift    # 主题扩展（可选）
```

### 3.3 主题值的来源

所有主题值均来自 React 项目的 `note.jsx`，确保设计一致性：

- **颜色**：Tailwind CSS 颜色系统
- **间距**：Tailwind 4px 基础单位
- **字体**：系统字体 + 固定尺寸
- **动画**：明确的时长和缓动函数
- **形状**：Tailwind 圆角系统

---

## 4. 颜色系统

### 4.1 色彩哲学

QuiteNote 采用深色主题，以深灰为基底，搭配蓝色作为主色调，营造专业、现代的视觉感受。

### 4.2 颜色分类

#### 4.2.1 中性色板 (Gray Scale)

| 颜色名称 | 十六进制 | RGBA | 用途 |
|---------|---------|------|------|
| Gray-900 | #111827 | (17,24,39,1) | 主背景色 |
| Gray-800 | #1F2937 | (31,41,55,1) | 次级背景 |
| Gray-700 | #374151 | (55,65,81,1) | 边框、分隔线 |
| Gray-600 | #4B5563 | (75,85,99,1) | 次要文本 |
| Gray-500 | #6B7280 | (107,114,128,1) | 禁用状态 |
| Gray-400 | #9CA3AF | (156,163,175,1) | 占位符文本 |
| Gray-300 | #D1D5DB | (209,213,221,1) | 浅边框 |
| Gray-200 | #E5E7EB | (229,231,235,1) | 高亮背景 |
| Gray-100 | #F3F4F6 | (243,244,246,1) | 弹窗背景（暂未使用） |

#### 4.2.2 主题色 (Blue Scale)

| 颜色名称 | 十六进制 | RGBA | 用途 |
|---------|---------|------|------|
| Blue-600 | #2563EB | (37,99,235,1) | 按钮悬停 |
| Blue-500 | #3B82F6 | (59,130,246,1) | 主色调 |
| Blue-400 | #60A5FA | (96,165,250,1) | 按钮默认 |
| Blue-300 | #93C5FD | (147,197,253,1) | 按钮激活 |

#### 4.2.3 语义色

| 颜色名称 | 十六进制 | RGBA | 用途 |
|---------|---------|------|------|
| Purple-500 | #A855F7 | (168,85,247,1) | AI 总结 |
| Green-500  | #22C55E | (34,197,94,1)  | 成功状态 |
| Red-500    | #EF4444 | (239,68,68,1)  | 错误状态 |
| Yellow-500 | #EAB308 | (234,179,8,1)  | 警告状态 |

#### 4.2.4 透明度变体

| 颜色名称 | 透明度 | 用途 |
|---------|--------|------|
| White-5  | 0.005  | 卡片背景 |
| White-10 | 0.01   | 悬浮面板背景 |
| White-20 | 0.02   | 悬停效果 |
| White-30 | 0.03   | 选中效果 |
| White-50 | 0.05   | 边框 |
| White-80 | 0.08   | 分隔线 |
| White-90 | 0.09   | 阴影 |

### 4.3 颜色使用规范

#### 4.3.1 背景色使用

```swift
// ✅ 正确：使用语义化颜色
.background(Color.themeBackground)  // 主背景
.background(Color.themeCard)        // 卡片背景
.background(Color.themePanel)       // 侧边栏背景

// ❌ 错误：直接使用具体颜色
.background(Color(red: 17/255, green: 24/255, blue: 39/255))
```

#### 4.3.2 文本颜色使用

```swift
// ✅ 正确：使用语义化文本颜色
.foreground(Color.themeTextPrimary)   // 主要文本
.foreground(Color.themeTextSecondary) // 次要文本
.foreground(Color.themeTextTertiary)  // 辅助文本
```

#### 4.3.3 边框颜色使用

```swift
// ✅ 正确：使用语义化边框颜色
.border(Color.themeBorder)           // 主边框
.border(Color.themeBorderSubtle)     // 次级边框
```

### 4.4 颜色对比度

所有颜色组合均需满足 WCAG 2.1 AA 标准：

- **正常文本**：对比度 ≥ 4.5:1
- **大文本**：对比度 ≥ 3:1
- **用户界面组件**：对比度 ≥ 3:1

**验证示例**：
- Gray-200 文本 (#E5E7EB) 在 Gray-900 背景 (#111827) 上：对比度 ≈ 13:1 ✅
- Gray-400 文本 (#9CA3AF) 在 Gray-900 背景 (#111827) 上：对比度 ≈ 5.7:1 ✅

### 4.5 颜色语义化

#### 4.5.1 状态颜色

| 状态 | 颜色 | 用途 |
|------|------|------|
| 默认 | Gray-500 | 未激活状态 |
| 激活 | Blue-500 | 当前选中 |
| 悬停 | Blue-400 | 鼠标悬停 |
| 按下 | Blue-600 | 按钮按下 |
| 禁用 | Gray-600 | 不可交互 |

#### 4.5.2 功能颜色

| 功能 | 颜色 | 用途 |
|------|------|------|
| AI | Purple-500 | AI 相关功能 |
| 成功 | Green-500 | 成功反馈 |
| 错误 | Red-500 | 错误提示 |
| 警告 | Yellow-500 | 警告信息 |

---

## 5. 字体系统

### 5.1 字体选择

**主字体**：SF Pro (San Francisco)
- Apple 官方系统字体
- 优秀的可读性和可访问性
- 支持动态字体大小

**代码字体**：SF Mono
- 等宽字体
- 适合代码和技术内容显示

### 5.2 字体尺寸

基于 Tailwind 的 rem 系统（1rem = 16px = 1.0），使用绝对尺寸：

| 尺寸名称 | CSS rem | pt | 用途 | 示例 |
|---------|---------|----|------|------|
| H1 | 1.0rem (16pt) | 16 | 标题、按钮文本 | "Settings" |
| H2 | 0.875rem (14pt) | 14 | 副标题、表单标签 | "AI Settings" |
| Body | 0.875rem (14pt) | 14 | 正文、列表项 | 记录内容 |
| Caption | 0.75rem (12pt) | 12 | 辅助文本、提示 | "Optional" |
| CaptionSmall | 0.625rem (10pt) | 10 | 标签、徽章 | "Local" |
| CaptionTiny | 0.5rem (8pt) | 8 | 版权信息（暂未使用） | "v1.0.0" |

### 5.3 字重

| 字重名称 | CSS | 数值 | 用途 |
|---------|-----|------|------|
| Light | font-light | 300 | 轻量文本 |
| Normal | normal | 400 | 普通文本 |
| Medium | font-medium | 500 | 中等强调 |
| Semibold | font-semibold | 600 | 重要标题 |
| Bold | font-bold | 700 | 强调文本 |

### 5.4 行高

基于 1.25 的行高比例（Tailwind 默认）：

| 字体尺寸 | 行高 (pt) | CSS 行高 |
|---------|-----------|----------|
| 16pt | 20pt | 1.25 |
| 14pt | 18pt | 1.29 |
| 12pt | 16pt | 1.33 |
| 10pt | 14pt | 1.4 |
| 8pt | 12pt | 1.5 |

### 5.5 字间距

| 字间距 | CSS | 数值 (em) | 用途 |
|-------|-----|-----------|------|
| Normal | tracking-normal | 0 | 默认 |
| Wider | tracking-wider | 0.05 | 标签、按钮 |

### 5.6 字体使用示例

```swift
// ✅ 正确：使用主题字体
Text("Settings")
    .font(.themeH1)           // 16pt, semibold

Text("API Key")
    .font(.themeCaption)      // 12pt, regular
    .foreground(Color.themeTextSecondary)

Text("Local")
    .font(.themeCaptionSmall) // 10pt, regular
    .foreground(Color.themeTextPrimary)
```

### 5.7 字体可访问性

- 支持系统动态字体
- 最小字号不小于 11pt
- 提供足够的行高
- 避免纯色背景上的纯色文本

---

## 6. 间距系统

### 6.1 间距原则

间距系统基于 4px 的基础单位，遵循 4 的倍数规则：

```
基础单位：4px (1 unit)
倍数序列：0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64, 80, 96, 128...
```

### 6.2 间距分类

#### 6.2.1 内边距 (Padding)

| 间距名称 | CSS | px | 用途 |
|---------|-----|----|------|
| p0 | p-0 | 0px | 无内边距 |
| p1 | p-1 | 4px | 紧凑内容 |
| p2 | p-2 | 8px | 默认内边距 |
| p3 | p-3 | 12px | 标准内边距 |
| p4 | p-4 | 16px | 宽松内边距 |
| p6 | p-6 | 24px | 大内边距 |
| p8 | p-8 | 32px | 特殊场景 |

#### 6.2.2 外边距 (Margin)

| 间距名称 | CSS | px | 用途 |
|---------|-----|----|------|
| m0 | m-0 | 0px | 无外边距 |
| m1 | m-1 | 4px | 紧凑布局 |
| m2 | m-2 | 8px | 标准间距 |
| m3 | m-3 | 12px | 内容分组 |
| m4 | m-4 | 16px | 区块分隔 |
| m6 | m-6 | 24px | 大分隔 |

#### 6.2.3 元素间距 (Gap)

| 间距名称 | px | 用途 |
|---------|----|------|
| gap-1 | 4px | 紧密元素 |
| gap-2 | 8px | 默认间距 |
| gap-3 | 12px | 标准间距 |
| gap-4 | 16px | 宽松间距 |

### 6.4 间距使用场景

#### 6.4.1 卡片间距

```swift
// ✅ 正确：使用主题间距
CardView()
    .padding(.themeP4.rawValue)  // 16px 内边距
    .spacing(.themeGap3.rawValue) // 12px 元素间距
```

#### 6.4.2 列表间距

```swift
// ✅ 正确：列表项间距
List {
    ItemView()
        .padding(.vertical, ThemeSpacing.p2.rawValue) // 8px 垂直间距
    Divider()
        .padding(.horizontal, ThemeSpacing.p4.rawValue) // 16px 水平间距
}
```

#### 6.4.3 表单间距

```swift
// ✅ 正确：表单布局间距
VStack(spacing: ThemeSpacing.p3.rawValue) { // 12px 垂直间距
    TextField("Enter API Key", text: $apiKey)
        .textFieldStyle(.roundedBorder)
        .padding(ThemeSpacing.p2.rawValue) // 8px 内边距

    Toggle("Enable AI", isOn: $isEnabled)
        .padding(.horizontal, ThemeSpacing.p3.rawValue) // 12px 水平间距
}
.padding(ThemeSpacing.p4.rawValue) // 16px 容器内边距
```

### 6.5 间距规范

#### 6.5.1 垂直节奏

保持垂直方向的视觉节奏一致：

- **段落间距**：16px (p4)
- **标题与内容**：12px (p3)
- **列表项间距**：8px (p2)
- **区块间距**：24px (p6)

#### 6.5.2 水平对齐

保持水平方向的对齐一致：

- **左对齐偏移**：16px (p4)
- **右对齐偏移**：16px (p4)
- **居中内容宽度**：最大 640px

---

## 7. 形状系统

### 7.1 圆角系统

基于 Tailwind 的 rounded 系统：

| 圆角名称 | CSS | px | 用途 |
|---------|-----|----|------|
| none | rounded-none | 0px | 锐角元素 |
| sm | rounded-sm | 2px | 紧凑元素 |
| base | rounded | 4px | 默认圆角 |
| md | rounded-md | 6px | 按钮、输入框 |
| lg | rounded-lg | 8px | 卡片、面板 |
| xl | rounded-xl | 12px | 大组件 |
| 2xl | rounded-2xl | 16px | 特殊容器 |
| 3xl | rounded-3xl | 24px | 特殊设计 |
| full | rounded-full | 9999px | 圆形 |

### 7.2 边框系统

#### 7.2.1 边框宽度

| 边框类型 | px | 用途 |
|---------|----|------|
| thin | 1px | 轻量分隔 |
| medium | 2px | 标准边框 |
| thick | 3px | 强调边框 |

#### 7.2.2 边框样式

```swift
// ✅ 正确：使用主题边框
View()
    .border(width: ThemeRadius.base.rawValue, color: Color.themeBorder)
```

### 7.3 阴影系统

基于主题颜色的阴影：

| 阴影类型 | 描述 | 用途 |
|---------|------|------|
| card | 中等阴影 | 卡片提升效果 |
| button | 轻微阴影 | 按钮立体感 |
| panel | 柔和阴影 | 面板边界 |
| inset | 内阴影 | 凹陷效果 |

```swift
// ✅ 正确：使用主题阴影
View()
    .themeShadow(color: .black, radius: 20, x: 0, y: 10)
```

### 7.4 形状使用规范

#### 7.4.1 组件形状

| 组件类型 | 推荐圆角 | 边框 | 阴影 |
|---------|---------|------|------|
| 卡片 | lg (8px) | thin (1px) | card |
| 按钮 | md (6px) | none | button |
| 输入框 | md (6px) | medium (2px) | none |
| 面板 | 2xl (16px) | thin (1px) | panel |
| 标签 | full (圆形) | thin (1px) | none |

#### 7.4.2 视觉层次

通过形状表达视觉层次：

- **高层级**：大圆角 + 强阴影
- **中层级**：中圆角 + 中阴影
- **低层级**：小圆角 + 弱阴影

---

## 8. 动画系统

### 8.1 动画原则

#### 8.1.1 微妙性

动画应该微妙而不突兀，时长控制在 200-500ms 之间。

#### 8.1.2 自然性

使用缓动函数模拟自然运动，避免线性动画。

#### 8.1.3 一致性

相同类型的交互使用相同的动画参数。

#### 8.1.4 性能

优先使用 transform 和 opacity，避免 layout 和 paint。

### 8.2 动画时长

| 动画类型 | 时长 (ms) | 用途 |
|---------|-----------|------|
| instant | 0ms | 即时反馈 |
| quick | 100ms | 快速响应 |
| normal | 300ms | 标准动画 |
| slow | 500ms | 重要过渡 |
| extra slow | 1000ms | 特殊场景 |

### 8.3 缓动函数

| 缓动名称 | 函数类型 | 描述 | 用途 |
|---------|---------|------|------|
| ease-in | 缓入 | 开始慢，结束快 | 淡入、展开 |
| ease-out | 缓出 | 开始快，结束慢 | 淡出、收起 |
| ease-in-out | 缓入缓出 | 两端慢，中间快 | 模态窗口 |
| spring | 弹性 | 模拟弹簧振荡 | 按钮点击 |
| linear | 线性 | 匀速运动 | 旋转动画 |

### 8.4 动画类型

#### 8.4.1 进入动画 (Entrance)

```swift
// ✅ 正确：使用主题动画
View()
    .animateIn(duration: ._300, curve: .easeOut)
```

**参数**：
- 透明度：0.0 → 1.0
- 缩放：0.9 → 1.0
- 位移：从下方 10px 移动到原位置

#### 8.4.2 退出动画 (Exit)

```swift
// ✅ 正确：使用主题动画
View()
    .transition(.slideBottom)
```

**参数**：
- 透明度：1.0 → 0.0
- 缩放：1.0 → 0.9
- 位移：移动到下方 10px

#### 8.4.3 悬停动画 (Hover)

```swift
// ✅ 正确：使用主题动画
Button("Click me")
    .animateSpring(response: 0.2, dampingFraction: 0.8)
```

**参数**：
- 缩放：1.0 → 1.05
- 阴影：增强
- 背景：轻微变亮

#### 8.4.4 点击反馈 (Press)

```swift
// ✅ 正确：使用主题动画
Button(action: action) {
    content
}
.buttonStyle(.pressable)
```

**参数**：
- 缩放：1.0 → 0.95
- 透明度：1.0 → 0.9
- 即时响应

### 8.5 动画实现

#### 8.5.1 淡入淡出

```swift
struct FadeInOutModifier: ViewModifier {
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1.0 : 0.0)
            .scaleEffect(isVisible ? 1.0 : 0.9)
            .animation(
                .easeOut(duration: ThemeDuration._300.rawValue),
                value: isVisible
            )
            .onAppear { isVisible = true }
    }
}
```

#### 8.5.2 滑动面板

```swift
struct SlideInModifier: ViewModifier {
    let direction: SlideDirection
    @State private var isSlidIn = false

    func body(content: Content) -> some View {
        content
            .offset(
                x: isSlidIn ? 0 : direction.offsetX,
                y: isSlidIn ? 0 : direction.offsetY
            )
            .animation(
                .easeOut(duration: ThemeDuration._300.rawValue),
                value: isSlidIn
            )
            .onAppear { isSlidIn = true }
    }
}
```

#### 8.5.3 按钮悬停

```swift
struct HoverEffectModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(
                .spring(response: 0.2, dampingFraction: 0.8),
                value: isHovering
            )
            .onHover { hovering in
                isHovering = hovering
            }
    }
}
```

### 8.6 动画性能优化

#### 8.6.1 使用 withAnimation

```swift
// ✅ 正确：使用 withAnimation
@State private var isActive = false

var body: some View {
    Button("Toggle") {
        withAnimation(.easeOut(duration: 0.3)) {
            isActive.toggle()
        }
    }
}
```

#### 8.6.2 避免重绘

- 使用 `.drawingGroup()` 合并图层
- 使用 `.allowsHitTesting(false)` 减少交互检测
- 使用 `.clipped()` 限制绘制区域

#### 8.6.3 动画降级

在性能较低的设备上，可以禁用动画：

```swift
var animation: Animation? {
    if PreferencesManager.shared.animationsEnabled {
        return .easeOut(duration: 0.3)
    } else {
        return nil
    }
}
```

---

## 9. 组件设计规范

### 9.1 按钮组件 (Button)

#### 9.1.1 样式分类

| 类型 | 背景 | 边框 | 文字 | 用途 |
|-----|------|------|------|------|
| Primary | Blue-500 | None | White | 主要操作 |
| Secondary | White-5 | White-10 | Gray-200 | 次要操作 |
| Ghost | None | White-10 | Gray-200 | 轻量操作 |
| Danger | Red-500 | None | White | 危险操作 |

#### 9.1.2 尺寸规格

| 尺寸 | 高度 | 内边距 | 字体 |
|-----|------|--------|------|
| Small | 32px | p2 | Caption |
| Medium | 36px | p3 | Body |
| Large | 40px | p4 | H2 |

#### 9.1.3 状态规范

```swift
// ✅ 正确：按钮状态样式
Button("Click me") { }
    .buttonStyle(ThemeButtonStyle(
        background: .themeBlue500,
        foreground: .white,
        cornerRadius: .md
    ))
    .hoverEffect(.automatic) // 自动悬停效果
```

**状态变化**：
- 默认：正常样式
- 悬停：背景色变亮，轻微放大
- 按下：背景色变暗，轻微缩小
- 禁用：透明度降低至 50%

### 9.2 输入框组件 (TextField)

#### 9.2.1 样式规范

```swift
// ✅ 正确：输入框样式
TextField("Enter text", text: $text)
    .textFieldStyle(ThemeTextFieldStyle())
    .padding(.themeP3.rawValue)
```

**设计参数**：
- 背景：Black-40 (40% 透明度)
- 边框：White-10 (10% 透明度)
- 圆角：md (6px)
- 内边距：p3 (12px)

#### 9.2.2 状态规范

- **默认**：标准边框
- **聚焦**：边框颜色变亮，添加外发光
- **禁用**：背景透明度降低

### 9.3 卡片组件 (Card)

#### 9.3.1 样式规范

```swift
// ✅ 正确：卡片样式
CardView(content: {
    // 卡片内容
})
.cardStyle(
    background: .themeCard,
    cornerRadius: .lg,
    border: .themeBorder,
    shadow: true
)
```

**设计参数**：
- 背景：White-5 (5% 透明度)
- 边框：White-10 (10% 透明度)
- 圆角：lg (8px)
- 阴影：中等强度

#### 9.3.2 交互规范

- **悬停**：背景色变亮 (White-10)
- **点击**：轻微按下效果 (scale 0.98)
- **选中**：边框高亮 (Blue-500)

### 9.4 开关组件 (Toggle)

#### 9.4.1 样式规范

```swift
// ✅ 正确：开关样式
Toggle("Enable feature", isOn: $isEnabled)
    .toggleStyle(ThemeToggleStyle())
```

**设计参数**：
- 轨道背景：White-10
- 轨道圆角：full (圆形)
- 滑块背景：Gray-200
- 滑块圆角：full (圆形)
- 激活色：Blue-500

#### 9.4.2 动画规范

- 滑动动画：300ms ease-out
- 颜色过渡：200ms ease-in-out

### 9.5 标签组件 (Tag)

#### 9.5.1 样式分类

| 类型 | 背景 | 边框 | 文字 | 用途 |
|-----|------|------|------|------|
| Default | White-5 | White-10 | Gray-200 | 默认标签 |
| Primary | Blue-500 | None | White | 主要标签 |
| Success | Green-500 | None | White | 成功标签 |
| Warning | Yellow-500 | None | White | 警告标签 |
| Error | Red-500 | None | White | 错误标签 |

#### 9.5.2 尺寸规格

| 尺寸 | 高度 | 内边距 | 字体 |
|-----|------|--------|------|
| Small | 20px | p1 + p2 | CaptionSmall |
| Medium | 24px | p2 + p3 | Caption |
| Large | 28px | p3 + p4 | Body |

---

## 10. 动效设计指南

### 10.1 悬浮窗动效

#### 10.1.1 显示动画

**目标**：平滑地从无到有地显示悬浮窗

**参数**：
- 透明度：0.0 → 1.0
- 缩放：0.9 → 1.0
- 时长：300ms
- 缓动：ease-out

```swift
// 实现示例
withAnimation(.easeOut(duration: 0.3)) {
    isPanelVisible = true
}
```

**设计考虑**：
- 从 0.9 缩放开始，避免突兀的出现
- 使用 ease-out 缓动，营造自然的"落地"感
- 300ms 时长平衡了响应速度和视觉流畅度

#### 10.1.2 隐藏动画

**目标**：优雅地隐藏悬浮窗

**参数**：
- 透明度：1.0 → 0.0
- 缩放：1.0 → 0.9
- 时长：300ms
- 缓动：ease-in

**实现要点**：
- 使用 `.transition()` 配合状态管理
- 先停止键盘监听，再播放动画
- 动画完成后才真正隐藏窗口

### 10.2 按钮动效

#### 10.2.1 悬停效果

**目标**：提供清晰的交互反馈

**参数**：
- 缩放：1.0 → 1.05
- 背景亮度：轻微提升
- 阴影：增强
- 时长：200ms
- 缓动：spring

```swift
// 实现示例
Button("Click me") { }
    .scaleEffect(isHovering ? 1.05 : 1.0)
    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovering)
```

**设计考虑**：
- 使用 spring 动画营造弹性反馈
- 缩放控制在 5%，避免过度夸张
- 配合背景色变化增强视觉效果

#### 10.2.2 点击反馈

**目标**：即时的触觉反馈

**参数**：
- 缩放：1.0 → 0.95
- 透明度：1.0 → 0.9
- 时长：100ms
- 类型：instant

**实现要点**：
- 使用 `withAnimation(.instant)` 实现即时反馈
- 可配合 `NSHapticFeedbackManager` 提供触觉反馈
- 快速的动画传达"已响应"的信息

### 10.3 记录卡片动效

#### 10.3.1 展开/收起

**目标**：平滑地切换记录的详细内容显示

**参数**：
- 高度：自动计算
- 缩放：1.0 → 1.0 (无缩放)
- 透明度：1.0 → 1.0 (无变化)
- 时长：300ms
- 缓动：ease-out

**实现挑战**：
- SwiftUI 的 `animation()` 对高度变化支持有限
- 需要手动计算目标高度
- 使用 `matchedGeometryEffect` 可能是解决方案

#### 10.3.2 悬停效果

**目标**：增强卡片的可交互性感知

**参数**：
- 上移：0 → -4px
- 阴影：增强
- 边框：高亮
- 时长：200ms
- 缓动：ease-out

### 10.4 Toast 消息动效

#### 10.4.1 进入动画

**目标**：从顶部滑入并淡入

**参数**：
- 位移：-20px → 0px
- 透明度：0.0 → 1.0
- 时长：300ms
- 缓动：ease-out

#### 10.4.2 离开动画

**目标**：平滑地淡出并滑出

**参数**：
- 位移：0px → -20px
- 透明度：1.0 → 0.0
- 时长：300ms
- 缓动：ease-in

### 10.5 设置面板动效

#### 10.5.1 侧滑动画

**目标**：从右侧滑入设置面板

**参数**：
- 位移：panel.width → 0
- 透明度：0.8 → 1.0
- 时长：300ms
- 缓动：ease-out

**实现方式**：
- 使用 `offset` 控制水平位置
- 使用 `matchedGeometryEffect` 同步动画
- 配合背景蒙层的透明度变化

### 10.6 加载动效

#### 10.6.1 旋转指示器

**目标**：提供清晰的加载状态反馈

**参数**：
- 旋转：0° → 360°
- 时长：1000ms
- 类型：linear (匀速)
- 重复：forever

```swift
// 实现示例
ProgressView()
    .progressViewStyle(CircularProgressViewStyle(tint: .themeBlue500))
    .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: isLoading)
```

#### 10.6.2 骨架屏

**目标**：在内容加载时提供占位反馈

**参数**：
- 透明度：0.3 ↔ 0.7
- 时长：1.5s
- 类型：ease-in-out
- 重复：forever

**实现方式**：
- 使用渐变色模拟文字形状
- 透明度循环变化营造"流动"感
- 适合长文本和图片的占位

### 10.7 AI 处理动效

#### 10.7.1 AI 状态指示

**目标**：可视化 AI 处理进度

**参数**：
- 颜色：Blue-500 → Purple-500
- 脉冲：轻微放大缩小
- 时长：1.5s
- 类型：ease-in-out
- 重复：forever

**实现方式**：
- 使用 `scaleEffect` 制造呼吸效果
- 颜色渐变表示处理状态
- 可配合微光效果增强科技感

### 10.8 窗口拖拽动效

#### 10.8.1 拖拽反馈

**目标**：提供清晰的拖拽状态反馈

**参数**：
- 缩放：1.0 → 1.02
- 阴影：增强
- 边框：高亮
- 时长：100ms

**实现要点**：
- 使用 `WindowDragHandler` 实现拖拽
- 鼠标按下时立即触发动画
- 鼠标释放时恢复原状

#### 10.8.2 边界吸附

**目标**：窗口靠近屏幕边缘时自动吸附

**参数**：
- 吸附距离：20px
- 动画时长：200ms
- 缓动：ease-in

**实现方式**：
- 检测窗口位置
- 计算到屏幕边缘的距离
- 超过阈值时触发动画移动

### 10.9 动效性能优化

#### 10.9.1 视图合并

```swift
// ✅ 正确：使用 drawingGroup 合并图层
View()
    .drawingGroup() // 合并为单个图层，提升动画性能
```

#### 10.9.2 减少重绘

```swift
// ✅ 正确：限制重绘区域
View()
    .clipped() // 限制在边界内绘制
    .allowsHitTesting(false) // 减少交互检测开销
```

#### 10.9.3 动画降级

```swift
// ✅ 正确：根据设置禁用动画
var animation: Animation? {
    if PreferencesManager.shared.animationsEnabled {
        return .easeOut(duration: 0.3)
    } else {
        return nil
    }
}

// 使用
withAnimation(animation) {
    // 状态变化
}
```

### 10.10 动效设计原则总结

1. **一致性**：相同类型的交互使用相同的动画
2. **自然性**：使用缓动函数模拟真实世界的运动
3. **微妙性**：动画应该增强体验，而不是分散注意力
4. **响应性**：动画时长应该与操作的重要性匹配
5. **性能优先**：在视觉效果和性能之间找到平衡

---

## 11. 响应式设计

### 11.1 断点系统

基于设备尺寸定义响应式断点：

| 断点名称 | 最小宽度 | 用途 |
|---------|---------|------|
| xs | 320px | 超小屏幕 |
| sm | 640px | 小屏幕 |
| md | 768px | 中等屏幕 |
| lg | 1024px | 大屏幕 |
| xl | 1280px | 超大屏幕 |

### 11.2 布局适配

#### 11.2.1 悬浮窗布局

```swift
// ✅ 正确：响应式悬浮窗
struct ResponsiveFloatingView: View {
    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 768 {
                // 大屏幕：侧边栏 + 主内容
                HStack(spacing: ThemeSpacing.p4.rawValue) {
                    SidebarView()
                        .frame(width: 200)
                    ContentView()
                }
            } else {
                // 小屏幕：垂直布局
                VStack(spacing: ThemeSpacing.p4.rawValue) {
                    HeaderView()
                    ContentView()
                }
            }
        }
    }
}
```

#### 11.2.2 设置面板

```swift
// ✅ 正确：响应式设置面板
struct ResponsiveSettingsView: View {
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(columns: gridColumns(for: geometry.size.width), spacing: ThemeSpacing.p4.rawValue) {
                    // 设置项
                }
                .padding(ThemeSpacing.p4.rawValue)
            }
        }
    }

    private func gridColumns(for width: CGFloat) -> [GridItem] {
        if width >= 1024 {
            return Array(repeating: GridItem(.fixed(300)), count: 3)
        } else if width >= 768 {
            return Array(repeating: GridItem(.fixed(280)), count: 2)
        } else {
            return [GridItem(.flexible())]
        }
    }
}
```

### 11.3 字体响应

使用动态字体适配不同屏幕：

```swift
// ✅ 正确：动态字体
Text("Title")
    .font(.system(size: dynamicFontSize(base: 16)))
    .minimumScaleFactor(0.8) // 允许缩小到 80%

private func dynamicFontSize(base: CGFloat) -> CGFloat {
    let size = max(12, min(20, base)) // 限制在 12-20pt 之间
    return UIFontMetrics.default.scaledValue(for: size)
}
```

### 11.4 图标响应

```swift
// ✅ 正确：响应式图标
Icon(name)
    .frame(width: iconSize, height: iconSize)
    .aspectRatio(1.0, contentMode: .fit)
```

---

## 12. 可访问性设计

### 12.1 键盘导航

确保所有交互元素支持键盘访问：

```swift
// ✅ 正确：键盘导航支持
Button("Save") {
    // 保存操作
}
.keyboardShortcut(.defaultAction) // 回车键
.onAppear {
    NSApp.keyWindow?.initialFirstResponder = self
}
```

### 12.2 语义化标签

为所有视觉元素提供语义化描述：

```swift
// ✅ 正确：语义化标签
Button(action: saveAction) {
    Image(systemName: "square.and.arrow.down")
        .accessibilityLabel("Save Document")
        .accessibilityAddTraits(.isButton)
}
```

### 12.3 动态字体

支持系统动态字体设置：

```swift
// ✅ 正确：动态字体
Text("Content")
    .font(.body) // 使用系统字体
    .allowsTightening(true) // 允许文字压缩
    .lineLimit(3) // 限制行数
```

### 12.4 高对比度

支持高对比度模式：

```swift
// ✅ 正确：高对比度支持
Text("Important")
    .foreground(
        colorScheme == .dark
            ? Color.accentColor
            : Color.primary
    )
    .shadow(
        color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1),
        radius: 4,
        x: 0,
        y: 2
    )
```

### 12.5 VoiceOver 支持

为复杂视图提供 VoiceOver 描述：

```swift
// ✅ 正确：VoiceOver 支持
struct AccessibleChart: View {
    var body: some View {
        ChartView()
            .accessibilityElement()
            .accessibilityLabel("Monthly Sales Chart")
            .accessibilityValue("January: 1000, February: 1200, March: 1100")
            .accessibilityHint("Double tap to hear detailed data")
    }
}
```

---

## 13. 主题切换机制

### 13.1 主题状态管理

使用 ObservableObject 管理主题状态：

```swift
// ✅ 正确：主题状态管理
@MainActor
final class ThemeManager: ObservableObject {
    @Published var currentTheme: Theme = .dark
    @Published var animationsEnabled: Bool = true

    init() {
        loadTheme()
    }

    func setTheme(_ theme: Theme) {
        currentTheme = theme
        saveTheme()
        // 发送主题变更通知
        NotificationCenter.default.post(name: .themeChanged, object: theme)
    }

    private func loadTheme() {
        // 从 UserDefaults 加载主题
    }

    private func saveTheme() {
        // 保存主题到 UserDefaults
    }
}
```

### 13.2 主题订阅

视图订阅主题变更：

```swift
// ✅ 正确：主题订阅
struct ThemedView: View {
    @StateObject private var themeManager = ThemeManager()

    var body: some View {
        content
            .environmentObject(themeManager)
            .onChange(of: themeManager.currentTheme) { newTheme in
                // 应用新主题
                applyTheme(newTheme)
            }
    }
}
```

### 13.3 动态主题切换

支持运行时切换主题：

```swift
// ✅ 正确：动态主题切换
func applyTheme(_ theme: Theme) {
    switch theme {
    case .dark:
        NSApp.appearance = NSAppearance(named: .darkAqua)
    case .light:
        NSApp.appearance = NSAppearance(named: .aqua)
    }
}
```

---

## 14. 实现指南

### 14.1 主题文件导入

在视图中导入主题扩展：

```swift
import SwiftUI
import AppKit

// 导入主题系统
import Color_Theme
import Font_Theme
import Spacing_Theme
import Shape_Theme
import Animation_Theme
```

### 14.2 视图使用主题

```swift
struct ExampleView: View {
    var body: some View {
        VStack(spacing: ThemeSpacing.p3.rawValue) {
            Text("Title")
                .font(.themeH1)
                .foreground(Color.themeTextPrimary)

            Text("Subtitle")
                .font(.themeCaption)
                .foreground(Color.themeTextSecondary)

            Button("Action") {
                // Action
            }
            .buttonStyle(ThemeButtonStyle())
            .animateSpring()
        }
        .padding(ThemeSpacing.p4.rawValue)
        .background(Color.themeBackground)
        .cornerRadius(ThemeRadius.lg.rawValue)
    }
}
```

### 14.3 组件库使用

```swift
// ✅ 正确：使用主题组件
struct ThemedComponents: View {
    var body: some View {
        VStack(spacing: ThemeSpacing.p4.rawValue) {
            // 主按钮
            ThemeButton(
                text: "Primary Action",
                style: .primary,
                action: primaryAction
            )

            // 次要按钮
            ThemeButton(
                text: "Secondary Action",
                style: .secondary,
                action: secondaryAction
            )

            // 输入框
            ThemeTextField(
                text: $inputText,
                placeholder: "Enter text"
            )

            // 开关
            ThemeToggle(
                isOn: $isEnabled,
                label: "Enable Feature"
            )
        }
        .padding(ThemeSpacing.p4.rawValue)
    }
}
```

### 14.4 动画使用

```swift
// ✅ 正确：使用主题动画
struct AnimatedView: View {
    @State private var isVisible = false
    @State private var isRotating = false

    var body: some View {
        VStack(spacing: ThemeSpacing.p4.rawValue) {
            Button("Toggle") {
                withAnimation(.easeOut(duration: 0.3)) {
                    isVisible.toggle()
                }
            }

            if isVisible {
                RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                    .fill(Color.themeBlue500)
                    .frame(width: 100, height: 100)
                    .animateSpin(duration: 1.0)
                    .onAppear { isRotating = true }
            }
        }
    }
}
```

---

## 15. 最佳实践

### 15.1 性能优化

#### 15.1.1 视图结构优化

```swift
// ✅ 正确：扁平化视图结构
struct OptimizedView: View {
    var body: some View {
        HStack {
            Image(systemName: "star")
                .foreground(Color.themeYellow500)

            Text("Title")
                .font(.themeH2)
                .foreground(Color.themeTextPrimary)

            Spacer()
        }
        .padding(ThemeSpacing.p3.rawValue)
        .background(Color.themeCard)
        .cornerRadius(ThemeRadius.md.rawValue)
    }
}
```

#### 15.1.2 动画性能

```swift
// ✅ 正确：优化动画性能
struct PerformantAnimation: View {
    @State private var isAnimating = false

    var body: some View {
        Rectangle()
            .fill(Color.themeBlue500)
            .frame(width: 100, height: 100)
            .scaleEffect(isAnimating ? 1.2 : 1.0)
            .animation(
                .easeOut(duration: 0.3),
                value: isAnimating
            )
            .drawingGroup() // 合并图层提升性能
            .onAppear {
                isAnimating = true
            }
    }
}
```

### 15.2 代码组织

#### 15.2.1 主题文件组织

```
Sources/QuiteNote/UI/Theme/
├── Color+Theme.swift           # 颜色定义
├── Font+Theme.swift            # 字体定义
├── Spacing+Theme.swift         # 间距定义
├── Shape+Theme.swift           # 形状定义
├── Animation+Theme.swift       # 动画定义
├── ThemeExtensions.swift       # 视图扩展
├── Components/                 # 主题组件
│   ├── ThemeButton.swift
│   ├── ThemeTextField.swift
│   ├── ThemeToggle.swift
│   └── ThemeCard.swift
└── Utilities/                  # 工具函数
    ├── ThemeUtils.swift
    └── Accessibility.swift
```

#### 15.2.2 视图组织

```
Sources/QuiteNote/UI/
├── FloatingPanelController.swift  # 悬浮窗控制器
├── FloatingRootView.swift           # 根视图
├── Components/                      # 通用组件
│   ├── RecordCardView.swift
│   ├── HeatmapView.swift
│   ├── ToastView.swift
│   └── SearchBar.swift
├── Settings/                        # 设置相关
│   ├── SettingsOverlayView.swift
│   └── SettingsComponents.swift
└── Theme/                           # 主题系统
    ├── Color+Theme.swift
    ├── Font+Theme.swift
    └── ...
```

### 15.3 测试策略

#### 15.3.1 主题测试

```swift
// ✅ 正确：测试主题颜色
func testThemeColors() {
    XCTAssertEqual(Color.themeBlue500, Color(red: 59/255, green: 130/255, blue: 246/255))
    XCTAssertEqual(Color.themeGray900, Color(red: 17/255, green: 24/255, blue: 39/255))
}

// ✅ 正确：测试间距
func testThemeSpacing() {
    XCTAssertEqual(ThemeSpacing.p4.rawValue, 16)
    XCTAssertEqual(ThemeSpacing.p8.rawValue, 32)
}

// ✅ 正确：测试动画时长
func testThemeAnimations() {
    XCTAssertEqual(ThemeDuration._300.rawValue, 0.3)
    XCTAssertEqual(ThemeDuration._500.rawValue, 0.5)
}
```

#### 15.3.2 UI 测试

```swift
// ✅ 正确：UI 测试
func testButtonAppearance() {
    let button = ThemeButton(text: "Test", style: .primary, action: {})

    // 测试背景色
    XCTAssertTrue(button.hasBackground(color: .themeBlue500))

    // 测试字体
    XCTAssertTrue(button.hasFont(.themeH2))

    // 测试圆角
    XCTAssertTrue(button.hasCornerRadius(ThemeRadius.md.rawValue))
}
```

### 15.4 维护建议

#### 15.4.1 主题更新

1. **颜色更新**：修改 `Color+Theme.swift`
2. **间距调整**：修改 `Spacing+Theme.swift`
3. **动画调整**：修改 `Animation+Theme.swift`
4. **字体调整**：修改 `Font+Theme.swift`

#### 15.4.2 版本控制

- 主题文件变更时更新文档
- 记录每次主题调整的原因
- 保持向后兼容性
- 提供迁移指南

#### 15.4.3 代码审查

- 确保使用主题 API
- 检查颜色对比度
- 验证动画性能
- 确认可访问性支持

---

## 16. 附录

### 16.1 颜色对照表

| 语义名称 | 颜色值 | 用途 |
|---------|--------|------|
| themeBackground | Gray-900 | 主背景 |
| themeCard | White-5 | 卡片背景 |
| themePanel | Black-20 | 侧边栏背景 |
| themeBorder | White-10 | 边框 |
| themeTextPrimary | Gray-200 | 主要文本 |
| themeTextSecondary | Gray-400 | 次要文本 |
| themeTextTertiary | Gray-500 | 辅助文本 |
| themeBlue500 | Blue-500 | 主色调 |
| themePurple500 | Purple-500 | AI 状态 |
| themeGreen500 | Green-500 | 成功状态 |
| themeRed500 | Red-500 | 错误状态 |
| themeYellow500 | Yellow-500 | 警告状态 |

### 16.2 间距对照表

| 间距名称 | 值 (px) | 用途 |
|---------|---------|------|
| p0 | 0 | 无间距 |
| p1 | 4 | 紧凑间距 |
| p2 | 8 | 默认间距 |
| p3 | 12 | 标准间距 |
| p4 | 16 | 宽松间距 |
| p6 | 24 | 大间距 |
| p8 | 32 | 特殊间距 |

### 16.3 动画对照表

| 动画名称 | 时长 | 缓动 | 用途 |
|---------|------|------|------|
| ease-in | 300ms | ease-in | 淡入 |
| ease-out | 300ms | ease-out | 淡出 |
| ease-in-out | 300ms | ease-in-out | 模态 |
| spring | 200ms | spring | 按钮 |
| spin | 1000ms | linear | 加载 |
| pulse | 1500ms | ease-in-out | 呼吸 |

### 16.4 字体对照表

| 字体名称 | 大小 (pt) | 字重 | 用途 |
|---------|-----------|------|------|
| themeH1 | 16 | semibold | 标题 |
| themeH2 | 14 | semibold | 副标题 |
| themeBody | 14 | regular | 正文 |
| themeCaption | 12 | regular | 辅助 |
| themeCaptionSmall | 10 | regular | 标签 |

### 16.5 圆角对照表

| 圆角名称 | 值 (px) | 用途 |
|---------|---------|------|
| none | 0 | 锐角 |
| sm | 2 | 紧凑 |
| base | 4 | 默认 |
| md | 6 | 按钮 |
| lg | 8 | 卡片 |
| xl | 12 | 大组件 |
| 2xl | 16 | 面板 |
| full | 9999 | 圆形 |

### 16.6 参考资源

1. [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
2. [Tailwind CSS Documentation](https://tailwindcss.com/docs)
3. [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
4. [WCAG 2.1 Guidelines](https://www.w3.org/TR/WCAG21/)

### 16.7 相关文档

1. **产品需求文档**：`docs/Product-Requirements-Document.md`
2. **技术设计文档**：`docs/Technical-Design-Document.md`
3. **API 文档**：`docs/API-Reference.md`
4. **用户手册**：`docs/User-Guide.md`

---

## 文档审批

| 角色 | 姓名 | 签名 | 日期 |
|------|------|------|------|
| 产品负责人 | | | |
| 设计负责人 | | | |
| 技术负责人 | | | |
| 项目经理 | | | |

---

**文档结束**