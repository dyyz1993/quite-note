#!/bin/zsh
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <binary-path> <application-support-directory>" >&2
  exit 2
fi

binary=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
support=$(cd "$2" && pwd)
install_dir="$support/CoreService"
database="$support/ClipboardHistory.sqlite"
state="$install_dir/state.json"

mkdir -p "$install_dir"
install -m 0755 "$binary" "$install_dir/quitenote-core"

sed \
  -e "s|/usr/local/bin/quitenote-core|$install_dir/quitenote-core|g" \
  -e "s|/Users/SHARED/Library/Application Support/QuiteNote/ClipboardHistory.sqlite|$database|g" \
  -e "s|/Users/SHARED/Library/Application Support/QuiteNote/CoreService/state.json|$state|g" \
  "$(dirname "$0")/../cloud/quitenote-core/com.quitenote.core.plist" \
  > "$HOME/Library/LaunchAgents/com.quitenote.core.plist"

launchctl unload "$HOME/Library/LaunchAgents/com.quitenote.core.plist" >/dev/null 2>&1 || true
launchctl load "$HOME/Library/LaunchAgents/com.quitenote.core.plist"
launchctl print "gui/$(id -u)/com.quitenote.core" | head -20
