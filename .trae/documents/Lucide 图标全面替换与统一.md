## 目标
- 将 note.jsx 引用的所有 Lucide 图标在 macOS 项目中一一对应替换，实现跨端图标统一。
- 统一图标渲染入口，保障大小、颜色、对齐、命名一致，便于维护与扩展。

## 图标清单与映射
- Bluetooth → bluetooth
- BluetoothConnected → bluetooth-connected
- BluetoothOff → bluetooth-off
- Copy → copy
- ChevronRight → chevron-right
- Clipboard → clipboard
- Activity → activity
- X → x
- Cpu → cpu
- Settings → settings
- ArrowLeft → arrow-left
- Sparkles → sparkles
- Bot → bot
- Check → check
- Save → save
- Rss → rss
- Trash2 → trash-2
- Star → star
- Search → search
- Maximize2 → maximize-2
- Minimize2 → minimize-2
- Database → database
- Link → link
- Zap → zap
- Clock → clock
- AppWindowMac（用于“悬浮窗设置”）→ app-window-mac

## 技术方案
1) 扩展图标封装
- 扩展 `Sources/QuiteNote/UI/Icon.swift`：
  - 新增上述全部 `IconName` 枚举项。
  - `LucideView(name:size:color)` 作为唯一渲染入口；若 Lucide 不可用则回退 SF Symbols。
  - 新增 `LucideLabel(icon:text:size:color)`（图标+文字组合）用于列表/标签场景。

2) 替换目标文件与位置
- `UI/FloatingPanelController.swift`
  - Header：齿轮 `settings`、搜索放大镜 `search`、蓝牙三态（已用 LucideConnected/Off/默认）。
  - 列表卡片：状态图标（sparkles/bolt/x/bot/clock）、右侧操作区（star/trash/chevron-right）、复制按钮（copy）。
- `UI/HeatmapView.swift`
  - 左栏标题图标改为 `activity`，保持浅白加柔光。
- `UI/SettingsOverlayView.swift`
  - Tab 导航：`sparkles`、`database`（替代 server.rack）、`bluetooth`、`app-window-mac`（替代 macwindow）。
  - 文本标签内的前置小图标统一改用 `LucideLabel`（如「模型服务商与连接」→ `link`）。
  - Header 右侧蓝牙状态：统一为 Lucide（点击跳转蓝牙页）。
- `UI/ToastView.swift`
  - 成功/错误/警告/信息的图标替换为 `check`/`x`/`zap`/`clipboard` 并保留现有配色。

3) 统一尺寸与造型
- 尺寸：顶部/标签 12px，列表/操作 14px，搜索与状态 16px。
- 颜色：与 note.jsx 一致（blue-400 / yellow-400 / gray-500 等），使用已定义 Theme 色。
- 渲染：Lucide 以 template 模式渲染，保持填充/描边一致；必要时通过 `.renderingMode(.template)`。

4) 交互与可用性
- 点击蓝牙图标跳转到蓝牙设置页签（已实现，保持）。
- 所有按钮的 overlay/分隔线保持 `.allowsHitTesting(false)`，避免遮挡点击。

5) 验证与用例
- 构建：`swift build` 成功。
- UI 验证：
  - 蓝牙三态切换，图标随状态变化。
  - 列表状态与操作区图标统一为 Lucide，交互正常。
  - 设置页 Tab 图标与标签图标全部为 Lucide，点击有效。
  - Toast 提示出现 Lucide 图标，位置与颜色正确。

6) 交付
- 更新上述文件并提交代码，提供图标映射清单与后续补充指南（若新增图标，只需在 `Icon.swift` 中追加枚举与回退映射）。
