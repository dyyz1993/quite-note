# Quite Note UI 自动化知识库

这份文档是 Quite Note UI 回归和 Computer Use 操作的总入口。执行任何 UI 自动化前，先读本文，再查 [错题本](ui-test-error-notebook.md)。

> 仓库本地的 `AGENTS.md` 包含开发者账号、签名与发布信息，已被 `.gitignore` 忽略，不得提交。
> 如果 Agent 需要入口规则，以本文档为准；本地可继续在 `AGENTS.md` 顶部引用本文档。

## 快速命令

```bash
# 解析版本、选择套件、生成报告骨架，不启动应用
./tools/ui-smoke/run_ui_smoke.sh --dry-run

# 发布/Tag 全量回归（默认基线 v1.3.0）
./tools/ui-smoke/run_ui_smoke.sh --mode release --baseline v1.3.0

# 当前 WIP 显式纳入测试
./tools/ui-smoke/run_ui_smoke.sh --allow-dirty --mode full

# 按变更增量回归
./tools/ui-smoke/run_ui_smoke.sh --mode incremental --incremental-since v1.3.0

# CI 产物 + xyz-mac 专用测试机（本机不启动 UI）
./tools/ui-smoke/run_ui_smoke.sh --remote xyz-mac --artifact-url <CI_BUILD_URL> --mode full

# GitLab Dev 产物作业：dev-ui-artifact
# 产物：QuiteNoteDev-<shortsha>.zip 和 .sha256

# 首次授权时打开 xyz-mac 的系统设置页
source tools/ui-smoke/run_ui_smoke.sh >/dev/null 2>&1 || true
authorize_remote_ui xyz-mac
```

报告位于 `tools/ui-smoke/runs/<run-id>/`。核心文件：

- `manifest.json`：版本、Tag、Commit、diff SHA、App 版本、系统与显示器绑定。
- `report.md` / `report.json`：人读和机器读结果。
- `timeline.jsonl`：套件执行时间线。
- `screenshots/`：关键证据和失败现场。
- `knowledge-candidate.md`：非 PASS 时自动生成的错题本候选。

目录 `tools/ui-smoke/runs/` 和 `.ui-smoke-worktrees/` 已忽略 Git；不要把运行证据提交进仓库。

## 回归策略

- 新 Tag、发布候选、`--mode release`：全量回归。
- 普通 Commit：按 `git diff --name-only` 选择增量套件。
- 无法映射的路径、构建配置变化或无最近绿色 run：自动升级全量。
- 当前工作区默认拒绝执行；只有显式 `--allow-dirty` 才测试 WIP，并把 diff 哈希写入 manifest。

路径映射：

| 变更路径 | 套件 |
|---|---|
| `Sources/QuiteNote/Clipboard/`、SharedStorage、CoreService | clipboard、devcore、launch |
| RecordStore、Search、FloatingPanel | flash-notes |
| AppLauncher | launcher |
| SettingsTabs、Preferences | settings |
| `Package.swift`、`build-app.sh` | 全量 |

## Computer Use 最短路径

固化操作序列在 `tools/ui-smoke/operations.json`，选择器在 `tools/ui-smoke/selectors.json`。命中后不要重新探索 UI。

当前脚本的确定性验收层已经可用：

- 检查 Accessibility 权限。
- 按 bundle id 找到 Dev 进程。
- 检查隔离存储目录。
- 检查可见窗口。
- 收尾检查生产版进程未被脚本管理。

场景内输入、搜索和键盘断言按 `operations.json` 继续增强。每次增强必须先接入 `selectors.json` 的稳定标识，再把实际可复用的 AX 查询回写 `operations.json`；不要在报告里散落一次性坐标。

优先级固定为：

1. `accessibilityIdentifier`
2. AX role + 稳定 label
3. 新获取窗口 frame 后的窗口相对坐标
4. 截图/模型复核，仅用于失败诊断

关键快捷键：

- 主闪记显示/隐藏：`⌥⌘R`
- 主闪记强制居中：`⌥⌘⇧R`
- 采集剪贴板：`⌥⌘C`
- 剪贴板历史：`⇧⌘V`
- 应用启动器：`⌥Space`

主流程：

1. 用 `open -n` 启动 worktree 内的 `Quite Note Dev.app`。
2. 通过 bundle id 找进程，不要按窗口标题猜。
3. 面板唤起后先等 AX 稳定，再操作输入框。
4. 剪贴板搜索有 200ms debounce，等待条件用 `search_idle`，不要固定 sleep。
5. `Esc` 语义：启动器/剪贴板先清搜索，再按一次才关闭。
6. 结束只退出 Dev 进程，绝不杀正式版 `com.quitenote.app`。

## xyz-mac 远程执行模式

- 本机只做控制、下载 CI 产物和收集报告，绝不启动测试 App、不执行键盘/鼠标交互。
- CI 构建产物必须是 `.zip`（内含一个 `.app`）或 `.dmg`（内含一个 `.app`）。
- GitLab `dev-ui-artifact` 作业产出根层为 `Quite Note Dev.app` 的 ZIP，并附带 SHA-256。
- 远端目录固定在 `~/QuitenoteUITest/`。
- 远端使用一次性 `QN_TEST_STORAGE_ROOT`，测试后报告 rsync 回本机 run 目录。
- 远端 Python 依赖为 PyObjC 10.3.2。
- 若远端报告 `BLOCKED`，优先检查辅助功能、屏幕录制、CI 产物签名/架构。
- 目前 `xyz-mac` 是 Intel Mac；CI 产物必须包含 x86_64 或 universal binary。

## 安全与权限红线

- 只使用 `com.quitenote.app.dev`。
- 必须设置一次性 `QN_TEST_STORAGE_ROOT`。
- 测试数据统一以 `QNUI_SMOKE_` 开头。
- 不修改生产配置，不读写生产剪贴板/闪记数据库。
- 不提交真实 AI 请求、蓝牙硬件、外发反馈、真实录屏保存等有副作用场景。
- Accessibility 和屏幕录制权限缺失时输出 `BLOCKED`，不要尝试绕过系统设置。

## 多屏与焦点注意点

- 面板可能出现在鼠标所在屏幕，不能假设主屏。
- 坐标操作前重新读取窗口 frame，并转换为该窗口局部坐标。
- 剪贴板面板和启动器互斥，测试前先关闭另一个。
- macOS accessory app 激活可能异步失败，等待 key window/AX 状态，不盲目重试。

## 错题本维护

非 PASS run 会生成 `knowledge-candidate.md`。人工或 Agent 确认后，把有效条目整理进 [错题本](ui-test-error-notebook.md)。

每条必须包含：

- 日期、版本/Commit、run id
- 症状
- 根因
- 修复方式
- 防复发规则
- 关联证据路径

重复问题更新原条目，不新建重复记录；已修复条目保留，用于防回归。
