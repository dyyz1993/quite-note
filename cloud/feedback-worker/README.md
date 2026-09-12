# quitenote-feedback

QuiteNote 用户反馈收集后端（Cloudflare Worker + D1 + R2），线上地址 **https://feedback.drel.app**。

> ⚠️ 域名必须是自定义域名 `feedback.drel.app`。`*.workers.dev` 在国内网络不可达（实测 12s 超时），App 端硬编码的是这个域名。

## 架构

```
App FeedbackService（Sources/QuiteNote/Feedback/）
  POST https://feedback.drel.app/feedback
        │
        ▼
Cloudflare Worker（src/worker.js）
  ├─ D1  quitenote-feedback     反馈落库（schema 见 schema.sql）
  ├─ R2  quitenote-feedback-att 附件截图（5MB×3）
  └─ 推送 GET https://push.drel.app/<key>/<title>/<body> → 开发者手机
```

## 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/feedback` | App 提交反馈。JSON：`type(bug/idea/other)`、`text(≤5000)`、`contact`、`appVersion/channel/osVersion/locale/entry`、`attachments[{name,mime,data(base64)}]`、可选 `logs`（诊断日志尾部，≤32KB，App 端已按打点规范脱敏）。同 IP 2 分钟限流 |
| GET | `/a/<key>?token=` | 下载附件（需 ADMIN_TOKEN，推送里的链接自带） |
| GET | `/list?token=&limit=` | 最近反馈列表（管理/调试） |
| GET | `/` | 健康检查 |

## 部署与运维

```bash
cd cloud/feedback-worker
wrangler deploy                 # 改代码后重新部署（自动重建 feedback.drel.app 路由）
wrangler d1 execute quitenote-feedback --remote \
  --command "SELECT id, created_at, type, substr(text,1,60) FROM feedback ORDER BY id DESC LIMIT 20"  # 查反馈
wrangler secret list            # PUSH_BASE / ADMIN_TOKEN 两个 secret
```

- **secrets**：`PUSH_BASE`（推送地址前缀）、`ADMIN_TOKEN`（附件/管理接口鉴权）。本地备份在 `.admin-token`（已 gitignore），云端用 `wrangler secret put <NAME>` 更新。
- **改表结构**：改 `schema.sql` 后 `wrangler d1 execute quitenote-feedback --remote --file=./schema.sql -y`（语句均为 IF NOT EXISTS，可重复执行；改列需另写 ALTER）。
- 全部在 CF 免费额度内（D1 免费 5GB / Worker 10 万请求/天 / R2 免费 10GB）。

## 数据与隐私

- D1 只存：类型、正文、选填联系方式、版本/系统/入口等环境字段、附件 R2 key、IP 哈希（仅限流用，不存原始 IP）。
- 附件经 token 鉴权才能访问，不公开索引。
- App 端提交文案已注明用途；**隐私政策（privacy-site）若上线附件收集，记得补一句"用户主动提交的反馈内容、联系方式与截图附件仅用于排查与回复"**。

## 历史

- 2026-09-09 搭建并全链路验证：curl 端到端（提交/限流/落库/附件下载 403 鉴权）+ App dev 变体实机 UI 冒烟（设置 → 反馈 Tab → 提交 #2 落库 + 手机推送）。
