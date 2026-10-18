#!/bin/zsh
set -euo pipefail

LABEL="com.quitenote.app.dev.core"
DOMAIN="gui/$(id -u)"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$REPO_ROOT/cloud/quitenote-core/com.quitenote.app.dev.core.plist"
SUPPORT_HOME="${HOME}/Library/Application Support"
SERVICE_HOME="$SUPPORT_HOME/com.quitenote.app.dev/CoreService"
DATABASE="$SUPPORT_HOME/QuiteNote-Debug/ClipboardHistory-Debug.sqlite"
STATE="$SERVICE_HOME/state.json"
LOG="$SERVICE_HOME/launchd.log"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
MONITOR_LABEL="com.quitenote.dev.core.monitor"
MONITOR_PLIST="$HOME/Library/LaunchAgents/$MONITOR_LABEL.plist"
MONITOR_REPORT="$SERVICE_HOME/24h-monitor.csv"
MONITOR_LOG="$SERVICE_HOME/monitor-launch.log"
SOURCE_BINARY="${QN_DEV_CORE_BINARY:-$REPO_ROOT/.build/release/QuiteNoteCoreService}"
INSTALLED_BINARY="$SERVICE_HOME/quitenote-core"
MONITOR_SCRIPT="$REPO_ROOT/tools/monitor-quitenote-dev-core.sh"
REPORT_SCRIPT="$REPO_ROOT/tools/report-quitenote-dev-core.sh"

usage() {
  cat <<EOF
Usage: manage-quitenote-dev-core.sh <install|uninstall|restart|status|verify|monitor-start|monitor-stop|monitor-status|report>

Dev-only LaunchAgent manager for QuiteNoteCoreService.
It always uses the isolated dev database and never touches production storage.

Environment:
  QN_DEV_CORE_BINARY  Optional core executable (default: .build/release/QuiteNoteCoreService)
  QN_CORE_MONITOR_INTERVAL  Monitor sample interval seconds (default 600)
  QN_CORE_MONITOR_DURATION  Monitor duration seconds (default 90000)
EOF
}

require_file() {
  [[ -f "$1" ]] || { echo "Missing file: $1" >&2; exit 1; }
}

write_plist() {
  mkdir -p "$HOME/Library/LaunchAgents" "$SERVICE_HOME" "$(dirname "$DATABASE")"
  sed \
    -e "s|/Users/DEV|$HOME|g" \
    -e "s|$SERVICE_HOME/quitenote-core|$INSTALLED_BINARY|g" \
    -e "s|$SUPPORT_HOME/QuiteNote-Debug/ClipboardHistory-Debug.sqlite|$DATABASE|g" \
    -e "s|$SERVICE_HOME/state.json|$STATE|g" \
    -e "s|$SERVICE_HOME/launchd.log|$LOG|g" \
    "$TEMPLATE" > "$PLIST"
  chmod 0644 "$PLIST"
  plutil -lint "$PLIST"
}

unload_service() {
  launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
}

load_service() {
  # bootstrap is fail-closed on transient GUI-domain I/O; retry once before failing.
  if ! launchctl bootstrap "$DOMAIN" "$PLIST"; then
    sleep 1
    launchctl bootstrap "$DOMAIN" "$PLIST"
  fi
  launchctl enable "$DOMAIN/$LABEL"
  launchctl kickstart "$DOMAIN/$LABEL"
}

assert_dev_path() {
  [[ "$DATABASE" == "$SUPPORT_HOME/QuiteNote-Debug/ClipboardHistory-Debug.sqlite" ]]
  [[ "$STATE" == "$SUPPORT_HOME/com.quitenote.app.dev/CoreService/state.json" ]]
}

wait_for_pid() {
  local deadline=$((SECONDS + 15))
  while (( SECONDS < deadline )); do
    local printed_pid
    printed_pid=$(launchctl print "$DOMAIN/$LABEL" 2>/dev/null | awk -F' = ' '/^\tpid = / { print $2; exit }')
    if [[ "$printed_pid" =~ ^[0-9]+$ ]]; then
      echo "pid = $printed_pid"
      return 0
    fi
    printf '.' >&2
    sleep 0.25
  done
  echo "Timed out waiting for $LABEL" >&2
  return 1
}

