# ScreenshotV2 技术文档索引

> **最后更新**: 2026-01-02

## 核心文档

### 1. [长截图功能架构文档](./LONG_SCREENSHOT_ARCHITECTURE.md) ⭐ 最新
- 功能概述和核心特性
- 完整的架构设计图
- 组件结构和职责划分
- 状态管理和交互流程
- 关键技术实现（事件穿透、滚动监听、窗口定位）
- 技术决策记录
- 代码位置索引
- 常见问题排查
- 未来扩展指南

### 2. [长截图事件穿透与定位逻辑](../../../../../../../../tmp/LONGSSHOT_EVENT_PENETRATION_LOGIC.md)
- 事件穿透机制详解
- 窗口级别切换逻辑
- 滚动检测服务实现
- 状态切换流程图
- 关键代码片段

## 开发指南

### 快速开始

1. **添加新的长截图功能** → 参考 `LONG_SCREENSHOT_ARCHITECTURE.md` 的"未来扩展"章节
2. **排查滚动监听问题** → 参考 `LONG_SCREENSHOT_ARCHITECTURE.md` 的"常见问题排查"章节
3. **理解事件穿透机制** → 参考 `LONG_SCREENSHOT_EVENT_PENETRATION_LOGIC.md` 的"事件穿透机制"章节

### 代码位置速查

| 功能 | 文件路径 |
|------|---------|
| 滚动检测 | `LongScreenshot/Services/ScrollDetectionService.swift` |
| 图片拼接 | `LongScreenshot/Services/ImageStitchingService.swift` |
| 流程控制 | `LongScreenshot/Controllers/LongScreenshotFlowController.swift` |
| 长图工具栏 | `Views/Toolbar/V2LongScreenshotToolbar.swift` |
| 预览面板 | `LongScreenshot/Views/LongScreenshotPreviewPanel.swift` |
| 事件穿透 | `Views/Panels/V2ScreenshotHostingView.swift` |

## 维护日志

| 日期 | 版本 | 更新内容 |
|------|------|---------|
| 2026-01-02 | 1.0 | 创建架构文档，记录完整的长截图功能设计 |
| 2026-01-01 | - | 创建事件穿透与定位逻辑文档 |

---

**维护者**: Claude Code
**项目**: Quite Note - macOS 截图应用
