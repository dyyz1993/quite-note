# Quite Note UI Smoke Report

Result: **PASS**

| Case | Result | ms | Selector | Evidence / reason |
|---|---|---:|---|---|
| permissions.accessibility | PASS | 1026 | `` | recordings/ui-recording.mov |
| launch | PASS | 4103 | `` | screenshots/launch-1795829036.png (main 520x640 panel exposed via cgwindow; status menu item 剪贴板历史 discoverable (menu stays open; later suites tolerate it); storage=/tmp/quitenote-ui-smoke/ui-20261128-012347-4712d130) |
| flash-notes | PASS | 719 | `` | screenshots/flash-notes-1795829036.png (main 520x640 panel exposed) |
| clipboard | PASS | 1688 | `` | screenshots/clipboard-1795829038.png (clipboard 760x520 panel exposed) |
| launcher | PASS | 3191 | `` | screenshots/launcher-1795829041.png (launcher panel exposed) |
| settings | PASS | 8254 | `` | screenshots/settings-1795829050.png (settings overlay visible in 520x640 panel, tab bar AX-reachable, clipboard tab switch verified by content markers, closed; open-frame=screenshots/settings-open-1795829048.png (dismissed quick panels first: launcher/clipboard panels)) |
| devcore | PASS | 673 | `` | screenshots/devcore-1795829050.png (DevCore storage isolation available) |
| screenshot-toolbar | PASS | 37665 | `` | screenshots/screenshot-toolbar-1795829088.png (toolbar ok: 右缘换工具高亮 874→640（贴边让位 -233pt）、居中换工具高亮 370→370 未横跳；录制钮 1332/1062 均屏内；frames=screenshot-toolbar-frame-stage1_default-1795829059.png,screenshot-toolbar-frame-stage2_widened-1795829065.png,screenshot-toolbar-frame-stage3_mid_default-1795829077.png,screenshot-toolbar-frame-stage4_mid_text-1795829083.png) |
| cleanup | PASS | 798 | `` | screenshots/cleanup-1795829089.png (production pids: none) |
