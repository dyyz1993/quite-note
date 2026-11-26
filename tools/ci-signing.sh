#!/bin/bash
# CI 签名公共库：把 secrets 里的 Developer ID 证书导入临时钥匙串、解析签名身份、job 结束销毁。
#
# build-macos.yml / ui-smoke.yml / release.yml 共用。此前三处各抄一份：2026-11-25 修
# 「list-keychains 把登录钥匙串挤出搜索列表」时只改了前两份，release.yml 留着旧写法——
# 同一件事多处拷贝必然漂移，所以收成一份。改这里之后要 grep 三个 workflow 里有没有残留的
# 内联写法（security create-keychain / list-keychains / set-key-partition-list）。
#
# 用法（workflow 的 run 段，默认 shell 是 bash）：
#   source "$GITHUB_WORKSPACE/tools/ci-signing.sh"
#   ci_signing_prepare "<p12 的 base64>" "<p12 密码>" "<临时钥匙串密码>"
#   …
#   ci_signing_cleanup            # 放在 if: always() 的步骤里
#
# ci_signing_prepare 成功后：Developer ID 的 SHA-1 指纹追加到 $GITHUB_ENV 的
# APP_SIGN_IDENTITY（build-app.sh 优先用它签名）。

# 临时钥匙串放 RUNNER_TEMP：job 结束 runner 自己会清
ci_signing_keychain_path() {
    printf '%s/qn-signing.keychain-db' "${RUNNER_TEMP:?RUNNER_TEMP 未设置（这个库只能在 GitHub Actions 的 job 里用）}"
}

#   $1  .p12 的 base64（MAC_CERTIFICATE_P12_BASE64）
#   $2  .p12 的密码（MAC_CERTIFICATE_PASSWORD）
#   $3  临时钥匙串的密码
ci_signing_prepare() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        echo "::error::签名 secrets 没配齐（MAC_CERTIFICATE_P12_BASE64 / MAC_CERTIFICATE_PASSWORD / KEYCHAIN_PASSWORD）"
        return 2
    fi

    local cert keychain identity
    cert="$RUNNER_TEMP/qn-signing-certificate.p12"
    keychain="$(ci_signing_keychain_path)"

    printf '%s' "$1" | base64 --decode -o "$cert"
    # 自托管 runner 上上一个 job 若被强杀、没走到 cleanup，同名钥匙串文件和搜索列表里的登记会留着。
    # 先按钥匙串删一次（delete-keychain 连同搜索列表里的登记一起清），再新建
    security delete-keychain "$keychain" 2>/dev/null || true
    security create-keychain -p "$3" "$keychain"
    security set-keychain-settings -lut 21600 "$keychain"
    security unlock-keychain -p "$3" "$keychain"
    security import "$cert" -P "$2" -A -t cert -f pkcs12 -k "$keychain"
    # codesign: 不能少——缺了它 codesign 拿不到私钥（errSecInternalComponent）
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$3" "$keychain"
    # 必须写完整路径：裸写 "login" 会被解析成 ~/Library/Keychains/login-db（不存在的文件），
    # 把真正的 login.keychain-db 挤出搜索列表——runner 所在机器上所有本地构建从此查不到签名身份
    # （2026-11-25 实锤，本机 macos-heavy 中招）。Cleanup 时 delete-keychain 会自动把自己移出列表
    security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"

    # 按 SHA-1 指纹解析（项目铁律：证书一律用 SHA-1 区分，不按名字选）。
    # find-identity 每行形如 `  1) ABCDEF… "Developer ID Application: …"`
    identity="$(security find-identity -v -p codesigning "$keychain" \
        | awk -F'"' '/Developer ID Application/{print $1; exit}' | awk '{print $2}')"
    if [ -z "$identity" ]; then
        echo "::error::临时钥匙串里没有 Developer ID Application 身份"
        return 2
    fi

    echo "APP_SIGN_IDENTITY=$identity" >> "$GITHUB_ENV"
    rm -f "$cert"
    echo "✅ 证书已导入临时钥匙串，签名身份 $identity"
}

ci_signing_cleanup() {
    security delete-keychain "$(ci_signing_keychain_path)" 2>/dev/null || true
}
