import uuid
from enum import Enum
from typing import List, Optional
from datetime import datetime
from pydantic import BaseModel, Field


class RecognitionStatus(str, Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"


class ContentType(str, Enum):
    TEXT = "text"
    FORMULA = "formula"


class TextChunk(BaseModel):
    """Единичный смысловой сегмент лекции с миллисекундными метками времени."""
    id: str = Field(default_factory=lambda: uuid.uuid4().hex[:8])
    index: int = 0
    content_type: ContentType = ContentType.TEXT
    text: str
    spoken_text: str
    is_formula: bool = False
    confidence: float = 1.0
    bbox: Optional[List[int]] = None  # [x_min, y_min, x_max, y_max]
    start_time: float = 0.0           # В секундах (с точностью до мс)
    end_time: float = 0.0             # В секундах (с точностью до мс)
    duration: float = 0.0


class RecognitionResponse(BaseModel):
    """Синхронизированный манифест распознанной лекции."""
    task_id: str
    status: RecognitionStatus
    full_text: str
    spoken_text: str
    audio_url: Optional[str] = None
    total_duration: float = 0.0
    chunks: List[TextChunk] = []
    processing_time: float = 0.0
    created_at: datetime = Field(default_factory=datetime.utcnow)
    error: Optional[str] = None


class HealthResponse(BaseModel):
    status: str
    version: str
    models_loaded: bool


class ServerInfoResponse(BaseModel):
    app_title: str
    app_version: str
    device: str
    models_loaded: bool
    supported_languages: List[str]
    tts_engine: str
    details: dict