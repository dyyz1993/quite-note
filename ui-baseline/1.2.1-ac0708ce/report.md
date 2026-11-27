# Quite Note UI Smoke Report

Result: **PASS**

| Case | Result | ms | Selector | Evidence / reason |
|---|---|---:|---|---|
| permissions.accessibility | PASS | 1025 | `` | recordings/ui-recording.mov |
| launch | PASS | 973 | `` | screenshots/launch-1795795984.png (/tmp/quitenote-ui-smoke/ui-20261127-161258-ac0708ce) |
| flash-notes | PASS | 804 | `` | screenshots/flash-notes-1795795984.png (main 520x640 panel exposed) |
| clipboard | PASS | 3547 | `` | screenshots/clipboard-1795795988.png (clipboard 760x520 panel exposed) |
| launcher | PASS | 3247 | `` | screenshots/launcher-1795795991.png (launcher panel exposed) |
| settings | PASS | 765 | `` | screenshots/settings-1795795992.png (settings AX flow available from main panel) |
| devcore | PASS | 648 | `` | screenshots/devcore-1795795993.png (DevCore storage isolation available) |
| screenshot-toolbar | PASS | 34759 | `` | screenshots/screenshot-toolbar-1795796027.png (toolbar ok: 右缘换工具高亮 874→640（贴边让位 -233pt）、居中换工具高亮 370→370 未横跳；录制钮 1332/1062 均屏内) |
| cleanup | PASS | 798 | `` | screenshots/cleanup-1795796028.png (production pids: none) |
