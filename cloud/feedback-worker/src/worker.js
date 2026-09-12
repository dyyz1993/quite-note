// QuiteNote 用户反馈收集 API
//
// 端点：
//   POST /feedback                  App 提交反馈（JSON，见下方校验）
//   GET  /a/<objectKey>?token=xxx   下载附件截图（需 ADMIN_TOKEN，链接由推送直接带出）
//   GET  /list?token=xxx&limit=20   最近反馈列表（开发者调试/管理用）
//   GET  /                          健康检查
//
// Bindings：DB(D1) / ATT(R2)；Secrets：PUSH_BASE（推送地址前缀）、ADMIN_TOKEN（附件/管理鉴权）
// 部署：cd cloud/feedback-worker && wrangler deploy（详见同目录 README.md）

const MAX_TEXT_LEN = 5000;
const MAX_ATTACHMENTS = 3;
const MAX_ATTACHMENT_BYTES = 5 * 1024 * 1024;
const RATE_LIMIT_SECONDS = 120;

const TYPES = { bug: "🐞 Bug", idea: "💡 建议", other: "💬 其他" };
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });
    try {
      if (request.method === "POST" && url.pathname === "/feedback")
        return await handleFeedback(request, env);
      if (request.method === "GET" && url.pathname.startsWith("/a/"))
        return await handleAttachment(url, env);
      if (request.method === "GET" && url.pathname === "/list")
        return await handleList(url, env);
      return json(200, { ok: true, service: "quitenote-feedback" });
    } catch (err) {
      return json(500, { ok: false, error: String((err && err.message) || err) });
    }
  },
};

function json(status, obj) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...CORS },
  });
}

async function handleFeedback(request, env) {
  let body;
  try { body = await request.json(); } catch { return json(400, { ok: false, error: "invalid json" }); }

  const type = body.type;
  if (!TYPES[type]) return json(400, { ok: false, error: "bad type (bug|idea|other)" });
  const text = String(body.text || "").trim();
  if (!text || text.length > MAX_TEXT_LEN) return json(400, { ok: false, error: "text required, max 5000 chars" });
  const contact = String(body.contact || "").slice(0, 200);

  const meta = {
    appVersion: String(body.appVersion || "").slice(0, 50),
    channel: String(body.channel || "").slice(0, 30),
    osVersion: String(body.osVersion || "").slice(0, 50),
    locale: String(body.locale || "").slice(0, 12),
    entry: String(body.entry || "unknown").slice(0, 30),
  };
  // 可选诊断日志尾部（App 端已脱敏：仅打点统计/尺寸/长度/哈希，无用户内容）
  const logs = String(body.logs || "").slice(0, 32 * 1024);

  // 附件：base64 图片，最多 3 张、单张 5MB
  const rawAtts = Array.isArray(body.attachments) ? body.attachments : [];
  if (rawAtts.length > MAX_ATTACHMENTS) return json(400, { ok: false, error: "max 3 attachments" });
  const atts = [];
  for (const a of rawAtts) {
    if (!a || typeof a.data !== "string") return json(400, { ok: false, error: "bad attachment" });
    const bytes = base64ToBytes(a.data);
    if (bytes.byteLength === 0) return json(400, { ok: false, error: "empty attachment" });
    if (bytes.byteLength > MAX_ATTACHMENT_BYTES) return json(413, { ok: false, error: "attachment over 5MB" });
    const mime = String(a.mime || "image/png").slice(0, 60);
    const key = `${datePath()}/${crypto.randomUUID()}.${extFor(mime)}`;
    atts.push({ key, bytes, mime, name: String(a.name || "screenshot.png").slice(0, 120) });
  }

  // 同 IP 限流（仅哈希入库，不存原始 IP）
  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  const ipHash = (await sha256Hex(ip)).slice(0, 32);
  const hit = await env.DB.prepare(
    `SELECT id FROM feedback WHERE ip_hash = ?1 AND created_at > datetime('now', '-${RATE_LIMIT_SECONDS} seconds') LIMIT 1`
  ).bind(ipHash).first();
  if (hit) return json(429, { ok: false, error: "rate limited, try later" });

  for (const a of atts) {
    await env.ATT.put(a.key, a.bytes, { httpMetadata: { contentType: a.mime } });
  }

  const attachmentsJson = JSON.stringify(atts.map(a => ({ key: a.key, name: a.name })));
  const ins = await env.DB.prepare(
    `INSERT INTO feedback (type, text, contact, app_version, channel, os_version, locale, entry, attachments, logs, ip_hash)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)`
  ).bind(type, text, contact, meta.appVersion, meta.channel, meta.osVersion, meta.locale, meta.entry, attachmentsJson, logs, ipHash).run();
  const id = (ins.meta && ins.meta.last_row_id) || 0;

  // 推送到手机（best-effort，失败不影响落库结果）
  try { await notify(request, env, { id, type, text, contact, meta, atts, logs }); } catch (_) {}

  return json(200, { ok: true, id });
}

