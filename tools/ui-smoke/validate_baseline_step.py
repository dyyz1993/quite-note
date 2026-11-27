#!/usr/bin/env python3
"""本地验证 UI 冒烟工作流里"基线快照"那一步（项目规矩：改 workflow 的 run 段，推送前用 PyYAML
取出原文、原样执行一遍，不手抄）。

做法：用一个本地裸仓库冒充 GitHub 的 gh-pages，把步骤里的克隆 / 推送地址重定向到它
（git 的 url.insteadOf，经 GIT_CONFIG_* 环境变量注入，步骤原文一字不改），然后：
  1. 原样执行步骤 → 断言新基线目录 + latest.json 已推上去、旧基线目录原样保留；
  2. 断言克隆下来的仓库里没有旧截图的文件内容（稀疏 + blob:none 生效）；
  3. 再执行一遍 → 断言输出"基线无变化"，远端提交数不变（幂等）。
顺带断言两份 workflow 的触发器：push 只在 main / master，pull_request 保留。
用法：validate_baseline_step.py [仓库根目录]（默认取本文件所在的仓库）
"""
import base64
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

repo = (Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]).resolve()
workflows = repo / ".github" / "workflows"
ui = yaml.safe_load((workflows / "ui-smoke.yml").read_text())
tests = yaml.safe_load((workflows / "test.yml").read_text())

# 触发器：push 只在主干，PR 分支只跑 pull_request 那一套
for name, wf in (("ui-smoke.yml", ui), ("test.yml", tests)):
    trig = wf[True] if True in wf else wf["on"]  # PyYAML 把 on 读成布尔 True
    branches = trig["push"]["branches"]
    assert branches == ["main", "master"], (name, branches)
    assert "pull_request" in trig, name
print("✓ 两份 workflow 都能解析；push 触发只限 main/master，pull_request 触发保留")


def find_run(wf, step_name):
    for job in wf["jobs"].values():
        for step in job.get("steps", []):
            if step.get("name") == step_name:
                return step["run"], step.get("if")
    raise SystemExit(f"找不到步骤 {step_name}")


run_block, step_if = find_run(ui, "Snapshot UI baseline (PASS only)")
assert step_if == "success()"


def sh(*args, cwd=None, env=None, check=True):
    result = subprocess.run(args, cwd=str(cwd) if cwd else None, env=env,
                            capture_output=True, text=True)
    if check and result.returncode != 0:
        print(result.stdout[-2000:], result.stderr[-2000:])
        raise SystemExit(f"命令失败: {args}")
    return result


tmp = Path(tempfile.mkdtemp(prefix="qn-snap-"))
remote = tmp / "remote.git"
sh("git", "init", "-q", "--bare", str(remote))
sh("git", "-C", str(remote), "config", "uploadpack.allowFilter", "true")

seed = tmp / "seed"
sh("git", "clone", "-q", str(remote), str(seed))
author = ("-c", "user.name=t", "-c", "user.email=t@example.com")


def seed_git(*args):
    sh("git", "-C", str(seed), *author, *args)


seed_git("checkout", "-q", "-b", "gh-pages")
old_shots = []
for name in ("1.2.0-aaaaaaaa", "1.2.0-bbbbbbbb"):
    d = seed / "ui-baseline" / name
    d.mkdir(parents=True)
    for i in range(3):
        p = d / f"shot-{i}.png"
        p.write_bytes(os.urandom(200_000))
        old_shots.append(p)
(seed / "ui-baseline" / "latest.json").write_text(json.dumps({"name": "1.2.0-bbbbbbbb"}))
(seed / "appcast.xml").write_text("<rss/>")
seed_git("add", "-A")
seed_git("commit", "-q", "-m", "seed")
for i in range(2):
    (seed / "appcast.xml").write_text(f"<rss>{i}</rss>")
    seed_git("add", "-A")
    seed_git("commit", "-q", "-m", f"c{i}")
seed_git("push", "-q", "origin", "gh-pages")
old_blob = sh("git", "-C", str(seed), "rev-parse", "HEAD:ui-baseline/1.2.0-aaaaaaaa/shot-0.png").stdout.strip()
remote_commits = sh("git", "-C", str(remote), "rev-list", "--count", "gh-pages").stdout.strip()
assert remote_commits == "3", remote_commits

