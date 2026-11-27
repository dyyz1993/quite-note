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

### 2026-10-19 · Dev artifact 在专用 runner 的首次下载副本哈希不符

- Version / Commit / Run: 2451d26e2f430c2e52738b613fd9503c1b394059 / 39262438516 attempt 1
- Symptom: `Verify artifact` 的 `shasum -a 256 --check` 报 `computed checksum did NOT match`；UI 测试尚未启动。
- Root cause: GitHub 原始 artifact 另行下载到开发机后 SHA-256 与随包清单完全匹配，ZIP 完整可解压；专用 runner 首次下载副本损坏，具体传输层原因未证实。
- Fix: 保留 SHA-256 硬门禁，重跑失败的 UI job；attempt 2 校验通过且 UI 8/8、WebP 视觉证据门禁全绿。
- Prevention: 不绕过哈希；若同类问题重复出现，再为 artifact 下载增加受控重试与下载副本哈希诊断。
- Evidence: GitHub run 39262438516 attempt 1/2；`QuiteNoteUI-2451d26e2f430c2e52738b613fd9503c1b394059`。
- Status: transient, monitor

### 2026-10-18 · xyz-mac Screen Recording 授权丢失导致录屏验收失败

- Version / Commit / Run: 551c8bd8da9594786c761b92793f101885752444 / 39135127430
- Symptom: AX smoke 全部场景 PASS，`screencapture -v` 返回 `capture error`；run 生成 `recordings/ui-recording.unavailable.txt`，CI 的 Require video evidence 步骤按预期失败。
- Root cause: xyz-mac 当前 GUI 会话中 runner Python 会话 `CGPreflightScreenCaptureAccess() == false`，用户 TCC 库中已无 Screen Recording 授权记录；疑似系统更新/权限重置后授权丢失。
- Interim fix: UI 回归使用 `recordings/frames.json` + Dev App 自绘的非空窗口帧作为连续录屏降级证据；CI 校验帧内容尺寸和每步证据，且人工目检关键面板。见绿色 run `39245202816`。这只能证明 App 窗口画面，不能当整屏录屏。
- Final fix: 在 xyz-mac 登录会话为 runner 使用的 `actions-runner-quitenote/externals/node24/bin/node`（以及 runner 子进程可用的 `screencapture` 执行链）重新授予 Screen Recording，重启 `quitenote-ui-xyz` LaunchAgent 后复测，恢复非空 `recordings/ui-recording.mov`。
- Prevention: 录屏证据链现在作为 CI 硬门禁；录屏能力缺失不能被 report PASS 掩盖。
- Evidence: run artifact `QuiteNoteUI-551c8bd8.../recordings/ui-recording.unavailable.txt` 与 GitHub run `39135127430`。
- Status: open

> 2026-10-19 更新：窗口截图现可合成为 `recordings/ui-timeline.webp`，不依赖 Screen Recording TCC；本条只跟踪可选的连续整屏录屏能力，不再阻塞截图时间线回归。

### 2026-10-19 · GUI launcher 响应文件名与当前 driver 脱节

- Version / Commit / Run: 68982b8 / 39235611588；990d0c0 / 39241779657
- Symptom: 第一轮 8 个 UI 场景全 PASS，但 runner 等待 `*.response.json` 超时；下一轮响应成功，报告仍引用不存在的旧截图路径，视觉证据门禁失败。
- Root cause: launcher 把 `*.request.claim` 的 stem 写成 `*.request.response.json`；修名后又从常驻安装目录导入旧 `computer_use_smoke.py`，未运行当前 checkout 的 fallback 逻辑。
- Fix: 响应文件名按请求 ID 生成；每个请求显式传当前 checkout 的 driver 路径，launcher 动态加载。录屏失败时由隔离 Dev App 自绘可见前台面板 PNG，并验证帧索引。
- Prevention: 回归报告的证据路径必须指向存在的非空图片；目检剪贴板和启动器帧，不能只看 UI assertion PASS。
- Evidence: run `39235611588` 的报告和错名响应文件；run `39241779657` 的 PASS 报告与空 `recordings/`；后续绿色 run 见索引。
- Status: fixed by `47a2765` / green run `39245202816`；Screen Recording 授权问题仍按上条 open 跟踪

