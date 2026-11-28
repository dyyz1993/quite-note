# Quite Note UI Smoke Report

Result: **PASS**

| Case | Result | ms | Selector | Evidence / reason |
|---|---|---:|---|---|
| permissions.accessibility | PASS | 1138 | `` | recordings/ui-recording.mov |
| launch | PASS | 4101 | `` | screenshots/launch-1795868443.png (main 520x640 panel exposed via cgwindow; status menu item 剪贴板历史 discoverable (menu stays open; later suites tolerate it); storage=/tmp/quitenote-ui-smoke/ui-20261128-122034-b4c679a2) |
| flash-notes | PASS | 735 | `` | screenshots/flash-notes-1795868444.png (main 520x640 panel exposed) |
| clipboard | PASS | 1713 | `` | screenshots/clipboard-1795868446.png (clipboard 760x520 panel exposed) |
| launcher | PASS | 3203 | `` | screenshots/launcher-1795868449.png (launcher panel exposed) |
| settings | PASS | 8261 | `` | screenshots/settings-1795868457.png (settings overlay visible in 520x640 panel, tab bar AX-reachable, clipboard tab switch verified by content markers, closed; open-frame=screenshots/settings-open-1795868456.png (dismissed quick panels first: launcher/clipboard panels)) |
| devcore | PASS | 680 | `` | screenshots/devcore-1795868458.png (DevCore storage isolation available) |
| screenshot-toolbar | PASS | 37742 | `` | screenshots/screenshot-toolbar-1795868496.png (toolbar ok: 右缘换工具高亮 874→640（贴边让位 -233pt）、居中换工具高亮 370→370 未横跳；录制钮 1332/1062 均屏内；frames=screenshot-toolbar-frame-stage1_default-1795868466.png,screenshot-toolbar-frame-stage2_widened-1795868472.png,screenshot-toolbar-frame-stage3_mid_default-1795868485.png,screenshot-toolbar-frame-stage4_mid_text-1795868491.png) |
| cleanup | PASS | 799 | `` | screenshots/cleanup-1795868496.png (production pids: none) |
