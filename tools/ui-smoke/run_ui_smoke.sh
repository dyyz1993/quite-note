#!/bin/bash
set -euo pipefail

SUITE_VERSION="1.0.0"
DEFAULT_BASELINE="v1.3.0"
MODE="full"
REF=""
BASELINE=""
SINCE=""
ALLOW_DIRTY=false
KEEP_DATA=true
EVIDENCE="fast"
SKIP_BUILD=false
DRY_RUN=false

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
  --skip-build                  Reuse the worktree app bundle when it already exists.
  --dry-run                     Resolve metadata/select suites, but do not build or launch.
  -h | --help                   Show this help.
EOF
}

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 2; }; }
json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))'; }
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
    --skip-build) SKIP_BUILD=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$MODE" =~ ^(full|release|incremental)$ ]] || { echo "Invalid mode: $MODE" >&2; exit 2; }
[[ "$EVIDENCE" =~ ^(fast|full)$ ]] || { echo "Invalid evidence mode: $EVIDENCE" >&2; exit 2; }
[[ -z "$BASELINE" && "$MODE" == "release" ]] && BASELINE="$DEFAULT_BASELINE"

need git
need python3
need sw_vers
need xcodebuild
need system_profiler
need screencapture

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
  GIT_DESCRIBE="$(git describe --tags --always --dirty "$GIT_COMMIT")"
fi

RUN_ID="ui-$(date -u +%Y%m%d-%H%M%S)-${GIT_COMMIT:0:8}"
RUN_DIR="$ROOT/tools/ui-smoke/runs/$RUN_ID"
STORAGE_ROOT="/tmp/quitenote-ui-smoke/$RUN_ID"
WORKTREE="$ROOT/.ui-smoke-worktrees/$GIT_COMMIT"
APP_PATH="$WORKTREE/Quite Note Dev.app"
mkdir -p "$RUN_DIR/screenshots" "$STORAGE_ROOT"

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
XCODE_VERSION="$(xcodebuild -version | head -1 | sed 's/^Xcode //')"
DISPLAY_TOPOLOGY="$(system_profiler SPDisplaysDataType -json 2>/dev/null | python3 tools/ui-smoke/display_topology.py)"
APP_VERSION="unknown"
APP_BUNDLE_ID="com.quitenote.app.dev"
if [[ -f "$APP_PATH/Contents/Info.plist" ]]; then
  APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo unknown)"
  APP_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo com.quitenote.app.dev)"
fi

cat > "$RUN_DIR/manifest.json" <<EOF
{
  "run_id": $(printf '%s' "$RUN_ID" | json_escape),
  "suite_version": $(printf '%s' "$SUITE_VERSION" | json_escape),
  "started_at": $(printf '%s' "$(iso_now)" | json_escape),
  "finished_at": null,
  "mode": $(printf '%s' "$MODE" | json_escape),
  "git_ref": $(printf '%s' "$GIT_REF" | json_escape),
  "git_commit": $(printf '%s' "$GIT_COMMIT" | json_escape),
  "git_tag": $(printf '%s' "$GIT_TAG_AT_COMMIT" | json_escape),
  "git_describe": $(printf '%s' "$GIT_DESCRIBE" | json_escape),
  "working_tree_patch_sha": $(printf '%s' "$PATCH_SHA" | json_escape),
  "baseline_ref": $(printf '%s' "$BASELINE" | json_escape),
  "baseline_commit": $(printf '%s' "$BASELINE_COMMIT" | json_escape),
  "baseline_tag": $(printf '%s' "$BASELINE_TAG" | json_escape),
  "baseline_run_id": null,
  "app_version": $(printf '%s' "$APP_VERSION" | json_escape),
  "app_bundle_id": $(printf '%s' "$APP_BUNDLE_ID" | json_escape),
  "storage_root": $(printf '%s' "$STORAGE_ROOT" | json_escape),
  "keep_data": $KEEP_DATA,
  "evidence": $(printf '%s' "$EVIDENCE" | json_escape),
  "suites": $SUITES_JSON,
  "macos_version": $(printf '%s' "$MACOS_VERSION" | json_escape),
  "xcode_version": $(printf '%s' "$XCODE_VERSION" | json_escape),
  "display_topology": $(printf '%s' "$DISPLAY_TOPOLOGY" | json_escape)
}
EOF

cat > "$RUN_DIR/baseline-comparison.json" <<EOF
{
  "baseline_ref": $(printf '%s' "$BASELINE" | json_escape),
  "baseline_commit": $(printf '%s' "$BASELINE_COMMIT" | json_escape),
  "target_commit": $(printf '%s' "$GIT_COMMIT" | json_escape),
  "new_failures": [],
  "fixed_failures": [],
  "still_failing": [],
  "baseline_failures": [],
  "comparison": "unavailable"
}
EOF

cat > "$RUN_DIR/timeline.jsonl" <<EOF
{"timestamp": $(printf '%s' "$(iso_now)" | json_escape), "event": "metadata_resolved", "mode": $(printf '%s' "$MODE" | json_escape), "suites": $SUITES_JSON}
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
  "manifest": $(printf '%s/manifest.json' "$RUN_DIR" | json_escape)
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
if [[ "$SKIP_BUILD" != true || ! -d "$APP_PATH" ]]; then
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
QN_TEST_STORAGE_ROOT="$STORAGE_ROOT" open -n -a "$APP_PATH" --args --ui-smoke-run "$RUN_ID"
DEADLINE=$((SECONDS + 15))
TEST_PID=""
while (( SECONDS < DEADLINE )); do
  TEST_PID="$(pgrep -f "$APP_PATH/Contents/MacOS/QuiteNoteDev" | tail -1 || true)"
  [[ -n "$TEST_PID" ]] && break
  sleep 1
done
[[ -n "$TEST_PID" ]] || { echo "BLOCKED: Quite Note Dev did not start" >&2; screencapture -x "$RUN_DIR/screenshots/blocked.png" 2>/dev/null || true; exit 3; }
echo "$TEST_PID" > "$TEST_PID_FILE"
sleep 2
TEST_PID="$(cat "$TEST_PID_FILE" 2>/dev/null || true)"

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

python3 "$ROOT/tools/ui-smoke/computer_use_smoke.py" \
  --run-dir "$RUN_DIR" \
  --app-path "$APP_PATH" \
  --suites "${SUITES[*]}" \
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
