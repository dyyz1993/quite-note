#!/usr/bin/env python3
"""CI 签名公共库（tools/ci-signing.sh）的本地自检。

改过 tools/ci-signing.sh 或三个 workflow（build-macos / ui-smoke / release）里的钥匙串步骤后，
推送前跑一遍（需要 PyYAML：python3 -c "import yaml" 能过即可）：

    python3 tools/validate_ci_signing.py

做两件事（对应 AGENTS「改 workflow 推送前的两道本地验证」）：
  1. 整份 workflow 用 yaml.safe_load 能解析；
  2. 把钥匙串步骤的 run 段**原文**取出来，在 `bash --noprofile --norc -eo pipefail`（GitHub 的默认
     shell）下原样执行——`security` 换成只记录调用的桩，所以不碰本机钥匙串。
断言：security 调用序列（先清掉上一个 job 可能残留的同名钥匙串）、钥匙串密码用对位置、
codesign 分区、保留登录钥匙串的搜索列表、
APP_SIGN_IDENTITY 是 Developer ID 的 SHA-1（而不是名字或别的身份）、清理段只删临时钥匙串、
缺 secret / 找不到身份时失败、build-release.sh 的身份解析（传入优先，未传入回退按名字）。
"""
import os, sys, subprocess, tempfile, yaml, shutil, json

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
HASH = "0123456789ABCDEF0123456789ABCDEF01234567"
OTHER = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"
STUB = r'''#!/bin/bash
# security 桩：只记录调用；find-identity 返回两份身份，Developer ID 不是第一行——验证 awk 挑对了行
printf '%s\n' "security $*" >> "$STUB_LOG"
if [ "$1" = "find-identity" ]; then
  if [ -f "$STUB_NOIDENT" ]; then printf '  0 valid identities found\n'; exit 0; fi
  printf '  1) %s "Apple Development: somebody (ABCDE12345)"\n' "OTHER"
  printf '  2) %s "Developer ID Application: Test Dev (ABCDE12345)"\n     2 valid identities found\n' "HASH"
fi
exit 0
'''

def run_block(block, env_over, no_identity=False, drop=()):
    d = tempfile.mkdtemp(prefix="qn-ci-")
    os.makedirs(d + "/bin"); os.makedirs(d + "/rt"); os.makedirs(d + "/home")
    open(d + "/bin/security", "w").write(STUB.replace("OTHER", OTHER).replace("HASH", HASH))
    os.chmod(d + "/bin/security", 0o755)
    if no_identity:
        open(d + "/noident", "w").close()
    env = dict(os.environ)
    env.pop("APP_SIGN_IDENTITY", None)
    env.update(PATH=d + "/bin:" + os.environ["PATH"], RUNNER_TEMP=d + "/rt", GITHUB_ENV=d + "/env",
               GITHUB_WORKSPACE=REPO, HOME=d + "/home", STUB_LOG=d + "/calls.log", STUB_NOIDENT=d + "/noident")
    env.update(env_over)
    for k in drop:
        env.pop(k, None)
    # GitHub 默认 shell：bash --noprofile --norc -eo pipefail {0}
    p = subprocess.run(["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", block], env=env,
                       capture_output=True, text=True)
    calls = open(d + "/calls.log").read() if os.path.exists(d + "/calls.log") else ""
    genv = open(d + "/env").read() if os.path.exists(d + "/env") else ""
    shutil.rmtree(d)
    return p.returncode, calls.splitlines(), genv, p.stdout + p.stderr

def step(doc, job, name):
    for s in doc["jobs"][job]["steps"]:
        if s.get("name") == name:
            return s["run"]
    raise SystemExit(f"step not found: {job}/{name}")

ok = True
def check(cond, msg):
    global ok
    print(("PASS  " if cond else "FAIL  ") + msg)
    ok = ok and cond

