"""Durable task manifests for a single-process server.

Each operation opens its own SQLite connection so the API thread and the OCR
worker can read and write safely without sharing a connection across threads.
"""

import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator

from server.app.models import RecognitionResponse, RecognitionStatus


INTERRUPTED_MESSAGE = "Обработка прервана перезапуском сервера. Отправьте снимок повторно."


class TaskStore:
    def __init__(self, path: Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as connection:
            connection.execute("PRAGMA journal_mode=WAL")
            connection.execute("""
                CREATE TABLE IF NOT EXISTS tasks (
                    task_id TEXT PRIMARY KEY,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    response_json TEXT,
                    error TEXT,
                    image_sha256 TEXT
                )
            """)
            columns = {row["name"] for row in connection.execute("PRAGMA table_info(tasks)")}
            if "image_sha256" not in columns:
                connection.execute("ALTER TABLE tasks ADD COLUMN image_sha256 TEXT")

    @contextmanager
    def _connect(self) -> Iterator[sqlite3.Connection]:
        connection = sqlite3.connect(self.path, timeout=30)
        connection.row_factory = sqlite3.Row
        try:
            yield connection
            connection.commit()
        finally:
            connection.close()

    def create(self, task_id: str, image_sha256: str | None = None) -> datetime:
        created_at = datetime.now(timezone.utc)
        with self._connect() as connection:
            connection.execute(
                "INSERT INTO tasks (task_id, status, created_at, updated_at, image_sha256) VALUES (?, ?, ?, ?, ?)",
                (task_id, RecognitionStatus.PENDING.value, created_at.isoformat(),
                 created_at.isoformat(), image_sha256),
            )
        return created_at

    def update(self, task_id: str, status: RecognitionStatus,
               response: RecognitionResponse | None = None, error: str | None = None) -> None:
        with self._connect() as connection:
            cursor = connection.execute(
                "UPDATE tasks SET status=?, updated_at=?, response_json=?, error=? WHERE task_id=?",
                (status.value, datetime.now(timezone.utc).isoformat(),
                 response.model_dump_json() if response is not None else None, error, task_id),
            )
            if cursor.rowcount != 1:
                raise KeyError(f"Задача {task_id} не найдена")

    def get(self, task_id: str) -> dict | None:
        with self._connect() as connection:
            row = connection.execute("SELECT * FROM tasks WHERE task_id=?", (task_id,)).fetchone()
        if row is None:
            return None
        return {
            "status": RecognitionStatus(row["status"]),
            "created_at": datetime.fromisoformat(row["created_at"]),
            "response": (RecognitionResponse.model_validate_json(row["response_json"])
                         if row["response_json"] else None),
            "error": row["error"],
            "image_sha256": row["image_sha256"],
        }

    def fail_interrupted(self) -> int:
        """A restart cannot resume OCR because uploaded image bytes are not kept."""
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT task_id, created_at FROM tasks WHERE status IN (?, ?)",
                (RecognitionStatus.PENDING.value, RecognitionStatus.PROCESSING.value),
            ).fetchall()
            for row in rows:
                response = RecognitionResponse(
                    task_id=row["task_id"], status=RecognitionStatus.FAILED,
                    full_text="", spoken_text="", error=INTERRUPTED_MESSAGE,
                    created_at=datetime.fromisoformat(row["created_at"]),
                )
                connection.execute(
                    "UPDATE tasks SET status=?, updated_at=?, response_json=?, error=? WHERE task_id=?",
                    (RecognitionStatus.FAILED.value, datetime.now(timezone.utc).isoformat(),
                     response.model_dump_json(), INTERRUPTED_MESSAGE, row["task_id"]),
                )
        return len(rows)
