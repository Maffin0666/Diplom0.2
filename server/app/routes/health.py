from fastapi import APIRouter, Request, Response, status
from server.app.models import HealthResponse, ServerInfoResponse
from server.config import settings

router = APIRouter(tags=["Health"])


@router.get("/health", response_model=HealthResponse)
async def health_check(request: Request, response: Response):
    """Проверка готовности к распознаванию и озвучиванию."""
    ready = bool(getattr(request.app.state, "models_ready", False))
    if not ready:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    return HealthResponse(
        status="ok" if ready else "degraded",
        version=settings.APP_VERSION,
        models_loaded=ready,
    )


@router.get("/info", response_model=ServerInfoResponse)
async def server_info(request: Request):
    """Сведения о конфигурации и доступных модулях сервера."""
    return ServerInfoResponse(
        app_title=settings.APP_TITLE,
        app_version=settings.APP_VERSION,
        device=getattr(getattr(request.app.state, "recognizer", None), "device", "unavailable"),
        models_loaded=bool(getattr(request.app.state, "models_ready", False)),
        supported_languages=settings.OCR_LANGUAGES,
        tts_engine=getattr(getattr(getattr(request.app.state, "audio_builder", None), "tts", None), "engine_type", "unavailable"),
        details={
            "silero_speaker": getattr(settings, "SILERO_SPEAKER", "xenia"),
            "sample_rate": getattr(settings, "SILERO_SAMPLE_RATE", 48000),
            "max_pending_tasks": settings.MAX_PENDING_TASKS,
            "pending_tasks": (request.app.state.task_queue.qsize()
                              if getattr(request.app.state, "task_queue", None) is not None else 0),
            "processing": getattr(request.app.state, "processing_task_id", None) is not None,
        }
    )