### 2026-10-15 · runner 工作区下载 artifact 后被误判为 dirty

- Version / Commit / Run: a73380e / 38774784730
- Symptom: GitHub artifact 下载到仓库根目录后，`run_ui_smoke.sh` 认为 checkout 是 dirty，尚未创建 run 目录即退出。
- Root cause: `actions/download-artifact` 默认写入工作区；下载的 ZIP/sha256 属于未跟踪文件，触发 runner 的 WIP 防护。
- Fix: artifact 固定下载到 `$RUNNER_TEMP/ui-artifact`，保持 Git checkout clean。
- Prevention: CI 中所有临时安装包、证书和报告输入不得写入仓库根目录；必须放在 `$RUNNER_TEMP` 或专用 ignored 目录。
- Evidence: run `38774784730` 的 `Verify artifact` PASS，`Run UI smoke` 在 dirty 检查处 exit 2。
- Status: fixed

### 2026-10-15 · artifact 目录导致 sha256 相对路径校验失败

- Version / Commit / Run: e61a908 / 38776352245
- Symptom: ZIP 已下载到 `$RUNNER_TEMP/ui-artifact`，但校验提示 `QuiteNoteDev-...zip: No such file or directory`。
- Root cause: `.sha256` 中的文件名是相对路径；`shasum --check` 在仓库工作目录执行，而不是在 artifact 目录执行。
- Fix: `cd "$RUNNER_TEMP/ui-artifact"` 后按 basename 校验。
- Prevention: 校验清单必须和清单引用的相对路径在同一工作目录执行。
- Evidence: run `38776352245` 的 `Verify artifact` 日志。
- Status: fixed

### 2026-10-15 · Apple Git 不支持 describe 同时带 dirty 和 ref

- Version / Commit / Run: 5a042d5 / 38778021033
- Symptom: clean checkout 中解析元数据时报 `fatal: option '--dirty' and commit-ishes cannot be used together`。
- Root cause: 新旧 Git 行为差异；xyz-mac 的 Apple Git 2.39 拒绝 `git describe --dirty <commit>`。
- Fix: dirty 后缀只从工作区 describe 获取；clean/指定 ref 场景使用 `git describe --tags --always <commit>`。
- Prevention: runner 脚本不能依赖最新本机 Git 的宽松参数组合；跨机器命令先用目标 macOS 自带 Git 验证。
- Evidence: run `38778021033` 的 `Run UI smoke from prebuilt artifact` 日志。
- Status: fixed

### 2026-10-15 · Bash 数组字符串被误传成一个 suite

- Version / Commit / Run: 4267f8d / ui-20261015-175138-4267f8d0
- Symptom: 报告出现 `unknown suite: launch flash-notes clipboard launcher settings devcore cleanup`，七个 suite 被拼成一个参数。
- Root cause: 本地执行分支把数组写成 `"${SUITES[*]}"`，展开为单个字符串；远端 SSH 分支没有此问题。
- Fix: Python `argparse nargs='+'` 场景必须传 `"${SUITES[@]}"`。
- Prevention: 每次新增本地/远端双路径时，用 `bash -x` 或日志确认数组展开语义保持一致。
- Evidence: run artifact `QuiteNoteUI-4267f8d0.../report.json`。
- Status: fixed

### 2026-10-15 · self-hosted runner 服务缺少屏幕录制授权

- Version / Commit / Run: 4267f8d / ui-20261015-175138-4267f8d0
- Symptom: `screencapture` 连续输出 `could not create image from display`，同时 `permissions.accessibility` BLOCKED。
- Root cause: LaunchAgent runner 与此前 SSH Python 进程的 TCC 身份不同；runner 服务身份尚未被授予当前 GUI 会话的辅助功能/屏幕录制权限。
- Fix: 在 xyz-mac 登录会话中打开「系统设置 → 隐私与安全性」，为 runner 相关 shell / 终端授予辅助功能和屏幕录制；重启 runner 后复测。
- Prevention: 更换执行身份（SSH → LaunchAgent/self-hosted runner）必须重新验证 TCC；旧的授权不能证明新身份可用。
- Evidence: run artifact 截图 `screenshots/permissions-accessibility-1792086705.png`。
- Status: open

