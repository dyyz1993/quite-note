#!/usr/bin/env python3
"""Seed deterministic clipboard rows into an isolated UI-smoke SQLite store."""

from __future__ import annotations

import sqlite3
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path


CORE_DATA_EPOCH = 978307200
FIXTURES = [
    ("QNUI_SMOKE_CLIP 左右键回归", 0),
    ("QNUI_SMOKE_CLIP 支持毫秒搜索", -15),
    ("QNUI_SMOKE_CLIP 防止输入吞字", -30),
    ("https://example.com/qnui-smoke-clipboard", -45),
]


def fnv1a(text: str) -> str:
    payload = f"quitenote-clipboard-v1{text}{len(text.encode('utf-8'))}".encode("utf-8")
    value = 14695981039346656037
    for byte in payload:
        value ^= byte
        value = (value * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    return f"{value:016x}"


def seed(database: Path) -> int:
    database.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(database)
    try:
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS ZCDCLIPBOARDENTRY (
              Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER,
              ZBYTESIZE INTEGER, ZISPINNED INTEGER, ZPASTECOUNT INTEGER,
              ZCREATEDAT FLOAT, ZLASTUSEDAT FLOAT, ZASSETPATH VARCHAR,
              ZCONTENTHASH VARCHAR, ZOCRSTATUS VARCHAR, ZOCRTEXT VARCHAR,
              ZPLAINTEXT VARCHAR, ZSOURCEAPP VARCHAR, ZSOURCEBUNDLEID VARCHAR,
              ZSOURCEURL VARCHAR, ZTYPE VARCHAR, ZID BLOB, ZSAVEDRECORDID BLOB
            )
            """
        )
        connection.execute(
            "CREATE INDEX IF NOT EXISTS Z_CDClipboardEntry_CDClipboardEntry_contentHash "
            "ON ZCDCLIPBOARDENTRY (ZCONTENTHASH COLLATE BINARY ASC)"
        )
        connection.execute(
            "CREATE TABLE IF NOT EXISTS Z_PRIMARYKEY "
            "(Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR, Z_SUPER INTEGER, Z_MAX INTEGER)"
        )
        now = datetime.now(timezone.utc)
        rows = []
        for text, offset in FIXTURES:
            timestamp = now + timedelta(seconds=offset)
            core_data_time = timestamp.timestamp() - CORE_DATA_EPOCH
            encoded = text.encode("utf-8")
            rows.append(
                (
                    1, 1, len(encoded), 0, 0, core_data_time, core_data_time,
                    fnv1a(text), text, "UI Smoke", "com.quitenote.ui-smoke",
                    "link" if text.startswith("https://") else "text", uuid.uuid4().bytes,
                )
            )
        # The one-way UI-smoke store is recreated per run; replace by stable content
        # hash so a replayed request cannot duplicate fixture rows.
        connection.executemany(
            """
            INSERT OR REPLACE INTO ZCDCLIPBOARDENTRY (
              Z_ENT, Z_OPT, ZBYTESIZE, ZISPINNED, ZPASTECOUNT, ZCREATEDAT,
              ZLASTUSEDAT, ZCONTENTHASH, ZPLAINTEXT, ZSOURCEAPP,
              ZSOURCEBUNDLEID, ZTYPE, ZID
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            rows,
        )
        connection.execute(
            "DELETE FROM ZCDCLIPBOARDENTRY WHERE Z_PK NOT IN (SELECT MIN(Z_PK) "
            "FROM ZCDCLIPBOARDENTRY GROUP BY ZCONTENTHASH)"
        )
        count = connection.execute(
            "SELECT COUNT(*) FROM ZCDCLIPBOARDENTRY WHERE ZPLAINTEXT LIKE 'QNUI_SMOKE_%' "
            "OR ZPLAINTEXT LIKE 'https://example.com/qnui-smoke-%'"
        ).fetchone()[0]
        entity = connection.execute(
            "SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME = 'CDClipboardEntry'"
        ).fetchone()
        maximum = connection.execute("SELECT COALESCE(MAX(Z_PK), 0) FROM ZCDCLIPBOARDENTRY").fetchone()[0]
        if entity:
            connection.execute(
                "UPDATE Z_PRIMARYKEY SET Z_MAX = ? WHERE Z_NAME = 'CDClipboardEntry'", (maximum,)
            )
        else:
            connection.execute(
                "INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME, Z_SUPER, Z_MAX) VALUES (1, 'CDClipboardEntry', 0, ?)",
                (maximum,),
            )
        connection.commit()
        return count
    finally:
        connection.close()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: seed_clipboard_history.py <ClipboardHistory-Debug.sqlite>")
    try:
        print(seed(Path(sys.argv[1])))
    except (OSError, sqlite3.Error, ValueError) as exc:
        raise SystemExit(f"Clipboard fixture seed failed: {exc}")
