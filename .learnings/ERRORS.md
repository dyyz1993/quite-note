
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