### 2026-10-16 · xyz-mac runner 屏幕录制二次授权

- Version / Commit / Run: 8d59a6b / 38829176703
- Symptom: Accessibility 已 PASS，但截图仍报 `could not create image from display`。
- Root cause: 用户为 runner node 重新勾选 Screen Recording 后，TCC 状态已变为 allowed=2，但 runner 进程未完全继承新授权状态。
- Fix: 重启 `quitenote-ui-xyz` LaunchAgent 后复测；窗口枚举与截图能力恢复。
- Prevention: Screen Recording 授权变更后必须重启 runner；验证要看真实 `screencapture` / `CGWindowList`，不能只读 TCC 数据库。
- Evidence: TCC `kTCCServiceScreenCapture=2`；重启后 `38831421667` 起窗口可见。
- Status: fixed

### 2026-10-16 · self-hosted runner 无法用 open 启动 Dev App

- Version / Commit / Run: 7a899b1 / ui-20261015-233220-7a899b18
- Symptom: runner 记录到 app pid 并创建了隔离存储，但后续 Python 会话立即找不到 Quite Note Dev 进程；手工排查发现进程已退出。
- Root cause: LaunchAgent 服务会话中 `open` 是异步启动，pid 捕获与进程生命周期不稳定；同时脚本用 `Foundation.NSWorkspace` 查找进程，该符号实际在 AppKit 中。
- Fix: 直接 fork/exec `$APP/Contents/MacOS/QuiteNoteDev`，保留 stdout/stderr，并继续传递 `QN_TEST_STORAGE_ROOT`；Python 从 `AppKit.NSWorkspace` 读取进程列表。
- Prevention: UI runner 不要依赖 `open` 的 LaunchServices 状态；执行身份切换后必须用真实 runner 会话做首跑验证，而不是只看 pid。
- Evidence: run `38781096843` attempt 3 的 app log 和 `report.json`。
- Status: fixed

### 2026-10-16 · NSWorkspace 返回了残留 Dev 实例 pid

- Version / Commit / Run: 0304bf8 / ui-20261015-235010-0304bf87
- Symptom: runner 子进程 pid `86389` 正常运行并有 GUI window，但 Python 通过 `NSWorkspace` 找到的是手工排查遗留的 pid `85233`，导致窗口列表为空。
- Root cause: 专用机此前手工验证留下一个同 bundle id Dev 实例；`NSWorkspace` 只返回第一个匹配，且未优先使用 runner 直接启动的 pid。
- Fix: runner 把 `$TEST_PID` 通过 `--app-pid` 传给 Python；AX、窗口和流程检查都使用这个确定的当前 run 子进程。
- Prevention: 手工调试 Dev App 后必须退出该实例；自动化运行必须绑定自身 fork/exec 得到的 pid，不能依赖全局进程枚举。
- Evidence: xyz-mac 上 `app.pid=86389`，`NSWorkspace` 返回 `85233`。
- Status: fixed

### 2026-10-16 · runner SessionCreate 隔离导致窗口不可枚举

- Version / Commit / Run: c74c76a / ui-20261016-004024-c74c76a4
- Symptom: Dev App 有启动日志和 WindowServer order-front 记录，但 Python `CGWindowListCopyWindowInfo` 看不到该 pid 的任何窗口。
- Root cause: `svc.sh install` 生成的 LaunchAgent 带 `SessionCreate=1`，runner 被放进独立 audit session；子进程 UI 与当前登录 GUI 会话隔离。
- Fix: 移除该 runner LaunchAgent 的 `SessionCreate`，重启 LaunchAgent，使其在当前 `gui/501` 登录会话中运行。
- Prevention: macOS UI runner 不能继承 `SessionCreate=1`；迁移 runner 后必须验证“真实 GUI window 可枚举”，仅凭进程/pid 不算通过。
- Evidence: `launchctl print gui/501/...quitenote-ui-xyz` 的 `asid` 与登录会话；run 截图无 App 窗口。
- Status: fixed

