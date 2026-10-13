# Quite Note

[![CI](https://github.com/dyyz1993/quite-note/actions/workflows/test.yml/badge.svg)](https://github.com/dyyz1993/quite-note/actions/workflows/test.yml)
[![Release](https://img.shields.io/github/v/release/dyyz1993/quite-note)](https://github.com/dyyz1993/quite-note/releases)
![Platform](https://img.shields.io/badge/platform-macOS%2012%2B-black)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange)
[![License](https://img.shields.io/badge/license-MIT-green)](#-许可证)

> macOS 原生剪切板管理器：历史记录 · AI 内容提炼 · 专业截图 · 长图拼接 —— **100% 本地运行，数据不出你的电脑**

基于 **SwiftUI** 构建，常驻状态栏，极致精简。

---

## ✨ 功能特性

### 📋 剪切板管理
- 完整的历史记录追踪，状态栏图标一键唤起
- 悬浮记录本：常驻桌面速查，支持蓝牙按钮触发

### 🤖 AI 内容提炼
- 智能分析剪切板内容，一键生成**摘要 / 关键词 / 多语言翻译**

### 📸 截图能力
- **专业截图 V2**：静态全屏采集，多屏幕支持，吸附窗口智能识别
- **长图截取**：实时滚动拼接 + 实时预览，侧边智能控制面板

### 🎨 体验细节
- 自定义主题图标（剪切板 + AI 闪光设计）
- LucideIcons 统一图标渲染与加载机制
- 极简状态栏显示逻辑

## 🔒 隐私

所有剪切板数据 **100% 本地存储与处理**，无任何上传、无任何追踪。

## 📥 安装

**方式一：DMG 安装包**（推荐）
1. 从 [Releases](https://github.com/dyyz1993/quite-note/releases) 下载 `QuiteNote-x.x.x.dmg`
2. 挂载并将应用拖入 Applications
3. 首次运行如遇 Gatekeeper 提示，在「系统设置 > 隐私与安全性」中允许

**方式二：直接使用 .app 包**
下载 `Quite Note.app` 移入 Applications 双击运行。

也可访问官网：**https://note.dyyz1993.com**

## 🛠 构建

项目使用 **Swift Package Manager** 管理，CI 全流程由 GitHub Actions 驱动：

```bash
swift build        # 构建
swift test         # 运行测试
```

工作流覆盖：测试 → macOS 打包 → DMG 生成 → Release 发布。

## 📄 许可证

MIT License
