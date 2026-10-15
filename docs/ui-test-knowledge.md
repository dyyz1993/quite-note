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

# CI 产物 + 专用测试机（本机不启动 UI）
./tools/ui-smoke/run_ui_smoke.sh --local-artifact <CI_BUILD.zip> --mode full

# CI Dev 产物：GitHub Actions artifact（或等价 CI 产物）
# 产物：QuiteNoteDev-<shortsha>.zip 和 .sha256

# 首次授权：在专用测试机上登录用户，打开「系统设置 → 隐私与安全性」，
# 为 runner shell / 终端授予辅助功能和屏幕录制权限后重启 runner。
```

报告位于 `tools/ui-smoke/runs/<run-id>/`。核心文件：

- `manifest.json`：版本、Tag、Commit、diff SHA、App 版本、系统与显示器绑定。
- `report.md` / `report.json`：人读和机器读结果。
- `timeline.jsonl`：套件执行时间线。
- `screenshots/`：关键证据和失败现场。
- `knowledge-candidate.md`：非 PASS 时自动生成的错题本候选。

目录 `tools/ui-smoke/runs/` 和 `.ui-smoke-worktrees/` 已忽略 Git；不要把运行证据提交进仓库。

## 标准工作流

1. **触发**
   - push / PR：GitHub Actions 自动在云端构建 Dev ZIP，再调度到专用测试机执行 UI。
   - 打 `v*.*.*` Tag：自动执行发布构建；发布前手动或后续 CI 触发 `--mode release` 全量回归。
2. **构建**
   - GitHub 云端 `Build Dev UI Artifact` 产出签名 universal `QuiteNoteDev-<sha>.zip` 与 SHA-256。
   - 用户日常 Mac 与专用测试机都不承担构建，不污染任何本机 WIP。
3. **执行**
   - `Local UI Smoke on Dedicated Mac` 运行在 `xyz-mac` self-hosted runner。
   - runner 从 GitHub artifact 下载当前 Commit 的 Dev ZIP，校验 SHA-256。
   - runner 用 `--local-artifact` 解包安装到自己的隔离测试目录，使用一次性 `QN_TEST_STORAGE_ROOT` 启动 Dev App。
4. **归档**
   - 专用测试机生成 `report.json / report.md / timeline.jsonl / screenshots/`。
   - GitHub 把这些文件作为当前 Commit 的 artifact 保留 30 天。
5. **复查**
   - 先看 `report.md` 的 PASS/FAIL/BLOCKED。
   - 有问题时按 `manifest.json` 锁定版本，再看 `report.json` 的失败 reason 与 `screenshots/` 证据。
   - 非 PASS 的 `knowledge-candidate.md` 需要整理进错题本。

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

## 专用测试机执行模式

- 用户日常 Mac 不参与 UI 工作流；专用测试机只执行测试，不承担构建。
- CI 产物必须是根层为 `Quite Note Dev.app` 的 ZIP，并附带 SHA-256。
- GitHub Actions workflow 为 `.github/workflows/ui-smoke.yml`：云端构建 universal Dev ZIP，`quitenote-ui` self-hosted runner 执行本地 UI，并上传报告/截图 artifact 保留 30 天。
- GitHub 和 runner 都是主动连接 GitHub；仓库不含、也不需要公开任何局域网地址或 SSH 反向入口。
- 专用测试机使用一次性 `QN_TEST_STORAGE_ROOT`，只退出 `com.quitenote.app.dev`。
- 专用测试机 Python 依赖为 PyObjC 10.3.2，无需 Xcode。
- 若专用测试机报告 `BLOCKED`，优先检查辅助功能、屏幕录制、CI 产物签名/架构。
- 当前专用测试机是 Intel Mac；CI 产物必须包含 x86_64 或 universal binary。

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