### 2026-10-16 · self-hosted runner 中 System Events 查询挂起

- Version / Commit / Run: 010df88 / ui-20261016-010539-010df885
- Symptom: AppleScript 通过 System Events 激活进程、点击菜单或发送按键时稳定超时。
- Root cause: System Events 需要跨进程枚举/控制目标 GUI 进程；在该 runner 服务身份下即使 AX trust 为 true 也会挂起。
- Fix: 面板热键改用 Quartz `CGEventPost` 直发；进程激活用 `NSWorkspace.activateWithOptions`；不再依赖 System Events 作为主路径。
- Prevention: UI runner 的主操作路径优先使用 AX API/CGEvent，System Events 只能作为诊断 fallback；每次必须设置短 timeout 并保留截图。
- Evidence: run `38833585020` 与后续 CGEvent 修复 run。
- Status: fixed

### 2026-10-16 · System Events 不可靠但全局热键也不触发

- Version / Commit / Run: ad1d95a / 38836400666
- Symptom: 改用 Quartz `CGEventPost` 发送 `⇧⌘V` 和 `⌥Space` 后命令执行成功，但 Clipboard / Launcher 面板仍未出现。
- Root cause: 全局热键依赖 Carbon 注册与窗口服务状态；在 self-hosted runner 的启动上下文中，合成键盘事件未触发应用注册的 global hotkey。继续沿“模拟快捷键”路径调试会偏离真实人工点击路径。
- Fix: 改为真实用户式菜单操作：AX 定位菜单栏 extra → 打开状态菜单 → 按 `AXTitle` 点击 `剪贴板历史` / `应用启动器`。
- Prevention: 用户可点击菜单项时，CI 主路径应优先模拟菜单点击；快捷键只能作为辅助路径或人工复核，不得因实现方便而引入 App 测试入口。
- Evidence: run `38836400666` 的 clipboard / launcher `RuntimeError`。
- Status: fixed

### 2026-10-16 · 状态菜单 AXPress 返回 actionFailed 但菜单已打开

- Version / Commit / Run: 5c9d1c5 / 38839634717
- Symptom: Clipboard 场景报 `AX press failed: -25204`，但后续 Launcher 场景能打开同一个状态菜单。
- Root cause: 对 transient menu extra 执行 `AXPress` 时，macOS 可返回 `actionFailed`；这并不代表菜单未展开，不能用单次返回码判断结果。
- Fix: 捕获状态菜单打开阶段的 AX press 错误，等待 300ms 后以 `AXChildren` 是否出现作为打开判据；菜单项本身的 `AXPress` 仍严格检查。
- Prevention: AX action 返回码必须按控件类型分类处理；transient menu open 需要用后续树状态验收，不能把 `-25204` 一律当失败。
- Evidence: 手工 AX 实测 `AXPress=-25204` 后 `AXChildren` 正常暴露；修复 run `38840392166` 全绿。
- Status: fixed

### 2026-10-16 · AX API 导入在 Python 命名空间中不稳定

- Version / Commit / Run: e26634e / 38839073990
- Symptom: 手工验证可用的 `AXUIElementPerformAction` 在 runner 中报 `NameError`。
- Root cause: PyObjC 的部分 `ApplicationServices` 符号由构造函数局部 import 后未可靠进入模块全局命名空间；跨进程环境与手工 `runpy` 验证不同。
- Fix: 在实际调用处局部导入 `AXUIElementPerformAction`，避免依赖构造函数 import 的副作用。
- Prevention: PyObjC API 必须在使用点显式 import；不要假设构造函数局部 import 会把符号提升为全局可见。
- Evidence: run `38839073990`。
- Status: fixed

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
- Fix: 迁移到 专用测试机；本机只构建/下载 CI 产物并控制 SSH，不启动 App UI。
- Prevention: 交互式 UI 用例必须通过 `--remote "$QN_UI_REMOTE_HOST"` 执行；本机只允许 dry-run、静态检查和单元测试。
- Evidence: `docs/ui-test-knowledge.md` 远程执行模式。
- Status: fixed

### 2026-10-16 · self-hosted runner 下载了错误 CPU 架构

