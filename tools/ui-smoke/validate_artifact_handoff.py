#!/usr/bin/env python3
"""本地验证 CI 提速改动里新加 / 改过的 run 段（项目规矩：改 workflow 的 run 段，推送前用 PyYAML
取出原文、原样执行一遍，不手抄）。覆盖：

  ui-smoke.yml   构建 job：Package artifact（多写一个 job 输出）→ 把产物经局域网交给测试机
                 冒烟 job：取产物（局域网副本优先）→ Verify artifact；局域网副本缺失时回退到 GitHub 下载
  build-macos.yml 安装 ImageMagick 的守卫（装过就不再碰 brew）
  test.yml       单测命令带 --scratch-path，且不再有 actions/cache 步骤

"测试机"用假 HOME 下的一个目录冒充，ssh / scp 用 PATH 上的两个桩替代（桩只认本脚本约定的
两个环境变量），所以整段离线、可重复、不会碰真机器。
用法：validate_artifact_handoff.py [仓库根目录]（默认取本文件所在的仓库）
"""
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

repo = (Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]).resolve()
wf_dir = repo / ".github" / "workflows"
ui = yaml.safe_load((wf_dir / "ui-smoke.yml").read_text())
tests = yaml.safe_load((wf_dir / "test.yml").read_text())
build = yaml.safe_load((wf_dir / "build-macos.yml").read_text())
print("✓ 三份 workflow 都能被 PyYAML 解析")


def step(job, name):
    for s in job["steps"]:
        if s.get("name") == name:
            return s
    raise SystemExit(f"找不到步骤 {name}")


def sh(cmd, cwd, env, check=True):
    r = subprocess.run(cmd, cwd=str(cwd), env=env, capture_output=True, text=True)
    if check and r.returncode != 0:
        print(r.stdout[-1500:], r.stderr[-1500:])
        raise SystemExit(f"命令失败: {cmd}")
    return r


tmp = Path(tempfile.mkdtemp(prefix="qn-handoff-"))
fake_home = tmp / "home"                      # 冒充测试机的 HOME
remote_dir = fake_home / "QuitenoteUITest" / "artifacts"
remote_dir.mkdir(parents=True)
fake_bin = tmp / "bin"                        # ssh / scp 桩
fake_bin.mkdir()

FAKE_DIR = "/Users/fake/QuitenoteUITest/artifacts"   # 步骤里写的测试机目录，在桩里映射到冒充目录
# ssh 桩：最后一个参数是远端命令，把其中的测试机目录换成冒充目录后在本机执行
(fake_bin / "ssh").write_text(f"""#!/bin/sh
for a in "$@"; do last="$a"; done
cmd="$(printf '%s' "$last" | sed 's#{FAKE_DIR}#{remote_dir}#g')"
exec /bin/sh -c "$cmd"
""")
# scp 桩：最后一个参数是 host:path，把前面的文件拷进冒充目录里对应的 path
(fake_bin / "scp").write_text(f"""#!/bin/sh
for a in "$@"; do last="$a"; done
target="${{last#*:}}"
target="${{target#{FAKE_DIR}}}"
mkdir -p "{remote_dir}/$(dirname "$target")"
for a in "$@"; do
  case "$a" in -*) ;; *:*) ;; *) cp "$a" "{remote_dir}/$target" ;; esac
done
""")
for f in fake_bin.iterdir():
    f.chmod(f.stat().st_mode | stat.S_IXUSR)

# 冒充构建机的工作区：一个假的 "Quite Note Dev.app"
work = tmp / "work"
(work / "Quite Note Dev.app" / "Contents" / "MacOS").mkdir(parents=True)
(work / "Quite Note Dev.app" / "Contents" / "MacOS" / "QuiteNoteDev").write_text("#!/bin/sh\necho fake\n")

env = dict(os.environ,
           PATH=f"{fake_bin}:{os.environ['PATH']}",
           GITHUB_SHA="0123456789abcdef0123456789abcdef01234567",
           GITHUB_ENV=str(tmp / "github_env.txt"), GITHUB_OUTPUT=str(tmp / "github_output.txt"),
           RUNNER_TEMP=str(tmp / "runner_temp"), HOME=str(fake_home),
           UI_SMOKE_HOST="fake-test-mac", UI_SMOKE_DIR=FAKE_DIR)
for name in ("github_env.txt", "github_output.txt"):
    (tmp / name).write_text("")
(tmp / "runner_temp").mkdir()

