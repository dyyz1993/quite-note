#!/usr/bin/env python3
"""本地验证 SwiftPM 依赖预热的收拢改动（项目规矩：改 workflow 的 run 段，推送前用 PyYAML
取出原文、原样执行一遍，不手抄）。覆盖：

  ui-smoke.yml / test.yml / build-macos.yml 三份的预热步骤都是调用
  tools/ci-prewarm-swiftpm.sh（接线断言 + 旧内联拷贝的标志物不得残留）；
  三份 workflow 的预热 run 段在假 HOME + 假源目录（QN_SWIFTPM_CACHE_SRC /
  QN_SPARKLE_MIRROR 指到临时目录）下原样执行，三种场景：
    ① 热缓存 + 有镜像：统计行计数正确、有 "Sparkle artifact primed from mirror"、无注解；
    ② 冷缓存（源目录缺失 / repositories 为空）：输出 ::warning 注解、统计行带 [cold]；
    ③ 镜像文件缺失：不报错、不拦 job，只是没有 Sparkle 那行；
  ui-smoke.yml 的 Build universal Dev app 步骤用 swift 桩原样执行（不真跑 swift build）：
    成功路径走到 build-app.sh；swift build 失败路径打印退出码 + 产物诊断并以同一码退出；
    产物缺失路径打印候选路径和 .build 顶层列表后退出 1。

整段离线、可重复、只写临时目录。用法：validate_swiftpm_prewarm.py [仓库根目录]
"""
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

repo = (Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]).resolve()
wf_dir = repo / ".github" / "workflows"
docs = {n: yaml.safe_load((wf_dir / f"{n}.yml").read_text()) for n in ("ui-smoke", "test", "build-macos")}
print("✓ 三份 workflow 都能被 PyYAML 解析")


def step(doc, job, name):
    for s in doc["jobs"][job]["steps"]:
        if s.get("name") == name:
            return s
    raise SystemExit(f"找不到步骤 {job}/{name}")


def sh(cmd, cwd, env):
    r = subprocess.run(cmd, cwd=str(cwd), env=env, capture_output=True, text=True)
    return r


# ---------- 接线断言：三份预热步骤都改成调用脚本，旧内联拷贝的标志物不得残留 ----------
PREWARM = "预热 SwiftPM 依赖缓存（自托管）"
prewarm_steps = {
    "ui-smoke": step(docs["ui-smoke"], "build-dev-artifact", PREWARM)["run"],
    "test": step(docs["test"], "unit-tests", PREWARM)["run"],
    "build-macos": step(docs["build-macos"], "build-macos", PREWARM)["run"],
}
for wf, run in prewarm_steps.items():
    assert 'source "$GITHUB_WORKSPACE/tools/ci-prewarm-swiftpm.sh"' in run, (wf, run)
    assert "ci_swiftpm_prewarm" in run, (wf, run)
    for marker in ("rsync", "org.swift.swiftpm", "SPARKLE_KEY", "SwiftPM cache primed"):
        assert marker not in run, f"{wf}: 预热 run 段仍有内联残留 {marker!r}: {run}"
print("✓ 接线正确：三份 workflow 的预热步骤都是 source 脚本 + ci_swiftpm_prewarm，无内联残留")

# ---------- 假环境：假 HOME、假源缓存、假镜像（QN_SWIFTPM_CACHE_SRC / QN_SPARKLE_MIRROR 指过去） ----------
tmp = Path(tempfile.mkdtemp(prefix="qn-prewarm-"))
KEY_NEW = "https___github_com_sparkle_project_Sparkle_releases_download_2_10_0_Sparkle_for_Swift_Package_Manager_zip"
KEY_LEGACY = "https_58__47__47_github_46_com_47_sparkle_45_project_47_Sparkle_47_releases_47_download_47_2_46_10_46_0_47_Sparkle_45_for_45_Swift_45_Package_45_Manager_46_zip"


def make_source(repos, artifacts):
    src = tmp / f"src-{repos}-{artifacts}"
    (src / "repositories").mkdir(parents=True)
    (src / "artifacts").mkdir(parents=True)
    for i in range(repos):
        (src / "repositories" / f"repo-{i}").mkdir()
    for i in range(artifacts):
        (src / "artifacts" / f"artifact-{i}").write_bytes(b"x")
    return src


