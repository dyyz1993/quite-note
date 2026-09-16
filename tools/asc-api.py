#!/usr/bin/env python3
"""ASC API 命令行——App Store Connect 官方 REST API 封装（ES256 JWT 认证，零外部依赖）。

用法：
  python3 asc-api.py get  /v1/apps/6802559186
  python3 asc-api.py versions 6802559186           # 各平台版本状态一览
  python3 asc-api.py submissions 6802559186         # 审核提交记录
  python3 asc-api.py shots 6802559186 [versionId]   # 截图清单（含上传/处理状态）

凭据（默认值适用于本机；环境变量可覆盖）：
  ASC_KEY_ID     默认 4NXJ8HL7K9（提交/元数据用）
  ASC_ISSUER_ID  默认 18f47979-0b65-4045-b969-00ba54177716
  ASC_KEY_PATH   默认 ~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8
"""
import base64
import json
import os
import sys
import time
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

KEY_ID = os.environ.get("ASC_KEY_ID", "4NXJ8HL7K9")
ISSUER = os.environ.get("ASC_ISSUER_ID", "18f47979-0b65-4045-b969-00ba54177716")
KEY_PATH = os.environ.get(
    "ASC_KEY_PATH",
    os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"),
)
API = "https://api.appstoreconnect.apple.com"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def make_token(ttl: int = 1200) -> str:
    with open(KEY_PATH, "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)
    header = b64url(json.dumps({"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}).encode())
    payload = b64url(json.dumps({
        "iss": ISSUER, "exp": int(time.time()) + ttl, "aud": "appstoreconnect-v1",
    }).encode())
    signing_input = f"{header}.{payload}".encode()
    der = key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    # DER → JWS raw (r||s 各 32 字节)。INTEGER 可能带 0x00 前缀填充（33 字节），
    # 游标必须按实际长度推进——坑：n 调整后仍用原长度推进会 off-by-one
    i, vals = 2, []
    while i < len(der) and len(vals) < 2:
        assert der[i] == 0x02, f"expect INTEGER at {i}"
        n = der[i + 1]
        vals.append(int.from_bytes(der[i + 2:i + 2 + n], "big"))
        i += 2 + n
    r, s = vals
    sig = b64url(r.to_bytes(32, "big") + s.to_bytes(32, "big"))
    return f"{header}.{payload}.{sig}"


def asc(method: str, path: str, body=None):
    req = urllib.request.Request(
        API + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={
            "Authorization": f"Bearer {make_token()}",
            "Content-Type": "application/json",
        },
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        return {"httpError": e.code, "detail": e.read().decode()[:500]}


def cmd_versions(app_id: str):
    out = asc("GET", f"/v1/apps/{app_id}/appStoreVersions?limit=10&fields[appStoreVersions]=versionString,appStoreState,platform,createdDate")
    for v in out.get("data", []):
        a = v["attributes"]
        print(f"{a.get('platform','?'):12} {a.get('versionString','?'):10} {a.get('appStoreState','?'):20} id={v['id']}")
    if "httpError" in out:
        print(json.dumps(out, ensure_ascii=False)[:400])


def cmd_submissions(app_id: str):
    # 关系端点在 app 上不存在——先拿版本 id 再过滤顶层 submissions
    vs = asc("GET", f"/v1/apps/{app_id}/appStoreVersions?limit=10&fields[appStoreVersions]=versionString")
    ids = ",".join(v["id"] for v in vs.get("data", []))
    out = asc("GET", f"/v1/appStoreVersionSubmissions?filter[appStoreVersion]={ids}&limit=5&include=appStoreVersion&fields[appStoreVersion]=versionString,state")
    inc = {i["id"]: i.get("attributes", {}) for i in out.get("included", [])}
    for s in out.get("data", []):
        ver = (s.get("relationships", {}).get("appStoreVersion", {}).get("data", {}) or {})
        va = inc.get(ver.get("id", ""), {})
        print(f"提交 id={s['id']} 创建={s.get('attributes',{}).get('createdDate','?')} → 版本 {va.get('versionString','?')} [{va.get('appStoreState','?')}]")
    if "httpError" in out:
        print(json.dumps(out, ensure_ascii=False)[:400])


def cmd_shots(app_id: str, version_id=None):
    if not version_id:
        vs = asc("GET", f"/v1/apps/{app_id}/appStoreVersions?limit=10&fields[appStoreVersions]=versionString,appStoreState,platform")
        cands = [v for v in vs.get("data", []) if v["attributes"].get("appStoreState") in ("PREPARE_FOR_SUBMISSION", "WAITING_FOR_REVIEW", "DEVELOPER_REJECTED", "REJECTED")]
        if not cands:
            print("无可操作版本"); return
        version_id = cands[0]["id"]
        print(f"自动选中版本 id={version_id} ({cands[0]['attributes'].get('versionString')})")
    out = asc("GET", f"/v1/appStoreVersions/{version_id}/appScreenshots?limit=30&fields[appScreenshots]=fileName,fileSize,assetDeliveryState,uploaded")
    for s in out.get("data", []):
        a = s["attributes"]
        st = a.get("assetDeliveryState", {}).get("state", "?")
        print(f"{a.get('fileName','?'):40} {a.get('fileSize',0)/1e6:.1f}MB  {st}")
    if "httpError" in out:
        print(json.dumps(out, ensure_ascii=False)[:400])


def main():
    if len(sys.argv) < 3:
        print(__doc__); return 1
    cmd, arg = sys.argv[1], sys.argv[2]
    if cmd == "get":
        print(json.dumps(asc("GET", arg), ensure_ascii=False, indent=1)[:2000])
    elif cmd == "versions":
        cmd_versions(arg)
    elif cmd == "submissions":
        cmd_submissions(arg)
    elif cmd == "shots":
        cmd_shots(arg, sys.argv[3] if len(sys.argv) > 3 else None)
    else:
        print(__doc__); return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
