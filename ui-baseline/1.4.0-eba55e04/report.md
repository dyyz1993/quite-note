# Quite Note UI Smoke Report

Result: **PASS**

| Case | Result | ms | Selector | Evidence / reason |
|---|---|---:|---|---|
| permissions.accessibility | PASS | 1126 | `` | recordings/ui-recording.mov |
| launch | PASS | 4118 | `` | screenshots/launch-1795830989.png (main 520x640 panel exposed via cgwindow; status menu item 剪贴板历史 discoverable (menu stays open; later suites tolerate it); storage=/tmp/quitenote-ui-smoke/ui-20261128-015620-eba55e04) |
| flash-notes | PASS | 744 | `` | screenshots/flash-notes-1795830990.png (main 520x640 panel exposed) |
| clipboard | PASS | 1684 | `` | screenshots/clipboard-1795830991.png (clipboard 760x520 panel exposed) |
| launcher | PASS | 3273 | `` | screenshots/launcher-1795830995.png (launcher panel exposed) |
| settings | PASS | 8354 | `` | screenshots/settings-1795831003.png (settings overlay visible in 520x640 panel, tab bar AX-reachable, clipboard tab switch verified by content markers, closed; open-frame=screenshots/settings-open-1795831002.png (dismissed quick panels first: launcher/clipboard panels)) |
| devcore | PASS | 683 | `` | screenshots/devcore-1795831004.png (DevCore storage isolation available) |
| screenshot-toolbar | PASS | 37609 | `` | screenshots/screenshot-toolbar-1795831041.png (toolbar ok: 右缘换工具高亮 874→640（贴边让位 -233pt）、居中换工具高亮 370→370 未横跳；录制钮 1332/1062 均屏内；frames=screenshot-toolbar-frame-stage1_default-1795831012.png,screenshot-toolbar-frame-stage2_widened-1795831018.png,screenshot-toolbar-frame-stage3_mid_default-1795831030.png,screenshot-toolbar-frame-stage4_mid_text-1795831036.png) |
| cleanup | PASS | 798 | `` | screenshots/cleanup-1795831042.png (production pids: none) |