def make_mirror(name="mirror"):
    p = tmp / name
    p.write_bytes(b"sparkle-zip-bytes")
    return p


def run_prewarm_segment(run, src, mirror):
    home = tmp / f"home-{abs(hash((str(src), str(mirror)))) % 10**10}"
    home.mkdir(exist_ok=True)
    env = dict(os.environ, GITHUB_WORKSPACE=str(repo), HOME=str(home),
               QN_SWIFTPM_CACHE_SRC=str(src), QN_SPARKLE_MIRROR=str(mirror))
    # GitHub 默认 shell：bash --noprofile --norc -eo pipefail {0}
    return sh(["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", run], tmp, env), home


# ---------- 场景①：热缓存 + 有镜像 ----------
src_hot = make_source(repos=3, artifacts=2)
mirror = make_mirror()
for wf, run in prewarm_steps.items():
    r, home = run_prewarm_segment(run, src_hot, mirror)
    assert r.returncode == 0, (wf, r.returncode, r.stdout, r.stderr)
    out = r.stdout + r.stderr
    assert "SwiftPM cache primed: 3 repos, 4 artifacts" in out, (wf, out)   # 源 2 个 artifact + 镜像 2 个 key
    assert "Sparkle artifact primed from mirror" in out, (wf, out)
    assert "::warning" not in out and "cold" not in out, (wf, out)
    dst = home / "Library" / "Caches" / "org.swift.swiftpm"
    assert len(list((dst / "repositories").iterdir())) == 3, (wf, list((dst / "repositories").iterdir()))
    assert (dst / "artifacts" / KEY_NEW).read_bytes() == b"sparkle-zip-bytes", (wf, "镜像内容不对")
    assert (dst / "artifacts" / KEY_LEGACY).is_file(), (wf, "旧 mangle key 没灌")
print("✓ 场景① 热缓存+有镜像：3 repos / 4 artifacts（源 2 + 镜像 2），镜像灌进两个 key，无注解、无 cold")

# ---------- 场景②：冷缓存（源目录缺失 / repositories 为空）→ ::warning + [cold] ----------
for label, src_cold in (("源目录缺失", tmp / "src-missing"), ("repositories 为空", make_source(repos=0, artifacts=1))):
    for wf, run in prewarm_steps.items():
        r, home = run_prewarm_segment(run, src_cold, mirror)
        assert r.returncode == 0, (wf, label, r.returncode, r.stdout, r.stderr)
        out = r.stdout + r.stderr
        assert "::warning title=SwiftPM 缓存为空::" in out, (wf, label, out)
        assert "先重跑" in out, (wf, label, out)
        assert "[cold]" in out and "SwiftPM cache primed: 0 repos" in out, (wf, label, out)
        # 冷缓存时镜像段照常工作（免掉 Sparkle 的网络下载），也不拦 job
        assert "Sparkle artifact primed from mirror" in out, (wf, label, out)
        assert (home / "Library" / "Caches" / "org.swift.swiftpm" / "artifacts" / KEY_NEW).is_file(), (wf, label)
print("✓ 场景② 冷缓存（源缺失 / repositories 空）：::warning 注解 + 统计行带 [cold]，镜像段照常，job 不拦")

# ---------- 场景③：镜像文件缺失 → 不报错、不拦 ----------
missing_mirror = tmp / "no-such-mirror.zip"
for wf, run in prewarm_steps.items():
    r, home = run_prewarm_segment(run, src_hot, missing_mirror)
    assert r.returncode == 0, (wf, r.returncode, r.stdout, r.stderr)
    out = r.stdout + r.stderr
    assert "SwiftPM cache primed: 3 repos, 2 artifacts" in out, (wf, out)
    assert "Sparkle artifact primed from mirror" not in out, (wf, out)
    assert "::warning" not in out, (wf, out)
print("✓ 场景③ 镜像缺失：不报错、不拦 job，统计行只计源缓存的 2 个 artifact")