expected_calls = [
    "security delete-keychain {RT}/qn-signing.keychain-db",
    "security create-keychain -p KEYCHAINPW {RT}/qn-signing.keychain-db",
    "security set-keychain-settings -lut 21600 {RT}/qn-signing.keychain-db",
    "security unlock-keychain -p KEYCHAINPW {RT}/qn-signing.keychain-db",
    "security import {RT}/qn-signing-certificate.p12 -P P12PW -A -t cert -f pkcs12 -k {RT}/qn-signing.keychain-db",
    "security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k KEYCHAINPW {RT}/qn-signing.keychain-db",
    "security list-keychains -d user -s {RT}/qn-signing.keychain-db {HOME}/Library/Keychains/login.keychain-db",
    "security find-identity -v -p codesigning {RT}/qn-signing.keychain-db",
]
cases = [
    ("build-macos.yml", "build-macos", "Prepare CI keychain for codesigning",
     {"QN_BUILD_CERTIFICATE_P12_BASE64": "Y2VydA==", "QN_BUILD_CERTIFICATE_PASSWORD": "P12PW"}),
    ("ui-smoke.yml", "build-dev-artifact", "Prepare CI keychain for codesigning",
     {"QN_UI_CERTIFICATE_P12_BASE64": "Y2VydA==", "QN_UI_CERTIFICATE_PASSWORD": "P12PW"}),
    ("release.yml", "release", "导入签名证书到临时钥匙串（job 结束销毁，不落盘）",
     {"MAC_CERTIFICATE_P12_BASE64": "Y2VydA==", "MAC_CERTIFICATE_PASSWORD": "P12PW", "KEYCHAIN_PASSWORD": "KEYCHAINPW"}),
]
for wf, job, name, env_over in cases:
    path = os.path.join(REPO, ".github/workflows", wf)
    doc = yaml.safe_load(open(path, encoding="utf-8"))          # 验证①
    check(isinstance(doc.get("jobs"), dict), f"{wf}: yaml.safe_load 解析通过")
    keychain_pw = env_over.get("KEYCHAIN_PASSWORD", env_over.get("QN_BUILD_CERTIFICATE_PASSWORD", env_over.get("QN_UI_CERTIFICATE_PASSWORD")))
    rc, calls, genv, out = run_block(step(doc, job, name), env_over)     # 验证②
    import re
    # 用占位比较：把随机临时目录抹掉（RUNNER_TEMP 在 <临时目录>/rt，HOME 在 <临时目录>/home）
    strip = lambda cs: [re.sub(r"/(private/)?var/folders/\S+?/qn-ci-[^/]+/", "{RT}/", c).replace("{RT}/rt/", "{RUNNER_TEMP}/").replace("{RT}/home/", "{HOME}/") for c in cs]
    # 这两个 workflow 按设计用 p12 密码兼作钥匙串密码；release 用独立的 KEYCHAIN_PASSWORD
    expected = [c.replace("KEYCHAINPW", keychain_pw).replace("{RT}/", "{RUNNER_TEMP}/") for c in expected_calls]
    check(rc == 0, f"{wf}: prepare 的 run 段退出码 0（实际 {rc}）{out.strip()[-300:] if rc else ''}")
    check(strip(calls) == expected, f"{wf}: security 调用序列与预期一致（钥匙串密码、codesign 分区、保留登录钥匙串、按 SHA-1 解析）" + ("" if strip(calls) == expected else f"\n      实际: {strip(calls)}\n      预期: {expected}"))
    check(f"APP_SIGN_IDENTITY={HASH}\n" in genv, f"{wf}: GITHUB_ENV 写入的是 Developer ID 的 SHA-1（不是名字、不是第一行的 Apple Development）")
    # 清理段
    rc2, calls2, _, out2 = run_block(step(doc, job, [s for s in doc["jobs"][job]["steps"] if "leanup" in s.get("name", "") or "清理" in s.get("name", "")][0]["name"]), {})
    check(rc2 == 0 and len(calls2) == 1 and calls2[0].startswith("security delete-keychain ") and calls2[0].endswith("/qn-signing.keychain-db"), f"{wf}: 清理段只删临时钥匙串")

# 失败路径
doc = yaml.safe_load(open(os.path.join(REPO, ".github/workflows/release.yml"), encoding="utf-8"))
blk = step(doc, "release", "导入签名证书到临时钥匙串（job 结束销毁，不落盘）")
rc, calls, genv, out = run_block(blk, {"MAC_CERTIFICATE_P12_BASE64": "", "MAC_CERTIFICATE_PASSWORD": "P12PW", "KEYCHAIN_PASSWORD": "KEYCHAINPW"})
check(rc != 0 and "::error::" in out and calls == [], "缺 secret：报 ::error:: 且不碰 security")
rc, calls, genv, out = run_block(blk, {"MAC_CERTIFICATE_P12_BASE64": "Y2VydA==", "MAC_CERTIFICATE_PASSWORD": "P12PW", "KEYCHAIN_PASSWORD": "KEYCHAINPW"}, no_identity=True)
check(rc != 0 and "APP_SIGN_IDENTITY" not in genv and "::error::" in out, "钥匙串里没有 Developer ID：失败且不写 APP_SIGN_IDENTITY")

# build-release.sh 的身份解析行：传入优先，未传入回退按名字
line = [l for l in open(os.path.join(REPO, "build-release.sh"), encoding="utf-8").read().splitlines() if l.startswith("SIGN_IDENTITY=")][0]
d = tempfile.mkdtemp(prefix="qn-ci-"); os.makedirs(d + "/bin")
open(d + "/bin/security", "w").write(STUB.replace("HASH", HASH).replace("OTHER", "OTHER")); os.chmod(d + "/bin/security", 0o755)
env = dict(os.environ, PATH=d + "/bin:" + os.environ["PATH"], STUB_LOG=d + "/log")
r1 = subprocess.run(["bash", "-c", line + '; printf "%s" "$SIGN_IDENTITY"'], env=dict(env, APP_SIGN_IDENTITY=HASH), capture_output=True, text=True).stdout
r2 = subprocess.run(["bash", "--noprofile", "--norc", "-c", 'unset APP_SIGN_IDENTITY; ' + line + '; printf "%s" "$SIGN_IDENTITY"'], env=env, capture_output=True, text=True).stdout
check(r1 == HASH, "build-release.sh：CI 传入 APP_SIGN_IDENTITY 时原样使用")
check(r2 == "Developer ID Application: Test Dev (ABCDE12345)", "build-release.sh：未传入时回退按名字查找（本机手动发版路径不变）")
shutil.rmtree(d)
print("\nALL PASS" if ok else "\nSOME FAILED"); sys.exit(0 if ok else 1)
