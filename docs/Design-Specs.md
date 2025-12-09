# 设计规范文档

## 概述

本设计规范基于 Tailwind CSS 设计系统，为 QuiteNote Mac App 提供统一的视觉语言和交互标准。

**源文件**: `/Users/xuyingzhou/Project/study-mac-app/quite-note/note.jsx`

**设计风格**: 现代、简洁、专业的 Mac 应用设计

---

## 1. 主题色调

### 1.1 颜色系统

#### 基础色板

| 颜色名称 | Hex 值 | RGB 值 | 用途 | 示例 |
|---------|--------|--------|------|------|
| themeGray900 | #111827 | (17, 24, 39) | 主背景色 | ![#111827](https://via.placeholder.com/20x20/111827/111827) |
| themeGray800 | #1F2937 | (31, 41, 55) | 次级背景 | ![#1F2937](https://via.placeholder.com/20x20/1F2937/1F2937) |
| themeGray700 | #374151 | (55, 65, 81) | 边框、分隔线 | ![#374151](https://via.placeholder.com/20x20/374151/374151) |
| themeGray600 | #4B5563 | (75, 85, 99) | 次级文本 | ![#4B5563](https://via.placeholder.com/20x20/4B5563/4B5563) |
| themeGray500 | #6B7280 | (107, 114, 128) | 三级文本 | ![#6B7280](https://via.placeholder.com/20x20/6B7280/6B7280) |
| themeGray400 | #9CA3AF | (156, 163, 175) | 四级文本 | ![#9CA3AF](https://via.placeholder.com/20x20/9CA3AF/9CA3AF) |
| themeGray300 | #D1D5DB | (209, 213, 221) | 占位文本 | ![#D1D5DB](https://via.placeholder.com/20x20/D1D5DB/D1D5DB) |
| themeGray200 | #E5E7EB | (229, 231, 235) | 主要文本 | ![#E5E7EB](https://via.placeholder.com/20x20/E5E7EB/E5E7EB) |
| themeGray100 | #F3F4F6 | (243, 244, 246) | 浅背景 | ![#F3F4F6](https://via.placeholder.com/20x20/F3F4F6/F3F4F6) |

#### 功能色

| 颜色名称 | Hex 值 | RGB 值 | 用途 | 示例 |
|---------|--------|--------|------|------|
| themeBlue600 | #2563EB | (37, 99, 235) | 主色调 | ![#2563EB](https://via.placeholder.com/20x20/2563EB/2563EB) |
| themeBlue500 | #3B82F6 | (59, 130, 246) | 次主色 | ![#3B82F6](https://via.placeholder.com/20x20/3B82F6/3B82F6) |
| themeBlue400 | #60A5FA | (96, 165, 250) | 悬停色 | ![#60A5FA](https://via.placeholder.com/20x20/60A5FA/60A5FA) |
| themeBlue300 | #93C5FD | (147, 197, 253) | 激活色 | ![#93C5FD](https://via.placeholder.com/20x20/93C5FD/93C5FD) |

#### 语义色

| 颜色名称 | Hex 值 | RGB 值 | 用途 | 示例 |
|---------|--------|--------|------|------|
| themePurple500 | #A855F7 | (168, 85, 247) | AI/智能 | ![#A855F7](https://via.placeholder.com/20x20/A855F7/A855F7) |
| themeGreen500 | #22C55E | (34, 197, 94) | 成功/确认 | ![#22C55E](https://via.placeholder.com/20x20/22C55E/22C55E) |
| themeRed500 | #EF4444 | (239, 68, 68) | 错误/删除 | ![#EF4444](https://via.placeholder.com/20x20/EF4444/EF4444) |
| themeYellow500 | #EAB308 | (234, 179, 8) | 警告/硬件 | ![#EAB308](https://via.placeholder.com/20x20/EAB308/EAB308) |

#### 透明色

