# Quite Note UI Smoke Report

Result: **PASS**

| Case | Result | ms | Selector | Evidence / reason |
|---|---|---:|---|---|
| permissions.accessibility | PASS | 1062 | `` | recordings/ui-recording.mov |
| launch | PASS | 718 | `` | screenshots/launch-1795770406.png (/tmp/quitenote-ui-smoke/ui-20261127-090640-8835b44c) |
| flash-notes | PASS | 749 | `` | screenshots/flash-notes-1795770407.png (main 520x640 panel exposed) |
| clipboard | PASS | 3520 | `` | screenshots/clipboard-1795770411.png (clipboard 760x520 panel exposed) |
| launcher | PASS | 3199 | `` | screenshots/launcher-1795770414.png (launcher panel exposed) |
| settings | PASS | 785 | `` | screenshots/settings-1795770415.png (settings AX flow available from main panel) |
| devcore | PASS | 723 | `` | screenshots/devcore-1795770415.png (DevCore storage isolation available) |
| screenshot-toolbar | PASS | 34835 | `` | screenshots/screenshot-toolbar-1795770450.png (toolbar ok: 右缘换工具高亮 874→640（贴边让位 -233pt）、居中换工具高亮 370→370 未横跳；录制钮 1332/1062 均屏内) |
| cleanup | PASS | 799 | `` | screenshots/cleanup-1795770451.png (production pids: none) |
