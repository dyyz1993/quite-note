# Quite Note UI Smoke Report

Result: **PASS**

| Case | Result | ms | Selector | Evidence / reason |
|---|---|---:|---|---|
| permissions.accessibility | PASS | 1033 | `` | recordings/ui-recording.mov |
| launch | PASS | 4104 | `` | screenshots/launch-1795837621.png (main 520x640 panel exposed via cgwindow; status menu item 剪贴板历史 discoverable (menu stays open; later suites tolerate it); storage=/tmp/quitenote-ui-smoke/ui-20261128-034652-775686fc) |
| flash-notes | PASS | 735 | `` | screenshots/flash-notes-1795837622.png (main 520x640 panel exposed) |
| clipboard | PASS | 1679 | `` | screenshots/clipboard-1795837624.png (clipboard 760x520 panel exposed) |
| launcher | PASS | 3177 | `` | screenshots/launcher-1795837627.png (launcher panel exposed) |
| settings | PASS | 8226 | `` | screenshots/settings-1795837635.png (settings overlay visible in 520x640 panel, tab bar AX-reachable, clipboard tab switch verified by content markers, closed; open-frame=screenshots/settings-open-1795837634.png (dismissed quick panels first: launcher/clipboard panels)) |
| devcore | PASS | 679 | `` | screenshots/devcore-1795837636.png (DevCore storage isolation available) |
| screenshot-toolbar | PASS | 37894 | `` | screenshots/screenshot-toolbar-1795837674.png (toolbar ok: 右缘换工具高亮 874→640（贴边让位 -233pt）、居中换工具高亮 370→370 未横跳；录制钮 1332/1062 均屏内；frames=screenshot-toolbar-frame-stage1_default-1795837644.png,screenshot-toolbar-frame-stage2_widened-1795837650.png,screenshot-toolbar-frame-stage3_mid_default-1795837663.png,screenshot-toolbar-frame-stage4_mid_text-1795837669.png) |
| cleanup | PASS | 794 | `` | screenshots/cleanup-1795837675.png (production pids: none) |
