# Quite Note UI Smoke Report

Result: **PASS**

| Case | Result | ms | Selector | Evidence / reason |
|---|---|---:|---|---|
| permissions.accessibility | PASS | 1084 | `` | recordings/ui-recording.mov |
| launch | PASS | 4191 | `` | screenshots/launch-1795843115.png (main 520x640 panel exposed via cgwindow; status menu item 剪贴板历史 discoverable (menu stays open; later suites tolerate it); storage=/tmp/quitenote-ui-smoke/ui-20261128-051826-ee50fc54) |
| flash-notes | PASS | 711 | `` | screenshots/flash-notes-1795843116.png (main 520x640 panel exposed) |
| clipboard | PASS | 1703 | `` | screenshots/clipboard-1795843118.png (clipboard 760x520 panel exposed) |
| launcher | PASS | 3182 | `` | screenshots/launcher-1795843121.png (launcher panel exposed) |
| settings | PASS | 8196 | `` | screenshots/settings-1795843129.png (settings overlay visible in 520x640 panel, tab bar AX-reachable, clipboard tab switch verified by content markers, closed; open-frame=screenshots/settings-open-1795843128.png (dismissed quick panels first: launcher/clipboard panels)) |
| devcore | PASS | 683 | `` | screenshots/devcore-1795843130.png (DevCore storage isolation available) |
| screenshot-toolbar | PASS | 37705 | `` | screenshots/screenshot-toolbar-1795843167.png (toolbar ok: 右缘换工具高亮 874→640（贴边让位 -233pt）、居中换工具高亮 370→370 未横跳；录制钮 1332/1062 均屏内；frames=screenshot-toolbar-frame-stage1_default-1795843138.png,screenshot-toolbar-frame-stage2_widened-1795843144.png,screenshot-toolbar-frame-stage3_mid_default-1795843156.png,screenshot-toolbar-frame-stage4_mid_text-1795843163.png) |
| cleanup | PASS | 806 | `` | screenshots/cleanup-1795843168.png (production pids: none) |