- Version / Commit / Run: runner v2.338.0 / xyz-mac
- Symptom: 在 Intel `xyz-mac` 执行 `Runner.Listener` 报 `Bad CPU type in executable`。
- Root cause: 首次复制的是 arm64 runner 包；该机器没有 Rosetta 可用。
- Fix: 下载 `actions-runner-osx-x64-2.338.0.tar.gz`，校验 SHA-256 后安装到独立目录 `~/actions-runner-quitenote`。
- Prevention: 安装前必须核对 `uname -m` 与发行包架构；不得复用/修改其它项目的 `~/actions-runner`。
- Evidence: GitHub runner 列表中 `quitenote-ui-xyz` 为 online，标签包含 `x86_64`。
- Status: fixed

### 2026-10-15 · 远端 UI 冒烟遍历 AX 菜单树导致挂起

- Version / Commit / Run: f707fa5
- Symptom: 在专用测试机上递归遍历应用 AX 树查找 TextField 时长时间无响应，尤其是启动器和面板切换场景。
- Root cause: NSStatusItem / 菜单相关的 AX 树会瞬时包含大量菜单节点，SSH 场景下遍历成本和时序不稳定。
- Fix: 冒烟层先用 CGWindow 判定固定尺寸浮层面板出现，再按需做 AX 细粒度断言；剪贴板与启动器均改为面板可见性快速判定。
- Prevention: 远端 UI 冒烟优先用窗口尺寸/层级做确定性面板存在性检查，避免递归遍历大 AX 树；AX 只用于输入和关键控件断言。
- Evidence: 本地 run `ui-20261015-120913-f707fa55`；远端修复后 `clipboard/launcher/cleanup` PASS。
- Status: fixed

### 2026-10-21 · 测试机屏幕录制月度重验与 SwiftUI 离屏取图限制（screenshot-toolbar E2E）
- 版本/Commit: codex/screenshot-toolbar-fix @ 0235bca；run ui-20261021-130554-0235bcac
- Symptom: screenshot-toolbar 场景时通时阻——同一代码一轮出真帧跑断言，一轮纯色图 BLOCKED。
- Root cause: ① macOS 15+ 屏幕录制"月度重验"：重验窗口期内每个 App/驱动**新会话首次抓屏**都弹系统确认，无人值守即挂起；CI 每轮重启 Dev App = 每轮可能触发。② macOS 26 SwiftUI hosting 内容**离屏取图四路径全灭**：cacheDisplay 纯背景 / CGWindowListCreateImage 纯黑 / layer.render 纯背景 / SCK 需 App 授权（受①制约）。③ 输入合成坐标空间：cliclick 吃逻辑 pt，cua 吃截图像素——换输入通道必须同步去掉缩放（本轮实锤：×2 坐标全打飞，红钮 1332→1332 假阴性）。
- Fix/现状: 场景取图纯色时 raise BlockedError 报 BLOCKED 而非 FAIL（981fbb7）；取图成功时像素断言链已验证可用（ui-20261021-124850：按钮检测/断言逻辑/流程时序全通过）。
- Prevention: ① 测试机取图只依赖"人点过确认的窗口期"，跑长 E2E 前先 `cua-driver call get_desktop_state` 探测一次；② 新增输入通道时核对坐标空间（逻辑 pt vs 像素）；③ SwiftUI 窗口的像素证据优先 ScreenCaptureKit（App 自身授权），离屏渲染路径一律不可信。
- Evidence: runs/ui-20261021-124850-d012ec21（成功样本）、ui-20261021-130554-0235bcac（BLOCKED 样本）

## 2026-11-20 · screenshot-toolbar 套件五连修后管线全通（遗留 6pt 标定 → 2026-11-25 随脆弱阶段退役后用例转绿）


**已修（807f3fd/4922d1b，全部有现场图实证）**：① 3901435 误删的截图会话触发行（一个月结构性必败）；② decode 红钮分支被简化丢弃（KeyError 'R'）；③ app 证据通道 Retina 2880px 未归一化（管线按 1366px 标定，几何全翻倍）；④ 工具栏锚定"最左蓝簇"被 Dock 污染（改工作区红蓝同行配对取最上）；⑤ /tmp/qn-manual 目录自建。取证主通道已切到 app 自身 UIEvidenceCaptureService（零 TCC 依赖，cua/screencapture 降级兜底——两外部通道 11-20 实锤同时无产物）。

