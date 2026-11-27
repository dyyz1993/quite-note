# Quite Note UI Smoke Report

Result: **PASS**

| Case | Result | ms | Selector | Evidence / reason |
|---|---|---:|---|---|
| permissions.accessibility | PASS | 1053 | `` | recordings/ui-recording.mov |
| launch | PASS | 729 | `` | screenshots/launch-1795760967.png (/tmp/quitenote-ui-smoke/ui-20261127-062921-8c52a79b) |
| flash-notes | PASS | 726 | `` | screenshots/flash-notes-1795760968.png (main 520x640 panel exposed) |
| clipboard | PASS | 3532 | `` | screenshots/clipboard-1795760971.png (clipboard 760x520 panel exposed) |
| launcher | PASS | 3192 | `` | screenshots/launcher-1795760974.png (launcher panel exposed) |
| settings | PASS | 772 | `` | screenshots/settings-1795760975.png (settings AX flow available from main panel) |
| devcore | PASS | 773 | `` | screenshots/devcore-1795760976.png (DevCore storage isolation available) |
| screenshot-toolbar | PASS | 34946 | `` | screenshots/screenshot-toolbar-1795761011.png (toolbar ok: 右缘换工具高亮 874→640（贴边让位 -233pt）、居中换工具高亮 370→370 未横跳；录制钮 1332/1062 均屏内) |
| cleanup | PASS | 793 | `` | screenshots/cleanup-1795761012.png (production pids: none) |
