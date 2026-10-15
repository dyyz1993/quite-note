# Quite Note UI 自动化错题本

用于长期沉淀 UI 回归、Computer Use 操作和 macOS 权限相关的踩坑。新增条目前先搜索是否已有同类问题。

## 模板

```markdown
## YYYY-MM-DD · 简短问题名

- Version / Commit / Run:
- Symptom:
- Root cause:
- Fix:
- Prevention:
- Evidence:
- Status: fixed / open / obsolete
```

## 已知问题

### 2026-10-15 · 菜单栏应用没有常规窗口

- Version / Commit / Run: Quite Note Dev
- Symptom: Computer Use 初次连接时看不到主窗口，误以为应用未启动。
- Root cause: App 是 `LSUIElement` 菜单栏应用，默认常驻浮球，未展开时不一定暴露可操作主窗口。
- Fix: 先通过 bundle id/进程确认运行，再用 `⌥⌘⇧R` 强制显示并居中；必要时双击浮球展开。
- Prevention: 不要用“必须有常规窗口”判断启动成功；先检查进程，再检查 AX/CGWindow。
- Evidence: 本地 Computer Use 实测。
- Status: fixed

### 2026-10-15 · 多屏截图坐标容易错位

- Version / Commit / Run: Quite Note Dev
- Symptom: 截图区域和实际面板内容不一致，容易误判 UI 缺失。
- Root cause: CGWindow 返回逻辑坐标，`screencapture` 输出物理像素，且主屏和副屏 origin 不同。
- Fix: 每次操作前重新读取窗口 frame；截图换算为物理坐标；失败时保存全屏截图再裁剪。
- Prevention: 禁止把上一次窗口坐标当作稳定选择器。
- Evidence: 本地 Computer Use 实测。
- Status: fixed

### 2026-10-15 · 本机 UI 自动化抢焦点影响日常使用

- Version / Commit / Run: efd41dc / 697c350
- Symptom: 在用户日常使用的 Mac 上执行 UI 用例会弹面板、抢占键盘焦点和剪贴板，干扰正常工作。
- Root cause: UI 自动化与用户交互共享同一 GUI 会话；macOS Accessibility/AppleScript 无法完全避免焦点影响。
- Fix: 迁移到 `xyz-mac` 专用测试机；本机只构建/下载 CI 产物并控制 SSH，不启动 App UI。
- Prevention: 交互式 UI 用例必须通过 `--remote xyz-mac` 执行；本机只允许 dry-run、静态检查和单元测试。
- Evidence: `docs/ui-test-knowledge.md` 远程执行模式。
- Status: fixed
