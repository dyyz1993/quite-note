#!/usr/bin/env python3
"""UI 冒烟成功后，把本次截图证据快照进仓库 gh-pages 的 ui-baseline/ 目录，
形成可持久回归的基准（不受 CI artifact 30 天过期限制）。

用法: snapshot_ui_baseline.py <run_dir> <gh_pages_dir>
- run_dir: tools/ui-smoke/runs/ui-*（要求 report PASS）
- gh_pages_dir: gh-pages 工作目录（已有 appcast.xml 的那份）

产出: gh-pages/ui-baseline/<suite_version>-<git_commit[:8]>/ 截图 + manifest
     并更新 gh-pages/ui-baseline/latest.json 指针
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path


def main() -> None:
    run_dir = Path(sys.argv[1])
    gh_pages = Path(sys.argv[2])

    report = json.loads((run_dir / "report.json").read_text())
    if report.get("status") != "PASS":
        print("UI report 非 PASS，不更新基线")
        sys.exit(1)

    manifest = json.loads((run_dir / "manifest.json").read_text())
    commit = (manifest.get("git_commit") or "unknown")[:8]
    suite = manifest.get("suite_version") or report.get("suite_version") or "unknown"
    name = f"{suite}-{commit}"

    dest = gh_pages / "ui-baseline" / name
    dest.mkdir(parents=True, exist_ok=True)

    # 拷截图 + 时间线 + 报告（不拷视频，体积大且 gh-pages 有 1GB 限制）
    copied = 0
    shots = run_dir / "screenshots"
    if shots.is_dir():
        for png in sorted(shots.glob("*.png")):
            shutil.copy2(png, dest / png.name)
            copied += 1
    for extra in ("manifest.json", "report.json", "report.md", "timeline.jsonl"):
        src = run_dir / extra
        if src.is_file():
            shutil.copy2(src, dest / extra)

    index_path = gh_pages / "ui-baseline" / "latest.json"
    index = {"name": name, "commit": commit, "suite": suite,
             "screenshots": copied,
             "url": f"https://dyyz1993.github.io/quite-note/ui-baseline/{name}/"}
    index_path.write_text(json.dumps(index, ensure_ascii=False, indent=2))
    print(f"基线已快照: {name}（{copied} 张截图）")


if __name__ == "__main__":
    main()
