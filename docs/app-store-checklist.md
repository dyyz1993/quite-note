# QuiteNote Mac App Store 上架进度表

> 真值文档。每完成一项就更新本文件的日期和勾选状态；发布相关的账号凭据明细见桌面
> `QuiteNote-App-Store-发布信息汇总.md`（不进仓库）。构建操作手册见
> [app-store-release.md](app-store-release.md)，商店文案素材见
> [app-store-metadata-draft.md](app-store-metadata-draft.md)。

**最近更新：2026-09-03（中国大陆正式上架）**

> 当前状态：版本 `1.0`（构建 `1.0.0 (5)`）已通过审核。2026-09-03 已创建供应范围并仅启用中国大陆（`CHN`）；App Store Connect 回读为 `AVAILABLE`，中国区公开商店查询已返回 Quite Note，价格为免费。其余 174 个地区保持关闭，新增地区不会自动开放。

> 🚀 **2026-08-21 经 ASC API（key 4NXJ8HL7K9）自动完成**：版本页元数据（描述/关键词/推广文本/URL）、副标题+隐私政策 URL、usesIdfa=false、年龄分级问卷（全无 → 4+）、审核备注（完整权限用途口径）、3 张 2560×1600 截图上传并处理 COMPLETE（旧的 2 张 1280×800 已删除）。构建 1.0.0 已关联。审核联系人系用户此前已填（许映洲/+8613751880018）。
> ✅ **2026-08-21 提交前检查单 5 缺口已清 4**（经 API）：出口合规（build `usesNonExemptEncryption=false`）、主类别（PRODUCTIVITY）、定价（免费，base USA，`appPricePoint` 关系名是踩坑点）、内容版权（本就已有 `© 2026 QuiteNote`，刷新即消）。年龄分级生效 FOUR_PLUS。
> ⛔ **仅剩 1 项必须网页做**：**App 隐私**（隐私营养标签问卷不在公开 REST API，且要求管理职能用户）——ASC 网页 → QuiteNote → 左栏「App 隐私」→ 开始填写 → 选 **「不从此 App 收集数据」**（Data Not Collected）→ 发布。之后版本页「添加以供审核」→ 提交即齐。JWT 工具在 `/tmp/asc/api.py`（ASC_ISSUER_ID=18f47979-…）。

> 📁 **提审资料总览（含电话/版权/文案定稿/问卷答案/审核备注）**：`app-store-submission/README-提交总览.md`（目录已 gitignore，不进仓库）；商店截图在 `app-store-submission/screenshots/final/`。

## 一句话状态

打包 → 签名 → pkg → 上传 → Apple 处理 → 审核 → 地区供应全链路已打通；
**Quite Note 1.0 已在中国大陆 App Store 免费上架。**

## 已完成 ✅

