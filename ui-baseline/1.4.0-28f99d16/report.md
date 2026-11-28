# Quite Note UI Smoke Report

Result: **PASS**

| Case | Result | ms | Selector | Evidence / reason |
|---|---|---:|---|---|
| permissions.accessibility | PASS | 1055 | `` | recordings/ui-recording.mov |
| launch | PASS | 4137 | `` | screenshots/launch-1795835924.png (main 520x640 panel exposed via cgwindow; status menu item 剪贴板历史 discoverable (menu stays open; later suites tolerate it); storage=/tmp/quitenote-ui-smoke/ui-20261128-031835-28f99d16) |
| flash-notes | PASS | 725 | `` | screenshots/flash-notes-1795835925.png (main 520x640 panel exposed) |
| clipboard | PASS | 1710 | `` | screenshots/clipboard-1795835927.png (clipboard 760x520 panel exposed) |
| launcher | PASS | 3310 | `` | screenshots/launcher-1795835930.png (launcher panel exposed) |
| settings | PASS | 8296 | `` | screenshots/settings-1795835938.png (settings overlay visible in 520x640 panel, tab bar AX-reachable, clipboard tab switch verified by content markers, closed; open-frame=screenshots/settings-open-1795835937.png (dismissed quick panels first: launcher/clipboard panels)) |
| devcore | PASS | 688 | `` | screenshots/devcore-1795835939.png (DevCore storage isolation available) |
| screenshot-toolbar | PASS | 38003 | `` | screenshots/screenshot-toolbar-1795835977.png (toolbar ok: 右缘换工具高亮 874→640（贴边让位 -233pt）、居中换工具高亮 370→370 未横跳；录制钮 1332/1062 均屏内；frames=screenshot-toolbar-frame-stage1_default-1795835947.png,screenshot-toolbar-frame-stage2_widened-1795835953.png,screenshot-toolbar-frame-stage3_mid_default-1795835966.png,screenshot-toolbar-frame-stage4_mid_text-1795835972.png) |
| cleanup | PASS | 799 | `` | screenshots/cleanup-1795835978.png (production pids: none) |
