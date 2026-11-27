# Quite Note UI Smoke Report

Result: **PASS**

| Case | Result | ms | Selector | Evidence / reason |
|---|---|---:|---|---|
| permissions.accessibility | PASS | 1060 | `` | recordings/ui-recording.mov |
| launch | PASS | 739 | `` | screenshots/launch-1795795024.png (/tmp/quitenote-ui-smoke/ui-20261127-155659-46a89158) |
| flash-notes | PASS | 734 | `` | screenshots/flash-notes-1795795025.png (main 520x640 panel exposed) |
| clipboard | PASS | 3532 | `` | screenshots/clipboard-1795795029.png (clipboard 760x520 panel exposed) |
| launcher | PASS | 3202 | `` | screenshots/launcher-1795795032.png (launcher panel exposed) |
| settings | PASS | 680 | `` | screenshots/settings-1795795032.png (settings AX flow available from main panel) |
| devcore | PASS | 724 | `` | screenshots/devcore-1795795033.png (DevCore storage isolation available) |
| screenshot-toolbar | PASS | 34599 | `` | screenshots/screenshot-toolbar-1795795068.png (toolbar ok: 右缘换工具高亮 874→640（贴边让位 -233pt）、居中换工具高亮 370→370 未横跳；录制钮 1332/1062 均屏内) |
| cleanup | PASS | 803 | `` | screenshots/cleanup-1795795069.png (production pids: none) |
