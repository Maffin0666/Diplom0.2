import os
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

try:
    from config import settings
except (ImportError, ModuleNotFoundError):
    from ..config import settings

from .routes import health, recognition
from .utils.logger import get_logger

logger = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Управление жизненным циклом приложения:
    Единовременная компиляция и загрузка моделей в память при старте Uvicorn.
    """
    logger.info("==================================================")
    logger.info(f" Инициализация сервиса {settings.APP_TITLE} (v{settings.APP_VERSION})")
    logger.info(" Предзагрузка нейросетевых весов и ONNX Runtime сессий...")

    # Создаем рабочие каталоги
    os.makedirs(settings.AUDIO_DIR, exist_ok=True)
    os.makedirs(settings.TEMP_DIR, exist_ok=True)
    os.makedirs(settings.MODELS_DIR, exist_ok=True)

    # Предзагрузка глобальных сервисов конвейера
    # Ссылки на инстансы привязываются к app.state для доступа из роутов без реаллокации
    try:
        from .services.text_recognition import TextRecognizer
        from .services.audio_builder import AudioBuilder

        app.state.recognizer = TextRecognizer()
        app.state.audio_builder = AudioBuilder()
        logger.info("✅ Все модели успешно скомпилированы и загружены в память")
    except Exception as e:
        logger.error(f"❌ Ошибка предзагрузки моделей: {e}", exc_info=True)

    logger.info(f" Сервер готов к обработке запросов на порту {settings.PORT}")
    logger.info("==================================================")

    yield

    # Освобождение ресурсов при остановке сервера
    logger.info("Завершение работы сервера и выгрузка моделей...")


app = FastAPI(
    title=settings.APP_TITLE,
    version=settings.APP_VERSION,
    description="Асинхронный сервер распознавания рукописных лекций и синтеза речи для слабовидящих пользователей",
    lifespan=lifespan
)

# Настройка CORS для доступа мобильного приложения Flutter
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Монтирование статической директории для раздачи аудиофайлов лекций
app.mount("/audio", StaticFiles(directory=str(settings.AUDIO_DIR)), name="audio")

# Подключение маршрутов API
app.include_router(health.router)
app.include_router(recognition.router)