**~~遗留~~ 已于 2026-11-25 转绿（下面的归因当时是错的，保留原文作教训）**：11-20 判断为"stage1 `暗带右端 1438 > 1432`——cua drag 选区投递偏差大，须改 cliclick 并按新版工具栏重标，修前视为 KNOWN-FAIL"。
**真因（11-25 查明）**：用例根本没跑到那一步——10-29 的提交 63774d0 删掉了脆弱的二级栏像素标定和它的 `find_sub` 实现，却漏删了一个调用点，用例每次都以 `NameError: find_sub is not defined` 失败。"暗带 1438" 是更早一轮的现象，被当成了长期阻塞项。补删调用点后（c0d3649）stage1/2 实测 `默认带右端 1168→撑开 1174 均屏内` PASS，9/9 全绿。
**教训**：红灯持续了四周没人核对"它到底为什么红"——KNOWN-FAIL 一旦挂久就成了免检牌。**挂 KNOWN-FAIL 时必须附上"最近一次确认根因的日期和证据"，超过两周的红灯要重新取证而不是沿用旧结论。** cua 拖拽偏差这个现象本身可能仍存在，但它不阻塞冒烟，需要时再作为独立任务取证。

## 2026-11-25 · 便利贴专项 E2E：自定义 driver 走 launcher 队列（一次性验证，未接入套件）

- Symptom: 便利贴修复后要在 xyz-mac 上做界面级验证（热键、便签输入、换底色、旧库升级、设置页新标签），现有套件没有这些场景；ssh 直连做不了 AX。
- Root cause / 通道事实:
  1. ssh 会话里 osascript 界面脚本化报 -1719、从 ssh 启动受信 Python 做 AX 报 -25211——只有常驻 launcher 的图形会话有辅助功能权限。
  2. 往 `/tmp/quitenote-ui-smoke-launcher/requests/` 写请求（`run_dir` / `app_path`(.app 目录) / `storage_root` / `run_id` / `driver_path` / `suites` / `evidence`），launcher 会先用 driver 同目录的 `seed_clipboard_history.py` 灌剪贴板库、再 Popen 启动 App（print 日志在 `app.stdout.log`）、以 `--run-dir --app-pid …` 调 driver 的 `main()`，结束时 SIGTERM 掉 App（stdout 缓冲会丢）。
  3. driver 里 `NSWorkspace.frontmostApplication()` / `runningApplications()` 返回陈旧值：焦点判定用系统级 AX（`AXUIElementCreateSystemWide` → `AXFocusedApplication` → `AXUIElementGetPid`），按 pid 取应用用 `NSRunningApplication.runningApplicationWithProcessIdentifier_`。
  4. App 刚启动时状态栏图标可能还没建好（菜单栏 extra 的 `AXChildren` 为空），要等 0.5s 重试。
  5. SwiftUI 按钮在设置页里是暴露 AXTitle 的，`.help()` 文本走 AXHelp，ScrollView 的纵向滚动条可以直接设 `AXValue` 滚动。
  6. 部署 Dev 包时 `rsync` 的远端路径带空格没转义 → **静默没传输**；而测试机上原有的旧 Dev 包同样是通用架构、签名有效，`lipo` / `codesign --verify` 全过——验证被假阳性骗过，跑了一轮旧二进制。正解：`tar -cf - | ssh … tar -xf -`，部署后比对二进制 SHA-256。
- Fix / Prevention: 自定义 driver + 通用提交脚本归档在开发机 `~/.agents/projects/quite-note/e2e-sticky/`（见其 README）。以后部署到测试机一律比哈希；`strings` 不认 UTF-8，不能用中文字面量判断二进制新旧。
- Evidence: xyz-mac 上五场景（旧库自动迁移 → Finder 里 ⌘⇧N 归还 → ⌥⇧⌘N 新建 → 输入并换底色 → 保存到记录）、设置页「便利贴」标签、旧版本打开新库的回滚验证，均有全屏截图。

