#!/bin/bash
set -euo pipefail

SUITE_VERSION="1.2.0"
DEFAULT_BASELINE="v1.3.0"
MODE="full"
REF=""
BASELINE=""
SINCE=""
ALLOW_DIRTY=false
KEEP_DATA=true
EVIDENCE="fast"
UI_PYTHON="python3"
SKIP_BUILD=false
DRY_RUN=false
REMOTE_HOST=""
ARTIFACT_URL=""
LOCAL_ARTIFACT_PATH=""

usage() {
  cat <<'EOF'
Usage: run_ui_smoke.sh [options]

Options:
  --ref <tag|commit|branch>     Ref to test. Defaults to HEAD.
  --baseline <tag|commit>       Baseline recorded in the manifest and comparison.
  --incremental-since <ref>     Select suites from changed paths since this ref.
  --mode <full|release|incremental>
                                Defaults to full; --incremental-since implies incremental.
  --allow-dirty                 Include the current patch and record its SHA.
  --no-keep-data                Delete this run's isolated storage after execution.
  --evidence <fast|full>        fast keeps key/failure screenshots; full saves every step.
  --ui-python <path>            Python executable used by the UI driver.
  --skip-build                  Reuse the worktree app bundle when it already exists.
  --remote <host>               Execute UI over SSH on the dedicated test Mac.
  --artifact-url <url>          Download a CI-produced .zip or .dmg artifact.
  --local-artifact <path>       Install and test a CI-produced .zip or .dmg without building.
  --dry-run                     Resolve metadata/select suites, but do not build or launch.
  -h | --help                   Show this help.
EOF
}

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 2; }; }
json_escape() { python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.argv[1]))' "$1"; }
iso_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref) REF="${2:?missing ref}"; shift 2 ;;
    --baseline) BASELINE="${2:?missing baseline}"; shift 2 ;;
    --incremental-since) SINCE="${2:?missing ref}"; MODE="incremental"; shift 2 ;;
    --mode) MODE="${2:?missing mode}"; shift 2 ;;
    --allow-dirty) ALLOW_DIRTY=true; shift ;;
    --no-keep-data) KEEP_DATA=false; shift ;;
    --evidence) EVIDENCE="${2:?missing evidence mode}"; shift 2 ;;
    --ui-python) UI_PYTHON="${2:?missing Python path}"; shift 2 ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    --remote) REMOTE_HOST="${2:?missing remote host}"; shift 2 ;;
    --artifact-url) ARTIFACT_URL="${2:?missing artifact URL}"; shift 2 ;;
    --local-artifact) LOCAL_ARTIFACT_PATH="${2:?missing artifact path}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -n "$REMOTE_HOST" ]]; then MODE="remote"; fi
if [[ -n "$LOCAL_ARTIFACT_PATH" ]]; then
  [[ -z "$REMOTE_HOST" && -z "$ARTIFACT_URL" ]] || {
    echo "--local-artifact cannot be combined with --remote or --artifact-url" >&2
    exit 2
  }
  SKIP_BUILD=true
fi
[[ "$MODE" =~ ^(full|release|incremental|remote)$ ]] || { echo "Invalid mode: $MODE" >&2; exit 2; }
[[ "$EVIDENCE" =~ ^(fast|full)$ ]] || { echo "Invalid evidence mode: $EVIDENCE" >&2; exit 2; }
[[ -z "$BASELINE" && "$MODE" == "release" ]] && BASELINE="$DEFAULT_BASELINE"

need git
need python3
need sw_vers
need system_profiler
need screencapture
if [[ -z "$LOCAL_ARTIFACT_PATH" ]]; then
  need xcodebuild
fi
if [[ -n "$REMOTE_HOST" ]]; then
  need ssh
  need rsync
fi

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

GIT_REF="${REF:-HEAD}"
if ! GIT_COMMIT="$(git rev-parse --verify "${GIT_REF}^{commit}")"; then
  echo "Invalid git ref: $GIT_REF" >&2
  exit 2
