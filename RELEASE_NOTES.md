# Quite Note v1.0.0 发布说明

## 🎉 首次发布

基于SwiftUI的macOS剪切板历史记录和AI提炼工具

## ✨ 新功能

- 📸 **专业截图 V2** - 采用全新的静态全屏采集架构，支持多显示器、智能窗口吸附、像素级取色与放大镜。
- 📜 **滚动长图** - 业界领先的长图截取方案，支持实时拼接预览、侧边悬浮控制台，支持网页与文档的无限滚动采集。
- 🎨 **自定义主题图标** - 全新设计的剪切板与 AI 闪光图标，与 macOS 系统风格完美融合。
- 🤖 **AI 提炼** - 智能内容分析与提炼，一键处理剪切板信息。
- 📋 **剪切板历史** - 增强的记录管理，支持快速搜索与预览。
- 📱 **状态栏优化** - 重新设计的状态栏图标，支持 Retina 高清显示与动态偏移优化。

## 📥 下载方式

### 方式一：GitHub Actions Artifacts（推荐）
1. 访问 [Actions页面](https://github.com/dyyz1993/quite-note/actions)
2. 点击最新的构建任务
3. 在 "Artifacts" 部分下载 `QuiteNote-macOS-{构建编号}`
4. 解压后获得：
   - `Quite Note.app` - 完整应用包
   - `QuiteNote-1.0.0.dmg` - DMG安装包

### 方式二：本地构建
```bash
git clone https://github.com/dyyz1993/quite-note.git
cd quite-note
./build-app.sh
./create-dmg.sh
```

## 📋 安装说明

### DMG安装（推荐用户）
1. 下载 `QuiteNote-1.0.0.dmg`
2. 双击挂载DMG文件
3. 拖拽应用到Applications文件夹
4. 首次运行需要在"系统偏好设置 > 安全性与隐私"中允许运行

### 应用包安装（推荐开发者）
1. 下载 `Quite Note.app`
2. 移动到Applications文件夹
3. 双击运行

## 🔧 系统要求

- macOS 12.0 或更高版本
- 支持Intel和Apple Silicon

## 🚀 使用说明

1. 应用启动后会出现在菜单栏状态栏
2. 点击状态栏图标查看剪切板历史
3. 使用AI功能提炼剪切板内容
4. 支持快捷键操作

## 🐛 已知问题

- 部分LucideIcons可能显示为系统默认图标
- 首次运行可能需要手动授权

## 🔮 后续计划

- [ ] 修复LucideIcons显示问题
- [ ] 添加更多AI提炼选项
- [ ] 支持快捷键自定义
- [ ] 添加数据同步功能

---

**构建时间**: 2025-12-17  
**构建版本**: v1.0.0  
**提交哈希**: a6450d1