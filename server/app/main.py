import asyncio
import os
import shutil
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from server.config import settings
from server.app.models import RecognitionResponse, RecognitionStatus
from server.app.task_store import TaskStore

from .routes import health, recognition, voice, help_speech
from .utils.logger import get_logger

logger = get_logger(__name__)


async def process_task_queue(app: FastAPI) -> None:
    """Keep heavyweight OCR and TTS serial on the CPU laptop."""
    queue = app.state.task_queue
    while True:
        task_id, content = await queue.get()
        app.state.processing_task_id = task_id
        try:
            # OCR and corrected-audio rendering share one CPU/TTS pipeline.
            async with app.state.audio_lock:
                await asyncio.to_thread(
                    recognition.execute_pipeline, task_id, content,
                    app.state.recognizer, app.state.audio_builder, app.state.task_store,
                )
        except Exception:
            # execute_pipeline handles normal OCR/TTS failures. Keep the worker
            # alive if persistence itself unexpectedly fails for one task.
            logger.exception("task=%s stage=worker_failed", task_id)
            try:
                record = app.state.task_store.get(task_id)
                if record and record["status"] in (RecognitionStatus.PENDING, RecognitionStatus.PROCESSING):
                    message = "Не удалось завершить обработку лекции. Отправьте снимок повторно."
                    failure = RecognitionResponse(
                        task_id=task_id, status=RecognitionStatus.FAILED,
                        full_text="", spoken_text="", error=message,
                        created_at=record["created_at"],
                    )
                    app.state.task_store.update(task_id, RecognitionStatus.FAILED, failure, message)
            except Exception:
                logger.exception("task=%s stage=worker_recovery_failed", task_id)
        finally:
            app.state.processing_task_id = None
            queue.task_done()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Управление жизненным циклом приложения:
    Единовременная компиляция и загрузка моделей в память при старте Uvicorn.
    """
    logger.info("==================================================")
    logger.info(f" Инициализация сервиса {settings.APP_TITLE} (v{settings.APP_VERSION})")
    logger.info(" Предзагрузка OCR и Silero TTS...")

    # StaticFiles создаётся при импорте приложения; остальные каталоги нужны
    # до загрузки моделей и инициализации постоянного хранилища.
    for directory in (settings.AUDIO_DIR, settings.TEMP_DIR, settings.MODELS_DIR):
        directory.mkdir(parents=True, exist_ok=True)

    # Предзагрузка глобальных сервисов конвейера
    # Ссылки на инстансы привязываются к app.state для доступа из роутов без реаллокации
    app.state.models_ready = False
    app.state.recognizer = None
    app.state.audio_builder = None
    app.state.startup_error = None
    app.state.task_store = None
    app.state.task_queue = None
    app.state.audio_lock = asyncio.Lock()
    app.state.processing_task_id = None
    app.state.worker_task = None
    try:
        app.state.task_store = TaskStore(settings.TASK_DB_PATH)
        interrupted = app.state.task_store.fail_interrupted()
        if interrupted:
            logger.warning("После перезапуска отмечено как failed незавершённых задач: %d", interrupted)
        ffmpeg = (str(settings.FFMPEG_BINARY) if settings.FFMPEG_BINARY is not None
                  else shutil.which("ffmpeg"))
        if not ffmpeg or not shutil.which(ffmpeg):
            raise RuntimeError("FFmpeg не найден; проверьте PATH или FFMPEG_BINARY")
        # Pydub ищет ffprobe в PATH, а ffmpeg для кодирования берёт из converter.
        # Явный путь в .env позволяет не менять системные настройки Windows.
        if settings.FFMPEG_BINARY is not None:
            os.environ["PATH"] = str(settings.FFMPEG_BINARY.parent) + os.pathsep + os.environ.get("PATH", "")
        from pydub import AudioSegment
        AudioSegment.converter = ffmpeg
        logger.info("FFmpeg: %s", ffmpeg)
        from .services.text_recognition import TextRecognizer
        from .services.audio_builder import AudioBuilder

        app.state.recognizer = TextRecognizer()
        app.state.audio_builder = AudioBuilder()
        if not app.state.audio_builder.tts.is_initialized:
            raise RuntimeError("Движок озвучивания не готов")
        app.state.task_queue = asyncio.Queue(maxsize=settings.MAX_PENDING_TASKS)
        app.state.worker_task = asyncio.create_task(process_task_queue(app))
        app.state.models_ready = True
        logger.info("OCR и TTS готовы к обработке запросов")
    except Exception as e:
        app.state.startup_error = str(e)
        logger.exception("Сервер не готов к обработке: %s", e)

    logger.info(" Готовность моделей: %s", app.state.models_ready)
    logger.info("==================================================")

    yield

    # Освобождение ресурсов при остановке сервера
    logger.info("Завершение работы сервера и выгрузка моделей...")
    if app.state.worker_task is not None:
        app.state.worker_task.cancel()
        try:
            await app.state.worker_task
        except asyncio.CancelledError:
            pass


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
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Монтирование статической директории для раздачи аудиофайлов лекций
app.mount("/audio", StaticFiles(directory=str(settings.AUDIO_DIR)), name="audio")

# Подключение маршрутов API
app.include_router(health.router)
app.include_router(recognition.router)
app.include_router(voice.router)
app.include_router(help_speech.router)
