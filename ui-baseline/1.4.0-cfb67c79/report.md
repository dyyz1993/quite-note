# Quite Note UI Smoke Report

Result: **PASS**

| Case | Result | ms | Selector | Evidence / reason |
|---|---|---:|---|---|
| permissions.accessibility | PASS | 1069 | `` | recordings/ui-recording.mov |
| launch | PASS | 4113 | `` | screenshots/launch-1795838140.png (main 520x640 panel exposed via cgwindow; status menu item 剪贴板历史 discoverable (menu stays open; later suites tolerate it); storage=/tmp/quitenote-ui-smoke/ui-20261128-035531-cfb67c79) |
| flash-notes | PASS | 726 | `` | screenshots/flash-notes-1795838141.png (main 520x640 panel exposed) |
| clipboard | PASS | 1694 | `` | screenshots/clipboard-1795838142.png (clipboard 760x520 panel exposed) |
| launcher | PASS | 3210 | `` | screenshots/launcher-1795838146.png (launcher panel exposed) |
| settings | PASS | 8211 | `` | screenshots/settings-1795838154.png (settings overlay visible in 520x640 panel, tab bar AX-reachable, clipboard tab switch verified by content markers, closed; open-frame=screenshots/settings-open-1795838153.png (dismissed quick panels first: launcher/clipboard panels)) |
| devcore | PASS | 687 | `` | screenshots/devcore-1795838154.png (DevCore storage isolation available) |
| screenshot-toolbar | PASS | 37741 | `` | screenshots/screenshot-toolbar-1795838192.png (toolbar ok: 右缘换工具高亮 874→640（贴边让位 -233pt）、居中换工具高亮 370→370 未横跳；录制钮 1332/1062 均屏内；frames=screenshot-toolbar-frame-stage1_default-1795838163.png,screenshot-toolbar-frame-stage2_widened-1795838169.png,screenshot-toolbar-frame-stage3_mid_default-1795838181.png,screenshot-toolbar-frame-stage4_mid_text-1795838187.png) |
| cleanup | PASS | 796 | `` | screenshots/cleanup-1795838193.png (production pids: none) |
