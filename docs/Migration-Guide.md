# 从 React (note.jsx) 到 SwiftUI 的完整迁移方案

## 概述

本方案提供了从基于 Tailwind CSS 的 React 组件 (`note.jsx`) 完整迁移到 SwiftUI (Mac App) 的详细指南。

**源文件**: `/Users/xuyingzhou/Project/study-mac-app/quite-note/note.jsx`

**目标平台**: macOS (SwiftUI + AppKit)

**设计风格**: Tailwind CSS 语义化设计系统

## 目录

1. [项目概览](#项目概览)
2. [主题系统](#主题系统)
3. [迁移步骤](#迁移步骤)
4. [代码示例](#代码示例)
5. [最佳实践](#最佳实践)
6. [检查清单](#检查清单)
7. [参考资料](#参考资料)

---

## 项目概览

### 设计目标

将 React 组件中的以下特性完整迁移到 SwiftUI：

- ✅ **颜色系统** - Tailwind CSS 颜色到 RGBA 的精确映射
- ✅ **字体系统** - 字号、字重、字体族规范
- ✅ **间距系统** - Padding、Margin、尺寸规范
- ✅ **动画系统** - Duration、Easing、Transition
- ✅ **组件迁移** - RecordCard、SettingsPanel 完整实现
- ✅ **交互逻辑** - 悬停、点击、展开/折叠

### 技术栈

- **前端框架**: SwiftUI (macOS)
- **状态管理**: @StateObject, @ObservedObject
- **图标库**: Lucide Icons (Swift Package)
- **蓝牙**: CoreBluetooth
- **数据存储**: CoreData

---

## 主题系统

### 1. 颜色系统 (Color+Theme.swift)

完整的 Tailwind 颜色映射到 RGBA 值：

```swift
// Gray Scale
Color.themeGray900  // #111827 (bg-gray-900)
Color.themeGray800  // #1F2937 (bg-gray-800)
Color.themeGray700  // #374151 (bg-gray-700)

// Blue Scale (AI/交互色)
Color.themeBlue600  // #2563EB (bg-blue-600)
Color.themeBlue500  // #3B82F6 (blue-500)

// Purple Scale (AI 总结)
Color.themePurple500 // #A855F7 (purple-500)

// Transparent variants
Color.themeWhite5   // bg-white/5
Color.themeWhite10  // bg-white/10
Color.themeWhite20  // bg-white/20
```

### 2. 字体系统 (Font+Theme.swift)

Tailwind 字体到 SwiftUI Font 的映射：

```swift
Font.themeH1           // text-base font-semibold (16px)
Font.themeH2           // text-sm font-semibold (14px)
Font.themeBody         // text-sm (14px, default)
Font.themeCaption      // text-xs (12px)
Font.themeCaptionSmall // text-[10px]
Font.themeCaptionTiny  // text-[8px]

Font.themeMono         // font-mono (monospace)
Font.themeWeightBold   // font-bold
```

### 3. 间距系统 (Spacing+Theme.swift)

Tailwind 间距到 CGFloat 的映射：

```swift
ThemeSpacing.p4   // p-4 (16px)
ThemeSpacing.p6   // p-6 (24px)
ThemeSpacing.w16  // w-16 (64px)
ThemeSpacing.h12  // h-12 (48px)

// View extensions
.padding(.p4)      // 应用主题间距
.frame(width: .w16) // 应用主题尺寸
```

### 4. 圆角和边框系统 (Shape+Theme.swift)

Tailwind 圆角到 SwiftUI 的映射：

```swift
ThemeRadius.lg    // rounded-lg (8px)
ThemeRadius.full  // rounded-full (圆形)

// View extensions
.cornerRadius(.lg) // 应用主题圆角
.border(width: 1)  // 应用主题边框
.cardStyle()       // 应用主题卡片样式
```

### 5. 动画系统 (Animation+Theme.swift)

Tailwind 动画到 SwiftUI 的映射：

```swift
ThemeDuration.`300` // 300ms
Animation.easeOut   // ease-out
Animation.customBezier // 自定义贝塞尔曲线

// View extensions
.animateIn()        // 应用主题动画
.transitionSlideRight() // 应用主题过渡
```

---

## 迁移步骤

### 步骤 1: 建立主题系统

1. 创建 `Sources/QuiteNote/UI/Theme/` 目录
2. 添加以下文件：
   - `Color+Theme.swift` - 颜色系统
   - `Font+Theme.swift` - 字体系统
   - `Spacing+Theme.swift` - 间距系统
   - `Shape+Theme.swift` - 圆角边框系统
   - `Animation+Theme.swift` - 动画系统

### 步骤 2: 迁移核心组件

1. **RecordCard** - 迁移记录卡片组件
   - 头部：图标、标题、元信息、操作按钮
   - 展开内容：原文、AI 总结
   - 动画：展开/折叠、悬停效果

2. **SettingsPanel** - 迁移设置面板
   - 标签页：AI、记录、蓝牙、窗口
   - 表单控件：开关、滑块、输入框
   - 过渡动画：左右滑动

### 步骤 3: 更新现有代码

1. 修改 `FloatingPanelController.swift`
   - 使用主题颜色替换硬编码颜色
   - 使用主题间距替换魔法数字
   - 使用主题动画替换自定义动画

2. 更新 `PreferencesView.swift`
   - 重写为完整的设置面板
   - 使用主题系统统一 UI

### 步骤 4: 添加缺失功能

1. **ToastView** - Toast 提示组件
2. **HeatmapView** - 热力图组件
3. **LucideView** - 图标组件
4. **Record 模型** - 数据模型定义

### 步骤 5: 测试和优化

1. 功能测试
   - 剪切板捕获
   - AI 总结
   - 蓝牙连接
   - 设置保存

2. 性能优化
   - 动画性能
   - 内存使用
   - 渲染效率

3. 用户体验
   - 交互反馈
   - 视觉一致性
   - 响应式布局

---

## 代码示例

### 完整的 RecordCard 迁移

```swift
struct RecordCard: View {
    let record: Record
    @Binding var expandedId: UUID?
    let store: RecordStore
    @State private var hovering = false

    var body: some View {
        let isExpanded = expandedId == record.id

        VStack(alignment: .leading, spacing: 0) {
            // 头部
            HStack(alignment: .top, spacing: ThemeSpacing.px3.rawValue) {
                // 图标
                LucideView(name: statusIconLucide, size: 16, color: statusColor)
                    .frame(width: 20, height: 20)

                // 内容
                VStack(alignment: .leading, spacing: ThemeSpacing.px2.rawValue) {
                    Text(displayTitle)
                        .font(.themeBody.weight(isExpanded ? .semibold : .medium))
                        .foregroundColor(.themeTextPrimary)
                        .lineLimit(1)

                    // 元信息
                    HStack(spacing: ThemeSpacing.px2.rawValue) {
                        Text(record.createdAt.formatted(date: .omitted, time: .shortened))
                        Rectangle().fill(Color.themeGray700).frame(width: ThemeRadius.base.rawValue, height: 10)
                        Text("\(record.content.count) 字符")

                        // 状态标签
                        HStack(spacing: 2) {
                            LucideView(name: statusIconLucide, size: 10, color: statusColor)
                            Text(statusText)
                        }
                        .foregroundColor(statusColor)
                    }
                    .font(.themeCaptionSmall.monospace())
                    .foregroundColor(.themeTextTertiary)
                }

                Spacer()

                // 操作按钮
                if hovering || isExpanded {
                    HStack(spacing: ThemeSpacing.px2.rawValue) {
                        IconButton(icon: .star, color: record.starred ? .themeYellow : .themeTextTertiary) {
                            store.toggleStar(record)
                        }
                        IconButton(icon: .trash2, color: .themeTextTertiary) {
                            store.delete(record)
                        }
                        LucideView(name: .chevronRight, size: 14, color: .themeTextTertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .transition(.opacity)
                }
            }
            .padding(ThemeSpacing.p3.rawValue)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    expandedId = isExpanded ? nil : record.id
                }
            }

            // 展开内容
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    // 原文
                    VStack(alignment: .leading, spacing: ThemeSpacing.p2.rawValue) {
                        HStack {
                            HStack(spacing: 4) {
                                LucideView(name: .rss, size: 10, color: .themeTextTertiary)
                                Text("原文内容")
                            }
                            .textCase(.uppercase)
                            Spacer()
                            Button("复制原文") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(record.content, forType: .string)
                                store.postLightHint("已复制原文")
                            }
                            .buttonStyle(.plain)
                        }

                        Text(record.content)
                            .font(.themeCaption.monospace())
                            .foregroundColor(.themeGray300)
                            .padding(ThemeSpacing.p3.rawValue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.themePanel)
                            .cornerRadius(ThemeRadius.base.rawValue)
                            .overlay(RoundedRectangle(cornerRadius: ThemeRadius.base.rawValue).stroke(Color.themeBorder))
                    }

                    // AI 总结
                    if record.summary != nil || record.aiStatus == "fail" {
                        VStack(alignment: .leading, spacing: ThemeSpacing.p2.rawValue) {
                            HStack {
                                HStack(spacing: 4) {
                                    LucideView(name: .sparkles, size: 10, color: record.aiStatus == "fail" ? .themeRed : .themePurple)
                                    Text("AI 智能总结")
                                }
                                .textCase(.uppercase)
                                Spacer()
                                if let s = record.summary {
                                    Button("复制总结") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(s, forType: .string)
                                        store.postLightHint("已复制总结")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            Text(record.summary ?? "提炼失败")
                                .font(.themeCaption)
                                .foregroundColor(Color.themePurple.opacity(0.8))
                                .padding(ThemeSpacing.p2.rawValue)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.themePurple.opacity(0.1))
                                .cornerRadius(ThemeRadius.lg.rawValue)
                                .overlay(RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue).stroke(Color.themePurple.opacity(0.2)))
                        }
                    }
                }
                .padding(ThemeSpacing.p3.rawValue)
                .padding(.top, 0)
            }
        }
        .background(isExpanded ? Color.themeHover : (hovering ? Color.themeHover : Color.themeItem))
        .cornerRadius(ThemeRadius.lg.rawValue)
        .overlay(RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue).stroke(isExpanded ? Color.themeBlue500.opacity(0.3) : Color.themeBorder))
        .shadow(color: isExpanded ? Color.black.opacity(0.5) : .clear, radius: 30, x: 0, y: 8)
        .animation(.easeOut(duration: ThemeDuration.`300`.rawValue), value: hovering)
        .onHover { hovering = $0 }
        .pointingHandCursor()
    }
}
```

### 完整的 SettingsPanel 迁移

```swift
struct SettingsPanel: View {
    @Environment(\.dismiss) var dismiss
    @StateObject var store: RecordStore
    @StateObject var bluetooth: BluetoothManager

    @State private var settingsTab: String = "ai"
    @State private var editConfig = PreferencesManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Tab Bar
            tabView

            // Content
            contentView

            // Footer
            footerView
        }
        .frame(width: 480, height: 600)
        .background(Color.themeBackground)
        .cornerRadius(ThemeRadius.`2xl`.rawValue)
        .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
    }

    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                LucideView(name: .arrowLeft, size: 18, color: .themeGray400)
            }
            .buttonStyle(.plain)

            Text("偏好设置")
                .font(.themeH1)
                .foregroundColor(.themeTextPrimary)

            Spacer()
        }
        .padding(ThemeSpacing.p4.rawValue)
        .background(Color.themeBackground.opacity(0.5))
        .overlay(Rectangle().frame(height: ThemeRadius.base.rawValue).foregroundColor(Color.themeBorder), alignment: .bottom)
    }

    private var tabView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ThemeSpacing.px2.rawValue) {
                let tabs = [
                    ("ai", .sparkles, "AI 提炼设置"),
                    ("history", .database, "记录设置"),
                    ("bluetooth", .bluetooth, "蓝牙设置"),
                    ("window", .maximize2, "悬浮窗设置")
                ]

                ForEach(tabs, id: \.0) { tab in
                    Button(action: { settingsTab = tab.0 }) {
                        HStack(spacing: ThemeSpacing.px2.rawValue) {
                            LucideView(name: tab.1, size: 12, color: .white)
                            Text(tab.2)
                        }
                        .font(.caption)
                        .padding(ThemeSpacing.p2.rawValue)
                        .padding(.horizontal, ThemeSpacing.px3.rawValue)
                        .background(settingsTab == tab.0 ? Color.themeBlue500 : Color.themeItem)
                        .cornerRadius(ThemeRadius.lg.rawValue)
                        .foregroundColor(settingsTab == tab.0 ? .white : .themeTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
            .padding(ThemeSpacing.p3.rawValue)
        }
        .background(Color.themeGray800.opacity(0.8))
        .overlay(Rectangle().frame(height: ThemeRadius.base.rawValue).foregroundColor(Color.themeBorder), alignment: .bottom)
    }

    private var contentView: some View {
        ScrollView {
            VStack(spacing: ThemeSpacing.p4.rawValue) {
                if settingsTab == "ai" {
                    aiSettingsView
                } else if settingsTab == "history" {
                    historySettingsView
                } else if settingsTab == "bluetooth" {
                    bluetoothSettingsView
                } else if settingsTab == "window" {
                    windowSettingsView
                }
            }
            .padding(ThemeSpacing.p4.rawValue)
        }
    }

    private var footerView: some View {
        HStack {
            Spacer()
            Button(action: {
                PreferencesManager.shared = editConfig
                dismiss()
            }) {
                HStack(spacing: ThemeSpacing.px2.rawValue) {
                    LucideView(name: .save, size: 16, color: .white)
                    Text("保存设置")
                }
                .font(.themeCaption.weight(.medium))
                .padding(ThemeSpacing.p2.rawValue)
                .padding(.horizontal, ThemeSpacing.px4.rawValue)
                .background(Color.themeBlue500)
                .cornerRadius(ThemeRadius.lg.rawValue)
                .shadow(color: Color.themeBlue500.opacity(0.2), radius: 20, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(ThemeSpacing.p3.rawValue)
        .background(Color.themeBackground.opacity(0.5))
        .overlay(Rectangle().frame(height: ThemeRadius.base.rawValue).foregroundColor(Color.themeBorder), alignment: .top)
    }

    // AI 设置视图
    private var aiSettingsView: some View {
        VStack(spacing: ThemeSpacing.p4.rawValue) {
            Toggle("启用 AI 自动提炼", isOn: $editConfig.aiEnabled)
                .toggleStyle(SwitchToggleStyle(tint: .themeBlue500))
                .foregroundColor(.themeTextPrimary)

            if editConfig.aiEnabled {
                VStack(spacing: ThemeSpacing.p3.rawValue) {
                    // 总结触发阈值
                    VStack(spacing: ThemeSpacing.px2.rawValue) {
                        HStack {
                            Text("总结触发长度")
                            Spacer()
                            Text("> \(editConfig.summaryTrigger) 字符")
                                .foregroundColor(.themeBlue500)
                                .font(.themeCaptionSmall.monospace())
                                .background(Color.themeBlue500.opacity(0.1))
                                .padding(ThemeSpacing.px2.rawValue)
                                .cornerRadius(ThemeRadius.base.rawValue)
                        }
                        Slider(value: $editConfig.summaryTrigger, in: 10...500, step: 10)
                            .accentColor(Color.themeBlue500)
                    }

                    // 标题长度限制
                    VStack(spacing: ThemeSpacing.px2.rawValue) {
                        HStack {
                            Text("标题长度限制")
                            Spacer()
                            Text("\(editConfig.titleLength) 字符")
                                .foregroundColor(.themeBlue500)
                                .font(.themeCaptionSmall.monospace())
                                .background(Color.themeBlue500.opacity(0.1))
                                .padding(ThemeSpacing.px2.rawValue)
                                .cornerRadius(ThemeRadius.base.rawValue)
                        }
                        Slider(value: $editConfig.titleLength, in: 10...40, step: 5)
                            .accentColor(Color.themeBlue500)
                    }

                    // 总结长度限制
                    VStack(spacing: ThemeSpacing.px2.rawValue) {
                        HStack {
                            Text("总结长度限制")
                            Spacer()
                            Text("\(editConfig.summaryLength) 字符")
                                .foregroundColor(.themeBlue500)
                                .font(.themeCaptionSmall.monospace())
                                .background(Color.themeBlue500.opacity(0.1))
                                .padding(ThemeSpacing.px2.rawValue)
                                .cornerRadius(ThemeRadius.base.rawValue)
                        }
                        Slider(value: $editConfig.summaryLength, in: 50...300, step: 10)
                            .accentColor(Color.themeBlue500)
                    }
                }
                .padding(ThemeSpacing.p3.rawValue)
                .background(Color.themePanel)
                .cornerRadius(ThemeRadius.lg.rawValue)
                .overlay(RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue).stroke(Color.themeBorder, lineWidth: ThemeRadius.base.rawValue))

                // 模型配置
                VStack(spacing: ThemeSpacing.px2.rawValue) {
                    Text("模型服务商与连接")
                        .font(.themeCaptionSmall.uppercase())
                        .foregroundColor(.themeTextTertiary)

                    HStack(spacing: ThemeSpacing.px2.rawValue) {
                        Button("Google Gemini") {
                            editConfig.aiProvider = "gemini"
                            editConfig.aiModel = "gemini-2.5-flash-preview"
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(editConfig.aiProvider == "gemini" ? .white : .themeTextSecondary)
                        .background(editConfig.aiProvider == "gemini" ? Color.themeBlue500 : Color.themeItem)
                        .cornerRadius(ThemeRadius.lg.rawValue)

                        Button("OpenAI GPT") {
                            editConfig.aiProvider = "openai"
                            editConfig.aiModel = "gpt-4o-mini"
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(editConfig.aiProvider == "openai" ? .white : .themeTextSecondary)
                        .background(editConfig.aiProvider == "openai" ? Color.themeBlue500 : Color.themeItem)
                        .cornerRadius(ThemeRadius.lg.rawValue)

                        Button("Local LLM") {
                            editConfig.aiProvider = "local"
                            editConfig.aiModel = "llama3"
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(editConfig.aiProvider == "local" ? .white : .themeTextSecondary)
                        .background(editConfig.aiProvider == "local" ? Color.themeBlue500 : Color.themeItem)
                        .cornerRadius(ThemeRadius.lg.rawValue)
                    }
                }

                // API Key
                VStack(spacing: ThemeSpacing.px2.rawValue) {
                    Text("API Key")
                        .font(.themeCaptionSmall.uppercase())
                        .foregroundColor(.themeTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    TextField("sk-...", text: $editConfig.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.themeCaptionSmall.monospace())
                        .foregroundColor(.themeTextPrimary)
                        .background(Color.themeInput)
                        .cornerRadius(ThemeRadius.base.rawValue)
                }

                // Base URL / Model
                VStack(spacing: ThemeSpacing.px2.rawValue) {
                    Text("Base URL / Model")
                        .font(.themeCaptionSmall.uppercase())
                        .foregroundColor(.themeTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(editConfig.baseUrl) / \(editConfig.aiModel)")
                        .font(.themeCaptionSmall.monospace())
                        .foregroundColor(.themeTextTertiary)
                        .padding(ThemeSpacing.p2.rawValue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.themeInput)
                        .cornerRadius(ThemeRadius.base.rawValue)
                }
            }
        }
    }

    // ... 其他设置视图 (history, bluetooth, window)
}
```

---

## 最佳实践

### 1. 保持一致性

- **颜色**: 所有颜色使用 `theme` 前缀
- **字体**: 所有字体使用 `theme` 前缀
- **间距**: 所有间距使用 `ThemeSpacing`
- **动画**: 所有动画使用 `ThemeDuration` 和 `Animation` 扩展

### 2. 类型安全

- 使用枚举而不是字符串
- 使用计算属性而不是魔法数字
- 使用 `Color` 而不是 `NSColor`（在 SwiftUI 中）

### 3. 性能优化

- 颜色和字体在编译时确定
- 避免在 `body` 中创建新对象
- 使用 `@StateObject` 而不是 `@ObservedObject` 管理状态

### 4. 可维护性

- 将主题系统独立到 Theme 文件夹
- 使用语义化命名
- 添加详细的文档注释

### 5. 可扩展性

- 预留自定义主题接口
- 支持深色/浅色模式切换
- 支持用户自定义设置

### 6. 代码组织

```
Sources/QuiteNote/
├── UI/
│   ├── Theme/                 # 主题系统
│   │   ├── Color+Theme.swift  # 颜色系统
│   │   ├── Font+Theme.swift   # 字体系统
│   │   ├── Spacing+Theme.swift # 间距系统
│   │   ├── Shape+Theme.swift  # 圆角边框系统
│   │   └── Animation+Theme.swift # 动画系统
│   ├── Components/            # 可复用组件
│   │   ├── RecordCard.swift   # 记录卡片
│   │   └── SettingsPanel.swift # 设置面板
│   ├── Examples/              # 使用示例
│   │   └── CompleteExample.swift
│   └── Views/                 # 页面视图
├── Models/                    # 数据模型
├── Services/                  # 业务服务
├── Utils/                     # 工具类
└── Resources/                 # 资源文件
```

---

## 检查清单

### ✅ 已完成

1. **颜色系统映射** - 完整的 Tailwind 颜色到 RGBA 转换
2. **字体系统映射** - 字号、字重、字体族规范
3. **间距系统映射** - Padding、Margin、尺寸规范
4. **圆角和边框系统** - Border radius 和边框规范
5. **动画系统映射** - Duration、Easing、Transition
6. **组件迁移** - RecordCard、SettingsPanel 完整实现
7. **使用示例** - 完整的迁移示例

### 🔄 进行中

1. **Toast 组件** - 需要实现 ToastView
2. **Heatmap 组件** - 需要实现 HeatmapView
3. **Lucide 图标** - 确保 LucideView 可用
4. **Record 模型** - 确保 Record 结构体定义完整
5. **Store 管理** - RecordStore、HeatmapViewModel 等
6. **蓝牙管理** - BluetoothManager 实现
7. **偏好设置** - PreferencesManager 和 UserDefaults 集成
8. **测试用例** - 单元测试和集成测试

### 📋 待开始

1. **性能优化** - 动画性能、内存使用
2. **用户体验** - 交互反馈、视觉一致性
3. **文档完善** - API 文档、使用指南
4. **部署准备** - 打包、签名、分发

---

## 参考资料

### Tailwind CSS 官方文档

- [Tailwind CSS Colors](https://tailwindcss.com/docs/customizing-colors)
- [Tailwind CSS Spacing](https://tailwindcss.com/docs/customizing-spacing)
- [Tailwind CSS Typography](https://tailwindcss.com/docs/typography)
- [Tailwind CSS Animations](https://tailwindcss.com/docs/animation)

### SwiftUI 官方文档

- [SwiftUI Documentation](https://developer.apple.com/xcode/swiftui/)
- [SwiftUI Tutorials](https://developer.apple.com/tutorials/swiftui/)
- [SwiftUI Animations](https://developer.apple.com/documentation/swiftui/animation)

### Lucide Icons

- [Lucide Icons](https://lucide.dev/)
- [Lucide Swift Package](https://github.com/lucide-icons/lucide-icons-swift)

### CoreBluetooth

- [CoreBluetooth Framework](https://developer.apple.com/documentation/corebluetooth)
- [Bluetooth Developer Guide](https://developer.apple.com/bluetooth/)

### CoreData

- [CoreData Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreData/index.html)
- [CoreData Tutorial](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/iPhoneCoreData01/Introduction/Introduction.html)

---

## 版本历史

- **v1.0** (2024-12-05) - 初始版本，完成主题系统和核心组件迁移
- **v1.1** (TODO) - 完善缺失功能和测试用例
- **v1.2** (TODO) - 性能优化和用户体验改进
- **v2.0** (TODO) - 正式版本发布

---

## 贡献指南

1. Fork 项目仓库
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

---

## 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

---

## 联系方式

如有问题或建议，请通过以下方式联系：

- **GitHub**: [@your-username](https://github.com/your-username)
- **Email**: your-email@example.com

---

**文档最后更新**: 2024-12-05

**文档版本**: v1.0

**作者**: Claude AI