case "${1:-}" in
  install)
    require_file "$TEMPLATE"
    require_file "$SOURCE_BINARY"
    assert_dev_path
    mkdir -p "$SERVICE_HOME"
    unload_service
    install -m 0755 "$SOURCE_BINARY" "$INSTALLED_BINARY"
    write_plist
    load_service
    wait_for_pid
    echo "Installed and started $LABEL"
    echo "database: $DATABASE"
    echo "state: $STATE"
    ;;
  uninstall)
    unload_service
    rm -f "$PLIST" "$INSTALLED_BINARY" "$STATE" "$LOG"
    launchctl bootout "$DOMAIN/$MONITOR_LABEL" >/dev/null 2>&1 || true
    rm -f "$MONITOR_PLIST"
    echo "Uninstalled $LABEL (dev data remains: $DATABASE)"
    ;;
  restart)
    require_file "$PLIST"
    plutil -lint "$PLIST"
    unload_service
    load_service
    wait_for_pid
    echo "Restarted $LABEL"
    ;;
  status)
    if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
      launchctl print "$DOMAIN/$LABEL" | sed -n '1,80p'
      [[ -f "$STATE" ]] && { echo "--- state ---"; cat "$STATE"; echo; }
      exit 0
    fi
    echo "$LABEL is not loaded"
    exit 3
    ;;
  verify)
    require_file "$PLIST"
    plutil -lint "$PLIST"
    assert_dev_path
    echo "--- before kill ---"
    OLD_PID=$(launchctl print "$DOMAIN/$LABEL" | awk -F' = ' '/^\tpid = / { print $2; exit }')
    [[ -n "$OLD_PID" ]] || { echo "Service has no live PID" >&2; exit 1; }
    echo "pid: $OLD_PID"
    kill -9 "$OLD_PID"
    wait_for_pid
    NEW_PID=$(launchctl print "$DOMAIN/$LABEL" | awk -F' = ' '/^\tpid = / { print $2; exit }')
    [[ -n "$NEW_PID" && "$NEW_PID" != "$OLD_PID" ]] || {
      echo "Service did not restart with a new PID" >&2
      exit 1
    }
    echo "--- after kill ---"
    echo "pid: $NEW_PID"
    echo "KeepAlive recovery verified"
    ;;
  monitor-start)
    require_file "$MONITOR_SCRIPT"
    require_file "$SOURCE_BINARY"
    launchctl bootout "$DOMAIN/$MONITOR_LABEL" >/dev/null 2>&1 || true
    if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
      launchctl print "$DOMAIN/$LABEL" | grep -q 'state = running' || {
        echo "Core is loaded but not running; run: $0 install" >&2
        exit 1
      }
    else
      echo "Core is not installed; run: $0 install" >&2
      exit 1
    fi
    cat > "$MONITOR_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$MONITOR_LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$MONITOR_SCRIPT</string><string>$MONITOR_REPORT</string></array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>QN_CORE_MONITOR_INTERVAL</key><string>${QN_CORE_MONITOR_INTERVAL:-600}</string>
    <key>QN_CORE_MONITOR_DURATION</key><string>${QN_CORE_MONITOR_DURATION:-90000}</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
  <key>StandardOutPath</key><string>$MONITOR_LOG</string>
  <key>StandardErrorPath</key><string>$MONITOR_LOG</string>
</dict>
</plist>
EOF
    chmod 0644 "$MONITOR_PLIST"
    plutil -lint "$MONITOR_PLIST"
    launchctl bootstrap "$DOMAIN" "$MONITOR_PLIST"
    launchctl kickstart "$DOMAIN/$MONITOR_LABEL"
    echo "Started $MONITOR_LABEL"
    echo "report: $MONITOR_REPORT"
    ;;
  monitor-stop)
    launchctl bootout "$DOMAIN/$MONITOR_LABEL" >/dev/null 2>&1 || true
    rm -f "$MONITOR_PLIST"
    echo "Stopped $MONITOR_LABEL"
    ;;
  monitor-status)
    if launchctl print "$DOMAIN/$MONITOR_LABEL" >/dev/null 2>&1; then
      launchctl print "$DOMAIN/$MONITOR_LABEL" | sed -n '1,80p'
      [[ -f "$MONITOR_REPORT" ]] && { echo "--- report tail ---"; tail -5 "$MONITOR_REPORT"; }
    else
      echo "$MONITOR_LABEL is not loaded"
      exit 3
    fi
    ;;
  report)
    "$REPORT_SCRIPT" "$MONITOR_REPORT"
    ;;
  *)
    usage
    exit 2
    ;;
esac
