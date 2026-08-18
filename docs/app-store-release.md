# Quite Note Mac App Store 发布

工程现在提供了独立的 App Store 发布脚本：

```bash
./build-app-store.sh 1.0.0
```

脚本会执行：

1. 使用 `./build-app.sh --app-store --no-launch` 构建沙盒应用。
2. 检查并嵌入匹配 `com.quitenote.app` 的 App Store provisioning profile。
3. 使用 Apple Distribution 证书签名应用。
4. 使用 Mac Installer Distribution 证书生成 `QuiteNote-<版本>-macOS.pkg`。
5. 校验应用签名和安装包签名。

## 首次配置

在 Apple Developer 后台完成以下项目：

- 为 `com.quitenote.app` 启用 App Sandbox，并确认应用使用的蓝牙、音频输入和网络能力。
- 创建 Mac App Store 类型的 provisioning profile，下载后放入：
  `~/Library/MobileDevice/Provisioning Profiles/`
- 在本机安装 Mac App Distribution 证书（部分系统显示为 Apple Distribution）。
- 在本机安装 Mac Installer Distribution 证书。

也可以通过环境变量显式指定 profile：

```bash
APP_STORE_PROVISIONING_PROFILE="/path/to/QuiteNote.provisionprofile" \
  ./build-app-store.sh 1.0.0
```

## 上传

把 App Store Connect API Key 的 `.p8` 文件放到：

```text
~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
```

然后执行：

```bash
ASC_KEY_ID="..." \
ASC_ISSUER_ID="..." \
  ./build-app-store.sh 1.0.0 --upload
```

上传完成后，仍需在 App Store Connect 中完成构建选择、商店元数据、隐私问卷、年龄分级、截图和审核提交。

## 当前本机状态

本机目前已检测到 Apple Development 和 Developer ID Application，但尚未检测到 Apple Distribution、Mac Installer Distribution 或匹配的 provisioning profile。因此脚本现在会安全地在前置检查阶段停止，不会生成不可提交的假包。
