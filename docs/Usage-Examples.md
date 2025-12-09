# 使用示例和最佳实践

## 概述

本文档提供了完整的使用示例和最佳实践，帮助开发者快速上手和正确使用主题系统。

**源文件**: `/Users/xuyingzhou/Project/study-mac-app/quite-note/note.jsx`

---

## 目录

1. [快速开始](#快速开始)
2. [颜色使用示例](#颜色使用示例)
3. [字体使用示例](#字体使用示例)
4. [间距使用示例](#间距使用示例)
5. [形状使用示例](#形状使用示例)
6. [动画使用示例](#动画使用示例)
7. [完整组件示例](#完整组件示例)
8. [最佳实践](#最佳实践)
9. [常见问题](#常见问题)

---

## 快速开始

### 1. 导入主题系统

```swift
import SwiftUI

// 导入主题扩展
import Color_Theme
import Font_Theme
import Spacing_Theme
import Shape_Theme
import Animation_Theme
```

### 2. 创建第一个主题化视图

```swift
struct ExampleView: View {
    var body: some View {
        VStack(spacing: ThemeSpacing.p4.rawValue) {
            Text("欢迎使用 QuiteNote")
                .font(.themeH1)
                .foregroundColor(.themeTextPrimary)

            Text("这是一个使用主题系统的示例")
                .font(.themeBody)
                .foregroundColor(.themeTextSecondary)
                .padding(ThemeSpacing.p4.rawValue)
                .background(Color.themeCard)
                .cornerRadius(ThemeRadius.lg.rawValue)
                .border(width: ThemeRadius.base.rawValue, color: Color.themeBorder)
        }
        .padding(ThemeSpacing.p6.rawValue)
        .background(Color.themeBackground)
        .cornerRadius(ThemeRadius.`2xl`.rawValue)
    }
}
```

---

## 颜色使用示例

### 基础颜色使用

```swift
struct ColorExamples: View {
    var body: some View {
        VStack(spacing: ThemeSpacing.p4.rawValue) {
            // 背景色示例
            Text("主题背景色")
                .foregroundColor(.themeTextPrimary)
                .padding()
                .background(Color.themeBackground)
                .cornerRadius(ThemeRadius.lg.rawValue)

            // 卡片背景色
            Text("卡片背景色")
                .foregroundColor(.themeTextPrimary)
                .padding()
                .background(Color.themeCard)
                .cornerRadius(ThemeRadius.lg.rawValue)
                .border(width: ThemeRadius.base.rawValue, color: Color.themeBorder)

            // 语义色示例
            HStack(spacing: ThemeSpacing.p3.rawValue) {
                // 成功状态
                Text("成功")
                    .foregroundColor(.white)
                    .padding(ThemeSpacing.p2.rawValue)
                    .padding(.horizontal, ThemeSpacing.p3.rawValue)
                    .background(Color.themeGreen500)
                    .cornerRadius(ThemeRadius.md.rawValue)

                // 错误状态
                Text("错误")
                    .foregroundColor(.white)
                    .padding(ThemeSpacing.p2.rawValue)
                    .padding(.horizontal, ThemeSpacing.p3.rawValue)
                    .background(Color.themeRed500)
                    .cornerRadius(ThemeRadius.md.rawValue)

                // 警告状态
                Text("警告")
                    .foregroundColor(.white)
                    .padding(ThemeSpacing.p2.rawValue)
                    .padding(.horizontal, ThemeSpacing.p3.rawValue)
                    .background(Color.themeYellow500)
                    .cornerRadius(ThemeRadius.md.rawValue)

                // AI 状态
                Text("AI")
                    .foregroundColor(.white)
                    .padding(ThemeSpacing.p2.rawValue)
                    .padding(.horizontal, ThemeSpacing.p3.rawValue)
                    .background(Color.themePurple500)
                    .cornerRadius(ThemeRadius.md.rawValue)
            }

            // 透明色示例
            VStack(spacing: ThemeSpacing.p2.rawValue) {
                Text("透明色示例")
                    .font(.themeCaptionSmall)
                    .foregroundColor(.themeTextTertiary)

                HStack(spacing: ThemeSpacing.p2.rawValue) {
                    Rectangle()
                        .fill(Color.themeWhite10)
                        .frame(width: 60, height: 40)
                        .cornerRadius(ThemeRadius.base.rawValue)
                        .overlay(Text("white/10"), alignment: .center)

                    Rectangle()
                        .fill(Color.themeWhite20)
                        .frame(width: 60, height: 40)
                        .cornerRadius(ThemeRadius.base.rawValue)
                        .overlay(Text("white/20"), alignment: .center)

                    Rectangle()
                        .fill(Color.themeWhite50)
                        .frame(width: 60, height: 40)
                        .cornerRadius(ThemeRadius.base.rawValue)
                        .overlay(Text("white/50"), alignment: .center)
                }
            }
        }
        .padding(ThemeSpacing.p6.rawValue)
        .background(Color.themeBackground)
    }
}
```

### 颜色组合使用

```swift
struct ColorCombinations: View {
    var body: some View {
        VStack(spacing: ThemeSpacing.p4.rawValue) {
            // 按钮组合
            VStack(spacing: ThemeSpacing.p3.rawValue) {
                Text("按钮样式")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)

                // 主按钮
                Button("主按钮") {
                    print("主按钮点击")
                }
                .buttonStyle(.plain)
                .padding(ThemeSpacing.p3.rawValue)
                .padding(.horizontal, ThemeSpacing.p4.rawValue)
                .background(Color.themeBlue500)
                .cornerRadius(ThemeRadius.lg.rawValue)
                .foregroundColor(.white)
                .shadow(color: Color.themeBlue500.opacity(0.3), radius: 20, x: 0, y: 4)

                // 次按钮
                Button("次按钮") {
                    print("次按钮点击")
                }
                .buttonStyle(.bordered)
                .foregroundColor(.themeTextSecondary)
                .background(Color.themeItem)
                .cornerRadius(ThemeRadius.lg.rawValue)
                .overlay(
                    RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                        .stroke(Color.themeBorder, lineWidth: ThemeRadius.base.rawValue)
                )

                // 危险按钮
                Button("删除") {
                    print("删除操作")
                }
                .buttonStyle(.bordered)
                .foregroundColor(.white)
                .background(Color.themeRed500)
                .cornerRadius(ThemeRadius.lg.rawValue)
            }

            // 卡片组合
            VStack(spacing: ThemeSpacing.p3.rawValue) {
                Text("卡片样式")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)

                // 成功卡片
                VStack(alignment: .leading, spacing: ThemeSpacing.p2.rawValue) {
                    HStack {
                        Text("成功提示")
                            .font(.themeH2)
                            .foregroundColor(.themeGreen600)
                        Spacer()
                        LucideView(name: .check, size: 16, color: .themeGreen500)
                    }

                    Text("操作已成功完成")
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                }
                .padding(ThemeSpacing.p4.rawValue)
                .background(Color.themeGreen500.opacity(0.1))
                .cornerRadius(ThemeRadius.lg.rawValue)
                .overlay(
                    RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                        .stroke(Color.themeGreen500.opacity(0.3), lineWidth: ThemeRadius.base.rawValue)
                )

                // 信息卡片
                VStack(alignment: .leading, spacing: ThemeSpacing.p2.rawValue) {
                    HStack {
                        Text("信息提示")
                            .font(.themeH2)
                            .foregroundColor(.themeBlue600)
                        Spacer()
                        LucideView(name: .info, size: 16, color: .themeBlue500)
                    }

                    Text("这是一条重要的信息")
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                }
                .padding(ThemeSpacing.p4.rawValue)
                .background(Color.themeBlue500.opacity(0.1))
                .cornerRadius(ThemeRadius.lg.rawValue)
                .overlay(
                    RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                        .stroke(Color.themeBlue500.opacity(0.3), lineWidth: ThemeRadius.base.rawValue)
                )
            }
        }
        .padding(ThemeSpacing.p6.rawValue)
        .background(Color.themeBackground)
    }
}
```

---

## 字体使用示例

### 字体层级示例

```swift
struct FontHierarchy: View {
    var body: some View {
        VStack(spacing: ThemeSpacing.p4.rawValue) {
            // 标题层级
            VStack(spacing: ThemeSpacing.p3.rawValue) {
                Text("字体层级")
                    .font(.themeH1)
                    .foregroundColor(.themeTextPrimary)

                Text("这是一个 H1 标题 (16px)")
                    .font(.themeH1)
                    .foregroundColor(.themeTextPrimary)

                Text("这是一个 H2 标题 (14px)")
                    .font(.themeH2)
                    .foregroundColor(.themeTextSecondary)
            }

            // 正文层级
            VStack(spacing: ThemeSpacing.p3.rawValue) {
                Text("正文示例")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)

                Text("这是正文文本 (14px)，用于显示主要内容。正文应该易于阅读，保持合适的行高和字间距。")
                    .font(.themeBody)
                    .foregroundColor(.themeTextPrimary)
                    .multilineTextAlignment(.leading)
                    .padding(ThemeSpacing.p3.rawValue)
                    .background(Color.themeCard)
                    .cornerRadius(ThemeRadius.lg.rawValue)
                    .overlay(
                        RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                            .stroke(Color.themeBorder, lineWidth: ThemeRadius.base.rawValue)
                    )
            }

            // 辅助文本层级
            VStack(spacing: ThemeSpacing.p3.rawValue) {
                Text("辅助文本")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)

                Text("这是辅助文本 (12px)，用于显示次要信息或说明文字。")
                    .font(.themeCaption)
                    .foregroundColor(.themeTextSecondary)

                Text("这是标签文本 (10px)，用于显示小的标签或提示。")
                    .font(.themeCaptionSmall)
                    .foregroundColor(.themeTextTertiary)

                Text("这是注释文本 (8px)，用于显示版权信息或详细说明。")
                    .font(.themeCaptionTiny)
                    .foregroundColor(.themeGray500)
            }
        }
        .padding(ThemeSpacing.p6.rawValue)
        .background(Color.themeBackground)
    }
}
```

### 字重和字族示例

```swift
struct FontWeightAndFamily: View {
    var body: some View {
        VStack(spacing: ThemeSpacing.p4.rawValue) {
            // 字重示例
            VStack(spacing: ThemeSpacing.p3.rawValue) {
                Text("字重示例")
                    .font(.themeH1)
                    .foregroundColor(.themeTextPrimary)

                Text("Light (300) - 轻量文本")
                    .font(.themeBody.weight(.light))
                    .foregroundColor(.themeTextPrimary)

                Text("Normal (400) - 普通文本")
                    .font(.themeBody.weight(.normal))
                    .foregroundColor(.themeTextPrimary)

                Text("Medium (500) - 中等文本")
                    .font(.themeBody.weight(.medium))
                    .foregroundColor(.themeTextPrimary)

                Text("Semibold (600) - 半粗体")
                    .font(.themeBody.weight(.semibold))
                    .foregroundColor(.themeTextPrimary)

                Text("Bold (700) - 粗体")
                    .font(.themeBody.weight(.bold))
                    .foregroundColor(.themeTextPrimary)
            }

            // 字族示例
            VStack(spacing: ThemeSpacing.p3.rawValue) {
                Text("字族示例")
                    .font(.themeH1)
                    .foregroundColor(.themeTextPrimary)

                Text("Sans-serif (默认字体族)")
                    .font(.themeBody)
                    .foregroundColor(.themeTextPrimary)

                Text("Monospace (等宽字体族)")
                    .font(.themeBody.monospace())
                    .foregroundColor(.themeTextPrimary)
            }

            // 字体组合示例
            VStack(spacing: ThemeSpacing.p3.rawValue) {
                Text("字体组合")
                    .font(.themeH1)
                    .foregroundColor(.themeTextPrimary)

                VStack(alignment: .leading, spacing: ThemeSpacing.p2.rawValue) {
                    Text("设置项标题")
                        .font(.themeH2.weight(.semibold))
                        .foregroundColor(.themeTextPrimary)

                    Text("这是对设置项的详细说明，使用较小的字体和较轻的字重。")
                        .font(.themeBody.weight(.normal))
                        .foregroundColor(.themeTextSecondary)

                    Text("代码示例：let value = 42")
                        .font(.themeCaptionSmall.monospace())
                        .foregroundColor(.themeTextPrimary)
                        .padding(ThemeSpacing.p2.rawValue)
                        .background(Color.themeInput)
                        .cornerRadius(ThemeRadius.base.rawValue)
                }
                .padding(ThemeSpacing.p4.rawValue)
                .background(Color.themeCard)
                .cornerRadius(ThemeRadius.lg.rawValue)
                .overlay(
                    RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                        .stroke(Color.themeBorder, lineWidth: ThemeRadius.base.rawValue)
                )
            }
        }
        .padding(ThemeSpacing.p6.rawValue)
        .background(Color.themeBackground)
    }
}
```

---

## 间距使用示例

### 间距系统示例

```swift
struct SpacingSystem: View {
    var body: some View {
        ScrollView {
            VStack(spacing: ThemeSpacing.p6.rawValue) {
                // 内边距示例
                VStack(spacing: ThemeSpacing.p4.rawValue) {
                    Text("内边距示例")
                        .font(.themeH1)
                        .foregroundColor(.themeTextPrimary)

                    // p-2
                    Text("p-2 (8px)")
                        .font(.themeBody)
                        .foregroundColor(.white)
                        .padding(ThemeSpacing.p2.rawValue)
                        .background(Color.themeBlue500)
                        .cornerRadius(ThemeRadius.lg.rawValue)

                    // p-4
                    Text("p-4 (16px)")
                        .font(.themeBody)
                        .foregroundColor(.white)
                        .padding(ThemeSpacing.p4.rawValue)
                        .background(Color.themePurple500)
                        .cornerRadius(ThemeRadius.lg.rawValue)

                    // p-6
                    Text("p-6 (24px)")
                        .font(.themeBody)
                        .foregroundColor(.white)
                        .padding(ThemeSpacing.p6.rawValue)
                        .background(Color.themeGreen500)
                        .cornerRadius(ThemeRadius.lg.rawValue)
                }

                // 外边距示例
                VStack(spacing: ThemeSpacing.p4.rawValue) {
                    Text("外边距示例")
                        .font(.themeH1)
                        .foregroundColor(.themeTextPrimary)

                    // m-2
                    Text("m-2 (8px)")
                        .font(.themeBody)
                        .foregroundColor(.white)
                        .padding(ThemeSpacing.p3.rawValue)
                        .background(Color.themeRed500)
                        .cornerRadius(ThemeRadius.lg.rawValue)
                        .offset(y: ThemeSpacing.p2.rawValue)

                    // m-4
                    Text("m-4 (16px)")
                        .font(.themeBody)
                        .foregroundColor(.white)
                        .padding(ThemeSpacing.p3.rawValue)
                        .background(Color.themeYellow500)
                        .cornerRadius(ThemeRadius.lg.rawValue)
                        .offset(y: ThemeSpacing.p4.rawValue)

                    // m-6
                    Text("m-6 (24px)")
                        .font(.themeBody)
                        .foregroundColor(.white)
                        .padding(ThemeSpacing.p3.rawValue)
                        .background(Color.themeBlue500)
                        .cornerRadius(ThemeRadius.lg.rawValue)
                        .offset(y: ThemeSpacing.p6.rawValue)
                }

                // 尺寸示例
                VStack(spacing: ThemeSpacing.p4.rawValue) {
                    Text("尺寸示例")
                        .font(.themeH1)
                        .foregroundColor(.themeTextPrimary)

                    // 宽度示例
                    VStack(spacing: ThemeSpacing.p3.rawValue) {
                        Rectangle()
                            .fill(Color.themeBlue500)
                            .frame(width: ThemeSpacing.w16.rawValue, height: 40)
                            .cornerRadius(ThemeRadius.lg.rawValue)
                            .overlay(Text("w-16 (64px)"), alignment: .center)

                        Rectangle()
                            .fill(Color.themePurple500)
                            .frame(width: ThemeSpacing.w16.rawValue * 2, height: 40)
                            .cornerRadius(ThemeRadius.lg.rawValue)
                            .overlay(Text("w-32 (128px)"), alignment: .center)
                    }

                    // 高度示例
                    VStack(spacing: ThemeSpacing.p3.rawValue) {
                        HStack(spacing: ThemeSpacing.p4.rawValue) {
                            Rectangle()
                                .fill(Color.themeGreen500)
                                .frame(width: 40, height: ThemeSpacing.h12.rawValue)
                                .cornerRadius(ThemeRadius.lg.rawValue)
                                .overlay(Text("h-12 (48px)"), alignment: .center)
                                .rotationEffect(.degrees(-90))

                            Rectangle()
                                .fill(Color.themeRed500)
                                .frame(width: 40, height: ThemeSpacing.h12.rawValue * 2)
                                .cornerRadius(ThemeRadius.lg.rawValue)
                                .overlay(Text("h-24 (96px)"), alignment: .center)
                                .rotationEffect(.degrees(-90))
                        }
                    }
                }

                // 间距组合示例
                VStack(spacing: ThemeSpacing.p4.rawValue) {
                    Text("间距组合")
                        .font(.themeH1)
                        .foregroundColor(.themeTextPrimary)

                    VStack(spacing: ThemeSpacing.p4.rawValue) {
                        Text("这是一个使用多种间距组合的示例")
                            .font(.themeBody)
                            .foregroundColor(.themeTextPrimary)
                            .padding(ThemeSpacing.p6.rawValue)
                            .background(Color.themeCard)
                            .cornerRadius(ThemeRadius.lg.rawValue)
                            .overlay(
                                RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                                    .stroke(Color.themeBorder, lineWidth: ThemeRadius.base.rawValue)
                            )

                        HStack(spacing: ThemeSpacing.p4.rawValue) {
                            Button("按钮 1") {
                                print("按钮 1 点击")
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.white)
                            .background(Color.themeBlue500)
                            .cornerRadius(ThemeRadius.lg.rawValue)
                            .padding(ThemeSpacing.p3.rawValue)
                            .padding(.horizontal, ThemeSpacing.p4.rawValue)

                            Button("按钮 2") {
                                print("按钮 2 点击")
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.white)
                            .background(Color.themePurple500)
                            .cornerRadius(ThemeRadius.lg.rawValue)
                            .padding(ThemeSpacing.p3.rawValue)
                            .padding(.horizontal, ThemeSpacing.p4.rawValue)
                        }
                    }
                    .padding(ThemeSpacing.p6.rawValue)
                    .background(Color.themePanel)
                    .cornerRadius(ThemeRadius.lg.rawValue)
                }
            }
            .padding(ThemeSpacing.p6.rawValue)
        }
        .background(Color.themeBackground)
    }
}
```

### 布局间距示例

```swift
struct LayoutSpacing: View {
    var body: some View {
        VStack(spacing: 0) {
            // 头部
            HStack {
                Text("头部区域")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)
                Spacer()
                Button("关闭") {
                    print("关闭")
                }
                .buttonStyle(.bordered)
                .foregroundColor(.white)
                .background(Color.themeRed500)
                .cornerRadius(ThemeRadius.md.rawValue)
            }
            .padding(ThemeSpacing.p3.rawValue)
            .background(Color.themePanel)
            .overlay(Rectangle().frame(height: ThemeRadius.base.rawValue).foregroundColor(Color.themeBorder), alignment: .bottom)

            // 内容区
            VStack(spacing: ThemeSpacing.p4.rawValue) {
                // 搜索栏
                HStack {
                    LucideView(name: .search, size: 16, color: .themeGray400)
                    TextField("搜索...", text: .constant(""))
                        .textFieldStyle(.plain)
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                }
                .padding(ThemeSpacing.p3.rawValue)
                .background(Color.themeItem)
                .cornerRadius(ThemeRadius.lg.rawValue)
                .overlay(
                    RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                        .stroke(Color.themeBorder, lineWidth: ThemeRadius.base.rawValue)
                )

                // 内容网格
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: ThemeSpacing.p4.rawValue),
                    GridItem(.flexible(), spacing: ThemeSpacing.p4.rawValue)
                ], spacing: ThemeSpacing.p4.rawValue) {
                    ForEach(0..<6) { index in
                        VStack(alignment: .leading, spacing: ThemeSpacing.p3.rawValue) {
                            Text("卡片标题 \(index + 1)")
                                .font(.themeH2)
                                .foregroundColor(.themeTextPrimary)

                            Text("这是卡片的描述文本，用来展示内容。")
                                .font(.themeBody)
                                .foregroundColor(.themeTextSecondary)
                                .lineLimit(3)
                        }
                        .padding(ThemeSpacing.p4.rawValue)
                        .background(Color.themeCard)
                        .cornerRadius(ThemeRadius.lg.rawValue)
                        .overlay(
                            RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                                .stroke(Color.themeBorder, lineWidth: ThemeRadius.base.rawValue)
                        )
                    }
                }
            }
            .padding(ThemeSpacing.p6.rawValue)

            // 底部
            HStack {
                Text("状态信息")
                    .font(.themeCaptionSmall)
                    .foregroundColor(.themeTextTertiary)
                Spacer()
                Text("© 2024 QuiteNote")
                    .font(.themeCaptionSmall)
                    .foregroundColor(.themeTextTertiary)
            }
            .padding(ThemeSpacing.p3.rawValue)
            .background(Color.themePanel)
            .overlay(Rectangle().frame(height: ThemeRadius.base.rawValue).foregroundColor(Color.themeBorder), alignment: .top)
        }
        .background(Color.themeBackground)
    }
}
```

---

## 形状使用示例

### 圆角示例

```swift
struct BorderRadiusExamples: View {
    var body: some View {
        VStack(spacing: ThemeSpacing.p6.rawValue) {
            Text("圆角示例")
                .font(.themeH1)
                .foregroundColor(.themeTextPrimary)

            // 不同圆角大小
            VStack(spacing: ThemeSpacing.p4.rawValue) {
                HStack(spacing: ThemeSpacing.p3.rawValue) {
                    // rounded-none
                    Rectangle()
                        .fill(Color.themeBlue500)
                        .frame(width: 80, height: 60)
                        .cornerRadius(ThemeRadius.none.rawValue)
                        .overlay(Text("none"), alignment: .center)

                    // rounded-sm
                    Rectangle()
                        .fill(Color.themePurple500)
                        .frame(width: 80, height: 60)
                        .cornerRadius(ThemeRadius.sm.rawValue)
                        .overlay(Text("sm"), alignment: .center)

                    // rounded
                    Rectangle()
                        .fill(Color.themeGreen500)
                        .frame(width: 80, height: 60)
                        .cornerRadius(ThemeRadius.base.rawValue)
                        .overlay(Text("base"), alignment: .center)
                }

                HStack(spacing: ThemeSpacing.p3.rawValue) {
                    // rounded-md
                    Rectangle()
                        .fill(Color.themeYellow500)
                        .frame(width: 80, height: 60)
                        .cornerRadius(ThemeRadius.md.rawValue)
                        .overlay(Text("md"), alignment: .center)

                    // rounded-lg
                    Rectangle()
                        .fill(Color.themeRed500)
                        .frame(width: 80, height: 60)
                        .cornerRadius(ThemeRadius.lg.rawValue)
                        .overlay(Text("lg"), alignment: .center)

                    // rounded-xl
                    Rectangle()
                        .fill(Color.themeGray600)
                        .frame(width: 80, height: 60)
                        .cornerRadius(ThemeRadius.xl.rawValue)
                        .overlay(Text("xl"), alignment: .center)
                }

                HStack(spacing: ThemeSpacing.p3.rawValue) {
                    // rounded-2xl
                    Rectangle()
                        .fill(Color.themeBlue600)
                        .frame(width: 80, height: 60)
                        .cornerRadius(ThemeRadius.`2xl`.rawValue)
                        .overlay(Text("2xl"), alignment: .center)

                    // rounded-3xl
                    Rectangle()
                        .fill(Color.themePurple600)
                        .frame(width: 80, height: 60)
                        .cornerRadius(ThemeRadius.`3xl`.rawValue)
                        .overlay(Text("3xl"), alignment: .center)

                    // rounded-full
                    Rectangle()
                        .fill(Color.themeGreen600)
                        .frame(width: 80, height: 60)
                        .cornerRadius(ThemeRadius.full.rawValue)
                        .overlay(Text("full"), alignment: .center)
                }
            }

            // 圆角形状组合
            VStack(spacing: ThemeSpacing.p4.rawValue) {
                Text("圆角形状组合")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)

                // 卡片样式
                VStack(alignment: .leading, spacing: ThemeSpacing.p3.rawValue) {
                    HStack {
                        Text("卡片标题")
                            .font(.themeH2)
                            .foregroundColor(.themeTextPrimary)
                        Spacer()
                        LucideView(name: .star, size: 16, color: .themeYellow)
                    }

                    Text("这是一个使用 lg 圆角的卡片示例。圆角大小让界面更加友好。")
                        .font(.themeBody)
                        .foregroundColor(.themeTextSecondary)

                    HStack {
                        Button("操作") {
                            print("操作按钮")
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.white)
                        .background(Color.themeBlue500)
                        .cornerRadius(ThemeRadius.lg.rawValue)
                        .padding(ThemeSpacing.p2.rawValue)

                        Spacer()

                        Button("取消") {
                            print("取消按钮")
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.themeTextSecondary)
                        .background(Color.themeItem)
                        .cornerRadius(ThemeRadius.lg.rawValue)
                        .padding(ThemeSpacing.p2.rawValue)
                        .overlay(
                            RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                                .stroke(Color.themeBorder, lineWidth: ThemeRadius.base.rawValue)
                        )
                    }
                }
                .padding(ThemeSpacing.p4.rawValue)
                .background(Color.themeCard)
                .cornerRadius(ThemeRadius.lg.rawValue)
                .overlay(
                    RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                        .stroke(Color.themeBorder, lineWidth: ThemeRadius.base.rawValue)
                )

                // 输入框样式
                VStack(spacing: ThemeSpacing.p2.rawValue) {
                    Text("输入框示例")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    TextField("请输入内容", text: .constant(""))
                        .textFieldStyle(.roundedBorder)
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                        .padding(ThemeSpacing.p3.rawValue)
                        .background(Color.themeInput)
                        .cornerRadius(ThemeRadius.base.rawValue)
                        .overlay(
                            RoundedRectangle(cornerRadius: ThemeRadius.base.rawValue)
                                .stroke(Color.themeBorder, lineWidth: ThemeRadius.base.rawValue)
                        )
                }
                .padding(ThemeSpacing.p4.rawValue)
                .background(Color.themePanel)
                .cornerRadius(ThemeRadius.lg.rawValue)
            }
        }
        .padding(ThemeSpacing.p6.rawValue)
        .background(Color.themeBackground)
    }
}
```

### 边框示例

```swift
struct BorderExamples: View {
    var body: some View {
        VStack(spacing: ThemeSpacing.p6.rawValue) {
            Text("边框示例")
                .font(.themeH1)
                .foregroundColor(.themeTextPrimary)

            // 不同边框样式
            VStack(spacing: ThemeSpacing.p4.rawValue) {
                // 细边框
                VStack(spacing: ThemeSpacing.p2.rawValue) {
                    Text("细边框 (1px)")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)

                    Text("这是一个使用细边框的示例")
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                        .padding(ThemeSpacing.p4.rawValue)
                        .background(Color.themeCard)
                        .cornerRadius(ThemeRadius.lg.rawValue)
                        .border(width: ThemeRadius.base.rawValue, color: Color.themeBorder)
                }

                // 中等边框
                VStack(spacing: ThemeSpacing.p2.rawValue) {
                    Text("中等边框 (2px)")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)

                    Text("这是一个使用中等边框的示例")
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                        .padding(ThemeSpacing.p4.rawValue)
                        .background(Color.themeItem)
                        .cornerRadius(ThemeRadius.lg.rawValue)
                        .border(width: ThemeRadius.md.rawValue, color: Color.themeBlue500)
                }

                // 粗边框
                VStack(spacing: ThemeSpacing.p2.rawValue) {
                    Text("粗边框 (3px)")
                        .font(.themeCaptionSmall)
                        .foregroundColor(.themeTextTertiary)

                    Text("这是一个使用粗边框的示例")
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                        .padding(ThemeSpacing.p4.rawValue)
                        .background(Color.themePanel)
                        .cornerRadius(ThemeRadius.lg.rawValue)
                        .border(width: ThemeRadius.lg.rawValue, color: Color.themePurple500)
                }
            }

            // 边框组合示例
            VStack(spacing: ThemeSpacing.p4.rawValue) {
                Text("边框组合")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)

                // 卡片网格
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: ThemeSpacing.p4.rawValue),
                    GridItem(.flexible(), spacing: ThemeSpacing.p4.rawValue)
                ], spacing: ThemeSpacing.p4.rawValue) {
                    // 成功卡片
                    VStack(alignment: .leading, spacing: ThemeSpacing.p3.rawValue) {
                        HStack {
                            LucideView(name: .check, size: 16, color: .themeGreen500)
                            Text("成功")
                                .font(.themeCaptionSmall.uppercase())
                                .foregroundColor(.themeGreen500)
                            Spacer()
                        }

                        Text("操作成功完成")
                            .font(.themeH2)
                            .foregroundColor(.themeTextPrimary)

                        Text("所有数据已保存到本地。")
                            .font(.themeBody)
                            .foregroundColor(.themeTextSecondary)
                    }
                    .padding(ThemeSpacing.p4.rawValue)
                    .background(Color.themeGreen500.opacity(0.05))
                    .cornerRadius(ThemeRadius.lg.rawValue)
                    .overlay(
                        RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                            .stroke(Color.themeGreen500.opacity(0.3), lineWidth: ThemeRadius.base.rawValue)
                    )

                    // 信息卡片
                    VStack(alignment: .leading, spacing: ThemeSpacing.p3.rawValue) {
                        HStack {
                            LucideView(name: .info, size: 16, color: .themeBlue500)
                            Text("信息")
                                .font(.themeCaptionSmall.uppercase())
                                .foregroundColor(.themeBlue500)
                            Spacer()
                        }

                        Text("系统更新")
                            .font(.themeH2)
                            .foregroundColor(.themeTextPrimary)

                        Text("发现新版本，建议立即更新。")
                            .font(.themeBody)
                            .foregroundColor(.themeTextSecondary)
                    }
                    .padding(ThemeSpacing.p4.rawValue)
                    .background(Color.themeBlue500.opacity(0.05))
                    .cornerRadius(ThemeRadius.lg.rawValue)
                    .overlay(
                        RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                            .stroke(Color.themeBlue500.opacity(0.3), lineWidth: ThemeRadius.base.rawValue)
                    )

                    // 警告卡片
                    VStack(alignment: .leading, spacing: ThemeSpacing.p3.rawValue) {
                        HStack {
                            LucideView(name: .alertTriangle, size: 16, color: .themeYellow500)
                            Text("警告")
                                .font(.themeCaptionSmall.uppercase())
                                .foregroundColor(.themeYellow500)
                            Spacer()
                        }

                        Text("配置变更")
                            .font(.themeH2)
                            .foregroundColor(.themeTextPrimary)

                        Text("修改设置后需要重启应用。")
                            .font(.themeBody)
                            .foregroundColor(.themeTextSecondary)
                    }
                    .padding(ThemeSpacing.p4.rawValue)
                    .background(Color.themeYellow500.opacity(0.05))
                    .cornerRadius(ThemeRadius.lg.rawValue)
                    .overlay(
                        RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                            .stroke(Color.themeYellow500.opacity(0.3), lineWidth: ThemeRadius.base.rawValue)
                    )

                    // 错误卡片
                    VStack(alignment: .leading, spacing: ThemeSpacing.p3.rawValue) {
                        HStack {
                            LucideView(name: .x, size: 16, color: .themeRed500)
                            Text("错误")
                                .font(.themeCaptionSmall.uppercase())
                                .foregroundColor(.themeRed500)
                            Spacer()
                        }

                        Text("操作失败")
                            .font(.themeH2)
                            .foregroundColor(.themeTextPrimary)

                        Text("无法连接到服务器，请检查网络。")
                            .font(.themeBody)
                            .foregroundColor(.themeTextSecondary)
                    }
                    .padding(ThemeSpacing.p4.rawValue)
                    .background(Color.themeRed500.opacity(0.05))
                    .cornerRadius(ThemeRadius.lg.rawValue)
                    .overlay(
                        RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                            .stroke(Color.themeRed500.opacity(0.3), lineWidth: ThemeRadius.base.rawValue)
                    )
                }
            }
        }
        .padding(ThemeSpacing.p6.rawValue)
        .background(Color.themeBackground)
    }
}
```

---

## 动画使用示例

### 基础动画示例

```swift
struct BasicAnimations: View {
    @State private var isExpanded = false
    @State private var isRotated = false
    @State private var isPulsing = false
    @State private var scale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: ThemeSpacing.p6.rawValue) {
            Text("基础动画")
                .font(.themeH1)
                .foregroundColor(.themeTextPrimary)

            // 展开/折叠动画
            VStack(spacing: ThemeSpacing.p3.rawValue) {
                Text("展开/折叠动画")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)

                Button("切换展开状态") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }
                .buttonStyle(.bordered)
                .foregroundColor(.white)
                .background(Color.themeBlue500)
                .cornerRadius(ThemeRadius.lg.rawValue)
                .padding(ThemeSpacing.p2.rawValue)

                VStack(alignment: .leading, spacing: ThemeSpacing.p2.rawValue) {
                    Text("标题")
                        .font(.themeH2)
                        .foregroundColor(.themeTextPrimary)

                    if isExpanded {
                        Text("这是展开的内容。当状态改变时，会使用弹簧动画平滑过渡。")
                            .font(.themeBody)
                            .foregroundColor(.themeTextSecondary)
                            .transition(.slideRight)
                    }
                }
                .padding(ThemeSpacing.p4.rawValue)
                .background(Color.themeCard)
                .cornerRadius(ThemeRadius.lg.rawValue)
                .overlay(
                    RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                        .stroke(Color.themeBorder, lineWidth: ThemeRadius.base.rawValue)
                )
                .animation(.easeInOut(duration: ThemeDuration.`300`.rawValue), value: isExpanded)
            }

            // 旋转动画
            VStack(spacing: ThemeSpacing.p3.rawValue) {
                Text("旋转动画")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)

                Button("旋转图标") {
                    withAnimation(.spin) {
                        isRotated.toggle()
                    }
                }
                .buttonStyle(.bordered)
                .foregroundColor(.white)
                .background(Color.themePurple500)
                .cornerRadius(ThemeRadius.lg.rawValue)
                .padding(ThemeSpacing.p2.rawValue)

                LucideView(name: .refreshCw, size: 48, color: .themePurple500)
                    .rotationEffect(.degrees(isRotated ? 360 : 0))
                    .animation(.spin, value: isRotated)
            }

            // 缩放动画
            VStack(spacing: ThemeSpacing.p3.rawValue) {
                Text("缩放动画")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)

                Button(action: {
                    withAnimation(.scale) {
                        scale = scale == 1.0 ? 1.2 : 1.0
                    }
                }) {
                    Text("缩放按钮")
                        .font(.themeBody)
                        .foregroundColor(.white)
                        .padding(ThemeSpacing.p4.rawValue)
                        .padding(.horizontal, ThemeSpacing.p6.rawValue)
                        .background(Color.themeGreen500)
                        .cornerRadius(ThemeRadius.lg.rawValue)
                        .scaleEffect(scale)
                }
            }

            // 脉冲动画
            VStack(spacing: ThemeSpacing.p3.rawValue) {
                Text("脉冲动画")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)

                Button("开始脉冲") {
                    isPulsing = true
                }
                .buttonStyle(.bordered)
                .foregroundColor(.white)
                .background(Color.themeRed500)
                .cornerRadius(ThemeRadius.lg.rawValue)
                .padding(ThemeSpacing.p2.rawValue)

                LucideView(name: .heart, size: 48, color: .themeRed500)
                    .scaleEffect(isPulsing ? 1.2 : 1.0)
                    .animation(.pulse, value: isPulsing)
                    .onAppear {
                        isPulsing = true
                    }
                    .onDisappear {
                        isPulsing = false
                    }
            }
        }
        .padding(ThemeSpacing.p6.rawValue)
        .background(Color.themeBackground)
    }
}
```

### 过渡动画示例

```swift
struct TransitionAnimations: View {
    @State private var showContent = false
    @State private var selectedTab = "tab1"

    var body: some View {
        VStack(spacing: ThemeSpacing.p6.rawValue) {
            Text("过渡动画")
                .font(.themeH1)
                .foregroundColor(.themeTextPrimary)

            // 滑入滑出动画
            VStack(spacing: ThemeSpacing.p3.rawValue) {
                Text("滑入滑出")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)

                Button("切换显示") {
                    withAnimation(.easeInOut(duration: ThemeDuration.`300`.rawValue)) {
                        showContent.toggle()
                    }
                }
                .buttonStyle(.bordered)
                .foregroundColor(.white)
                .background(Color.themeBlue500)
                .cornerRadius(ThemeRadius.lg.rawValue)
                .padding(ThemeSpacing.p2.rawValue)

                if showContent {
                    VStack(alignment: .leading, spacing: ThemeSpacing.p2.rawValue) {
                        Text("滑入的内容")
                            .font(.themeH2)
                            .foregroundColor(.themeTextPrimary)

                        Text("这个内容使用 slideRight 过渡效果。")
                            .font(.themeBody)
                            .foregroundColor(.themeTextSecondary)
                    }
                    .padding(ThemeSpacing.p4.rawValue)
                    .background(Color.themeCard)
                    .cornerRadius(ThemeRadius.lg.rawValue)
                    .transition(.slideRight)
                    .animation(.slideRight, value: showContent)
                }
            }

            // 标签页切换
            VStack(spacing: ThemeSpacing.p3.rawValue) {
                Text("标签页切换")
                    .font(.themeH2)
                    .foregroundColor(.themeTextPrimary)

                HStack(spacing: ThemeSpacing.p2.rawValue) {
                    TabButton(title: "标签 1", isSelected: selectedTab == "tab1") {
                        withAnimation(.settingsIn) {
                            selectedTab = "tab1"
                        }
                    }

                    TabButton(title: "标签 2", isSelected: selectedTab == "tab2") {
                        withAnimation(.settingsIn) {
                            selectedTab = "tab2"
                        }
                    }

                    TabButton(title: "标签 3", isSelected: selectedTab == "tab3") {
                        withAnimation(.settingsIn) {
                            selectedTab = "tab3"
                        }
                    }
                }

                // 标签内容
                Group {
                    if selectedTab == "tab1" {
                        TabContent(title: "标签 1 内容", color: .themeBlue500)
                            .transition(.settingsIn)
                    } else if selectedTab == "tab2" {
                        TabContent(title: "标签 2 内容", color: .themePurple500)
                            .transition(.settingsIn)
                    } else {
                        TabContent(title: "标签 3 内容", color: .themeGreen500)
                            .transition(.settingsIn)
                    }
                }
                .animation(.settingsIn, value: selectedTab)
            }
        }
        .padding(ThemeSpacing.p6.rawValue)
        .background(Color.themeBackground)
    }

    @ViewBuilder
    private func TabButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .foregroundColor(isSelected ? .white : .themeTextSecondary)
            .background(isSelected ? Color.themeBlue500 : Color.themeItem)
            .cornerRadius(ThemeRadius.lg.rawValue)
            .padding(ThemeSpacing.p2.rawValue)
    }

    private func TabContent(title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.p2.rawValue) {
            Text(title)
                .font(.themeH2)
                .foregroundColor(.themeTextPrimary)

            Text("这是 \(title) 的详细内容。标签页切换使用 settingsIn 过渡动画。")
                .font(.themeBody)
                .foregroundColor(.themeTextSecondary)
                .lineLimit(3)
        }
        .padding(ThemeSpacing.p4.rawValue)
        .background(Color.themeCard)
        .cornerRadius(ThemeRadius.lg.rawValue)
        .overlay(
            RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue)
                .stroke(Color.themeBorder, lineWidth: ThemeRadius.base.rawValue)
        )
    }
}
```

### Toast 动画示例

```swift
struct ToastAnimations: View {
    @State private var showToast = false
    @State private var toastMessage = ""

    var body: some View {
        VStack(spacing: ThemeSpacing.p6.rawValue) {
            Text("Toast 动画")
                .font(.themeH1)
                .foregroundColor(.themeTextPrimary)

            VStack(spacing: ThemeSpacing.p3.rawValue) {
                Button("显示成功 Toast") {
                    toastMessage = "操作成功！"
                    showToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showToast = false
                    }
                }
                .buttonStyle(.bordered)
                .foregroundColor(.white)
                .background(Color.themeGreen500)
                .cornerRadius(ThemeRadius.lg.rawValue)
                .padding(ThemeSpacing.p2.rawValue)

                Button("显示错误 Toast") {
                    toastMessage = "操作失败！"
                    showToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showToast = false
                    }
                }
                .buttonStyle(.bordered)
                .foregroundColor(.white)
                .background(Color.themeRed500)
                .cornerRadius(ThemeRadius.lg.rawValue)
                .padding(ThemeSpacing.p2.rawValue)

                Button("显示警告 Toast") {
                    toastMessage = "请注意！"
                    showToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showToast = false
                    }
                }
                .buttonStyle(.bordered)
                .foregroundColor(.white)
                .background(Color.themeYellow500)
                .cornerRadius(ThemeRadius.lg.rawValue)
                .padding(ThemeSpacing.p2.rawValue)
            }

            // Toast 显示区域
            if showToast {
                ToastView(message: toastMessage, type: toastMessage.contains("成功") ? .success : toastMessage.contains("失败") ? .error : .warning)
                    .transition(.toastIn)
                    .animation(.toastIn, value: showToast)
            }
        }
        .padding(ThemeSpacing.p6.rawValue)
        .background(Color.themeBackground)
    }
}

struct ToastView: View {
    let message: String
    let type: ToastType

    enum ToastType {
        case success
        case error
        case warning
        case info
    }

    var body: some View {
        HStack(spacing: ThemeSpacing.p2.rawValue) {
            // 图标
            let iconColor: Color = {
                switch type {
                case .success: return .white
                case .error: return .white
                case .warning: return .themeGray900
                case .info: return .white
                }
            }()

            let icon: IconName = {
                switch type {
                case .success: return .check
                case .error: return .x
                case .warning: return .alertTriangle
                case .info: return .info
                }
            }()

            LucideView(name: icon, size: 16, color: iconColor)

            Text(message)
                .font(.themeCaptionSmall)
                .foregroundColor(.white)

            Spacer()
        }
        .padding(ThemeSpacing.p3.rawValue)
        .padding(.horizontal, ThemeSpacing.p4.rawValue)
        .background(toastBackgroundColor)
        .cornerRadius(ThemeRadius.lg.rawValue)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 4)
    }

    private var toastBackgroundColor: Color {
        switch type {
        case .success: return Color.themeGreen500.opacity(0.9)
        case .error: return Color.themeRed500.opacity(0.9)
        case .warning: return Color.themeYellow500.opacity(0.9)
        case .info: return Color.themeGray800.opacity(0.9)
        }
    }
}
```

---

## 完整组件示例

### RecordCard 完整示例

```swift
struct FullRecordCardExample: View {
    @State private var expandedId: UUID? = nil
    @State private var records: [MockRecord] = sampleRecords

    private struct MockRecord {
        let id = UUID()
        let title: String
        let content: String
        let summary: String?
        let createdAt: Date
        let starred: Bool
        let aiStatus: String
    }

    private static let sampleRecords: [MockRecord] = [
        MockRecord(
            title: "Rust 语言介绍",
            content: "Rust 是一种系统级编程语言，专注于安全性，尤其是并发安全。它支持函数式和命令式以及泛型等编程范式的多范式语言。",
            summary: "Rust 是一种注重安全与性能的系统级编程语言，解决了 C++ 在内存安全和并发性上的痛点。",
            createdAt: Date(),
            starred: true,
            aiStatus: "summarized"
        ),
        MockRecord(
            title: "React Hook 使用",
            content: "const [count, setCount] = useState(0); useEffect(() => { console.log('Count changed'); }, [count]);",
            summary: null,
            createdAt: Date().addingTimeInterval(-3600),
            starred: false,
            aiStatus: "title-only"
        ),
        MockRecord(
            title: "TODO 事项",
            content: "1. 完成项目文档\n2. 修复 bug\n3. 代码审查",
            summary: null,
            createdAt: Date().addingTimeInterval(-7200),
            starred: false,
            aiStatus: "raw"
        )
    ]

    var body: some View {
        VStack(spacing: ThemeSpacing.p4.rawValue) {
            Text("完整的 RecordCard 示例")
                .font(.themeH1)
                .foregroundColor(.themeTextPrimary)

            List(records) { record in
                RecordCardView(
                    record: record,
                    expandedId: $expandedId
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(PlainListStyle())
            .background(Color.themeBackground)
        }
        .padding(ThemeSpacing.p6.rawValue)
        .background(Color.themeBackground)
    }

    @ViewBuilder
    private func RecordCardView(record: MockRecord, expandedId: Binding<UUID?>) -> some View {
        let isExpanded = expandedId.wrappedValue == record.id

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: ThemeSpacing.px3.rawValue) {
                // 图标
                let icon: IconName = record.aiStatus == "summarized" ? .sparkles : .clipboard
                let iconColor: Color = record.aiStatus == "summarized" ? .themePurple500 : .themeGray400

                LucideView(name: icon, size: 16, color: iconColor)
                    .frame(width: 20, height: 20)
                    .padding(.top, 4)

                // 内容
                VStack(alignment: .leading, spacing: ThemeSpacing.px2.rawValue) {
                    Text(record.title)
                        .font(.themeBody.weight(isExpanded ? .semibold : .medium))
                        .foregroundColor(.themeTextPrimary)
                        .lineLimit(1)

                    HStack(spacing: ThemeSpacing.px2.rawValue) {
                        Text(record.createdAt.formatted(date: .omitted, time: .shortened))
                        Rectangle().fill(Color.themeGray700).frame(width: ThemeRadius.base.rawValue, height: 10)
                        Text("\(record.content.count) 字符")
                        Rectangle().fill(Color.themeGray700).frame(width: ThemeRadius.base.rawValue, height: 10)

                        // 状态标签
                        HStack(spacing: 2) {
                            let statusIcon: IconName = record.aiStatus == "summarized" ? .sparkles : .clock
                            let statusColor: Color = record.aiStatus == "summarized" ? .themePurple500 : .themeGray500
                            let statusText: String = record.aiStatus == "summarized" ? "已总结" : "原始记录"

                            LucideView(name: statusIcon, size: 10, color: statusColor)
                            Text(statusText)
                        }
                        .foregroundColor(record.aiStatus == "summarized" ? .themePurple500 : .themeGray500)
                    }
                    .font(.themeCaptionSmall.monospace())
                    .foregroundColor(.themeTextTertiary)
                }

                Spacer()

                // 操作按钮
                if isExpanded {
                    HStack(spacing: ThemeSpacing.px2.rawValue) {
                        Button(action: {
                            // 切换星标
                        }) {
                            LucideView(name: .star, size: 14, color: record.starred ? .themeYellow : .themeGray500)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            // 删除记录
                        }) {
                            LucideView(name: .trash2, size: 14, color: .themeGray500)
                        }
                        .buttonStyle(.plain)

                        LucideView(name: .chevronRight, size: 14, color: .themeGray500)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
            }
            .padding(ThemeSpacing.p3.rawValue)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    expandedId.wrappedValue = isExpanded ? nil : record.id
                }
            }

            // 展开内容
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    // 原文
                    VStack(alignment: .leading, spacing: ThemeSpacing.p2.rawValue) {
                        HStack {
                            HStack(spacing: 4) {
                                LucideView(name: .alignLeft, size: 10, color: .themeTextTertiary)
                                Text("原文内容")
                            }
                            .textCase(.uppercase)
                            Spacer()
                            Button("复制原文") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(record.content, forType: .string)
                                print("已复制原文")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.themeTextSecondary)
                            .padding(ThemeSpacing.p2.rawValue)
                            .padding(.horizontal, ThemeSpacing.px3.rawValue)
                            .background(Color.themeItem)
                            .cornerRadius(ThemeRadius.base.rawValue)
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
                    if let summary = record.summary {
                        VStack(alignment: .leading, spacing: ThemeSpacing.p2.rawValue) {
                            HStack {
                                HStack(spacing: 4) {
                                    LucideView(name: .sparkles, size: 10, color: .themePurple500)
                                    Text("AI 智能总结")
                                }
                                .textCase(.uppercase)
                                Spacer()
                                Button("复制总结") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(summary, forType: .string)
                                    print("已复制总结")
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.themePurple500)
                                .padding(ThemeSpacing.p2.rawValue)
                                .padding(.horizontal, ThemeSpacing.px3.rawValue)
                                .background(Color.themePurple500.opacity(0.1))
                                .cornerRadius(ThemeRadius.base.rawValue)
                            }

                            Text(summary)
                                .font(.themeCaption)
                                .foregroundColor(Color.themePurple500.opacity(0.8))
                                .padding(ThemeSpacing.p2.rawValue)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.themePurple500.opacity(0.1))
                                .cornerRadius(ThemeRadius.lg.rawValue)
                                .overlay(RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue).stroke(Color.themePurple500.opacity(0.2)))
                        }
                    }
                }
                .padding(ThemeSpacing.p3.rawValue)
                .padding(.top, 0)
            }
        }
        .background(isExpanded ? Color.themeHover : Color.themeItem)
        .cornerRadius(ThemeRadius.lg.rawValue)
        .overlay(RoundedRectangle(cornerRadius: ThemeRadius.lg.rawValue).stroke(isExpanded ? Color.themeBlue500.opacity(0.3) : Color.themeBorder, lineWidth: ThemeRadius.base.rawValue))
        .shadow(color: isExpanded ? Color.black.opacity(0.5) : .clear, radius: 30, x: 0, y: 8)
    }
}
```

### SettingsPanel 完整示例

```swift
struct FullSettingsPanelExample: View {
    @State private var showSettings = false
    @State private var selectedTab = "ai"

    var body: some View {
        VStack(spacing: ThemeSpacing.p6.rawValue) {
            Text("完整的 SettingsPanel 示例")
                .font(.themeH1)
                .foregroundColor(.themeTextPrimary)

            Button("打开设置面板") {
                showSettings = true
            }
            .buttonStyle(.bordered)
            .foregroundColor(.white)
            .background(Color.themeBlue500)
            .cornerRadius(ThemeRadius.lg.rawValue)
            .padding(ThemeSpacing.p2.rawValue)

            if showSettings {
                SettingsPanelView(showSettings: $showSettings, selectedTab: $selectedTab)
                    .transition(.slideRight)
                    .animation(.settingsIn, value: showSettings)
            }
        }
        .padding(ThemeSpacing.p6.rawValue)
        .background(Color.themeBackground)
    }
}

struct SettingsPanelView: View {
    @Binding var showSettings: Bool
    @Binding var selectedTab: String
    @State private var enableAI: Bool = true
    @State private var summaryTrigger: Double = 50
    @State private var titleLimit: Double = 20
    @State private var summaryLimit: Double = 100
    @State private var dedupEnabled: Bool = true
    @State private var maxRecords: Double = 100

    var body: some View {
        VStack(spacing: 0) {
            // 头部
            HStack {
                Button(action: { showSettings = false }) {
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

            // 标签栏
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ThemeSpacing.px2.rawValue) {
                    TabButton(title: "AI 提炼设置", icon: .sparkles, isSelected: selectedTab == "ai") {
                        selectedTab = "ai"
                    }

                    TabButton(title: "记录设置", icon: .database, isSelected: selectedTab == "history") {
                        selectedTab = "history"
                    }

                    TabButton(title: "蓝牙设置", icon: .bluetooth, isSelected: selectedTab == "bluetooth") {
                        selectedTab = "bluetooth"
                    }

                    TabButton(title: "悬浮窗设置", icon: .maximize2, isSelected: selectedTab == "window") {
                        selectedTab = "window"
                    }
                }
                .padding(ThemeSpacing.p3.rawValue)
            }
            .background(Color.themeGray800.opacity(0.8))
            .overlay(Rectangle().frame(height: ThemeRadius.base.rawValue).foregroundColor(Color.themeBorder), alignment: .bottom)

            // 内容
            contentView
                .padding(ThemeSpacing.p4.rawValue)

            // 底部
            HStack {
                Spacer()
                Button("保存设置") {
                    showSettings = false
                    print("设置已保存")
                }
                .buttonStyle(.bordered)
                .foregroundColor(.white)
                .background(Color.themeBlue500)
                .cornerRadius(ThemeRadius.lg.rawValue)
                .padding(ThemeSpacing.p2.rawValue)
                .padding(.horizontal, ThemeSpacing.p3.rawValue)
                .shadow(color: Color.themeBlue500.opacity(0.3), radius: 20, x: 0, y: 2)
            }
            .padding(ThemeSpacing.p3.rawValue)
            .background(Color.themeBackground.opacity(0.5))
            .overlay(Rectangle().frame(height: ThemeRadius.base.rawValue).foregroundColor(Color.themeBorder), alignment: .top)
        }
        .frame(width: 480, height: 600)
        .background(Color.themeBackground)
        .cornerRadius(ThemeRadius.`2xl`.rawValue)
        .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
    }

    private var contentView: some View {
        ScrollView {
            VStack(spacing: ThemeSpacing.p4.rawValue) {
                if selectedTab == "ai" {
                    aiSettingsView
                } else if selectedTab == "history" {
                    historySettingsView
                } else if selectedTab == "bluetooth" {
                    bluetoothSettingsView
                } else {
                    windowSettingsView
                }
            }
        }
    }

    private var aiSettingsView: some View {
        VStack(spacing: ThemeSpacing.p4.rawValue) {
            // AI 开关
            HStack {
                Text("启用 AI 自动提炼")
                    .font(.themeBody)
                    .foregroundColor(.themeTextPrimary)
                Spacer()
                Toggle("", isOn: $enableAI)
                    .toggleStyle(SwitchToggleStyle(tint: .themeBlue500))
            }

            // 总结触发阈值
            VStack(spacing: ThemeSpacing.px2.rawValue) {
                HStack {
                    Text("总结触发长度")
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                    Spacer()
                    Text("> \(Int(summaryTrigger)) 字符")
                        .font(.themeCaptionSmall.monospace())
                        .foregroundColor(.themeBlue500)
                        .background(Color.themeBlue500.opacity(0.1))
                        .padding(ThemeSpacing.p2.rawValue)
                        .cornerRadius(ThemeRadius.base.rawValue)
                }
                Slider(value: $summaryTrigger, in: 10...500, step: 10)
                    .accentColor(Color.themeBlue500)
            }

            // 标题长度限制
            VStack(spacing: ThemeSpacing.px2.rawValue) {
                HStack {
                    Text("标题长度限制")
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                    Spacer()
                    Text("\(Int(titleLimit)) 字符")
                        .font(.themeCaptionSmall.monospace())
                        .foregroundColor(.themeBlue500)
                        .background(Color.themeBlue500.opacity(0.1))
                        .padding(ThemeSpacing.p2.rawValue)
                        .cornerRadius(ThemeRadius.base.rawValue)
                }
                Slider(value: $titleLimit, in: 10...40, step: 5)
                    .accentColor(Color.themeBlue500)
            }

            // 总结长度限制
            VStack(spacing: ThemeSpacing.px2.rawValue) {
                HStack {
                    Text("总结长度限制")
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                    Spacer()
                    Text("\(Int(summaryLimit)) 字符")
                        .font(.themeCaptionSmall.monospace())
                        .foregroundColor(.themeBlue500)
                        .background(Color.themeBlue500.opacity(0.1))
                        .padding(ThemeSpacing.p2.rawValue)
                        .cornerRadius(ThemeRadius.base.rawValue)
                }
                Slider(value: $summaryLimit, in: 50...300, step: 10)
                    .accentColor(Color.themeBlue500)
            }

            // 模型配置
            VStack(spacing: ThemeSpacing.px2.rawValue) {
                Text("模型服务商与连接")
                    .font(.themeCaptionSmall.uppercase())
                    .foregroundColor(.themeTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: ThemeSpacing.px2.rawValue) {
                    ModelButton(title: "Google Gemini", isSelected: true) {
                        print("选择 Google Gemini")
                    }

                    ModelButton(title: "OpenAI GPT", isSelected: false) {
                        print("选择 OpenAI GPT")
                    }

                    ModelButton(title: "Local LLM", isSelected: false) {
                        print("选择 Local LLM")
                    }
                }
            }

            // API Key
            VStack(spacing: ThemeSpacing.px2.rawValue) {
                Text("API Key")
                    .font(.themeCaptionSmall.uppercase())
                    .foregroundColor(.themeTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField("sk-...", text: .constant(""))
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

                Text("https://generativelanguage.googleapis.com / gemini-2.5-flash-preview")
                    .font(.themeCaptionSmall.monospace())
                    .foregroundColor(.themeTextTertiary)
                    .padding(ThemeSpacing.p2.rawValue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.themeInput)
                    .cornerRadius(ThemeRadius.base.rawValue)
            }
        }
    }

    private var historySettingsView: some View {
        VStack(spacing: ThemeSpacing.p4.rawValue) {
            Text("记录管理")
                .font(.themeH2)
                .foregroundColor(.themeTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, ThemeSpacing.p2.rawValue)
                .overlay(Rectangle().frame(height: ThemeRadius.base.rawValue).foregroundColor(Color.themeBorder), alignment: .bottom)

            // 自动去重
            HStack {
                Text("自动去重（10分钟内）")
                    .font(.themeBody)
                    .foregroundColor(.themeTextPrimary)
                Spacer()
                Toggle("", isOn: $dedupEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .themeGreen500))
            }

            // 记录保留条数
            VStack(spacing: ThemeSpacing.px2.rawValue) {
                HStack {
                    Text("记录保留条数 (当前: \(Int(maxRecords)))")
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                    Spacer()
                    Text("\(Int(maxRecords)) 条")
                        .font(.themeCaptionSmall.monospace())
                        .foregroundColor(.themeBlue500)
                        .background(Color.themeBlue500.opacity(0.1))
                        .padding(ThemeSpacing.p2.rawValue)
                        .cornerRadius(ThemeRadius.base.rawValue)
                }
                Slider(value: $maxRecords, in: 50...500, step: 50)
                    .accentColor(Color.themeBlue500)
            }

            // 导出
            Button("导出所有记录 (Markdown/TXT)") {
                print("导出记录")
            }
            .buttonStyle(.bordered)
            .foregroundColor(.themeTextSecondary)
            .background(Color.themeItem)
            .cornerRadius(ThemeRadius.lg.rawValue)

            // 清空
            Button("清空历史 (需二次确认)") {
                print("清空历史")
            }
            .buttonStyle(.bordered)
            .foregroundColor(.themeRed500)
            .background(Color.themeRed500.opacity(0.1))
            .cornerRadius(ThemeRadius.lg.rawValue)
        }
    }

    private var bluetoothSettingsView: some View {
        VStack(spacing: ThemeSpacing.p4.rawValue) {
            Text("硬件与反馈")
                .font(.themeH2)
                .foregroundColor(.themeTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, ThemeSpacing.p2.rawValue)
                .overlay(Rectangle().frame(height: ThemeRadius.base.rawValue).foregroundColor(Color.themeBorder), alignment: .bottom)

            // 连接状态
            HStack {
                Text("当前状态：")
                    .font(.themeBody)
                    .foregroundColor(.themeTextPrimary)

                LucideView(name: .bluetoothConnected, size: 14, color: .themeBlue400)

                Text("已连接")
                    .font(.themeBody)
                    .foregroundColor(.themeTextPrimary)

                Spacer()

                Button("断开连接") {
                    print("断开连接")
                }
                .buttonStyle(.bordered)
                .foregroundColor(.white)
                .background(Color.themeBlue500)
                .cornerRadius(ThemeRadius.lg.rawValue)
            }

            // 防抖时长
            VStack(spacing: ThemeSpacing.px2.rawValue) {
                HStack {
                    Text("硬件按钮防抖时长")
                        .font(.themeBody)
                        .foregroundColor(.themeTextPrimary)
                    Spacer()
                    Text("1 秒")
                        .font(.themeCaptionSmall.monospace())
                        .foregroundColor(.themeBlue500)
                        .background(Color.themeBlue500.opacity(0.1))
                        .padding(ThemeSpacing.p2.rawValue)
                        .cornerRadius(ThemeRadius.base.rawValue)
                }
                Slider(value: .constant(1000), in: 500...2000, step: 250)
                    .accentColor(Color.themeBlue500)
            }
        }
    }

    private var windowSettingsView: some View {
        VStack(spacing: ThemeSpacing.p4.rawValue) {
            Text("窗口行为")
                .font(.themeH2)
                .foregroundColor(.themeTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, ThemeSpacing.p2.rawValue)
                .overlay(Rectangle().frame(height: ThemeRadius.base.rawValue).foregroundColor(Color.themeBorder), alignment: .bottom)

            // 位置锁定
            HStack {
                Text("位置锁定")
                    .font(.themeBody)
                    .foregroundColor(.themeTextPrimary)
                Spacer()
                Toggle("", isOn: .constant(false))
                    .toggleStyle(SwitchToggleStyle(tint: .gray))
            }

            Text("* 在真实 Mac 应用中，最小化和关闭操作会收缩到菜单栏或临时隐藏。")
                .font(.themeCaptionSmall)
                .foregroundColor(.themeTextTertiary)
        }
    }

    @ViewBuilder
    private func TabButton(title: String, icon: IconName, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: ThemeSpacing.px2.rawValue) {
                LucideView(name: icon, size: 12, color: .white)
                Text(title)
            }
            .font(.caption)
            .padding(ThemeSpacing.p2.rawValue)
            .padding(.horizontal, ThemeSpacing.px3.rawValue)
            .background(isSelected ? Color.themeBlue500 : Color.themeItem)
            .cornerRadius(ThemeRadius.lg.rawValue)
            .foregroundColor(isSelected ? .white : .themeTextSecondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func ModelButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.themeCaptionSmall)
                .foregroundColor(isSelected ? .white : .themeTextSecondary)
                .padding(ThemeSpacing.p2.rawValue)
                .padding(.horizontal, ThemeSpacing.px3.rawValue)
                .background(isSelected ? Color.themeBlue500 : Color.themeItem)
                .cornerRadius(ThemeRadius.lg.rawValue)
        }
        .buttonStyle(.bordered)
    }
}
```

---

## 最佳实践

### 1. 保持一致性

**✅ 推荐做法**

```swift
// 使用主题颜色
Color.themeBackground
Color.themeCard
Color.themeTextPrimary

// 使用主题间距
.padding(ThemeSpacing.p4.rawValue)
.frame(width: ThemeSpacing.w16.rawValue)

// 使用主题圆角
.cornerRadius(ThemeRadius.lg.rawValue)

// 使用主题动画
.animation(.easeOut, value: someValue)
.transition(.slideRight)
```

**❌ 避免做法**

```swift
// 硬编码颜色
Color(red: 0.07, green: 0.09, blue: 0.15)

// 魔法数字
.padding(16)
.frame(width: 64)

// 不一致的圆角
.cornerRadius(8)
.cornerRadius(12)

// 自定义动画
.animation(.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.3))
```

### 2. 性能优化

**✅ 推荐做法**

```swift
struct OptimizedView: View {
    @StateObject private var store = RecordStore.shared

    var body: some View {
        // 使用 computed 属性而不是在 body 中创建对象
        let cardBackground = Color.themeCard

        return VStack {
            // 使用 LazyVStack 优化长列表
            LazyVStack(spacing: ThemeSpacing.p4.rawValue) {
                ForEach(records) { record in
                    RecordCard(record: record)
                }
            }

            // 使用 @StateObject 管理状态
            Button("Action") {
                store.doSomething()
            }
        }
        .background(Color.themeBackground) // 在外层设置背景
    }
}
```

**❌ 避免做法**

```swift
struct UnoptimizedView: View {
    @ObservedObject var store = RecordStore() // 每次重建都会创建新实例

    var body: some View {
        // 在 body 中创建对象
        let color = Color(red: 17/255, green: 24/255, blue: 39/255)
        let spacing = CGFloat(16)

        return VStack {
            // 使用 List 可能导致性能问题
            List(records) { record in
                RecordCard(record: record)
            }

            // 使用 @ObservedObject
            Button("Action") {
                store.doSomething()
            }
        }
        .background(color) // 重复的颜色定义
    }
}
```

### 3. 可维护性

**✅ 推荐做法**

```swift
// 使用语义化命名
struct RecordCard: View { /* ... */ }
struct SettingsPanel: View { /* ... */ }
struct ToastView: View { /* ... */ }

// 添加详细的文档注释
/// Toast 提示视图
///
/// 用于显示临时消息，支持成功、错误、警告、信息四种类型
struct ToastView: View {
    let message: String
    let type: ToastType

    // ...
}

// 将复杂视图拆分为小组件
struct ComplexView: View {
    var body: some View {
        VStack {
            HeaderView()
            ContentView()
            FooterView()
        }
    }
}
```

**❌ 避免做法**

```swift
// 使用无意义的命名
struct View1: View { /* ... */ }
struct ComponentA: View { /* ... */ }

// 缺少文档注释
struct ToastView: View {
    let message: String
    let type: Int
    // ...
}

// 过于复杂的单个视图
struct ComplexView: View {
    var body: some View {
        // 500+ 行代码都在这里
        // ...
    }
}
```

### 4. 类型安全

**✅ 推荐做法**

```swift
// 使用枚举
enum ToastType {
    case success
    case error
    case warning
    case info
}

// 使用计算属性
enum ThemeSpacing: CGFloat {
    case p4 = 16
    var rawValue: CGFloat { return CGFloat(self.rawValue) }
}

// 使用泛型
struct GenericView<T: View>: View {
    let content: T
    var body: some View {
        content
    }
}
```

**❌ 避免做法**

```swift
// 使用字符串
let type = "success" // 容易拼写错误

// 使用魔法数字
.padding(16) // 为什么是 16？

// 使用 Any
let content: Any // 失去类型安全
```

### 5. 状态管理

**✅ 推荐做法**

```swift
// 使用 @StateObject 管理共享状态
@StateObject private var store = RecordStore.shared

// 使用 @Binding 传递状态
RecordCard(record: record, expandedId: $expandedId)

// 使用 @Published 触发更新
@Published var records: [Record] = []

// 合理使用 @State
@State private var isExpanded = false
```

**❌ 避免做法**

```swift
// 使用 @ObservedObject 管理需要持久化的状态
@ObservedObject var store = RecordStore() // 每次重建都会创建新实例

// 过度使用 @State
@State private var data1: String = ""
@State private var data2: String = ""
// ... 大量的 @State

// 在视图中直接修改状态
Button("Add") {
    records.append(newRecord) // 应该通过 store 来管理
}
```

### 6. 布局优化

**✅ 推荐做法**

```swift
// 使用 VStack/HStack/Spacer 进行布局
VStack {
    Header()
    Spacer()
    Content()
    Spacer()
    Footer()
}

// 使用 LazyVStack/LazyHStack 优化长列表
LazyVStack(spacing: 16) {
    ForEach(items) { item in
        ItemView(item: item)
    }
}

// 使用 frame 设置固定尺寸
.frame(width: 100, height: 100)

// 使用 padding 设置间距
.padding(.all, 16)
```

**❌ 避免做法**

```swift
// 使用 offset 进行布局
.offset(x: 100, y: 50) // 不稳定

// 使用 Spacer 过度
VStack {
    Text("Header")
    Spacer()
    Text("Content")
    Spacer()
    Text("Footer")
    Spacer() // 过多的 Spacer
}

// 使用 geometryReader 过度
GeometryReader { geometry in
    // 复杂的布局计算
}

// 使用绝对定位
.position(x: 100, y: 100) // 不响应式
```

### 7. 动画最佳实践

**✅ 推荐做法**

```swift
// 使用预定义的动画
.animation(.easeOut(duration: ThemeDuration.`300`.rawValue), value: isExpanded)

// 使用 withAnimation 包装状态变化
Button("Toggle") {
    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        isExpanded.toggle()
    }
}

// 使用 transition 实现视图过渡
.transition(.slideRight)

// 使用状态驱动动画
@State private var scale: CGFloat = 1.0

.scaleEffect(scale)
.animation(.easeInOut(duration: 0.3), value: scale)
```

**❌ 避免做法**

```swift
// 在 body 中直接修改动画
.animation(.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.3))

// 过度使用动画
.animation(.easeOut(duration: 0.3), value: value1)
.animation(.easeOut(duration: 0.3), value: value2)
.animation(.easeOut(duration: 0.3), value: value3)

// 使用过长的动画时间
.animation(.easeOut(duration: 2.0)) // 太慢

// 使用不合适的缓动函数
.animation(.linear(duration: 0.3)) // 缺少自然感
```

---

## 常见问题

### Q1: 如何自定义主题颜色？

**A:** 可以在 `Color+Theme.swift` 中添加自定义颜色：

```swift
extension Color {
    static let themeCustom = Color(red: 0.5, green: 0.5, blue: 0.5)
}
```

### Q2: 如何修改字体大小？

**A:** 可以在 `Font+Theme.swift` 中调整字体大小：

```swift
extension Font {
    static let themeBody = Font.system(size: 16) // 修改为 16px
}
```

### Q3: 如何添加新的间距值？

**A:** 可以在 `Spacing+Theme.swift` 中添加：

```swift
enum ThemeSpacing: CGFloat {
    case px12 = 48 // 新的间距值
}
```

### Q4: 如何自定义动画时长？

**A:** 可以在 `Animation+Theme.swift` 中添加：

```swift
enum ThemeDuration: Double {
    case `150` = 0.15 // 新的时长
}
```

### Q5: 如何在不同组件间共享状态？

**A:** 使用 `@StateObject` 和 `@ObservedObject`：

```swift
// 共享状态
@StateObject private var store = RecordStore.shared

// 子组件使用
@ObservedObject var store: RecordStore
```

### Q6: 如何优化长列表性能？

**A:** 使用 `LazyVStack` 和 `@StateObject`：

```swift
LazyVStack(spacing: 16) {
    ForEach(records) { record in
        RecordCard(record: record)
    }
}
```

### Q7: 如何处理深色/浅色模式？

**A:** 使用系统颜色或动态颜色：

```swift
Color.primary // 自动适应模式
Color.secondary // 自动适应模式
```

### Q8: 如何添加新的图标？

**A:** 确保 Lucide 图标包已添加，并使用正确的图标名称：

```swift
LucideView(name: .newIconName, size: 16, color: .themeTextPrimary)
```

### Q9: 如何调试布局问题？

**A:** 可以临时添加边框和背景色：

```swift
.frame(width: 100, height: 100)
.background(Color.red.opacity(0.3)) // 临时调试
.border(Color.blue, width: 1) // 临时调试
```

### Q10: 如何处理响应式布局？

**A:** 使用 `GeometryReader` 和条件布局：

```swift
GeometryReader { geometry in
    if geometry.size.width > 800 {
        // 大屏幕布局
    } else {
        // 小屏幕布局
    }
}
```

---

**文档版本**: v1.0

**最后更新**: 2024-12-05

**维护者**: Claude AI