// GET https://push.drel.app/<key>/<title>/<body> → 推送到手机
async function notify(request, env, f) {
  const origin = new URL(request.url).origin;
  const label = TYPES[f.type];
  const excerpt = f.text.replace(/\s+/g, " ").slice(0, 60) + (f.text.length > 60 ? "…" : "");
  const bits = [excerpt];
  if (f.meta.appVersion) bits.push(`${f.meta.appVersion}${f.meta.channel ? " · " + f.meta.channel : ""}`);
  if (f.contact) bits.push(`📮 ${f.contact}`);
  if (f.atts.length) bits.push(`📎 ${origin}/a/${f.atts[0].key}?token=${env.ADMIN_TOKEN}`);
  if (f.logs) bits.push("📋 含日志");
  const title = `QuiteNote 反馈 ${label} #${f.id}`;
  const body = bits.join(" | ");
  const url = `${env.PUSH_BASE}/${encodeURIComponent(title)}/${encodeURIComponent(body)}`;
  await fetch(url, { method: "GET" });
}

async function handleAttachment(url, env) {
  const token = url.searchParams.get("token") || "";
  if (!env.ADMIN_TOKEN || token !== env.ADMIN_TOKEN) return new Response("forbidden", { status: 403 });
  const key = url.pathname.slice(3);
  if (!key || key.includes("..")) return new Response("bad key", { status: 400 });
  const obj = await env.ATT.get(key);
  if (!obj) return new Response("not found", { status: 404 });
  return new Response(obj.body, {
    headers: {
      "Content-Type": (obj.httpMetadata && obj.httpMetadata.contentType) || "application/octet-stream",
      "Cache-Control": "private, max-age=86400",
    },
  });
}

async function handleList(url, env) {
  const token = url.searchParams.get("token") || "";
  if (!env.ADMIN_TOKEN || token !== env.ADMIN_TOKEN) return json(403, { ok: false, error: "forbidden" });
  const limit = Math.min(parseInt(url.searchParams.get("limit") || "20", 10) || 20, 100);
  const { results } = await env.DB.prepare(
    `SELECT id, created_at, type, substr(text, 1, 200) AS text, contact, app_version, channel, os_version, entry, attachments, length(logs) AS logs_len, substr(logs, 1, 400) AS logs_head
     FROM feedback ORDER BY id DESC LIMIT ?1`
  ).bind(limit).all();
  return json(200, { ok: true, count: results.length, feedback: results });
}

// —— 工具 ——
function base64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
async function sha256Hex(s) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, "0")).join("");
}
function datePath() {
  return new Date().toISOString().slice(0, 10).replace(/-/g, "/");
}
function extFor(mime) {
  if (mime.includes("jpeg") || mime.includes("jpg")) return "jpg";
  if (mime.includes("webp")) return "webp";
  if (mime.includes("gif")) return "gif";
  return "png";
}