# ---------- Build universal Dev app 步骤：swift 桩执行包装逻辑（不真跑 swift build） ----------
build_run = step(docs["ui-smoke"], "build-dev-artifact", "Build universal Dev app")["run"]
fake_bin = tmp / "stub-bin"
fake_bin.mkdir()
(fake_bin / "swift").write_text('''#!/bin/bash
# swift 桩：按 STUB_SWIFT_RC 退出；STUB_SWIFT_OUT 指定产物布局（none=不产产物）
echo "stub swift build $*"
rc="${STUB_SWIFT_RC:-0}"
out="${STUB_SWIFT_OUT:-apple}"
if [ "$out" != "none" ]; then
  mkdir -p ".build/$out/Products/Release"
  : > ".build/$out/Products/Release/QuiteNote"
fi
echo "Build complete! (stub)"
exit "$rc"
''')
(fake_bin / "swift").chmod((fake_bin / "swift").stat().st_mode | stat.S_IXUSR)
build_app_log = tmp / "build-app-calls.log"
work = tmp / "work"
work.mkdir()
(work / "build-app.sh").write_text(f'''#!/bin/bash
echo "build-app.sh $*" >> "{build_app_log}"
''')
(work / "build-app.sh").chmod((work / "build-app.sh").stat().st_mode | stat.S_IXUSR)
build_env = dict(os.environ, PATH=f"{fake_bin}:{os.environ['PATH']}",
                 APP_SIGN_IDENTITY="0123456789ABCDEF0123456789ABCDEF01234567",
                 BUILD_APP_LOG=str(build_app_log))


def run_build_step(**stub_env):
    build_app_log.write_text("")
    shutil.rmtree(work / ".build", ignore_errors=True)
    env = dict(build_env, **{k: str(v) for k, v in stub_env.items()})
    return sh(["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", build_run], work, env), build_app_log.read_text()


# 成功路径：产物在老 SwiftPM 布局 → 继续往下走到 build-app.sh
r, calls = run_build_step()
assert r.returncode == 0, (r.returncode, r.stdout, r.stderr)
assert "swift build exit code: 0" in r.stdout, r.stdout
assert calls == "build-app.sh --dev --no-build --no-launch\n", repr(calls)
print("✓ Build 步骤·成功路径（.build/apple 布局）：swift build 退出码 0，继续走到 build-app.sh")

# 成功路径：产物在新 swiftbuild 布局（.build/out/…）→ 候选探测命中第二个
r, calls = run_build_step(STUB_SWIFT_OUT="out")
assert r.returncode == 0, (r.returncode, r.stdout, r.stderr)
assert calls == "build-app.sh --dev --no-build --no-launch\n", repr(calls)
print("✓ Build 步骤·成功路径（.build/out 布局）：候选探测命中，build-app.sh 照常被调")

# 失败路径：swift build 以 42 退出 → 打印退出码 + 产物诊断，并以同一个 42 退出
r, calls = run_build_step(STUB_SWIFT_RC=42)
assert r.returncode == 42, (r.returncode, r.stdout)
assert "swift build exit code: 42" in r.stdout, r.stdout
assert "产物目录" in r.stdout, r.stdout
assert calls == "", repr(calls)  # 失败时绝不能再往下走 build-app.sh
# 失败路径：退出码 1（2026-11-28 事故同款）→ 同样有声 + 原码退出
r, _ = run_build_step(STUB_SWIFT_RC=1)
assert r.returncode == 1, (r.returncode, r.stdout)
assert "swift build exit code: 1" in r.stdout and "产物目录" in r.stdout, r.stdout
print("✓ Build 步骤·swift build 失败（退出 42 / 1）：打印退出码与产物目录，以同一码退出，不再往下走")

# 产物缺失路径：swift build 成功但没产物 → 候选路径 + .build 顶层列表 + 退出 1
r, calls = run_build_step(STUB_SWIFT_OUT="none")
assert r.returncode == 1, (r.returncode, r.stdout)
assert "universal binary not found in .build" in r.stdout, r.stdout
assert "候选路径" in r.stdout and ".build 顶层" in r.stdout, r.stdout
assert calls == "", repr(calls)
print("✓ Build 步骤·产物缺失：打印候选路径与 .build 顶层列表后退出 1")

shutil.rmtree(tmp)
print("全部通过")
