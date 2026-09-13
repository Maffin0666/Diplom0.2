"""
Эндпоинты проверки здоровья и информации о сервере.
"""

import torch
from fastapi import APIRouter, Depends

from server.app.models import HealthResponse, ServerInfoResponse
from server.config import Settings, get_settings

router = APIRouter(tags=["health"])


@router.get("/health", response_model=HealthResponse)
async def health_check(settings: Settings = Depends(get_settings)):
    """
    Health-check эндпоинт.
    Проверяет состояние сервера и доступность моделей.
    """
    # Проверяем загрузку OCR
    ocr_loaded = False
    try:
        from server.app.services.text_recognition import TextRecognizer
        recognizer = TextRecognizer.__new__(TextRecognizer)
        ocr_loaded = recognizer._reader is not None
    except Exception:
        pass

    # Проверяем GPU
    gpu_available = torch.cuda.is_available()

    return HealthResponse(
        status="ok",
        version="1.0.0",
        ocr_loaded=ocr_loaded,
        tts_engine=settings.TTS_ENGINE,
        gpu_available=gpu_available
    )


@router.get("/info", response_model=ServerInfoResponse)
async def server_info(settings: Settings = Depends(get_settings)):
    """Информация о сервере для обнаружения клиентами"""
    import socket

    # Определяем локальный IP
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
    except Exception:
        local_ip = "127.0.0.1"

    return ServerInfoResponse(
        name=settings.MDNS_SERVICE_NAME,
        host=local_ip,
        port=settings.PORT,
        version="1.0.0"
    )