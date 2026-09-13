"""
Конфигурация сервера.
Все параметры можно переопределить через переменные окружения или .env файл.
"""

import os
from pathlib import Path
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Настройки приложения"""

    # --- Сервер ---
    HOST: str = "0.0.0.0"
    PORT: int = 8000
    DEBUG: bool = True

    # --- Пути ---
    BASE_DIR: Path = Path(__file__).parent
    TEMP_DIR: Path = BASE_DIR / "temp"
    OUTPUT_DIR: Path = BASE_DIR / "output"

    # --- OCR ---
    OCR_LANGUAGES: list[str] = ["ru", "en"]
    # GPU ускорение (True если есть CUDA)
    OCR_USE_GPU: bool = False

    # --- TTS ---
    # "silero" (нейросеть, естественно), "pyttsx3" (офлайн, робот), "gtts" (онлайн)
    TTS_ENGINE: str = "silero"
    TTS_LANGUAGE: str = "ru"
    # Голос Silero: aidar, baya, kseniya, xenia, eugene
    TTS_SPEAKER: str = "xenia"
    # Для pyttsx3
    TTS_RATE: int = 150
    TTS_VOLUME: float = 0.9

    # --- mDNS ---
    MDNS_ENABLED: bool = True
    MDNS_SERVICE_NAME: str = "LectureOCR"

    # --- Обработка изображений ---
    # Максимальный размер стороны изображения (px)
    IMAGE_MAX_SIDE: int = 2048
    # JPEG качество при сохранении
    IMAGE_QUALITY: int = 95

    # --- Лимиты ---
    # Максимальный размер загружаемого файла (байт) — 20 МБ
    MAX_UPLOAD_SIZE: int = 20 * 1024 * 1024

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


def get_settings() -> Settings:
    """Фабрика настроек (синглтон через lru_cache в FastAPI)"""
    settings = Settings()

    # Создаём директории если не существуют
    settings.TEMP_DIR.mkdir(parents=True, exist_ok=True)
    settings.OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    return settings