fi
GIT_COMMIT="${GIT_COMMIT%% *}"
GIT_DESCRIBE_DIRTY="$(git describe --tags --always --dirty)"
GIT_TAG_AT_COMMIT="$(git describe --tags --exact-match "$GIT_COMMIT" 2>/dev/null || true)"
BASELINE_COMMIT=""
BASELINE_TAG=""
if [[ -n "$BASELINE" ]]; then
  if ! BASELINE_COMMIT="$(git rev-parse --verify "${BASELINE}^{commit}")"; then
    echo "Invalid baseline: $BASELINE" >&2
    exit 2
  fi
  BASELINE_COMMIT="${BASELINE_COMMIT%% *}"
  BASELINE_TAG="$(git describe --tags --exact-match "$BASELINE_COMMIT" 2>/dev/null || true)"
fi

DIRTY=false
if [[ -n "$(git status --porcelain)" ]]; then
  DIRTY=true
  if [[ "$ALLOW_DIRTY" != true ]]; then
    cat >&2 <<EOF
Working tree is dirty. Use --allow-dirty to test the patch, or pass --ref <commit>.
The default workflow tests committed refs in a temporary worktree.
EOF
    exit 2
  fi
fi
PATCH_SHA="$(git diff --binary | shasum -a 256 | awk '{print $1}')"
if [[ "$DIRTY" == true ]]; then
  GIT_DESCRIBE="$GIT_DESCRIBE_DIRTY"
else
  # Apple Git used by self-hosted runners rejects combining --dirty with a ref.
  GIT_DESCRIBE="$(git describe --tags --always "$GIT_COMMIT")"
fi

RUN_ID="ui-$(date -u +%Y%m%d-%H%M%S)-${GIT_COMMIT:0:8}"
RUN_DIR="$ROOT/tools/ui-smoke/runs/$RUN_ID"
STORAGE_ROOT="/tmp/quitenote-ui-smoke/$RUN_ID"
WORKTREE="$ROOT/.ui-smoke-worktrees/$GIT_COMMIT"
APP_PATH="$WORKTREE/Quite Note Dev.app"
mkdir -p "$RUN_DIR/screenshots" "$STORAGE_ROOT"
mkdir -p "$RUN_DIR/recordings"

select_suites() {
  local since="$1" mode="$2"
  python3 - "$since" "$mode" <<'PY'
import json, subprocess, sys
since, mode = sys.argv[1:]
if mode in ("full", "release"):
    print(json.dumps(["launch", "flash-notes", "clipboard", "launcher", "settings", "devcore", "cleanup"]))
    raise SystemExit
if not since:
    print(json.dumps(["launch", "flash-notes", "clipboard", "launcher", "settings", "devcore", "cleanup"]))
    raise SystemExit
try:
    changed = subprocess.check_output(["git", "diff", "--name-only", f"{since}..HEAD"], text=True).splitlines()
except subprocess.CalledProcessError:
    print(json.dumps(["launch", "flash-notes", "clipboard", "launcher", "settings", "devcore", "cleanup"]))
    raise SystemExit
mapping = {
    "clipboard": {"Sources/QuiteNote/Clipboard/", "Sources/QuiteNoteSharedStorage/", "Sources/QuiteNoteCoreService/"},
    "flash-notes": {"Sources/QuiteNote/Records/", "Sources/QuiteNote/Search/", "Sources/QuiteNote/UI/FloatingPanel/"},
    "launcher": {"Sources/QuiteNote/AppLauncher/"},
    "settings": {"Sources/QuiteNote/UI/SettingsTabs/", "Sources/QuiteNote/Preferences/"},
}
suites = {"launch", "cleanup"}
for path in changed:
    if path in {"Package.swift", "build-app.sh"}:
        suites.update(mapping)
        suites.add("devcore")
        break
    for suite, prefixes in mapping.items():
        if path.startswith(tuple(prefixes)):
            suites.add(suite)
print(json.dumps(sorted(suites)))
PY
}

