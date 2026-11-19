from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from src.models import RawItem


class TopicMemory:
    """SQLite-backed local long-term memory for deduplicating seen hotspots."""

    def __init__(self, db_path: Path) -> None:
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    def _init_db(self) -> None:
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS seen_items (
                    fingerprint TEXT PRIMARY KEY,
                    source TEXT NOT NULL,
                    title TEXT NOT NULL,
                    url TEXT NOT NULL,
                    first_seen_at TEXT NOT NULL
                )
                """
            )
            conn.commit()

    def filter_unseen(self, items: list[RawItem]) -> list[RawItem]:
        """Return only items not yet recorded in SQLite, also deduplicating within the batch."""
        if not items:
            return []
        with sqlite3.connect(self.db_path) as conn:
            existing = {
                row[0] for row in conn.execute("SELECT fingerprint FROM seen_items")
            }
        unseen: list[RawItem] = []
        batch_seen: set[str] = set()
        for item in items:
            fp = item.fingerprint
            if fp not in existing and fp not in batch_seen:
                batch_seen.add(fp)
                unseen.append(item)
        return unseen

    def mark_seen(self, items: list[RawItem]) -> int:
        """Persist items into memory and return count of newly inserted rows."""
        if not items:
            return 0
        now = datetime.now(timezone.utc).isoformat()
        inserted = 0
        with sqlite3.connect(self.db_path) as conn:
            for item in items:
                cur = conn.execute(
                    """
                    INSERT OR IGNORE INTO seen_items (fingerprint, source, title, url, first_seen_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (item.fingerprint, item.source, item.title, item.url, now),
                )
                inserted += cur.rowcount
            conn.commit()
        return inserted