## 2026-11-25 · 便利贴 E2E：断言 20/20 全过，截图里底色按钮却根本没画出来

- Symptom: 全功能验证 20/20 通过之后逐张看截图：工具栏右下角该有"便签底色"按钮的位置是空的；设置页「默认颜色」的六个圆点在深色卡片上几乎分不清彼此。
- Root cause:
  1. SwiftUI `Menu` + `.menuStyle(.borderlessButton)` 的 label **画不出 SwiftUI 图形**（`Circle`），只画得出 `Image`——同一排的"文字颜色"按钮看得见，因为 `LucideView` 内部就是 `Image(nsImage:)`。
  2. 把 label 换成图片后按钮出现了，但**选完菜单项按钮图标一直半亮**（约 35–50%），等几秒、打字、重新悬停都不恢复，再开一次菜单才恢复。真鼠标的点击-点击、按下-拖动-松开，以及辅助功能按压三条路径都复现。
  3. 断言验证的是"控件存在、能点、点了有效、值写进去了"，验证不了"画没画出来、人眼找不找到"。
  4. **诊断过程本身也是错题**：第一次把原因判成"默认深蓝的圆点压在深色工具栏上没对比度"，据此改了色板、做了双色色块，部署后才被实拍打脸（换成亮色环照样看不见）。
- Fix / Prevention:
  - 底色按钮改成自绘控件 `StickyNoteColorButton`（`NSViewRepresentable` + `NSMenu.popUp(positioning:at:in:)`），自己画、自己弹菜单。`popUp` 的 `at` 是菜单**顶边**在视图坐标系（原点左下）的位置，不是菜单左下角——第一次给 `(0, bounds.height + gap)` 菜单朝下弹、盖住了工具栏。
  - 全功能验证加了「底色按钮可见」一步：截按钮位置数色环像素（修之前实测 0，修之后 230 左右）；另写六色探针逐个底色截图。
  - **先实拍、再下结论；每次改动前后都拍。** 断言全过之后必须逐张看真实截图。菜单类控件除了辅助功能按压，必须用真鼠标再测点击-点击和按下-拖动-松开。
- Evidence: `~/.agents/projects/quite-note/e2e-sticky/screenshots/2026-11-25-final/`（构建 `30615546e6c2…`：全功能 21/21、六色探针、真鼠标按压日志、五场景、降级/再升级回环）。

## 2026-11-25 · 便利贴 E2E 环境的坑：launcher 模块缓存 / 便签偏好残留 / 合成点击瞬移 / 截图色彩配置

- Symptom: 四个互不相干的现象——(a) 改了辅助模块里的函数并拷到测试机，跑起来仍报 `ImportError: cannot import name`；(b) 一启动就恢复出 7 张叠在一起的便签，探针全程在操作被盖住的窗口，选色全部"失败"；(c) 真点击打开菜单后，再点菜单项选不中；(d) 像素量里青色色环量到 0，其余五色正常。
- Root cause:
  1. `gui_smoke_launcher` 是**常驻进程**：driver 文件本身每次用 `spec_from_file_location` 重新加载，但 driver 里 `import` 的辅助模块留在它的 `sys.modules` 缓存里，下次运行直接复用旧模块对象。
  2. 便签数据存在 dev 变体 UserDefaults 的 `StickyNotes` 里；提交脚本只重建隔离数据库，不清偏好。前几轮探针各建过一张便签，全部跨运行残留。
  3. 合成点击是"瞬移"：没有 `mouseMoved` 事件，菜单高亮不跟着走，随后的点击落空、把菜单点没了。
  4. `screencapture` 出的 PNG 带显示器 ICC 配置，读到的色值整体漂移（青色的红通道实测 123，色板是 88），±18 的逐通道容差不够。
