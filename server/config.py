# import os
# from pathlib import Path
# from functools import lru_cache
# from typing import List
# from pydantic_settings import BaseSettings
#
#
# class Settings(BaseSettings):
#     """Конфигурация сервера распознавания и озвучивания лекций."""
#
#     # Параметры сервиса
#     APP_TITLE: str = "Система распознавания лекций и озвучивания"
#     APP_VERSION: str = "0.1.0"
#     HOST: str = "0.0.0.0"
#     PORT: int = 8000
#     DEBUG: bool = True
#
#     # Пути директорий
#     BASE_DIR: Path = Path(__file__).resolve().parent
#     MODELS_DIR: Path = BASE_DIR / "server" / "models"
#     AUDIO_DIR: Path = BASE_DIR / "static" / "audio"
#     TEMP_DIR: Path = BASE_DIR / "temp"
#
#     # Настройки OCR
#     OCR_LANGUAGES: List[str] = ["ru", "en"]
#     USE_GPU: bool = False
#
#     # Настройки TTS (Silero)
#     TTS_ENGINE: str = "silero"          # kseniya, gtts, pyttsx3
#     SILERO_MODEL_PATH: Path = MODELS_DIR / "silero_v4_ru.pt"
#     SILERO_SAMPLE_RATE: int = 48000
#     SILERO_SPEAKER: str = "xenia"       # xenia, baya, aidar, eugene
#     USE_FALLBACK_TTS: bool = True        # gTTS в случае ошибки Silero
#
#     class Config:
#         env_file = ".env"
#         extra = "ignore"
#
#
# @lru_cache()
# def get_settings() -> Settings:
#     s = Settings()
#     os.makedirs(s.MODELS_DIR, exist_ok=True)
#     os.makedirs(s.AUDIO_DIR, exist_ok=True)
#     os.makedirs(s.TEMP_DIR, exist_ok=True)
#     return s
#
#
# settings = get_settings()

import os
from pathlib import Path
from functools import lru_cache
from typing import List
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Конфигурация сервера распознавания и озвучивания лекций."""

    APP_TITLE: str = "Система распознавания лекций и озвучивания"
    APP_VERSION: str = "0.1.0"
    HOST: str = "0.0.0.0"
    PORT: int = 8000
    DEBUG: bool = True

    # Автоматическое определение корня проекта без дублирования server/server
    CURRENT_FILE: Path = Path(__file__).resolve()
    # Если config.py лежит внутри server/, поднимаемся на уровень выше
    BASE_DIR: Path = CURRENT_FILE.parent.parent if CURRENT_FILE.parent.name == "server" else CURRENT_FILE.parent

    MODELS_DIR: Path = BASE_DIR / "server" / "models"
    AUDIO_DIR: Path = BASE_DIR / "static" / "audio"
    TEMP_DIR: Path = BASE_DIR / "temp"

    OCR_LANGUAGES: List[str] = ["ru", "en"]
    USE_GPU: bool = False

    TTS_ENGINE: str = "silero"
    SILERO_MODEL_PATH: Path = MODELS_DIR / "silero_v4_ru.pt"
    SILERO_SAMPLE_RATE: int = 48000
    SILERO_SPEAKER: str = "xenia"
    USE_FALLBACK_TTS: bool = True

    class Config:
        env_file = ".env"
        extra = "ignore"


@lru_cache()
def get_settings() -> Settings:
    s = Settings()
    os.makedirs(s.MODELS_DIR, exist_ok=True)
    os.makedirs(s.AUDIO_DIR, exist_ok=True)
    os.makedirs(s.TEMP_DIR, exist_ok=True)
    return s


settings = get_settings()