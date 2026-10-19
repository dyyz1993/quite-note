#!/usr/bin/env python3
"""Seed deterministic clipboard rows into an isolated UI-smoke SQLite store."""

from __future__ import annotations

import base64
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

CORE_DATA_TABLES = {
    "ZCDCLIPBOARDENTRY", "Z_PRIMARYKEY", "Z_METADATA", "Z_MODELCACHE",
    "ACHANGE", "ATRANSACTION", "ATRANSACTIONSTRING",
}

MODEL_VERSION = 1
MODEL_UUID = "D5B1382A-7BBF-4ADF-8DF0-4B3C16475D75"
MODEL_CACHE_B64 = (
    "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"
)


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
        connection.execute(
            "CREATE TABLE IF NOT EXISTS Z_METADATA "
            "(Z_VERSION INTEGER PRIMARY KEY, Z_UUID VARCHAR(255), Z_PLIST BLOB)"
        )
        connection.execute(
            "CREATE TABLE IF NOT EXISTS Z_MODELCACHE (Z_CONTENT BLOB)"
        )
        connection.execute(
            "CREATE TABLE IF NOT EXISTS ACHANGE ("
            "Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZCHANGETYPE INTEGER, "
            "ZENTITY INTEGER, ZENTITYPK INTEGER, ZTRANSACTIONID INTEGER, ZCOLUMNS BLOB)"
        )
        connection.execute(
            "CREATE TABLE IF NOT EXISTS ATRANSACTION ("
            "Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZAUTHORTS INTEGER, "
            "ZBUNDLEIDTS INTEGER, ZCONTEXTNAMETS INTEGER, ZPROCESSIDTS INTEGER, "
            "ZTIMESTAMP FLOAT, ZAUTHOR VARCHAR, ZBUNDLEID VARCHAR, ZCONTEXTNAME VARCHAR, "
            "ZPROCESSID VARCHAR, ZQUERYGEN BLOB)"
        )
        connection.execute(
            "CREATE TABLE IF NOT EXISTS ATRANSACTIONSTRING "
            "(Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZNAME VARCHAR)"
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
        # CoreData recognizes a preexisting store only when its model cache and
        # metadata match the managed-object model used by the Dev app.
        connection.execute("DELETE FROM Z_MODELCACHE")
        connection.execute("DELETE FROM Z_METADATA")
        connection.execute(
            "INSERT INTO Z_MODELCACHE (Z_CONTENT) VALUES (?)",
            (sqlite3.Binary(base64.b64decode(MODEL_CACHE_B64)),),
        )
        connection.execute(
            "INSERT INTO Z_METADATA (Z_VERSION, Z_UUID, Z_PLIST) VALUES (?, ?, NULL)",
            (MODEL_VERSION, MODEL_UUID),
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