| 项目 | 状态 | 说明 / 时间 |
|---|---|---|
| Apple Distribution 应用签名证书 | ✅ | 钥匙串 `3rd Party Mac Developer Application: xu yingzhou (B45VZCNYU3)`（系统也认 Apple Distribution 名称），2026-08-18 |
| Mac Installer Distribution 打包证书 | ✅ | 钥匙串 `3rd Party Mac Developer Installer: xu yingzhou (B45VZCNYU3)`，2027-08 到期 |
| App ID + App Store Provisioning Profile | ✅ | `B45VZCNYU3.com.quitenote.app`，profile 已装 `~/Library/MobileDevice/Provisioning Profiles/QuiteNote_Mac_App_Store.provisionprofile`，有效期至 2027-08-18 |
| App Store Connect 应用记录 | ✅ | ASC App ID `6802559186` |
| ASC 上传凭据（API Key） | ✅ | `~/.appstoreconnect/private_keys/`，上传用 Developer 团队密钥（Issuer ID 不进仓库） |
| 沙盒 entitlements | ✅ | `QuiteNote-AppStore.entitlements`：sandbox + 网络客户端 + 音频输入 + 用户选择目录 + app-scope bookmark；**没有**全局 Downloads 目录权限 |
| 一键打包脚本 | ✅ | `./build-app-store.sh <版本> [--upload]`（构建→签名→pkg→可选上传）；`build-app.sh --app-store` 可本地沙盒验证 |
| 沙盒代码适配 | ✅ | commit `f9e68b5`（书签存储 + 隐私合规）+ `6404fc2`（附件/截图/录屏保存目录全部安全书签化）；最低系统 12.0→13.0，补齐权限用途描述 |
| 隐私合规 | ✅ | AI 日志不记录 API key 片段；AI 新装默认关；设置页明确数据外发文案 |
| 隐私政策网站上线上 | ✅ | https://quitenote-privacy.pages.dev/（中英双语，2026-08-18 生效） |
| pkg 构建验证 | ✅ | `QuiteNote-1.0.0-macOS.pkg` 双签名校验通过 |
| **上传 App Store Connect** | ✅ | 2026-08-18，Delivery UUID `29b15c46-d246-440f-bef4-2d38a1371b5b`，Apple 处理结果 `VALID`，构建状态 `APP_STORE_ELIGIBLE` |
| **拒审修复构建 4 上传并重提** | ✅ | 2026-08-26，Delivery UUID `15a5a371-9b31-42ee-8454-78732b09b5e5`；构建 4 `VALID`，已替换构建 2，审核备注已更新，Submission 状态 `WAITING_FOR_REVIEW` |
| **拒审修复构建 5 构建与上传** | ✅ | 2026-08-28：移除 Downloads 权限；最终签名 `.app` 回读确认该权限不存在；123 tests 全绿。已上传至 App Store Connect（Delivery UUID 已记录于上传日志），等待 Apple 处理。 |
| **拒审修复构建 5 关联并重提** | ✅ | 2026-08-28：Apple 处理状态 `VALID`；原提交中 build 4 已精确替换为 build 5，审核项已恢复为 `READY_FOR_REVIEW`，原 Submission 已重新提交并回读为 `WAITING_FOR_REVIEW`。 |
| **App Review 通过** | ✅ | 版本 1.0 / 构建 5 已获批，版本状态为可分发。 |
| **中国大陆供应范围** | ✅ | 2026-09-03：通过 App Store Connect API v2 创建全部 175 个地区的供应记录，仅 `CHN` 设为可用；最终回读 `contentStatuses=[AVAILABLE]`，中国区公开查询返回免费版本 1.0。 |

## 首次上架完成情况

1. ✅ **macOS 截图**：3 张 2560×1600 已生成于 `app-store-submission/screenshots/final/`（2026-08-21，**Dev 变体（隔离库）+ 精选示例记录**合成，无生产数据/隐私问题——像素级验证过素材来源）。重制方法见资料总览第 7 节。
2. ✅ **版本页元数据**：文案已填写（副标题/关键词/推广文本/描述/版权 `© 2026 xu yingzhou`）。
3. ✅ **App 隐私问卷**（App Privacy）：已按开发者不收集数据口径发布，隐私政策网址为 pages.dev 地址。
4. ✅ **年龄分级 + 出口合规问卷**：已完成（4+ / 出口合规豁免）。
5. ✅ **审核联系信息**：姓名/邮箱/电话（+86 137 5188 0018）已定稿；App 无登录，无需提供账号。审核备注（Review Notes）也已拟好（资料总览第 3 节）。
6. ✅ **在版本页选择构建**：最终审核构建为 `1.0.0 (5)`。
7. ✅ **提审并通过**：原 Submission 经修复后通过审核；2026-09-03 完成中国大陆供应设置并验证公开商店结果。

## 提审前建议的验证（非阻塞，但强烈建议）