SUITES_JSON="$(select_suites "$SINCE" "$MODE")"
read -r -a SUITES <<<"$(python3 -c 'import json,sys; print(" ".join(json.loads(sys.argv[1])))' "$SUITES_JSON")"
[[ ${#SUITES[@]} -gt 0 ]] || SUITES=(launch flash-notes clipboard launcher settings devcore cleanup)

MACOS_VERSION="$(sw_vers -productVersion)"
XCODE_VERSION="not-required"
if [[ -z "$LOCAL_ARTIFACT_PATH" ]]; then
  XCODE_VERSION="$(xcodebuild -version | head -1 | sed 's/^Xcode //')"
fi
DISPLAY_TOPOLOGY_FILE="$RUN_DIR/display-topology.json"
/usr/sbin/system_profiler SPDisplaysDataType -json > "$DISPLAY_TOPOLOGY_FILE" 2>/dev/null || true
DISPLAY_TOPOLOGY="$(python3 tools/ui-smoke/display_topology.py < "$DISPLAY_TOPOLOGY_FILE" 2>/dev/null || true)"
APP_VERSION="unknown"
APP_BUNDLE_ID="com.quitenote.app.dev"

LOCAL_ARTIFACT=""
download_ci_artifact() {
  local name
  name="$(basename "$ARTIFACT_URL" | sed 's/[?#].*$//')"
  [[ "$name" =~ \.(zip|dmg)$ ]] || { echo "Artifact URL must end in .zip or .dmg" >&2; exit 2; }
  local dest="$RUN_DIR/$name"
  curl -fL --retry 3 --connect-timeout 15 "$ARTIFACT_URL" -o "$dest"
  LOCAL_ARTIFACT="$dest"
}

if [[ -n "$ARTIFACT_URL" && "$DRY_RUN" != true ]]; then
  download_ci_artifact
elif [[ "$MODE" != "remote" && "$SKIP_BUILD" != true ]]; then
  APP_PATH_HINT="$APP_PATH"
else
  APP_PATH_HINT="$APP_PATH"
fi

if [[ -f "$APP_PATH/Contents/Info.plist" ]]; then
  APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo unknown)"
  APP_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo com.quitenote.app.dev)"
fi

cat > "$RUN_DIR/manifest.json" <<EOF
{
  "run_id": $(json_escape "$RUN_ID"),
  "suite_version": $(json_escape "$SUITE_VERSION"),
  "started_at": $(json_escape "$(iso_now)"),
  "finished_at": null,
  "mode": $(json_escape "$MODE"),
  "git_ref": $(json_escape "$GIT_REF"),
  "git_commit": $(json_escape "$GIT_COMMIT"),
  "git_tag": $(json_escape "$GIT_TAG_AT_COMMIT"),
  "git_describe": $(json_escape "$GIT_DESCRIBE"),
  "working_tree_patch_sha": $(json_escape "$PATCH_SHA"),
  "baseline_ref": $(json_escape "$BASELINE"),
  "baseline_commit": $(json_escape "$BASELINE_COMMIT"),
  "baseline_tag": $(json_escape "$BASELINE_TAG"),
  "baseline_run_id": null,
  "app_version": $(json_escape "$APP_VERSION"),
  "app_bundle_id": $(json_escape "$APP_BUNDLE_ID"),
  "storage_root": $(json_escape "$STORAGE_ROOT"),
  "keep_data": $KEEP_DATA,
  "evidence": $(json_escape "$EVIDENCE"),
  "video_evidence": $(json_escape "recordings/ui-recording.mov"),
  "suites": $SUITES_JSON,
  "macos_version": $(json_escape "$MACOS_VERSION"),
  "xcode_version": $(json_escape "$XCODE_VERSION"),
  "display_topology": $(json_escape "$DISPLAY_TOPOLOGY"),
  "remote_host": $(json_escape "$REMOTE_HOST"),
  "artifact_url": $(json_escape "$ARTIFACT_URL"),
  "local_artifact": $(json_escape "$LOCAL_ARTIFACT_PATH")
}
EOF

cat > "$RUN_DIR/baseline-comparison.json" <<EOF
{
  "baseline_ref": $(json_escape "$BASELINE"),
  "baseline_commit": $(json_escape "$BASELINE_COMMIT"),
  "target_commit": $(json_escape "$GIT_COMMIT"),
  "new_failures": [],
  "fixed_failures": [],
  "still_failing": [],
  "baseline_failures": [],
  "comparison": "unavailable"
}
EOF

cat > "$RUN_DIR/timeline.jsonl" <<EOF
{"timestamp": $(json_escape "$(iso_now)"), "event": "metadata_resolved", "mode": $(json_escape "$MODE"), "suites": $SUITES_JSON}
EOF

cat > "$RUN_DIR/report.md" <<EOF
# Quite Note UI Smoke — $RUN_ID

- Result: **RUNNING**
- Mode: \`$MODE\`
- Git: \`$GIT_REF\` / \`$GIT_COMMIT\`
- Describe: \`$GIT_DESCRIBE\`
- Baseline: \`$BASELINE\` / \`$BASELINE_COMMIT\`
- Suites: \`${SUITES[*]}\`
- Report: \`$RUN_DIR/report.md\`
EOF

echo "Run: $RUN_ID"
echo "Mode: $MODE; suites: ${SUITES[*]}"
echo "Report: $RUN_DIR/report.md"

if [[ "$DRY_RUN" == true ]]; then
  cat > "$RUN_DIR/report.json" <<EOF
{
  "status": "DRY_RUN",
  "results": [],
  "manifest": $(json_escape "$RUN_DIR/manifest.json")
}
EOF
  sed -i '' 's/Result: \*\*RUNNING\*\*/Result: **DRY_RUN**/' "$RUN_DIR/report.md"
  python3 - "$RUN_DIR/manifest.json" <<'PY'
import datetime
import json
import sys

path = sys.argv[1]
data = json.load(open(path))
data["status"] = "DRY_RUN"
data["finished_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")
with open(path, "w") as stream:
    json.dump(data, stream, indent=2, ensure_ascii=False)
    stream.write("\n")
PY
  rm -rf "$STORAGE_ROOT"
  echo "Dry run OK: $RUN_DIR/manifest.json"
  exit 0
fi

if [[ -n "$LOCAL_ARTIFACT_PATH" ]]; then
  # Building a signed universal artifact is delegated to the cloud; the UI host
  # only needs test assets and the Python runtime from this checkout.
  need ditto
  [[ -x "/usr/libexec/PlistBuddy" ]] || { echo "Missing command: PlistBuddy" >&2; exit 2; }
fi

if [[ "$MODE" == "remote" ]]; then
  [[ -n "$REMOTE_HOST" ]] || { echo "Remote mode requires --remote <host>" >&2; exit 2; }
  [[ -n "$ARTIFACT_URL" ]] || { echo "Remote mode requires --artifact-url <CI artifact>" >&2; exit 2; }

  REMOTE_ROOT="/Users/$(ssh "$REMOTE_HOST" 'stat -f %Su')/QuitenoteUITest"
  REMOTE_RUN_DIR="$REMOTE_ROOT/runs/$RUN_ID"
  REMOTE_APP_DIR="$REMOTE_ROOT/apps/$GIT_COMMIT"
  REMOTE_ARTIFACT="$REMOTE_ROOT/artifacts/$(basename "$LOCAL_ARTIFACT")"

  ssh "$REMOTE_HOST" "mkdir -p '$REMOTE_ROOT/runs/$RUN_ID/screenshots' '$REMOTE_ROOT/apps/$GIT_COMMIT' '$REMOTE_ROOT/artifacts'"
  rsync -a "$LOCAL_ARTIFACT" "$REMOTE_HOST:$REMOTE_ARTIFACT"
  rsync -a "$ROOT/tools/ui-smoke/computer_use_smoke.py" "$REMOTE_HOST:$REMOTE_ROOT/tools/"

  ssh "$REMOTE_HOST" "python3 - '$REMOTE_ROOT' '$REMOTE_RUN_DIR' '$REMOTE_APP_DIR' '$REMOTE_ARTIFACT' '$STORAGE_ROOT' '$RUN_ID'" <<'PY'
import datetime
import json
import shutil, subprocess, sys
from pathlib import Path

root, run_dir, app_dir, archive, storage = (Path(x) for x in sys.argv[1:6])
run_id = sys.argv[6]
if archive.suffix == ".dmg":
    mount = root / "mounts" / run_id
    mount.mkdir(parents=True, exist_ok=True)
    subprocess.run(["hdiutil", "attach", str(archive), "-mountpoint", str(mount), "-nobrowse", "-readonly"], check=True)
    source = next(mount.glob("*.app"), None)
else:
    tmp = root / "extract" / run_id
    tmp.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ditto", "-x", "-k", str(archive), str(tmp)], check=True)
    source = next(tmp.glob("*.app"), None)
if source is None:
    raise SystemExit("BLOCKED: artifact contains no .app")
if app_dir.exists():
    shutil.rmtree(app_dir)
shutil.copytree(source, app_dir, symlinks=True)
(run_dir / "manifest.json").write_text(json.dumps({"run_id": run_id, "started_at": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"), "mode": "remote", "app_path": str(app_dir), "artifact": str(archive), "storage_root": str(storage)}, indent=2) + "\n")
print(app_dir)
PY

  # The remote host is dedicated to UI testing; suppress one-time onboarding so
  # deterministic panel assertions can run without mutating application data.
  ssh "$REMOTE_HOST" "defaults write com.quitenote.app.dev clipboardOnboarded -bool true"
  ssh "$REMOTE_HOST" "QN_TEST_STORAGE_ROOT='$STORAGE_ROOT' open -n '$REMOTE_APP_DIR/Contents/MacOS/QuiteNoteDev' --args --ui-smoke-run '$RUN_ID'"
  sleep 4
  set +e
  ssh "$REMOTE_HOST" "python3 '$REMOTE_ROOT/tools/computer_use_smoke.py' --run-dir '$REMOTE_RUN_DIR' --app-path '$REMOTE_APP_DIR' --suites ${SUITES[*]} --evidence '$EVIDENCE'"
  STATUS=$?
  set -e
  ssh "$REMOTE_HOST" "osascript -e 'tell application id \"com.quitenote.app.dev\" to quit' >/dev/null 2>&1 || true; pkill -f '$REMOTE_APP_DIR/Contents/MacOS/QuiteNoteDev' 2>/dev/null || true"
  rsync -a "$REMOTE_HOST:$REMOTE_RUN_DIR/" "$RUN_DIR/"
  python3 - "$RUN_DIR" "$RUN_ID" "$GIT_REF" "$GIT_COMMIT" "$GIT_TAG_AT_COMMIT" "$GIT_DESCRIBE" "$PATCH_SHA" "$BASELINE" "$BASELINE_COMMIT" "$REMOTE_HOST" "$ARTIFACT_URL" "$SUITE_VERSION" "$MACOS_VERSION" "$XCODE_VERSION" "$DISPLAY_TOPOLOGY" <<'PYEOF'
import datetime
import json
import pathlib
import sys

run_dir = pathlib.Path(sys.argv[1])
report = json.loads((run_dir / "report.json").read_text())
remote = json.loads((run_dir / "manifest.json").read_text())
manifest = {
    "run_id": sys.argv[2],
    "started_at": remote.get("started_at"),
    "finished_at": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
    "mode": "remote",
    "git_ref": sys.argv[3],
    "git_commit": sys.argv[4],
    "git_tag": sys.argv[5],
    "git_describe": sys.argv[6],
    "working_tree_patch_sha": sys.argv[7],
    "baseline_ref": sys.argv[8],
    "baseline_commit": sys.argv[9],
    "remote_host": sys.argv[10],
    "artifact_url": sys.argv[11],
    "suite_version": sys.argv[12],
    "macos_version": sys.argv[13],
    "xcode_version": sys.argv[14],
    "display_topology": sys.argv[15],
    "status": report.get("status"),
    "results": report.get("results"),
}
(run_dir / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
PYEOF
  if [[ "$STATUS" -eq 3 ]]; then exit 3; fi
  if [[ "$STATUS" -ne 0 ]]; then
    python3 - "$RUN_DIR" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); results=json.loads((p/"report.json").read_text()) if (p/"report.json").exists() else {"results":[]}
lines=["# Knowledge candidate","", f"- Generated by run: `{p.name}`","", "## Failures requiring triage",""]
for r in results.get("results",[]):
    if r.get("status") not in ("PASS","SKIP"):
        lines += [f"### {r.get('name','unknown')}", f"- Reason: {r.get('reason','not recorded')}", f"- Evidence: `{r.get('evidence','')}`", ""]
(p/"knowledge-candidate.md").write_text("\n".join(lines))
PY
  fi
  exit "$STATUS"
fi


prepare_worktree() {
  if [[ ! -d "$WORKTREE/.git" && ! -f "$WORKTREE/.git" ]]; then
    git worktree add --detach "$WORKTREE" "$GIT_COMMIT" >/dev/null
  fi
  if [[ "$ALLOW_DIRTY" == true && "$GIT_REF" == "HEAD" ]]; then
    # Include untracked test/source files required by the current WIP without
    # mutating the main checkout. Keep this explicit; switch to git worktree
    # staging later if the WIP becomes committed.
    files=(
      "Sources/QuiteNoteSharedStorage/ClipboardHistoryRepository.swift"
      "Tests/QuiteNoteSharedStorageTests/ClipboardHistoryPersistenceTests.swift"
    )
    for rel in "${files[@]}"; do
      mkdir -p "$WORKTREE/$(dirname "$rel")"
      cp "$ROOT/$rel" "$WORKTREE/$rel"
    done
  fi
}

prepare_worktree

if [[ -n "$LOCAL_ARTIFACT_PATH" ]]; then
  [[ -f "$LOCAL_ARTIFACT_PATH" ]] || { echo "Local artifact not found: $LOCAL_ARTIFACT_PATH" >&2; exit 2; }
  case "$LOCAL_ARTIFACT_PATH" in
    *.zip|*.dmg) ;;
    *) echo "Local artifact must be a .zip or .dmg" >&2; exit 2 ;;
  esac
  cp "$LOCAL_ARTIFACT_PATH" "$RUN_DIR/$(basename "$LOCAL_ARTIFACT_PATH")"
  if [[ -d "$APP_PATH" ]]; then rm -rf "$APP_PATH"; fi
  ARTIFACT_INSTALL_DIR="$ROOT/.ui-smoke-artifacts/$GIT_COMMIT"
  rm -rf "$ARTIFACT_INSTALL_DIR"
  mkdir -p "$ARTIFACT_INSTALL_DIR" "$WORKTREE"
  case "$LOCAL_ARTIFACT_PATH" in
    *.zip)
      ditto -x -k "$LOCAL_ARTIFACT_PATH" "$ARTIFACT_INSTALL_DIR"
      ;;
    *.dmg)
      ARTIFACT_MOUNT="$ROOT/.ui-smoke-artifacts/$RUN_ID.mount"
      mkdir -p "$ARTIFACT_MOUNT"
      hdiutil attach "$LOCAL_ARTIFACT_PATH" -mountpoint "$ARTIFACT_MOUNT" -nobrowse -readonly
      ditto "$ARTIFACT_MOUNT" "$ARTIFACT_INSTALL_DIR"
      hdiutil detach "$ARTIFACT_MOUNT" || true
      ;;
  esac
  ARTIFACT_APP="$(find "$ARTIFACT_INSTALL_DIR" -maxdepth 2 -type d -name '*.app' -print -quit)"
  [[ -n "$ARTIFACT_APP" ]] || { echo "Artifact contains no .app" >&2; exit 2; }
  mkdir -p "$(dirname "$APP_PATH")"
  cp -R "$ARTIFACT_APP" "$APP_PATH"
elif [[ "$SKIP_BUILD" != true || ! -d "$APP_PATH" ]]; then
  (cd "$WORKTREE" && ./build-app.sh --dev --no-launch)
fi

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
APP_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
python3 - "$RUN_DIR/manifest.json" "$APP_VERSION" "$APP_BUNDLE_ID" <<'PY'
import json, sys
p, version, bundle = sys.argv[1:]
d=json.load(open(p)); d["app_version"]=version; d["app_bundle_id"]=bundle
with open(p,"w") as f: json.dump(d,f,indent=2,ensure_ascii=False); f.write("\n")
PY

TEST_PID_FILE="$RUN_DIR/app.pid"
defaults write com.quitenote.app.dev clipboardOnboarded -bool true
PYTHON_APP_PATH="$(cd "$(dirname "$UI_PYTHON")/../.." && pwd)"
if [[ -d "$PYTHON_APP_PATH" && -f "$PYTHON_APP_PATH/Contents/Info.plist" ]]; then
  # Screen Recording TCC follows the responsible GUI app. The launcher app
  # owns both Dev app startup and the smoke driver, keeping AX and capture in
  # one authorized audit context while GitHub's runner only waits for results.
  LAUNCH_REQUEST="$RUN_DIR/gui-launch.request.json"
  LAUNCH_RESPONSE="$RUN_DIR/gui-launch.response.json"
  python3 - "$LAUNCH_REQUEST" "$RUN_DIR" "$APP_PATH" "$STORAGE_ROOT" "$RUN_ID" "$EVIDENCE" "${SUITES[@]}" <<'PY'
import json, sys
out, run_dir, app_path, storage, run_id, evidence, *suites = sys.argv[1:]
request = {
    "run_dir": run_dir,
    "app_path": app_path,
    "storage_root": storage,
    "run_id": run_id,
    "evidence": evidence,
    "suites": suites,
}
open(out, "w").write(json.dumps(request, ensure_ascii=False, indent=2) + "\n")
PY
  open -n "$PYTHON_APP_PATH" --args "$ROOT/tools/ui-smoke/gui_smoke_launcher.py" "$LAUNCH_REQUEST" "$LAUNCH_RESPONSE"
  DEADLINE=$((SECONDS + 180))
  until [[ -f "$LAUNCH_RESPONSE" ]]; do
    (( SECONDS < DEADLINE )) || break
    sleep 0.5
  done
  python3 - "$LAUNCH_RESPONSE" "$RUN_DIR" <<'PY'
import json, pathlib, sys
response, run_dir = (pathlib.Path(value) for value in sys.argv[1:])
if not response.exists():
    raise SystemExit("BLOCKED: GUI smoke launcher did not finish")
result = json.loads(response.read_text())
if result.get("error"):
    (run_dir / "launcher-error.txt").write_text(result["error"])
if result.get("returncode") == 3:
    raise SystemExit(3)
raise SystemExit(result.get("returncode", 1))
PY
  GUI_STATUS=$?
else
  # The LaunchAgent runner creates its own audit session. A direct child app is
  # registered with WindowServer but remains invisible to that session; ask
  # LaunchServices to place the app in the interactive login session instead.
  QN_TEST_STORAGE_ROOT="$STORAGE_ROOT" open -n "$APP_PATH" --args --ui-smoke-run "$RUN_ID"
  GUI_STATUS=100
fi

if [[ "${GUI_STATUS:-100}" != 100 ]]; then
  exit "$GUI_STATUS"
fi
DEADLINE=$((SECONDS + 15))
TEST_PID=""
while (( SECONDS < DEADLINE )); do
  TEST_PID="$(pgrep -f "$APP_PATH/Contents/MacOS/QuiteNoteDev" | tail -1 || true)"
  [[ -n "$TEST_PID" && -d "$STORAGE_ROOT" ]] && break
  sleep 1
done
if [[ -z "$TEST_PID" ]] || ! kill -0 "$TEST_PID" 2>/dev/null; then
  echo "BLOCKED: Quite Note Dev did not start" >&2
  screencapture -x "$RUN_DIR/screenshots/blocked.png" 2>/dev/null || true
  exit 3
fi
echo "$TEST_PID" > "$TEST_PID_FILE"
[[ -d "$STORAGE_ROOT" ]] || { echo "BLOCKED: isolated storage root was not created: $STORAGE_ROOT" >&2; screencapture -x "$RUN_DIR/screenshots/blocked.png" 2>/dev/null || true; exit 3; }
sleep 2

cleanup() {
  if [[ -n "${TEST_PID:-}" ]] && kill -0 "$TEST_PID" 2>/dev/null; then
    kill "$TEST_PID" 2>/dev/null || true
  fi
  if [[ "$KEEP_DATA" != true ]]; then rm -rf "$STORAGE_ROOT"; fi
}
trap cleanup EXIT INT TERM

if [[ ! -d "$STORAGE_ROOT" ]]; then
  echo "BLOCKED: isolated storage root was not created: $STORAGE_ROOT" >&2
  screencapture -x "$RUN_DIR/screenshots/blocked.png" 2>/dev/null || true
  exit 3
fi

"$UI_PYTHON" "$ROOT/tools/ui-smoke/computer_use_smoke.py" \
  --run-dir "$RUN_DIR" \
  --app-path "$APP_PATH" \
  --app-pid "$TEST_PID" \
  --suites "${SUITES[@]}" \
  --evidence "$EVIDENCE"
STATUS=$?
if [[ "$STATUS" -eq 3 ]]; then
  exit 3
fi

if [[ "$STATUS" -ne 0 ]]; then
  python3 - "$RUN_DIR" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); results=json.loads((p/"report.json").read_text()) if (p/"report.json").exists() else {"results":[]}
failing=[r for r in results.get("results",[]) if r.get("status") not in ("PASS","SKIP")]
lines=["# Knowledge candidate","", f"- Generated by run: `{p.name}`","", "## Failures requiring triage",""]
for r in failing:
    lines += [f"### {r.get('name','unknown')}", f"- Status: `{r.get('status','FAIL')}`", f"- Reason: {r.get('reason','not recorded')}", f"- Evidence: `{r.get('evidence','')}`", ""]
(p/"knowledge-candidate.md").write_text("\n".join(lines))
PY
fi

exit "$STATUS"

authorize_remote_ui() {
  echo "Opening remote UI test Mac System Settings for one-time Accessibility and Screen Recording authorization." >&2
  ssh "$1" "open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'; open 'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'"
}
