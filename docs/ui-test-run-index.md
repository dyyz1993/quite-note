# Quite Note UI 回归复查入口

本文件是 UI 回归证据的长期索引。每个 Tag / 发布候选必须有一行绿色记录；普通 Commit 按增量策略记录最近绿色 run。不要把报告本体提交进仓库。

## 查看入口

1. 打开本文件，按 Tag / Commit 找到对应 GitHub Run。
2. 进入 Run URL 的 Artifacts 区域。
3. 下载 `QuiteNoteUI-<full-commit>`。
4. 先看 `report.md` 结论，再看 `manifest.json` 绑定信息。
5. `evidence=full` 时逐步查看 `screenshots/`，并用 `recordings/ui-recording.mov` 复查焦点与瞬时交互；录屏不可用但 `recordings/frames.json` 与整屏帧完整时，明确标记为“时间线截图证据”，不得写成录屏证据。

本地快速下载：

```bash
gh run download <run-id> \
  --repo dyyz1993/quite-note \
  --name QuiteNoteUI-<full-commit> \
  --dir /tmp/quitenote-ui-<short-commit>
```

## 必须归档的字段

- Tag：精确 Tag；未打 Tag 时填 `-`。
- Commit / describe：完整 Commit 与 `git describe --tags --always`。
- Run / Report：GitHub Run ID 与 `run_id`。
- Evidence：`full` 或 `fast`。
- Result：仅记录 `PASS`；失败 run 不作为版本归档入口。

## 绿色归档

| Date | Tag | Commit | Describe | Run | Report | Evidence | Result | Notes |
|---|---|---|---|---|---|---|---|---|
| 2026-10-16 | - | [a85901558b120dd026c9117d716903da61fe1089](https://github.com/dyyz1993/quite-note/actions/runs/38840392166) | `v1.3.0-53-ga859015` | 38840392166 | `ui-20261016-023329-a8590155` | fast | PASS | 首个真实菜单栏 AX 点击全绿；Clipboard/Launcher 面板断言通过 |
| 2026-10-16 | - | [557f9f62067213cb2ca5ced9fe7e6be5563675db](https://github.com/dyyz1993/quite-note/actions/runs/38841532953) | `v1.3.0-54-g557f9f6` | 38841532953 | `ui-20261016-025233-557f9f62` | fast | PASS | AX 操作流程与选择器沉淀后复测全绿 |
| 2026-10-16 | - | [6a0a66c6119b8703480613882db86b20b3c3f3f2](https://github.com/dyyz1993/quite-note/actions/runs/38843129826) | `v1.3.0-55-g6a0a66c` | 38843129826 | `ui-20261016-030856-6a0a66c6` | full | PASS | 首个逐步截图归档 run：8 个场景截图 + report/timeline/manifest |
| 2026-10-18 | - | [07a3755a0eaa060353a93e35638e9d23641c3d45](https://github.com/dyyz1993/quite-note/actions/runs/39128454712) | `v1.3.0-67-g07a3755` | 39128454712 | `ui-20261018-132725-07a3755a` | full | PASS | macOS 15 SDK CI 兼容修复后全量 Tests 绿；Dev 1.0.0 @ `com.quitenote.app.dev`，macOS 13.7.8，7 场景 + cleanup 全绿，生产进程无残留 |

## 当前验收范围

- permissions / launch / flash-notes / clipboard / launcher / settings / devcore / cleanup。
- Clipboard 和 Launcher 走真实用户路径：AX 点击菜单栏状态菜单，再点击 `剪贴板历史` / `应用启动器`。
- `flash-notes`、`settings` 当前仍是确定性面板存在性 / AX flow 可用性检查；搜索、输入和逐页设置巡检继续按 `operations.json` 增强。

## 维护规则

- 新 Tag：必须执行 `--mode release --evidence full`，全绿后新增一行。
- 发布候选：同 Tag 规则，并在 Notes 标明 RC。
- 普通 Commit：增量回归全绿后可更新该分支最新绿色入口；不要求每个 Commit 建行。
- 现有 `evidence=fast` 的历史绿色 run 保留为基线证据；从下一次 run 起使用 `evidence=full`，每步截图保留在 GitHub Artifact。
- 若 GitHub Artifact 超过 30 天，需要把关键 `manifest/report/timeline/screenshots` 另存到长期发布包或对象存储，再更新本索引的存储位置。
