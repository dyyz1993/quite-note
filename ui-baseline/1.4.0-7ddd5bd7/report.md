# Quite Note UI Smoke Report

Result: **PASS**

| Case | Result | ms | Selector | Evidence / reason |
|---|---|---:|---|---|
| permissions.accessibility | PASS | 958 | `` | recordings/ui-recording.mov |
| launch | PASS | 4287 | `` | screenshots/launch-1795843950.png (main 520x640 panel exposed via cgwindow; status menu item 剪贴板历史 discoverable (menu stays open; later suites tolerate it); storage=/tmp/quitenote-ui-smoke/ui-20261128-053221-7ddd5bd7) |
| flash-notes | PASS | 671 | `` | screenshots/flash-notes-1795843951.png (main 520x640 panel exposed) |
| clipboard | PASS | 1679 | `` | screenshots/clipboard-1795843952.png (clipboard 760x520 panel exposed) |
| launcher | PASS | 3141 | `` | screenshots/launcher-1795843955.png (launcher panel exposed) |
| settings | PASS | 8249 | `` | screenshots/settings-1795843964.png (settings overlay visible in 520x640 panel, tab bar AX-reachable, clipboard tab switch verified by content markers, closed; open-frame=screenshots/settings-open-1795843962.png (dismissed quick panels first: launcher/clipboard panels)) |
| devcore | PASS | 688 | `` | screenshots/devcore-1795843964.png (DevCore storage isolation available) |
| screenshot-toolbar | PASS | 37542 | `` | screenshots/screenshot-toolbar-1795844002.png (toolbar ok: 右缘换工具高亮 874→640（贴边让位 -233pt）、居中换工具高亮 370→370 未横跳；录制钮 1332/1062 均屏内；frames=screenshot-toolbar-frame-stage1_default-1795843973.png,screenshot-toolbar-frame-stage2_widened-1795843979.png,screenshot-toolbar-frame-stage3_mid_default-1795843991.png,screenshot-toolbar-frame-stage4_mid_text-1795843997.png) |
| cleanup | PASS | 811 | `` | screenshots/cleanup-1795844003.png (production pids: none) |
