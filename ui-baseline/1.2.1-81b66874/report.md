# Quite Note UI Smoke Report

Result: **PASS**

| Case | Result | ms | Selector | Evidence / reason |
|---|---|---:|---|---|
| permissions.accessibility | PASS | 1040 | `` | recordings/ui-recording.mov |
| launch | PASS | 710 | `` | screenshots/launch-1795787202.png (/tmp/quitenote-ui-smoke/ui-20261127-134635-81b66874) |
| flash-notes | PASS | 745 | `` | screenshots/flash-notes-1795787202.png (main 520x640 panel exposed) |
| clipboard | PASS | 3557 | `` | screenshots/clipboard-1795787206.png (clipboard 760x520 panel exposed) |
| launcher | PASS | 3185 | `` | screenshots/launcher-1795787209.png (launcher panel exposed) |
| settings | PASS | 763 | `` | screenshots/settings-1795787210.png (settings AX flow available from main panel) |
| devcore | PASS | 705 | `` | screenshots/devcore-1795787211.png (DevCore storage isolation available) |
| screenshot-toolbar | PASS | 34880 | `` | screenshots/screenshot-toolbar-1795787245.png (toolbar ok: 右缘换工具高亮 874→640（贴边让位 -233pt）、居中换工具高亮 370→370 未横跳；录制钮 1332/1062 均屏内) |
| cleanup | PASS | 802 | `` | screenshots/cleanup-1795787246.png (production pids: none) |
