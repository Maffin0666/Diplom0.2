"""Общий журнал приложения: консоль и ежедневные UTF-8 файлы без удаления архивов."""

import logging
import sys
import threading
import time
from logging.handlers import TimedRotatingFileHandler
from typing import Optional

from server.config import settings


_lock = threading.Lock()
_configured = False


def setup_logger(name: Optional[str] = None) -> logging.Logger:
    """Один набор обработчиков для всех модулей сервера, без дублей записей."""
    global _configured
    with _lock:
        if not _configured:
            formatter = logging.Formatter(
                "%(asctime)sZ [%(levelname)s] %(name)s: %(message)s",
                datefmt="%Y-%m-%dT%H:%M:%S",
            )
            formatter.converter = time.gmtime
            console = logging.StreamHandler(sys.stdout)
            console.setFormatter(formatter)
            handlers: list[logging.Handler] = [console]
            try:
                settings.LOG_DIR.mkdir(parents=True, exist_ok=True)
                file_handler = TimedRotatingFileHandler(
                    settings.LOG_DIR / "server.log", when="midnight", utc=True,
                    backupCount=0, encoding="utf-8", delay=True,
                )
                file_handler.setFormatter(formatter)
                handlers.append(file_handler)
            except OSError as exc:
                console.handle(logging.LogRecord(
                    "server", logging.WARNING, __file__, 0,
                    "Не удалось открыть файловый журнал: %s", (exc,), None,
                ))

            for root_name in ("server", "app"):
                root = logging.getLogger(root_name)
                root.setLevel(logging.INFO)
                root.propagate = False
                for handler in handlers:
                    root.addHandler(handler)
            _configured = True
    return logging.getLogger(name or "app")


get_logger = setup_logger
logger = setup_logger("app")
