#!/bin/zsh
set -euo pipefail

LABEL="com.quitenote.app.dev.core"
DOMAIN="gui/$(id -u)"
SUPPORT_HOME="${HOME}/Library/Application Support"
SERVICE_HOME="$SUPPORT_HOME/com.quitenote.app.dev/CoreService"
DATABASE="$SUPPORT_HOME/QuiteNote-Debug/ClipboardHistory-Debug.sqlite"
STATE="$SERVICE_HOME/state.json"
OUTPUT="${1:-$SERVICE_HOME/24h-monitor.csv}"
INTERVAL_SECONDS="${QN_CORE_MONITOR_INTERVAL:-600}"
DURATION_SECONDS="${QN_CORE_MONITOR_DURATION:-86400}"

usage() {
  cat <<EOF
Usage: $0 [output.csv]

Samples the Dev-only core every \$QN_CORE_MONITOR_INTERVAL seconds
(default 600) for \$QN_CORE_MONITOR_DURATION seconds (default 86400).
The output never touches production storage.
EOF
}

if [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$(dirname "$OUTPUT")"
[[ -f "$OUTPUT" ]] || echo "timestamp,pid,runs,rss_kb,cpu_percent,wal_bytes,state_running,heartbeat_age_seconds,captured_count,last_error" > "$OUTPUT"

deadline=$((SECONDS + DURATION_SECONDS))
while (( SECONDS < deadline )); do
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printed=$(launchctl print "$DOMAIN/$LABEL" 2>/dev/null || true)
  pid=$(printf '%s\n' "$printed" | awk -F' = ' '/^\tpid = / { print $2; exit }')
  runs=$(printf '%s\n' "$printed" | awk -F' = ' '/^\truns = / { print $2; exit }')
  rss=0
  cpu=0
  if [[ "$pid" =~ ^[0-9]+$ ]]; then
    ps -o rss=,pcpu= -p "$pid" | read rss cpu
  fi
  wal_bytes=0
  [[ -f "$DATABASE-wal" ]] && wal_bytes=$(stat -f %z "$DATABASE-wal")

  running=false
  heartbeat_age=
  captured=0
  last_error=
  if [[ -f "$STATE" ]]; then
    parsed=$(python3 - "$STATE" <<'PY'
import datetime, json, sys
try:
    with open(sys.argv[1]) as f:
        s=json.load(f)
    hb=s.get("heartbeatAt")
    age=int((datetime.datetime.now(datetime.timezone.utc)-datetime.datetime.fromisoformat(hb.replace("Z","+00:00"))).total_seconds()) if hb else ""
    print(str(s.get("running",False)).lower(), age, s.get("capturedCount"), (s.get("lastError") or "").replace(",", ";"))
except Exception as e:
    print("false", "", 0, f"state-read-failed;{type(e).__name__}")
PY
    )
    read running heartbeat_age captured last_error <<< "$parsed"
  else
    last_error="state-file-missing"
  fi

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$timestamp" "${pid:-}" "${runs:-}" "${rss:-0}" "${cpu:-0}" "$wal_bytes" \
    "$running" "$heartbeat_age" "$captured" "$last_error" >> "$OUTPUT"

  # Stop early if launchd unloaded the service; the 24h report should expose it.
  [[ -n "${runs:-}" ]] || true
  sleep "$INTERVAL_SECONDS"
done

echo "$OUTPUT"
