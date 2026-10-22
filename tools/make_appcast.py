#!/usr/bin/env python3
"""合并/创建 Sparkle appcast.xml（CI 发版时调用）。

用法: make_appcast.py <version> <dmg_url> <dmg_size> <ed_signature> <pub_date>
在 gh-pages 工作目录内运行；有 appcast.xml 则替换同版本 item 后插入新 item，
无则创建骨架文件。"""
import sys
import os
import re


def build_item(version: str, dmg_url: str, dmg_size: str, sig: str, pub_date: str) -> str:
    return (
        "    <item>\n"
        f"        <title>Version {version}</title>\n"
        f"        <pubDate>{pub_date}</pubDate>\n"
        f"        <sparkle:version>{version}</sparkle:version>\n"
        f"        <sparkle:shortVersionString>{version}</sparkle:shortVersionString>\n"
        "        <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>\n"
        f'        <enclosure url="{dmg_url}" length="{dmg_size}" '
        f'type="application/x-bzip2" sparkle:edSignature="{sig}"/>\n'
        "    </item>\n"
    )


def main() -> None:
    version, dmg_url, dmg_size, sig, pub_date = sys.argv[1:6]
    path = "appcast.xml"
    item = build_item(version, dmg_url, dmg_size, sig, pub_date)

    if os.path.exists(path):
        content = open(path).read()
        # 移除同版本旧 item（重发同 tag 时替换而不是重复）
        content = re.sub(
            r"    <item>\n(?:(?!    </item>).)*?"
            rf"<sparkle:version>{re.escape(version)}</sparkle:version>.*?    </item>\n",
            "",
            content,
            flags=re.S,
        )
        content = content.replace("</channel>", item + "</channel>")
    else:
        content = (
            '<?xml version="1.0" standalone="yes"?>\n'
            '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">\n'
            "    <channel>\n"
            "        <title>QuiteNote</title>\n"
            "        <link>https://dyyz1993.github.io/quite-note/appcast.xml</link>\n"
            "        <description>QuiteNote 更新清单</description>\n"
            "        <language>zh-cn</language>\n"
            + item
            + "    </channel>\n</rss>\n"
        )
    open(path, "w").write(content)
    print(f"appcast 已更新：版本 {version}")


if __name__ == "__main__":
    main()
