# Quite Note v1.0.0 发布说明

## 🎉 首次发布

基于SwiftUI的macOS剪切板历史记录和AI提炼工具

## ✨ 新功能

- 🎨 **自定义主题图标** - 剪切板+AI闪光设计
- 🔧 **改进的图标加载** - 优化的LucideIcons加载机制  
- 📱 **状态栏优化** - 改进的状态栏图标显示
- 📋 **剪切板历史** - 完整的剪切板记录管理
- 🤖 **AI提炼** - 智能内容提炼功能

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