- ✅ **悬浮球还原动画崩溃（已修复，2026-08-21）**：曾三次触发 `NSGenericException "Update Constraints in Window pass"`（crash-1787244990 / 1787248218 / 1787248582）。根因：「SwiftUI 内容过渡动画（withAnimation）」与「窗口逐帧 resize」并发时，NSHostingView 会把过渡期理想尺寸经 updateAnimatedWindowSize 回写窗口，约束循环闪退。**最终定版修复**（经 6 版动画迭代后落在 commit 9aa0a7a + 4c362b5）：展开=纯窗口生长动画（0.25s easeInEaseOut）+ 内容瞬时切换（不包 withAnimation/transition）+ `isAnimatingWindowFrame` 标志抑制动画期间逐帧写 UserDefaults。⚠️ 注意：`FloatingBallController` 是无引用死代码（真路径在 `FloatingPanelController.restoreFromBall`），别改错文件。全套 103 测试绿。
- ⬜ **沙盒 pkg 实机冒烟**：`pkgutil --expand` 或直接安装 `QuiteNote-1.0.0-macOS.pkg`，过一遍核心链路：
  - 剪贴板记录 + 搜索（NSPasteboard 轮询，沙盒可用）
  - 截图选区 + 标注 + OCR（ScreenCaptureKit + TCC，沙盒下需实测授权弹窗行为）
  - 区域录屏 + 快剪导出（SCK 系统声 / 麦克风 entitlement 已带）
  - 全局快捷键（Carbon RegisterEventHotKey，沙盒可用）；直接粘贴是可选功能，未授权辅助功能时必须先复制并允许用户手动按 ⌘V
  - 保存目录选择（安全书签，二次启动仍可写）
  - AI 摘要（network.client 已带，用户自配接口）
- ⬜ **失败项要有降级**：任一权限被拒时功能要优雅降级而不是崩溃/假死（审核会拔权限测试）。
- ⬜ **审核应对口径**：屏幕录制/剪贴板仅在本机处理、不上传服务器；App 启动不会请求辅助功能或打开系统设置；仅用户主动点「直接粘贴」才可选择前往授权。AI 功能默认关闭且用户自配第三方接口（隐私政策已如此声明）。

## 版本号策略（两渠道并行）

| 渠道 | 身份 | 当前版本 | 说明 |
|---|---|---|---|
| 官网/GitHub DMG | Developer ID + 公证 | 1.3.x | `./build-release.sh <版本>` |
| Mac App Store | Apple Distribution + 沙盒 | 1.0.0 | `./build-app-store.sh <版本> [--upload]` |

两渠道互不升级、版本号独立演进是允许的；但为避免用户困惑，App Store 版后续可一次性追平到与 DMG 相同的功能版本号（提审前定夺即可，不阻塞首次上架）。

## 常用命令

```bash
# 打 App Store 包（产物 QuiteNote-<版本>-macOS.pkg）
./build-app-store.sh 1.0.0

# 打包并直接上传 App Store Connect（需 ~/.appstoreconnect/private_keys/ 的 key）
ASC_KEY_ID="..." ASC_ISSUER_ID="..." ./build-app-store.sh 1.0.0 --upload

# 校验
pkgutil --check-signature QuiteNote-1.0.0-macOS.pkg
codesign --verify --strict --verbose=2 "Quite Note.app"
codesign --display --entitlements :- "Quite Note.app"   # 应含 com.apple.security.app-sandbox
```

## 审核被拒的常见预案

- **2.4.5 硬件兼容性**：拒绝屏幕录制/辅助功能后启动 App 不能假死或跳转系统设置；截图触发时才展示屏幕录制引导，直接粘贴触发时才说明辅助功能为可选权限，并始终保留手动 ⌘V 降级路径。
- **2.3 准确元数据**：截图必须来自真实 App 界面，不夸大 AI 能力。
- **5.1.1 隐私**：隐私问卷与实际行为一致——剪贴板/截图默认仅本机，AI 明确可选且外发地址用户自配。
- **4.2 最小化功能**：菜单栏工具已多见，风险低；描述里强调"本地优先的剪贴板/截图/录屏效率工具"。
