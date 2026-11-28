# Quite Note UI 回归复查入口

本文件是 UI 回归证据的长期索引。每个 Tag / 发布候选必须有一行绿色记录；普通 Commit 按增量策略记录最近绿色 run。不要把报告本体提交进仓库。

## 查看入口

1. 打开本文件，按 Tag / Commit 找到对应 GitHub Run。
2. 进入 Run URL 的 Artifacts 区域。
3. 下载 `QuiteNoteUI-<full-commit>`。
4. 先看 `report.md` 结论，再看 `manifest.json` 绑定信息。
5. `evidence=full` 时先看 `recordings/ui-timeline.webp` 动态截图汇总，再按 `recordings/frames.json` 查看原始窗口 PNG 与 `screenshots/`；动态 WebP 不是连续录屏，也不能证明截图间的瞬时交互。若存在 `recordings/ui-recording.mov`，可另用它复查连续过程。

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
| 2026-10-19 | - | [47a2765cafe14ff104a7f5c0b8edbdc8a0640bba](https://github.com/dyyz1993/quite-note/actions/runs/39245202816) | `47a2765` | 39245202816 | `ui-20261019-114303-47a2765c` | full | PASS | Dev 1.0.0、套件 1.2.0、macOS 13.7.8；8/8 PASS，16 张非空时间线窗口 PNG。GitHub Artifact 已下载复验，目检剪贴板 760×520 与启动器 640×496 面板；连续录屏仍不可用。Tests run [39245203791](https://github.com/dyyz1993/quite-note/actions/runs/39245203791) 绿色 |
| 2026-10-19 | - | [2451d26e2f430c2e52738b613fd9503c1b394059](https://github.com/dyyz1993/quite-note/actions/runs/39262438516) | `2451d26` | 39262438516 (attempt 2) | `ui-20261019-143453-2451d26e` | full | PASS | Dev 1.0.0、套件 1.2.0、macOS 13.7.8；8/8 PASS，16 张原始窗口 PNG + 16 帧 `recordings/ui-timeline.webp`（174,954 B）。Artifact 已下载，逐帧解码复验并目检剪贴板/启动器面板；动图为截图合成，非连续录屏。首次下载副本 SHA-256 不符，重跑后校验通过；Tests run [39262439757](https://github.com/dyyz1993/quite-note/actions/runs/39262439757) 绿色 |
| 2026-10-20 | - | [d06557907356e9c63042eb178bb9877afc5646db](https://github.com/dyyz1993/quite-note/actions/runs/39315217013) | `d065579` | 39315217013 | `ui-20261019-200317-d0655790` | full | PASS | 首个带隔离剪贴板夹具的绿色 UI run：Dev 1.0.0、macOS 13.7.8；8/8 PASS。注入 4 条 `QNUI_SMOKE_CLIP` 记录，搜索 `QNUI_SMOKE_CLIP` 后过滤为 3 条且右侧详情可见；16 帧截图 + 动态 WebP 门禁通过。Tests run [39315218216](https://github.com/dyyz1993/quite-note/actions/runs/39315218216) 绿色。Actions Annotations 有历史 `ScrollSnap` gitlink 无 `.gitmodules` 错误，checkout 自动重建后所有步骤成功；该非阻塞问题另行跟踪，不构成本次 UI 验收失败 |
| 2026-11-25 | v1.7.0 | [abb691bfb5ec48af79fc44c0f0a96c7f3588e286](https://github.com/dyyz1993/quite-note/actions/runs/45609218896) | `v1.7.0-8-gabb691b` | 45609218896 | `ui-20261125-102241-c0d36494` | full | PASS | 9/9 用例全过（含 screenshot-toolbar；修复链见错题本 2026-11-25 CI 修复链条目）；基线已归档 gh-pages ui-baseline/abb691bf |
| 2026-11-27 | - | [4c4ddcd99ceb8a2f1dad7a0d3c43bd068fa4aa76](https://github.com/dyyz1993/quite-note/actions/runs/45861506702) | `v1.7.0-38-g4c4ddcd` | 45861506702 | `ui-20261126-171018-4c4ddcd9` | full | PASS | 9/9 用例全过；PR #7（22 个提交：删约 6,000 行不可达代码 + 翻页 / 启动器 key 梯子 / 写库失败提示 / 导出读整库等修复）合并后的首轮。report.md 与截图取自测试机 runner 工作目录（GitHub 证据包在本机下载断流），逐张与基线 `ui-baseline/1.2.0-1b95ec15` 同一用例比对，构图一致。基线快照步骤在本行写入时仍在进行（测试机到 GitHub 约 35KB/s），是否归档以 `ui-baseline/latest.json` 为准。Tests run [45861507912](https://github.com/dyyz1993/quite-note/actions/runs/45861507912)、Build macOS App run [45861506793](https://github.com/dyyz1993/quite-note/actions/runs/45861506793) 绿色 |
| 2026-11-27 | - | [5d7ccd610f622c142ae59ead61537ff7ec016dfb](https://github.com/dyyz1993/quite-note/actions/runs/45980999236) | `v1.7.1-8-g5d7ccd6` | 45980999236 | `ui-20261127-104551-5d7ccd61` | full | PASS | 9/9 用例全过；PR #8（截图启动改为后台并行截屏 + 工具栏换工具左缘锚定 + 焦点看门狗不再对调 key）合并后的首轮，套件升到 1.2.1：`screenshot-toolbar` 改成真测（右缘选区换工具高亮 874→640、居中选区 370→370 未横跳；此前该用例自最早基线起一直空转，见错题本 2026-11-27 条）。report.md 取自测试机 runner 工作目录，四张阶段截图逐张看过；八张收尾截图取自 gh-pages 基线 `ui-baseline/1.2.1-5d7ccd61`（`latest.json` 已指向它），与上一版基线同用例构图一致。Tests run [45981000403](https://github.com/dyyz1993/quite-note/actions/runs/45981000403)、Build macOS App run [45980999235](https://github.com/dyyz1993/quite-note/actions/runs/45980999235) 绿色 |
| 2026-11-27 | - | [2ef7afeb550bdf988fa7d188ade17f0a4d077a50](https://github.com/dyyz1993/quite-note/actions/runs/46010852856) | `v1.7.1-14-g2ef7afe` | 46010852856 | `ui-20261127-141726-2ef7afeb` | full | PASS | 9/9 用例全过；合并 PR #9（遮罩首帧 / 上屏观测点，测试机日志：截屏就绪 25–42ms、首帧 29–44ms、上屏 53–68ms）和 PR #10（CI 提效：push 只在 main 触发、基线快照改稀疏克隆，本步实测 25 秒）后的 main 首轮。screenshot-toolbar 数值与上一行逐位一致（右缘 874→640、居中 370→370）。八张收尾截图取自 gh-pages 基线 `ui-baseline/1.2.1-2ef7afeb` 逐张看过：工具栏、剪贴板、启动器、闪记与上一版构图一致；**launch 和 settings 两张里主面板没在屏上**（settings 那张拍到的是残留的启动器面板）——这两个用例本就只断言进程 / 隔离存储和「存在浮窗」，不断言主面板可见，属既有的弱断言，本轮没有变坏。Tests run [46010853990](https://github.com/dyyz1993/quite-note/actions/runs/46010853990)、Build macOS App run [46010852848](https://github.com/dyyz1993/quite-note/actions/runs/46010852848) 绿色 |
| 2026-11-27 | - | [4121799ef146b4c3fe7ee81a1c4c4e9c6b5cb2b7](https://github.com/dyyz1993/quite-note/actions/runs/46018111609) | `v1.7.1-18-g4121799` | 46018111609 | `ui-20261127-145213-4121799e` | full | PASS | 9/9 用例全过；合并 PR #11（CI 第二轮提速：Dev 安装包经局域网 scp 到测试机、单测用工作区外的常驻构建目录、删重复预构建）后的 main 首轮。从推送到三个工作流全绿共 13 分 26 秒（改前约 30 分钟）：冒烟 job 4 分 07 秒（取产物 0 秒、冒烟 51 秒、证据上传 44 秒、基线归档 27 秒）、单测 job 59 秒、Dev 构建 job 3 分 44 秒。screenshot-toolbar 数值与上一行逐位一致（右缘 874→640、居中 370→370），四张阶段截图取自测试机逐张看过：居中选区换工具后主栏左缘不动。应用日志：首帧 29–43ms、上屏 31–67ms。基线 `ui-baseline/1.2.1-4121799e` 已归档。Tests run [46018113154](https://github.com/dyyz1993/quite-note/actions/runs/46018113154)、Build macOS App run [46018111711](https://github.com/dyyz1993/quite-note/actions/runs/46018111711) 绿色 |
| 2026-11-28 | - | [ac0708ce7fce53dfe7e02239e21aa33c6439e93e](https://github.com/dyyz1993/quite-note/actions/runs/46030415324) | `v1.7.1-21-gac0708c` | 46030415324 | `ui-20261127-161258-ac0708ce` | full | PASS | 9/9 用例全过；合并 PR #12（基线推送绕开代理）后的 main 首轮。screenshot-toolbar：右缘换工具高亮 874→640（贴边让位）、居中 370→370 未横跳。基线已归档 gh-pages ui-baseline/1.2.1-ac0708ce |
| 2026-11-28 | v1.7.2 | [a4911402cf9e8810114d0aee33ac987ef7e110fa](https://github.com/dyyz1993/quite-note/actions/runs/46035665556) | `v1.7.2` | 46035665556 | `ui-20261127-165458-a4911402` | full | PASS | 9/9 用例全过；发版提交（PR #13，只切 CHANGELOG 段，代码与 ac0708c 相同）合并后的 main 首轮，tag v1.7.2 打在该提交上。screenshot-toolbar：右缘换工具高亮 874→640、居中 370→370。基线已归档 gh-pages ui-baseline/1.2.1-a4911402（18 张截图）。注：该用例归档的两张截图是会话前（启动器面板）和会话后（桌面），工具栏本身不在基线截图里，断言依据是运行中抓取的帧 |
| 2026-11-28 | - | [0cc798581171542722772e1e2ea76f37d29c55fe](https://github.com/dyyz1993/quite-note/actions/runs/46093083165) | `v1.7.2-6-g0cc7985` | 46093083165 | `ui-20261128-013110-0cc79858` | full | PASS | 9/9 用例全过；合并 PR #15（冒烟套件 1.4.0：launch / settings 断言收紧到「看得见」、toolbar 四个断言帧带检测框归档、settings 停稳帧）后的 main 首轮。launch 4094ms（主面板 520x640 + 状态菜单项可发现）、settings 8173ms（打开 → 切剪贴板 Tab → 关闭）。基线已归档 gh-pages ui-baseline/1.4.0-0cc79858（23 张截图，含 settings-open 与 4 张 toolbar 帧） |
| 2026-11-28 | - | [986b9421e7fb8d14174c121514f26174e5c1947a](https://github.com/dyyz1993/quite-note/actions/runs/46096058897) | `v1.7.2-11-g986b942` | 46096058897 | `ui-20261128-020602-986b9421` | full | PASS | 9/9 用例全过；合并 PR #17（SwiftPM 预热收成一份脚本 `tools/ci-prewarm-swiftpm.sh`、源缓存为空时打 `::warning` 注解、Dev 构建显式打印 swift build 退出码）后的 main 首轮。三个 workflow 的预热步骤在真实 runner 上各跑过一次（`SwiftPM cache primed: 3 repos, 2 artifacts` + 镜像已灌，无报警）。基线已归档 gh-pages ui-baseline/1.4.0-986b9421 |
| 2026-11-28 | - | [cfb67c799161ff71702dede83d51a694c1d47b28](https://github.com/dyyz1993/quite-note/actions/runs/46104031925) | `v1.7.2-16-gcfb67c7` | 46104031925 | `ui-20261128-035531-cfb67c79` | full | PASS | 9/9 用例全过；合并 PR #19（顶栏更新按钮：下载中显示圆环进度 + 百分比，Sparkle user driver 换成转发壳 `UpdateProgressUserDriver`）后的 main 首轮。冒烟环境里 Dev 包查的是正式更新源、没有可用更新，所以顶栏按钮不出现；下载进度另在测试机用本地无签名更新源真实验证过（20%→45%→70%→95%，见错题本 2026-11-28 条）。基线已归档 gh-pages ui-baseline/1.4.0-cfb67c79 |

## 当前验收范围

- permissions / launch / flash-notes / clipboard / launcher / settings / devcore / screenshot-toolbar / cleanup。
- Clipboard 和 Launcher 走真实用户路径：AX 点击菜单栏状态菜单，再点击 `剪贴板历史` / `应用启动器`。
- screenshot-toolbar 走真鼠标：从状态菜单发起会话，拖出选区，点文字组换工具；断言选中高亮还停在点击处（右缘选区允许 234pt 贴边让位）且主栏真的变宽，最后点「复制」结束会话。冒烟环境里键盘事件到不了应用，ESC / ⌘C 不在覆盖范围内。
- `flash-notes`、`settings` 当前仍是确定性面板存在性 / AX flow 可用性检查；搜索、输入和逐页设置巡检继续按 `operations.json` 增强。

## 维护规则

- 新 Tag：必须执行 `--mode release --evidence full`，全绿后新增一行。
- 发布候选：同 Tag 规则，并在 Notes 标明 RC。
- 普通 Commit：增量回归全绿后可更新该分支最新绿色入口；不要求每个 Commit 建行。
- 现有 `evidence=fast` 的历史绿色 run 保留为基线证据；从下一次 run 起使用 `evidence=full`，每步截图保留在 GitHub Artifact。
- 若 GitHub Artifact 超过 30 天，需要把关键 `manifest/report/timeline/screenshots` 另存到长期发布包或对象存储，再更新本索引的存储位置。
