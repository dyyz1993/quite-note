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
