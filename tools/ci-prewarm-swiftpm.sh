#!/bin/bash
# CI 依赖预热公共库：把开发机真实 SwiftPM 缓存灌进 runner job 的 HOME，缓存冷时如实报警。
#
# build-macos.yml / ui-smoke.yml / test.yml 共用。此前三处各抄一份，而且已经漂移——
# ui-smoke.yml 那份缺 Sparkle 镜像段（2026-11-28 事故轮 Sparkle 只能从网络现拉 10.2MB）。
# 同一件事多处拷贝必然漂移，所以收成一份（与 tools/ci-signing.sh 同理）。改这里之后要
# grep 三个 workflow 有没有残留的内联预热写法（rsync org.swift.swiftpm / SPARKLE_KEY /
# "SwiftPM cache primed"）；改完跑 python3 tools/validate_swiftpm_prewarm.py。
#
# 用法（workflow 的 run 段，默认 shell 是 bash）：
#   source "$GITHUB_WORKSPACE/tools/ci-prewarm-swiftpm.sh"
#   ci_swiftpm_prewarm
#
# 背景（为什么有这一步）：GitHub 托管的 runner 每个 job 覆盖 HOME，SwiftPM 用户级缓存
# （lucide 镜像仓库 + Sparkle 二进制产物）不可见，而本机直连 GitHub releases/codeload 不稳
# （大包断流，~80KB/s 下 resolve 直接失败 "invalid index-pack output"，b98935d 轮 UI Smoke
# 实锤），所以要先把缓存拷进 job HOME（2026-11-25 补齐）。
# 注意：本仓库现在用的自托管 runner **不覆盖 HOME**——job 用的就是真实 HOME（2026-11-28 实测：
# 缓存被清空后是构建 job 自己把依赖拉回了真实缓存目录，目录 mtime 就是它拉取的时刻）。所以在
# 这两台机器上 rsync 那两行是空操作，真正起作用的是 Sparkle 镜像兜底和下面的冷缓存报警。
#
# 缓存冷必须如实报警：真实缓存会被 SwiftPM 在下载失败时清除（2026-11-20 实锤 artifacts=0；
# 镜像目录见 /Users/xuyingzhou/runners/swiftpm-mirror），2026-11-28 整个缓存被清空后依赖
# 现拉，构建 job 在 "Build complete!" 之后无声退出 1（重跑即过，根因未钉死，见 ERRORS.md
# 2026-11-28）。所以源缓存的 repositories 为空 / 源目录不存在时，输出 ::warning 注解并在
# 统计行标 [cold]——提示依赖将从网络现拉、首次构建可能失败，失败先重跑。热缓存不输出注解。
#
# 只写 $HOME/Library/Caches/org.swift.swiftpm/，不碰 security / defaults 等任何全局状态；
# 失败不拦 job（危险命令全部 || true，函数恒返回 0）——与收拢前的语义一致。
#
# 可用环境变量（验证器用它们指向假目录；默认值是开发机真实路径）：
#   QN_SWIFTPM_CACHE_SRC  源缓存目录（默认 /Users/xuyingzhou/Library/Caches/org.swift.swiftpm）
#   QN_SPARKLE_MIRROR     Sparkle zip 镜像（默认 /Users/xuyingzhou/runners/swiftpm-mirror/sparkle-2.10.0.zip）

ci_swiftpm_prewarm() {
    : "${HOME:?HOME 未设置（这个库在 GitHub Actions 的 job 里用，runner 会提供 HOME）}"
    local src dst cold
    src="${QN_SWIFTPM_CACHE_SRC:-/Users/xuyingzhou/Library/Caches/org.swift.swiftpm}"
    dst="$HOME/Library/Caches/org.swift.swiftpm"
    cold=""

    if [ ! -d "${src}" ]; then
        cold=1
        echo "WARN: 开发机 SwiftPM 缓存不存在，回退网络下载"
    elif [ -z "$(ls "${src}/repositories" 2>/dev/null)" ]; then
        cold=1
    fi
    if [ -n "${cold}" ]; then
        echo "::warning title=SwiftPM 缓存为空::源缓存（${src}）的 repositories 为空或目录不存在，依赖将从网络现拉，首次构建可能失败（2026-11-28 同款事故），失败先重跑一次"
    fi

    if [ -d "${src}" ]; then
        mkdir -p "${dst}"
        rsync -a --delete "${src}/repositories/" "${dst}/repositories/" 2>/dev/null || true
        rsync -a "${src}/artifacts/" "${dst}/artifacts/" 2>/dev/null || true
    fi

    # Sparkle 二进制产物从本机镜像灌入（镜像不依赖源缓存，冷缓存时更要灌——免掉 10.2MB
    # 网络下载）。两个 key 名对应不同工具链版本的 mangle 规则，双保险（旧 mangle 是
    # _<十进制>_ 形式）
    local mirror key_new key_legacy
    mirror="${QN_SPARKLE_MIRROR:-/Users/xuyingzhou/runners/swiftpm-mirror/sparkle-2.10.0.zip}"
    key_new="https___github_com_sparkle_project_Sparkle_releases_download_2_10_0_Sparkle_for_Swift_Package_Manager_zip"
    key_legacy="https_58__47__47_github_46_com_47_sparkle_45_project_47_Sparkle_47_releases_47_download_47_2_46_10_46_0_47_Sparkle_45_for_45_Swift_45_Package_45_Manager_46_zip"
    if [ -f "${mirror}" ]; then
        mkdir -p "${dst}/artifacts"
        cp "${mirror}" "${dst}/artifacts/${key_new}" || true
        cp "${mirror}" "${dst}/artifacts/${key_legacy}" || true
        echo "Sparkle artifact primed from mirror"
    fi

    local stats
    stats="SwiftPM cache primed: $(ls "${dst}/repositories" 2>/dev/null | wc -l | tr -d ' ') repos, $(ls "${dst}/artifacts" 2>/dev/null | wc -l | tr -d ' ') artifacts"
    if [ -n "${cold}" ]; then
        stats="${stats} [cold]"
    fi
    echo "${stats}"
    return 0
}