build_job = ui["jobs"]["build-dev-artifact"]
smoke_job = ui["jobs"]["remote-ui-smoke"]
# 接线断言：job 输出 ← package 步骤输出；下载步骤只在没拿到局域网副本时跑
assert build_job.get("outputs", {}).get("artifact") == "${{ steps.package.outputs.artifact }}", build_job.get("outputs")
assert step(build_job, "Package artifact").get("id") == "package"
handoff = step(build_job, "把产物经局域网交给测试机")
assert handoff.get("continue-on-error") is True, "局域网交付出错不应拦住构建 job"
assert step(smoke_job, "取产物（局域网副本优先）").get("id") == "fetch"
downloads = [s for s in smoke_job["steps"] if s.get("uses", "").startswith("actions/download-artifact")]
assert len(downloads) == 1 and downloads[0].get("if") == "steps.fetch.outputs.source != 'lan'", downloads
print("✓ 接线正确：job 输出 ← package 步骤；局域网交付失败不拦 job；下载步骤带回退条件")

sh(["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", step(build_job, "Package artifact")["run"]], work, env)
github_env = dict(l.split("=", 1) for l in (tmp / "github_env.txt").read_text().splitlines() if "=" in l)
github_out = dict(l.split("=", 1) for l in (tmp / "github_output.txt").read_text().splitlines() if "=" in l)
artifact = f"QuiteNoteDev-{env['GITHUB_SHA'][:8]}-universal.zip"
assert github_env["UI_ARTIFACT"] == artifact and github_out["artifact"] == artifact, (github_env, github_out)
assert (work / artifact).is_file() and (work / f"{artifact}.sha256").is_file()
env["UI_ARTIFACT"] = github_env["UI_ARTIFACT"]
print("✓ Package artifact：产出 zip + sha256，并写了 GITHUB_ENV 和 job 输出")

sh(["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", handoff["run"]], work, env)
assert (remote_dir / artifact).is_file() and (remote_dir / f"{artifact}.sha256").is_file(), list(remote_dir.iterdir())
print("✓ 局域网交付：产物和校验文件到了测试机的 artifacts 目录，远端校验和步骤也执行了")

fetch_env = dict(env, ARTIFACT_NAME=artifact, GITHUB_OUTPUT=str(tmp / "fetch_output.txt"))
(tmp / "fetch_output.txt").write_text("")
sh(["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", step(smoke_job, "取产物（局域网副本优先）")["run"]],
   tmp, fetch_env)
fetch_out = dict(l.split("=", 1) for l in (tmp / "fetch_output.txt").read_text().splitlines() if "=" in l)
assert fetch_out.get("source") == "lan", fetch_out
verify = sh(["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", step(smoke_job, "Verify artifact")["run"]], tmp, env)
assert f"{artifact}: OK" in verify.stdout, verify.stdout
print("✓ 冒烟 job 取产物：source=lan（跳过 GitHub 下载），原样的 Verify artifact 校验通过")

# 回退分支：测试机上没有局域网副本
for f in remote_dir.iterdir():
    f.unlink()
shutil.rmtree(tmp / "runner_temp" / "ui-artifact")
(tmp / "fetch_output.txt").write_text("")
out = sh(["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", step(smoke_job, "取产物（局域网副本优先）")["run"]],
         tmp, fetch_env).stdout
fetch_out = dict(l.split("=", 1) for l in (tmp / "fetch_output.txt").read_text().splitlines() if "=" in l)
assert fetch_out.get("source") == "github" and "改从 GitHub 下载" in out, (fetch_out, out)
print("✓ 回退分支：局域网副本不存在时 source=github，由 actions/download-artifact 接手")

# build-macos.yml：ImageMagick 守卫（本机已装，应直接跳过 brew）
out = sh(["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", step(build["jobs"]["build-macos"], "安装ImageMagick（用于图标转换）")["run"]], tmp, env).stdout
assert "已安装" in out, out
assert "构建Release版本" not in [s.get("name") for s in build["jobs"]["build-macos"]["steps"]], "重复的预构建步骤应已删除"
print("✓ build-macos：ImageMagick 守卫生效（本机已装，未碰 brew），重复的预构建步骤已删除")

# test.yml：单测命令带外置 scratch path，且不再还原 .build 缓存
utests = tests["jobs"]["unit-tests"]
names = [s.get("name") or s.get("uses") for s in utests["steps"]]
assert not any((n or "").startswith("actions/cache") for n in names), names
assert "--scratch-path /Users/xuyingzhou/runners/qn-build/debug-tests" in step(utests, "运行全部单元测试")["run"]
print("✓ test.yml：去掉了 actions/cache，单测命令指向常驻的 scratch 目录")

shutil.rmtree(tmp)
print("全部通过")
