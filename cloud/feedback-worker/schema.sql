-- QuiteNote 用户反馈库
-- 部署：wrangler d1 execute quitenote-feedback --remote --file=./schema.sql -y
CREATE TABLE IF NOT EXISTS feedback (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  type TEXT NOT NULL,             -- bug | idea | other
  text TEXT NOT NULL,             -- 反馈正文（≤5000 字）
  contact TEXT DEFAULT '',        -- 选填联系方式
  app_version TEXT DEFAULT '',    -- 如 1.3.0 (17)
  channel TEXT DEFAULT '',        -- dmg | appstore | dev
  os_version TEXT DEFAULT '',     -- 如 macOS 26.2 (ARM)
  locale TEXT DEFAULT '',         -- zh-Hans
  entry TEXT DEFAULT 'unknown',   -- 来源入口 prefs | menubar | ball | screenshot
  attachments TEXT DEFAULT '[]',  -- JSON: [{key, name}]，图片本体在 R2
  logs TEXT DEFAULT '',           -- 可选诊断日志尾部（打点统计，非用户内容，≤32KB）
  ip_hash TEXT DEFAULT ''         -- IP SHA-256 前 32 位，仅用于限流
);

CREATE INDEX IF NOT EXISTS idx_feedback_created ON feedback(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_feedback_ip ON feedback(ip_hash, created_at);
