"""
Pydantic-модели для валидации запросов и ответов API.
"""

from pydantic import BaseModel, Field
from enum import Enum
from typing import Optional


class TaskStatus(str, Enum):
    """Статусы задачи обработки"""
    PENDING = "pending"
    PREPROCESSING = "preprocessing"
    RECOGNIZING = "recognizing"
    SYNTHESIZING = "synthesizing"
    COMPLETED = "completed"
    ERROR = "error"


class TimestampedSegment(BaseModel):
    """
    Сегмент текста с временными метками для синхронизации с аудио.

    Attributes:
        start: время начала в секундах
        end: время окончания в секундах
        text: распознанный текст сегмента
        is_formula: является ли сегмент формулой
        original: исходный текст (LaTeX для формул)
    """
    start: float = Field(..., ge=0, description="Время начала (сек)")
    end: float = Field(..., ge=0, description="Время окончания (сек)")
    text: str = Field(..., description="Текст для отображения")
    is_formula: bool = Field(default=False, description="Это формула?")
    original: Optional[str] = Field(default=None, description="Исходный текст/LaTeX")


class RecognitionResult(BaseModel):
    """
    Результат распознавания — полный ответ клиенту.
    """
    task_id: str = Field(..., description="Уникальный ID задачи")
    status: TaskStatus = Field(..., description="Статус обработки")
    recognized_text: str = Field(default="", description="Полный распознанный текст")
    segments: list[TimestampedSegment] = Field(default_factory=list, description="Сегменты с метками")
    audio_url: Optional[str] = Field(default=None, description="URL аудиофайла")
    audio_duration: float = Field(default=0.0, ge=0, description="Длительность аудио (сек)")
    error_message: Optional[str] = Field(default=None, description="Сообщение об ошибке")


class TaskStatusResponse(BaseModel):
    """Ответ на запрос статуса задачи"""
    task_id: str
    status: TaskStatus
    progress: float = Field(default=0.0, ge=0, le=100, description="Прогресс в %")
    message: str = Field(default="", description="Описание текущего этапа")


class HealthResponse(BaseModel):
    """Ответ health-check эндпоинта"""
    status: str = "ok"
    version: str = "1.0.0"
    ocr_loaded: bool = False
    tts_engine: str = ""
    gpu_available: bool = False


class ServerInfoResponse(BaseModel):
    """Информация о сервере для mDNS-обнаружения"""
    name: str
    host: str
    port: int
    version: str = "1.0.0"