# Quite Note

[![CI](https://github.com/dyyz1993/quite-note/actions/workflows/test.yml/badge.svg)](https://github.com/dyyz1993/quite-note/actions/workflows/test.yml)
[![Release](https://img.shields.io/github/v/release/dyyz1993/quite-note)](https://github.com/dyyz1993/quite-note/releases)
![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange)
[![License](https://img.shields.io/badge/license-MIT-green)](#-许可证)

> macOS 原生剪切板管理器：历史记录 · AI 内容提炼 · 专业截图 · 长图拼接 —— **记录本地保存，AI 服务按需启用**

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

- 剪贴板历史、闪记和附件默认保存在你的 Mac，截图 OCR 使用 macOS Vision 在本机处理。
- AI 是可选功能。启用并使用后，相关文本或图片会发送到你配置的连接及所选模型；是否在本地处理取决于该服务和模型，不能仅凭本机接口地址判断。API 密钥保存在 macOS 钥匙串中。
- 主动提交用户反馈时，会上传你提交的反馈及所选附件；链接图标可能向对应网站请求 favicon。请根据需要选择这些功能。

详细数据处理说明见[隐私政策](privacy-site/index.html)。

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
./build-app.sh --dev --no-launch   # 构建隔离的开发版应用包，不启动应用
swift test                       # 在具备相应 macOS SDK 的 Xcode 环境运行测试
```

单元测试 CI 使用 macOS 15 / Xcode 16.4，并通过 `LEGACY_CI_SDK` 编译兼容路径；这条测试不覆盖需要 macOS 26 SDK 的语音转录实现。交互式 UI 验证使用专用测试 Mac 和隔离数据目录，参见 [UI 测试说明](docs/ui-test-knowledge.md)。

工作流覆盖：测试 → macOS 打包 → DMG 生成 → Release 发布。

## 📄 许可证

MIT License
