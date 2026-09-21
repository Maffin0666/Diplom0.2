import logging
import sys
from typing import Optional


def setup_logger(name: Optional[str] = None) -> logging.Logger:
    """Настройка и получение экземпляра логгера."""
    logger_name = name if name else "app"
    log = logging.getLogger(logger_name)

    if not log.handlers:
        log.setLevel(logging.INFO)
        formatter = logging.Formatter(
            fmt="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )

        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(formatter)
        log.addHandler(handler)

    return log


# Алиас для вызова функции
get_logger = setup_logger

# Глобальный экземпляр логгера по умолчанию для прямого импорта
logger = setup_logger("app")
logger = setup_logger("app")