# 冒烟 run 目录（步骤里 find tools/ui-smoke/runs/ui-* 找的就是它）
run_dir = tmp / "work/tools/ui-smoke/runs/ui-20260101-000000-01234567"
(run_dir / "screenshots").mkdir(parents=True)
shutil.copy(repo / "tools/ui-smoke/snapshot_ui_baseline.py", run_dir.parent.parent / "snapshot_ui_baseline.py")
png = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")
(run_dir / "screenshots" / "launch-1.png").write_bytes(png)
(run_dir / "screenshots" / "cleanup-2.png").write_bytes(png)
(run_dir / "manifest.json").write_text(json.dumps({"suite_version": "9.9.9", "git_commit": "0123456789abcdef0123456789abcdef01234567"}))
(run_dir / "report.json").write_text(json.dumps({"status": "PASS"}))
(run_dir / "report.md").write_text("# ok\n")
(run_dir / "timeline.jsonl").write_text("{}\n")
runner_temp = tmp / "runner_temp"
runner_temp.mkdir()

env = dict(os.environ,
           GITHUB_TOKEN="dummytoken", REPO="owner/repo",
           GITHUB_SHA="0123456789abcdef0123456789abcdef01234567",
           RUNNER_TEMP=str(runner_temp),
           GIT_CONFIG_COUNT="1",
           GIT_CONFIG_KEY_0=f"url.file://{remote}.insteadOf",
           GIT_CONFIG_VALUE_0="https://x-access-token:dummytoken@github.com/owner/repo.git")


def run_step():
    # GitHub 的默认 shell：bash --noprofile --norc -eo pipefail
    return sh("bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", run_block,
              cwd=tmp / "work", env=env)


out1 = run_step().stdout
assert "基线已推送到 gh-pages" in out1, out1[-800:]

files = sh("git", "-C", str(remote), "ls-tree", "-r", "--name-only", "gh-pages").stdout.split()
new_dir = "ui-baseline/9.9.9-01234567/"
added = sorted(f[len(new_dir):] for f in files if f.startswith(new_dir))
assert added == ["cleanup-2.png", "launch-1.png", "manifest.json", "report.json", "report.md", "timeline.jsonl"], added
for name in ("1.2.0-aaaaaaaa", "1.2.0-bbbbbbbb"):
    for i in range(3):
        assert f"ui-baseline/{name}/shot-{i}.png" in files, (name, i)
assert "appcast.xml" in files
latest = json.loads(sh("git", "-C", str(remote), "show", "gh-pages:ui-baseline/latest.json").stdout)
assert latest["name"] == "9.9.9-01234567" and latest["screenshots"] == 2, latest
assert sh("git", "-C", str(remote), "rev-list", "--count", "gh-pages").stdout.strip() == "4"
head_msg = sh("git", "-C", str(remote), "log", "-1", "--format=%s", "gh-pages").stdout
assert "ui-baseline: 01234567 [skip ci]" in head_msg, head_msg
print("✓ 第一遍：新基线目录 6 个文件 + latest.json 已推到 gh-pages，旧基线目录和 appcast.xml 原样保留")

clone_dir = runner_temp / "gh-pages-baseline"
# 稀疏检出：工作区只有 latest.json + 这一轮新写的基线目录（顶层文件和旧基线目录都不铺）
present = sorted(str(p.relative_to(clone_dir)) for p in clone_dir.rglob("*")
                 if p.is_file() and ".git" not in p.parts)
assert present == sorted(new_dir + name for name in added) + ["ui-baseline/latest.json"], present
# blob:none：旧截图的文件内容没有下载到本地
probe = sh("git", "-C", str(clone_dir), "cat-file", "-e", old_blob, check=False)
assert probe.returncode != 0, "旧截图的 blob 被下载了，--filter=blob:none 没生效"
print("✓ 克隆下来的工作区只有 ui-baseline/latest.json + 本轮新基线目录，旧基线目录和顶层文件都没铺，旧截图的文件内容没有下载")

out2 = run_step().stdout
assert "基线无变化" in out2, out2[-800:]
assert sh("git", "-C", str(remote), "rev-list", "--count", "gh-pages").stdout.strip() == "4"
print("✓ 第二遍：同一轮再跑输出「基线无变化」，远端提交数不变（幂等）")

shutil.rmtree(tmp)
print("全部通过")
