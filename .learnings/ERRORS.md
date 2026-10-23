
## 2026-10-22 · 测试机 UI 自动化的权限矩阵与取图链路（一晚 20+ 轮的教训）
- 任务: Quite Note 截图工具栏修复的测试机 E2E 验证
- Symptom: 自动化时通时断——热键不触发、截屏纯色/黑图、点击落空，每轮修好一个又冒一个
- Root cause（按层）:
  1. 显示器睡眠：睡眠/锁屏下截屏 API、键盘合成、鼠标拖拽**全部静默失效**（caffeinate -u -d 保活即恢复）——今晚最大元凶
  2. 测试机权限矩阵缺口：cliclick 键盘合成需"输入监控"权限（只有辅助功能不够）；CuaDriver 截屏需屏幕录制+显示器唤醒
  3. Dev App 反复部署在 /tmp 漂移路径反复解压 → quarantine 属性 + TCC csreq 绑定漂移 → 屏幕录制授权反复失效（应固定路径部署）
  4. App 被 pkill -9 强杀后 Carbon 热键注册残留，新实例注册延迟/失败（应优雅 TERM + 等待注册日志）
- Fix/预防:
  - 流程开头 caffeinate -u -d 保活；取图前再唤醒一次
  - 新测试机初始化清单：屏幕录制（CuaDriver+被测App）、辅助功能（CuaDriver+cliclick）、输入监控（cliclick）一次配齐
  - 被测 App 固定路径部署（~/Applications），永不放 /tmp
- 关联: [测试机取图链路最终形态] 证据服务四层（screencapture-in-app→CGWindowList拒黑→layer.render→SCK）在 App 授权正常时可用

## 2026-10-23 · CI codesign 对 Sparkle.framework 嵌套结构签名失败（待修）
- 任务: v1.5.0 发布（首次含 Sparkle.framework 的 CI 构建）
- Symptom: 本机 build-app.sh --install 一切正常；同代码 CI（macos-15 runner）在 `codesign --force --deep --sign` 步骤报 "bundle format unrecognized, invalid, or unsuitable / In subcomponent: Quite Note.app/Contents/Frameworks/Versions/B/Resources/he.lproj"
- Root cause: CI 老版 codesign 在 --deep 扫描 app bundle 时，对 Sparkle.framework（Versions 结构 + 顶层 symlink Resources->Versions/Current/Resources）的嵌套子组件解析出错——报错路径缺 "Sparkle.framework" 层（Contents/Frameworks/Versions/B/...），疑似 symlink 规范化路径误报。本地 macOS 26 codesign 无此问题
- ✅ 已修复（2026-10-23，共 4 个叠加问题，验证 run 39902024176 重跑全绿）:
  1. build-release.sh 有独立的 --deep 签名段，build-app.sh 修了它没修（63cc7d7 补）
  2. build-release.sh 调 build-app.sh 未传 APP_SIGN_IDENTITY → build-app.sh 预签被跳过（6786799 补）
  3. **真根因**：CI 老 SwiftPM 的测试阶段 swift build 已把 Sparkle 内容"铺开"拷进 .build 产物 app 的 Contents/Frameworks/（无 Sparkle.framework 目录层，直接 Autoupdate/Versions/... 铺在 Frameworks/ 根）——所以报错路径没有 framework 层；且 CI checkout 状态下 cp -R 会把 symlink 骨架拷错（diag 实锤"cp 后 Sparkle.framework 不是目录"）
  4. 修复 = 检测铺开形态先清 Frameworks/ + **用 ditto 替代 cp -R**（ditto 保真 symlink 骨架）+ 拷贝异常直接终止构建（80e1b71）
  5. 后续一次失败是 Staple 时 Apple 服务器网络抖动（Error 68 connection lost），重跑即过——公证/Staple 类失败先看是不是网络 flake 再查代码
- 教训: ① 引入嵌套 bundle 依赖时签名策略必须 CI+本地双端验证；② 复制 macOS framework 必须用 ditto，不用 cp -R；③ "报错路径缺目录层级"= 环境产物结构与本地不同，先 dump 结构再猜
