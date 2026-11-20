#!/bin/bash
# 剪贴板面板键盘链路 E2E v2（xyz-mac）：footer 断言走 PyObjC，按键走 System Events
set -uo pipefail
APP=$(ls -d /Users/xyz/actions-runner-quitenote/_work/quite-note/quite-note/.ui-smoke-worktrees/d1554fd*/Quite\ Note\ Dev.app 2>/dev/null | head -1)
PY="$HOME/Desktop/QuitenoteRunnerPython.app/Contents/MacOS/Python"
LOG_DIR="$HOME/Library/Application Support/com.quitenote.app.dev/Logs"
LOG=$(ls -t "$LOG_DIR"/app-*.log 2>/dev/null | head -1)

footer() {  # 输出剪贴板面板 footer 文本（无面板输出空）
"$PY" - <<'PYEOF'
from ApplicationServices import AXUIElementCreateApplication, AXUIElementCopyAttributeValue, AXValueGetValue, kAXValueCGSizeType
from AppKit import NSWorkspace
pid = next((a.processIdentifier() for a in NSWorkspace.sharedWorkspace().runningApplications()
            if a.bundleIdentifier() == "com.quitenote.app.dev"), None)
if not pid: print(""); raise SystemExit
def texts(el, depth=0, acc=None):
    if acc is None: acc = []
    if depth > 12 or len(acc) > 3000: return acc
    _, role = AXUIElementCopyAttributeValue(el, "AXRole", None)
    if role == "AXStaticText":
        _, v = AXUIElementCopyAttributeValue(el, "AXValue", None)
        if v: acc.append(str(v))
    _, kids = AXUIElementCopyAttributeValue(el, "AXChildren", None)
    for k in (kids or []): texts(k, depth + 1, acc)
    return acc
appEl = AXUIElementCreateApplication(pid)
_, wins = AXUIElementCopyAttributeValue(appEl, "AXWindows", None)
for w in (wins or []):
    _, szref = AXUIElementCopyAttributeValue(w, "AXSize", None)
    ok, size = (AXValueGetValue(szref, kAXValueCGSizeType, None) if szref else (None, None))
    if size and 700 < size.width < 800 and 450 < size.height < 600:
        f = [v for v in texts(w) if v.startswith("第 ")]
        print(f[0] if f else ""); raise SystemExit
print("")
PYEOF
}

panel_open() { [[ "$(footer)" == 第* ]]; }

# 1) 重启 + 唤醒
osascript -e 'tell application id "com.quitenote.app.dev" to quit' 2>/dev/null
sleep 1.5; open -a "$APP"; (caffeinate -u -d -t 240 >/dev/null 2>&1 &); sleep 4
MARK=$(wc -l < "$LOG" 2>/dev/null | tr -d "[:space:]"); MARK=${MARK:-0}

# 2) 打开剪贴板面板
osascript <<'OSA'
tell application "System Events"
  tell process "QuiteNoteDev"
    set frontmost to true
    click menu bar item 1 of menu bar 2
    delay 0.4
    click menu item "剪贴板历史" of menu 1 of menu bar item 1 of menu bar 2
  end tell
end tell
OSA
sleep 1.5
F0=$(footer); echo "footer 初始: '$F0'"
panel_open || { echo "FAIL: 面板未开"; exit 1; }

# 3) ↑↓ 导航（local monitor 路径）
osascript -e 'tell application "System Events" to key code 125'; sleep 0.4
osascript -e 'tell application "System Events" to key code 125'; sleep 0.4
osascript -e 'tell application "System Events" to key code 126'; sleep 0.6
F1=$(footer); echo "footer ↓↓↑后: '$F1'"
[[ "$F1" != "$F0" ]] && echo "PASS: ↑↓ 选中移动" || echo "FAIL: ↑↓ 未移动"

# 4) ⌘1 直贴（Carbon 兜底传输判定=日志）
osascript -e 'tell application "System Events" to key code 18 using command down'; sleep 2
if tail -n +$MARK "$LOG" | grep -q "Carbon 兜底按键：pasteIndex(1)"; then
  echo "PASS: ⌘1 Carbon 兜底传输（日志实锤）"
else
  echo "FAIL: ⌘1 无 Carbon 兜底日志"; tail -n +$MARK "$LOG" | grep -E "Clipboard|兜底" | tail -4
fi
sleep 0.5
panel_open && echo "WARN: ⌘1 后面板未收起" || echo "PASS: ⌘1 粘贴后自动收起"

# 5) 重开 + ESC 关闭（Carbon 5004）
osascript <<'OSA'
tell application "System Events"
  tell process "QuiteNoteDev"
    set frontmost to true
    click menu bar item 1 of menu bar 2
    delay 0.4
    click menu item "剪贴板历史" of menu 1 of menu bar item 1 of menu bar 2
  end tell
end tell
OSA
sleep 1.2
osascript -e 'tell application "System Events" to key code 53'; sleep 0.8
panel_open && echo "FAIL: ESC 未关闭面板" || echo "PASS: ESC 关闭面板"

echo "=== 日志尾部 ==="; tail -n +$MARK "$LOG" | grep -E "Clipboard|兜底" | tail -8