- Fix / Prevention:
  1. 探针类 driver 在 import 前 `sys.modules.pop("sticky_full_e2e_driver", None)`；driver 必须暴露 `main()`（launcher 调 `module.main`）。
  2. `submit_generic.sh` 每次开跑前（App 没在运行时）重置 `StickyNotes` / `stickyNoteShortcut` / `stickyNoteShortcutFlags` / `stickyNoteDefaultColor`；`QN_KEEP_ROOT=1` 的回退验证不动它们。
  3. 点菜单项之前先发 `mouseMoved` 到目标位置。
  4. 判据不比色值：比"通道大小关系"（哪些通道最高、哪些最低）+ 饱和度 + 亮度。
  5. 另两个小的：菜单跟踪模式下连按 ESC 关不干净（状态栏菜单高亮卡住、面板打不开），点一下空桌面最稳；迁移验证里读 schema 要轮询（App 做迁移比 driver 的第一次查询晚，固定先读一次会误报"没有底色列"）。
- Evidence: 同上目录；`submit_generic.sh` / `run_driver.sh` 的注释里有对应说明。

## 2026-11-27 · screenshot-toolbar 用例自最早基线起一直在空转：蓝钮认错、坐标差 2 倍、ESC 到不了应用

- Symptom: 套件 9/9 PASS，但取证里"默认态"和"点文字组后"两张阶段截图字节相同（md5 一致）。逐项复核后是三处问题叠在一起，`1.2.0-1b95ec15` 到 `1.2.0-b5506c29` 每一轮的结论都是同一句"默认带右端 1168→撑开 1168 均屏内"。
- Root cause:
  1. `decode` 的蓝色阈值 `b > 185` 恰好漏掉选中工具组的高亮（`themeOverlaySelected` 实测 (60,89,184)），蓝簇只剩主栏右侧的蓝色钉图钮；"点文字组（蓝钮 + 76pt）"于是点在复制和录制之间。
  2. cua 桌面坐标的单位是主显示器的**原生像素**（测试机 Retina：2880px / 1440pt = 2），脚本按旧的 `1366 / 1440` 换算，拖拽和点击的落点只有预期的一半——"贴右缘的选区"一直拖在屏幕中间（实测发 (1117,285)→(1326,455)，落在逻辑 (558,143)→(662,226)）。cua 自己的回执写得很清楚：`desktop-pixel (1440,1074) → screen-point (720,537)`。
  3. 冒烟环境里键盘事件到不了应用：测试机 11-25 以来每轮冒烟的应用日志都是"截图会话开始 1 次、结束 0 次"，`cliclick kp:esc` 从没关掉过会话，一直靠 cleanup 结束进程。**截图遮罩的键盘链路（ESC / ⌘C）至今没有任何 UI 覆盖。**
  4. 暗带右端量到的是工具栏背后深色窗口的边缘（1168 = "闪记"窗口的右缘），和主栏无关，"均屏内"的断言恒真。
- Fix / Prevention:
  - 蓝阈值按实测色重定（`b > 160 and r < 80 and 70 < g < 150`）；坐标换成 `_cua_px_per_pt()`（读主显示器显示模式的像素宽 / 点宽）。
  - 找工具栏不再靠红簇配对：候选蓝簇里，"录制钮在高亮右侧 534pt（默认态）或 692pt（变宽后）"且图上颜色对得上的才算数。录制钮直接比色、不走聚类——主栏压在橙红色壁纸上时，录制钮会和壁纸连成一簇被整簇丢弃。
  - 用例改成四阶段：右缘选区点文字组（贴边让位 234pt）、屏幕中间选区点文字组（不允许位移）。断言"换工具后选中高亮还在点击处"，这才是"主栏左缘锚定"的像素证据；中间选区那一段才能区分旧行为"重新居中"（高亮会左移 117pt）。
  - 结束会话走鼠标点「复制」（录制钮左侧 45pt），不依赖 ESC。套件版本升到 1.2.1。
  - 冒烟里凡是"两张阶段截图字节相同"都要当异常查，不能只看 PASS。
- Evidence: 测试机手工运行 `ui-20261127-061015-75b51750` / `ui-20261127-061438-75b51750`（连过两轮，数值逐位一致）：右缘 874→640（预期 641）、居中 370→370；应用日志里两个会话都有"截图会话结束"。四张阶段截图逐张看过：中间选区下主栏左缘不动，颜色 + 尺寸控件从右侧长出。
