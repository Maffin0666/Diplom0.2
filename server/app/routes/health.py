from fastapi import APIRouter
from server.app.models import HealthResponse, ServerInfoResponse

try:
    from config import Settings, get_settings, settings
except (ImportError, ModuleNotFoundError):
    from server.config import Settings, get_settings, settings

router = APIRouter(tags=["Health"])


@router.get("/health", response_model=HealthResponse)
async def health_check():
    """Проверка доступности сервиса."""
    return HealthResponse(
        status="ok",
        version=settings.APP_VERSION,
        models_loaded=True
    )


@router.get("/info", response_model=ServerInfoResponse)
async def server_info():
    """Сведения о конфигурации и доступных модулях сервера."""
    return ServerInfoResponse(
        app_title=settings.APP_TITLE,
        app_version=settings.APP_VERSION,
        device="cpu",
        models_loaded=True,
        supported_languages=settings.OCR_LANGUAGES,
        tts_engine=getattr(settings, "TTS_ENGINE", "silero"),
        details={
            "silero_speaker": getattr(settings, "SILERO_SPEAKER", "xenia"),
            "sample_rate": getattr(settings, "SILERO_SAMPLE_RATE", 48000),
        }
    )