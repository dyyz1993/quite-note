#!/bin/bash
set -euo pipefail

APP="$HOME/Desktop/QuitenoteRunnerPython.app"
SCRIPT="$HOME/QuitenoteUITest/tools/gui_smoke_launcher.py"
LABEL="com.quitenote.ui-smoke-launcher"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/QuitenoteUITest/launcher-logs"

mkdir -p "$(dirname "$SCRIPT")" "$LOG_DIR"
cp "$(dirname "$0")/gui_smoke_launcher.py" "$SCRIPT"
chmod +x "$SCRIPT"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP/Contents/MacOS/Python</string>
    <string>$SCRIPT</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$LOG_DIR/launcher.stdout.log</string>
  <key>StandardErrorPath</key><string>$LOG_DIR/launcher.stderr.log</string>
</dict>
</plist>
EOF

launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "$PLIST"
launchctl kickstart -k gui/$(id -u)/$LABEL
sleep 1
pgrep -f "[g]ui_smoke_launcher.py"
echo "GUI launcher installed: $LABEL"
