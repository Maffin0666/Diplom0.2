from pathlib import Path
from functools import lru_cache
from typing import Literal
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


PROJECT_ROOT = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    """Конфигурация сервера распознавания и озвучивания лекций."""

    model_config = SettingsConfigDict(
        env_file=PROJECT_ROOT / ".env", env_file_encoding="utf-8", extra="ignore"
    )

    APP_TITLE: str = "Система распознавания лекций и озвучивания"
    APP_VERSION: str = "0.2.0"
    HOST: str = "0.0.0.0"
    PORT: int = 8000
    DEBUG: bool = False

    MODELS_DIR: Path = PROJECT_ROOT / "server" / "models"
    AUDIO_DIR: Path = PROJECT_ROOT / "static" / "audio"
    TEMP_DIR: Path = PROJECT_ROOT / "server" / "temp"
    LOG_DIR: Path = PROJECT_ROOT / "server" / "logs"
    TASK_DB_PATH: Path = PROJECT_ROOT / "server" / "data" / "tasks.sqlite3"
    MAX_PENDING_TASKS: int = Field(default=2, ge=1, le=20)
    FFMPEG_BINARY: Path | None = None

    OCR_LANGUAGES: list[str] = ["ru", "en"]
    USE_GPU: bool = False
    TROCR_MODEL_NAME: str = "raxtemur/trocr-base-ru"
    TROCR_REVISION: str = "5d25b856d7942d3803caa4bb8c4dcf4df4dd94eb"
    OCR_BATCH_SIZE: int = Field(default=6, ge=1, le=16)
    TROCR_NUM_BEAMS: int = Field(default=2, ge=1, le=4)
    TROCR_QUANTIZE_DECODER: bool = True
    TROCR_USE_KV_CACHE: bool = True

    TTS_ENGINE: Literal["silero", "pyttsx3", "gtts"] = "silero"
    SILERO_MODEL_PATH: Path = PROJECT_ROOT / "server" / "models" / "silero_v4_ru.pt"
    SILERO_SAMPLE_RATE: Literal[8000, 24000, 48000] = 48000
    SILERO_SPEAKER: str = "xenia"
    USE_FALLBACK_TTS: bool = False
    ALLOW_ONLINE_TTS: bool = False

    MAX_IMAGE_BYTES: int = Field(default=15 * 1024 * 1024, ge=1)
    MAX_IMAGE_PIXELS: int = Field(default=20_000_000, ge=1)
    MAX_IMAGE_SIDE: int = Field(default=6000, ge=1)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    s = Settings()
    s.MODELS_DIR.mkdir(parents=True, exist_ok=True)
    s.AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    s.TEMP_DIR.mkdir(parents=True, exist_ok=True)
    return s


settings = get_settings()
