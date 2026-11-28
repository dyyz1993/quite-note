# Quite Note UI Smoke Report

Result: **PASS**

| Case | Result | ms | Selector | Evidence / reason |
|---|---|---:|---|---|
| permissions.accessibility | PASS | 1038 | `` | recordings/ui-recording.mov |
| launch | PASS | 4097 | `` | screenshots/launch-1795831571.png (main 520x640 panel exposed via cgwindow; status menu item 剪贴板历史 discoverable (menu stays open; later suites tolerate it); storage=/tmp/quitenote-ui-smoke/ui-20261128-020602-986b9421) |
| flash-notes | PASS | 717 | `` | screenshots/flash-notes-1795831571.png (main 520x640 panel exposed) |
| clipboard | PASS | 1678 | `` | screenshots/clipboard-1795831573.png (clipboard 760x520 panel exposed) |
| launcher | PASS | 3256 | `` | screenshots/launcher-1795831576.png (launcher panel exposed) |
| settings | PASS | 8204 | `` | screenshots/settings-1795831584.png (settings overlay visible in 520x640 panel, tab bar AX-reachable, clipboard tab switch verified by content markers, closed; open-frame=screenshots/settings-open-1795831583.png (dismissed quick panels first: launcher/clipboard panels)) |
| devcore | PASS | 688 | `` | screenshots/devcore-1795831585.png (DevCore storage isolation available) |
| screenshot-toolbar | PASS | 37721 | `` | screenshots/screenshot-toolbar-1795831623.png (toolbar ok: 右缘换工具高亮 874→640（贴边让位 -233pt）、居中换工具高亮 370→370 未横跳；录制钮 1332/1062 均屏内；frames=screenshot-toolbar-frame-stage1_default-1795831594.png,screenshot-toolbar-frame-stage2_widened-1795831599.png,screenshot-toolbar-frame-stage3_mid_default-1795831612.png,screenshot-toolbar-frame-stage4_mid_text-1795831618.png) |
| cleanup | PASS | 813 | `` | screenshots/cleanup-1795831624.png (production pids: none) |