| 颜色名称 | 透明度 | 用途 | 示例 |
|---------|--------|------|------|
| themeWhite5 | 0.02 | 微透明白色 | ![#FFFFFF](https://via.placeholder.com/20x20/FFFFFF/FFFFFF?text=+) |
| themeWhite10 | 0.04 | 轻透明白色 | ![#FFFFFF](https://via.placeholder.com/20x20/FFFFFF/FFFFFF?text=+) |
| themeWhite20 | 0.08 | 中透明白色 | ![#FFFFFF](https://via.placeholder.com/20x20/FFFFFF/FFFFFF?text=+) |
| themeWhite50 | 0.20 | 高透明白色 | ![#FFFFFF](https://via.placeholder.com/20x20/FFFFFF/FFFFFF?text=+) |

| 颜色名称 | 透明度 | 用途 | 示例 |
|---------|--------|------|------|
| themeBlack20 | 0.20 | 低透明黑色 | ![#000000](https://via.placeholder.com/20x20/000000/000000?text=+) |
| themeBlack40 | 0.40 | 中透明黑色 | ![#000000](https://via.placeholder.com/20x20/000000/000000?text=+) |
| themeBlack50 | 0.50 | 高透明黑色 | ![#000000](https://via.placeholder.com/20x20/000000/000000?text=+) |

### 1.2 颜色使用规范

#### 背景色使用

- **主背景**: `themeGray900` (bg-gray-900/90)
- **卡片背景**: `themeWhite5` (bg-white/5)
- **悬停背景**: `themeWhite20` (hover:bg-white/10)
- **输入框背景**: `themeBlack40` (bg-black/40)
- **面板背景**: `themeBlack20` (bg-black/20)

#### 文本颜色使用

- **主要文本**: `themeGray200` (text-gray-200)
- **次要文本**: `themeGray400` (text-gray-400)
- **辅助文本**: `themeGray500` (text-gray-500)
- **占位文本**: `themeGray300` (text-gray-300)

#### 边框颜色使用

- **主要边框**: `themeWhite10` (border-white/10)
- **次要边框**: `themeWhite20` (border-white/20)
- **激活边框**: `themeBlue500` (border-blue-500)

#### 语义颜色使用

- **成功状态**: `themeGreen500` + `themeGreen500.opacity(0.1)`
- **错误状态**: `themeRed500` + `themeRed500.opacity(0.1)`
- **警告状态**: `themeYellow500` + `themeYellow500.opacity(0.1)`
- **AI 状态**: `themePurple500` + `themePurple500.opacity(0.1)`

---

## 2. 字体规范

### 2.1 字体族

| 字体名称 | 说明 | 使用场景 |
|---------|------|----------|
| themeSans | 系统无衬线字体 | 全局默认字体 |
| themeMono | 等宽字体 | 代码、技术内容 |

### 2.2 字号层级

| 字体名称 | 字号 (px) | Tailwind | 用途 | 示例 |
|---------|-----------|----------|------|------|
| themeH1 | 16 | text-base | 大标题 | **大标题** |
| themeH2 | 14 | text-sm | 小标题 | **小标题** |
| themeBody | 14 | text-sm | 正文 | 正文内容 |
| themeCaption | 12 | text-xs | 辅助文本 | 辅助文本 |
| themeCaptionSmall | 10 | text-[10px] | 标签、说明 | 标签 |
| themeCaptionTiny | 8 | text-[8px] | 版权、注释 | 注释 |

### 2.3 字重

| 字重名称 | 字重值 | Tailwind | 用途 | 示例 |
|---------|--------|----------|------|------|
| themeWeightLight | 300 | font-light | 轻量文本 | **轻量** |
| themeWeightNormal | 400 | normal | 普通文本 | 普通 |
| themeWeightMedium | 500 | font-medium | 中等文本 | **中等** |
| themeWeightSemibold | 600 | font-semibold | 半粗体 | **半粗体** |
| themeWeightBold | 700 | font-bold | 粗体 | **粗体** |

### 2.4 字间距

| 字间距 | 值 | 用途 |
|--------|----|------|
| themeTrackingNormal | 默认 | 正常字间距 |
| themeTrackingWide | 手动调整 | 宽字间距 (uppercase) |

### 2.5 行高

- **标题行高**: 1.2
- **正行高**: 1.5
- **代码行高**: 1.4

---

## 3. 间距规范

### 3.1 间距系统

基于 Tailwind CSS 的 4px 基准：

| 间距名称 | 像素值 | Tailwind | 用途 | 示例 |
|---------|--------|----------|------|------|
| px0 | 0px | 0 | 无间距 | - |
| px1 | 4px | 1 | 微小间距 | - |
| px2 | 8px | 2 | 小间距 | - |
| px3 | 12px | 3 | 标准间距 | - |
| px4 | 16px | 4 | 常用间距 | - |
| px5 | 20px | 5 | 较大间距 | - |
| px6 | 24px | 6 | 大间距 | - |
| px8 | 32px | 8 | 超大间距 | - |

### 3.2 常用间距组合

| 间距组合 | 值 | 用途 |
|---------|----|------|
| p2 | px8 | 小内边距 |
| p3 | px12 | 标准内边距 |
| p4 | px16 | 常用内边距 |
| p6 | px24 | 大内边距 |
| p8 | px32 | 超大内边距 |

### 3.3 尺寸规范

| 尺寸名称 | 像素值 | Tailwind | 用途 |
|---------|--------|----------|------|
| w16 | 64px | w-16 | 侧边栏宽度 |
| h12 | 48px | h-12 | 头部高度 |
| h8 | 32px | h-8 | 底部高度 |
| h1 | 4px | h-1 | 分隔线高度 |

---

## 4. 圆角和边框规范

### 4.1 圆角系统

| 圆角名称 | 像素值 | Tailwind | 用途 | 示例 |
|---------|--------|----------|------|------|
| none | 0px | rounded-none | 无圆角 | ▢ |
| sm | 2px | rounded-sm | 小圆角 | ◔ |
| base | 4px | rounded | 标准圆角 | ◕ |
| md | 6px | rounded-md | 中等圆角 | ◕ |
| lg | 8px | rounded-lg | 大圆角 | ◕ |
| xl | 12px | rounded-xl | 超大圆角 | ◕ |
| 2xl | 16px | rounded-2xl | 特大圆角 | ◕ |
| 3xl | 24px | rounded-3xl | 巨大圆角 | ◕ |
| full | 9999px | rounded-full | 圆形 | ◯ |

### 4.2 边框规范

| 边框类型 | 宽度 | 颜色 | 用途 |
|---------|------|------|------|
| thin | 1px | themeBorder | 细边框 |
| medium | 2px | themeBorder | 中等边框 |
| thick | 3px | themeBorder | 粗边框 |

---

## 5. 动效规范

### 5.1 动画时长

| 时长名称 | 秒数 | 用途 | 示例 |
|---------|------|------|------|
| 100ms | 0.1s | 快速反馈 | 按钮点击 |
| 200ms | 0.2s | 标准动画 | 悬停效果 |
| 300ms | 0.3s | 常用动画 | 展开/折叠 |
| 500ms | 0.5s | 慢速动画 | 页面过渡 |
| 1000ms | 1.0s | 长动画 | 加载动画 |

### 5.2 缓动函数

| 缓动名称 | 函数 | 用途 | 示例 |
|---------|------|------|------|
| easeIn | easeIn | 加速进入 | 淡入效果 |
| easeOut | easeOut | 减速结束 | 淡出效果 |
| easeInOut | easeInOut | 先加速后减速 | 标准过渡 |
| customBezier | timingCurve(0.34,1.56,0.64,1.0) | 自定义贝塞尔 | 悬浮窗展开 |
| spring | spring(response:0.3,dampingFraction:0.7) | 弹性动画 | 卡片展开 |

### 5.3 动画类型

#### 过渡动画

| 动画名称 | 描述 | 用途 |
|---------|------|------|
| slideRight | 从右侧滑入 | 页面从右到左切换 |
| slideLeft | 从左侧滑入 | 页面从左到右切换 |
| slideTop | 从顶部滑入 | Toast 提示 |
| slideBottom | 从底部滑入 | 底部弹窗 |

#### 状态动画

| 动画名称 | 描述 | 用途 |
|---------|------|------|
| pulse | 呼吸效果 | 加载指示器 |
| spin | 旋转效果 | 加载 spinner |
| scale | 缩放效果 | 按钮反馈 |

---

## 6. Icon 规范

### 6.1 图标库

使用 [Lucide Icons](https://lucide.dev/) 作为图标库。

### 6.2 图标尺寸

| 尺寸名称 | 像素值 | 用途 |
|---------|--------|------|
| 10px | 小图标 | 标签、按钮 |
| 12px | 中等图标 | 导航、操作 |
| 14px | 大图标 | 头部、重要操作 |
| 16px | 超大图标 | 标题、主要功能 |

### 6.3 图标语义

| 图标名称 | 含义 | 使用场景 |
|---------|------|----------|
| bluetooth | 蓝牙未连接 | 蓝牙状态 |
| bluetoothConnected | 蓝牙已连接 | 蓝牙状态 |
| bluetoothOff | 蓝牙关闭 | 蓝牙状态 |
| clipboard | 剪切板 | 原文内容 |
| sparkles | AI 智能 | AI 总结 |
| bot | 机器人 | 自动化 |
| star | 星标 | 收藏 |
| trash2 | 删除 | 删除操作 |
| copy | 复制 | 复制操作 |
| settings | 设置 | 偏好设置 |
| search | 搜索 | 搜索功能 |
| alignLeft | 左对齐 | 文本对齐 |
| chevronRight | 右箭头 | 展开/折叠 |
| maximize2 | 最大化 | 窗口操作 |
| database | 数据库 | 数据存储 |
| link | 链接 | 连接状态 |
| zap | 闪电 | 快速操作 |
| clock | 时钟 | 时间戳 |

### 6.4 图标颜色

| 场景 | 颜色 | 说明 |
|------|------|------|
| 默认 | themeGray400 | 普通状态 |
| 激活 | themeBlue400 | 蓝牙连接 |
| 悬停 | themeGray200 | 鼠标悬停 |
| 禁用 | themeGray500 | 不可用状态 |

---

## 7. 交互规范

### 7.1 状态管理

#### 视图状态

| 状态名称 | 说明 | 示例 |
|---------|------|------|
| isVisible | 悬浮窗是否可见 | true/false |
| isKeyWindow | 是否为关键窗口 | true/false |
| isHovering | 是否悬停 | true/false |
| isExpanded | 是否展开 | true/false |
| isInteracting | 是否正在交互 | true/false |

#### 数据状态

| 状态名称 | 说明 | 示例 |
|---------|------|------|
| raw | 原始记录 | 未处理的剪切板文本 |
| title-only | 仅标题 | AI 生成了标题但未总结 |
| summarized | 已总结 | AI 完整总结 |
| ai-failed | AI 失败 | AI 处理失败 |
| deduplicated | 已去重 | 重复记录合并 |

### 7.2 交互反馈

#### 视觉反馈

- **悬停效果**: 背景色从 `themeItem` 变为 `themeHover`
- **点击效果**: 缩放动画 `scaleEffect(0.98)`
- **展开/折叠**: 弹性动画 `spring(response:0.3,dampingFraction:0.7)`
- **状态变化**: 颜色变化 + 图标动画

#### 动画反馈

- **Toast 提示**: `slideTop` + `fade` 过渡
- **设置面板**: `slideRight` 过渡
- **记录卡片**: `scale` + `opacity` 过渡
- **按钮**: `pulse` 效果

#### 声音反馈

- **成功**: 系统提示音
- **错误**: 系统错误音
- **警告**: 系统警告音

### 7.3 用户操作

#### 鼠标操作

- **点击**: 选择、展开、折叠
- **双击**: 无特殊操作
- **悬停**: 显示工具提示、改变样式
- **拖拽**: 移动悬浮窗（如果启用）

#### 键盘操作

- **Esc**: 关闭悬浮窗
- **Enter**: 确认操作
- **箭头键**: 导航（TODO）
- **快捷键**: Option+Cmd+R 唤起/收起

#### 硬件操作

- **按钮 1**: 采集剪切板
- **按钮 2**: 唤起/收起悬浮窗
- **防抖**: 1000ms 最小间隔

### 7.4 响应式行为

#### 窗口尺寸

- **固定尺寸**: 520px × 640px
- **最小尺寸**: 400px × 400px
- **最大尺寸**: 800px × 1000px

#### 布局适配

- **侧边栏**: 固定 64px 宽度
- **主内容区**: 自适应剩余空间
- **滚动**: 内容超出时自动滚动

---

## 8. 组件规范

### 8.1 RecordCard 组件

#### 结构

```
RecordCard
├── Header (头部)
│   ├── Icon (图标)
│   ├── Content (内容)
│   │   ├── Title (标题)
│   │   └── Meta (元信息)
│   └── Actions (操作)
│       ├── Star (星标)
│       ├── Trash (删除)
│       └── Chevron (箭头)
└── Expanded Content (展开内容)
    ├── Raw Content (原文)
    └── AI Summary (AI 总结)
```

#### 样式规范

- **背景**: `themeItem` / `themeHover` / `themeCard`
- **圆角**: `ThemeRadius.lg` (8px)
- **边框**: `ThemeRadius.base` (1px)
- **阴影**: `isExpanded` 时显示
- **动画**: `ThemeDuration.300` + `easeOut`

#### 交互规范

- **点击**: 展开/折叠
- **悬停**: 显示操作按钮
- **星标**: 切换收藏状态
- **删除**: 删除记录
- **复制**: 复制原文/AI 总结

### 8.2 SettingsPanel 组件

#### 结构

```
SettingsPanel
├── Header (头部)
├── TabBar (标签栏)
├── Content (内容区)
│   ├── AI Settings (AI 设置)
│   ├── History Settings (记录设置)
│   ├── Bluetooth Settings (蓝牙设置)
│   └── Window Settings (窗口设置)
└── Footer (底部)
```

#### 样式规范

- **背景**: `themeBackground`
- **圆角**: `ThemeRadius.2xl` (16px)
- **边框**: `ThemeRadius.base` (1px)
- **阴影**: `radius: 20, x: 0, y: 10`
- **动画**: `slideRight` 过渡

#### 交互规范

- **标签切换**: 左右滑动过渡
- **表单控件**: 即时反馈
- **保存**: 保存到 UserDefaults
- **关闭**: 淡出动画

### 8.3 Toast 组件

#### 结构

```
Toast
├── Icon (图标)
└── Message (消息文本)
```

#### 样式规范

- **背景**: 根据类型变化
  - 成功: `themeGreen500` + `opacity(0.8)`
  - 错误: `themeRed500` + `opacity(0.8)`
  - 警告: `themeYellow500` + `opacity(0.8)`
  - 信息: `themeGray800` + `opacity(0.8)`
- **圆角**: `ThemeRadius.lg` (8px)
- **阴影**: `radius: 20, x: 0, y: 10`
- **动画**: `slideTop` + `fade` 过渡

#### 交互规范

- **显示**: 自动显示 2 秒
- **关闭**: 自动淡出或手动关闭
- **位置**: 右上角固定

---

## 9. 布局规范

### 9.1 悬浮窗布局

#### 整体结构

```
FloatingPanel (520 × 640)
├── Sidebar (64px) - 热力图
└── Main Content (456px) - 主内容区
    ├── Header (48px) - 头部
    ├── Content Area (544px) - 内容区
    │   ├── Search Bar (48px) - 搜索栏
    │   ├── List View (剩余空间) - 列表视图
    │   └── Status Bar (32px) - 状态栏
    └── Footer (可选)
```

#### 坐标系统

- **原点**: 屏幕中心
- **X 轴**: 从左到右
- **Y 轴**: 从上到下
- **Z 轴**: 从后到前（层级）

### 9.2 响应式断点

| 断点 | 最小宽度 | 说明 |
|------|----------|------|
| sm | 320px | 超小屏幕 |
| md | 768px | 小屏幕 |
| lg | 1024px | 中等屏幕 |
| xl | 1280px | 大屏幕 |

### 9.3 网格系统

使用 Flexbox 布局：

- **主轴**: 垂直方向 (column)
- **交叉轴**: 水平方向
- **间距**: `ThemeSpacing.p4` (16px)
- **对齐**: flex-start

---

## 10. 可访问性规范

### 10.1 语义化

- 使用语义化的 HTML 元素
- 正确的 heading 层级
- 表单元素有 label
- 图标有 alt 文本

### 10.2 键盘导航

- Tab 键顺序合理
- 支持 Enter 确认
- 支持 Esc 关闭
- 焦点可见

### 10.3 屏幕阅读器

- ARIA 标签
- 角色定义
- 状态说明
- 说明文本

### 10.4 颜色对比度

- 文本对比度 ≥ 4.5:1
- 大文本对比度 ≥ 3:1
- UI 元素对比度 ≥ 3:1

---

## 11. 性能规范

### 11.1 渲染性能

- 使用 `@StateObject` 管理状态
- 避免在 `body` 中创建对象
- 使用 `LazyVStack` 优化长列表
- 图片使用合适的尺寸

### 11.2 内存使用

- 及时释放资源
- 避免循环引用
- 使用弱引用
- 缓存策略

### 11.3 动画性能

- 使用硬件加速
- 避免复杂计算
- 合理的帧率
- 减少重绘

---

## 12. 测试规范

### 12.1 单元测试

- 颜色计算
- 间距计算
- 动画时长
- 状态管理

### 12.2 集成测试

- 组件交互
- 数据流
- 用户流程
- 错误处理

### 12.3 UI 测试

- 视觉一致性
- 响应式布局
- 交互反馈
- 可访问性

---

## 13. 版本控制

### 13.1 文件命名

- 使用驼峰命名法
- 语义化命名
- 统一后缀: `+Theme.swift`

### 13.2 提交规范

- feat: 新功能
- fix: 修复 bug
- docs: 文档更新
- style: 代码格式
- refactor: 重构
- test: 测试
- chore: 构建过程

### 13.3 分支策略

- main: 主分支
- develop: 开发分支
- feature/*: 功能分支
- hotfix/*: 修复分支

---

## 14. 部署规范

### 14.1 构建流程

1. 代码检查
2. 单元测试
3. 集成测试
4. UI 测试
5. 打包构建

### 14.2 发布流程

1. 版本号更新
2. 代码签名
3. 应用打包
4. 提交审核
5. 发布上线

### 14.3 版本号规范

- 语义化版本: `主版本.次版本.修订版本`
- 示例: `1.0.0`, `1.1.0`, `1.1.1`

---

## 附录

### A. 颜色对照表

完整的 RGBA 值对照：

```swift
// Gray Scale
Color(red: 17/255, green: 24/255, blue: 39/255)   // themeGray900
Color(red: 31/255, green: 41/255, blue: 55/255)   // themeGray800
Color(red: 55/255, green: 65/255, blue: 81/255)   // themeGray700
Color(red: 75/255, green: 85/255, blue: 99/255)   // themeGray600
Color(red: 107/255, green: 114/255, blue: 128/255) // themeGray500
Color(red: 156/255, green: 163/255, blue: 175/255) // themeGray400
Color(red: 209/255, green: 213/255, blue: 221/255) // themeGray300
Color(red: 229/255, green: 231/255, blue: 235/255) // themeGray200
Color(red: 243/255, green: 244/255, blue: 246/255) // themeGray100

// Blue Scale
Color(red: 37/255, green: 99/255, blue: 235/255)   // themeBlue600
Color(red: 59/255, green: 130/255, blue: 246/255)  // themeBlue500
Color(red: 96/255, green: 165/255, blue: 250/255)  // themeBlue400
Color(red: 147/255, green: 197/255, blue: 253/255) // themeBlue300

// Purple Scale
Color(red: 147/255, green: 51/255, blue: 234/255)  // themePurple600
Color(red: 168/255, green: 85/255, blue: 247/255)  // themePurple500
Color(red: 192/255, green: 132/255, blue: 252/255) // themePurple400
Color(red: 216/255, green: 180/255, blue: 254/255) // themePurple300

// Green Scale
Color(red: 22/255, green: 163/255, blue: 74/255)   // themeGreen600
Color(red: 34/255, green: 197/255, blue: 94/255)   // themeGreen500
Color(red: 74/255, green: 222/255, blue: 128/255)  // themeGreen400
Color(red: 132/255, green: 255/255, blue: 173/255) // themeGreen300

// Red Scale
Color(red: 185/255, green: 28/255, blue: 28/255)   // themeRed600
Color(red: 239/255, green: 68/255, blue: 68/255)   // themeRed500
Color(red: 248/255, green: 113/255, blue: 113/255) // themeRed400
Color(red: 254/255, green: 172/255, blue: 172/255) // themeRed300

// Yellow Scale
Color(red: 180/255, green: 83/255, blue: 9/255)    // themeYellow600
Color(red: 234/255, green: 179/255, blue: 8/255)   // themeYellow500
Color(red: 250/255, green: 204/255, blue: 21/255)  // themeYellow400
Color(red: 253/255, green: 230/255, blue: 138/255) // themeYellow300
```

### B. 主题文件结构

```
Sources/QuiteNote/UI/Theme/
├── Color+Theme.swift          # 颜色系统
├── Font+Theme.swift           # 字体系统
├── Spacing+Theme.swift        # 间距系统
├── Shape+Theme.swift          # 圆角边框系统
└── Animation+Theme.swift      # 动画系统
```

### C. 使用示例

```swift
// 颜色使用
Color.themeBackground          // 主背景色
Color.themeCard                // 卡片背景色
Color.themeTextPrimary         // 主要文本色

// 字体使用
.font(.themeH2)                // 小标题字体
.font(.themeBody)              // 正文字体
.font(.themeCaptionSmall)      // 小字字体

// 间距使用
.padding(ThemeSpacing.p4)       // 16px 内边距
.frame(width: ThemeSpacing.w16) // 64px 宽度

// 圆角使用
.cornerRadius(ThemeRadius.lg)  // 8px 圆角
.cornerRadius(ThemeRadius.full) // 圆形

// 动画使用
.animation(.easeOut, value: someValue) // 淡出动画
.transition(.slideRight)               // 右滑过渡
```

---

**文档版本**: v1.0

**最后更新**: 2024-12-05

**维护者**: Claude AI