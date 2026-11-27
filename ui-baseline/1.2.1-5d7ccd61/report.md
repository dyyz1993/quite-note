# Quite Note UI Smoke Report

Result: **PASS**

| Case | Result | ms | Selector | Evidence / reason |
|---|---|---:|---|---|
| permissions.accessibility | PASS | 1095 | `` | recordings/ui-recording.mov |
| launch | PASS | 751 | `` | screenshots/launch-1795776358.png (/tmp/quitenote-ui-smoke/ui-20261127-104551-5d7ccd61) |
| flash-notes | PASS | 735 | `` | screenshots/flash-notes-1795776358.png (main 520x640 panel exposed) |
| clipboard | PASS | 3530 | `` | screenshots/clipboard-1795776362.png (clipboard 760x520 panel exposed) |
| launcher | PASS | 3157 | `` | screenshots/launcher-1795776365.png (launcher panel exposed) |
| settings | PASS | 782 | `` | screenshots/settings-1795776366.png (settings AX flow available from main panel) |
| devcore | PASS | 657 | `` | screenshots/devcore-1795776366.png (DevCore storage isolation available) |
| screenshot-toolbar | PASS | 34644 | `` | screenshots/screenshot-toolbar-1795776401.png (toolbar ok: 右缘换工具高亮 874→640（贴边让位 -233pt）、居中换工具高亮 370→370 未横跳；录制钮 1332/1062 均屏内) |
| cleanup | PASS | 808 | `` | screenshots/cleanup-1795776402.png (production pids: none) |
