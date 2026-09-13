"""
Настройка логирования для всего приложения.
Логи пишутся в консоль и в файл server.log.
"""

import logging
import sys
from pathlib import Path


def setup_logger(name: str = "lecture_ocr", level: int = logging.DEBUG) -> logging.Logger:
    """
    Создаёт и настраивает логгер.

    Args:
        name: имя логгера
        level: уровень логирования

    Returns:
        настроенный логгер
    """
    logger = logging.getLogger(name)

    # Не добавляем обработчики повторно
    if logger.handlers:
        return logger

    logger.setLevel(level)

    # Формат: [2024-01-15 14:30:00] [INFO] [module] Сообщение
    formatter = logging.Formatter(
        fmt="[%(asctime)s] [%(levelname)s] [%(module)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )

    # --- Консольный обработчик ---
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(level)
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)

    # --- Файловый обработчик ---
    log_dir = Path(__file__).parent.parent.parent  # server/
    log_file = log_dir / "server.log"
    file_handler = logging.FileHandler(log_file, encoding="utf-8")
    file_handler.setLevel(logging.INFO)
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)

    return logger


# Глобальный логгер приложения
logger = setup_logger()