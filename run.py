"""
Главный модуль FastAPI приложения.

Создаёт экземпляр приложения, подключает роуты,
настраивает CORS, middleware и события жизненного цикла.
"""

import sys
from pathlib import Path

# Добавляем директорию server в системные пути до любых импортов проекта
BASE_DIR = Path(__file__).resolve().parent
SERVER_DIR = BASE_DIR / "server"

if str(SERVER_DIR) not in sys.path:
    sys.path.insert(0, str(SERVER_DIR))
if str(BASE_DIR) not in sys.path:
    sys.path.insert(0, str(BASE_DIR))


import time
import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from server.app.routes import health, recognition
from server.app.services.text_recognition import TextRecognizer
from server.app import logger
from config import get_settings

import uvicorn


import sys
from pathlib import Path

# Добавляем пути к корню и папке server в системные пути поиска
BASE_DIR = Path(__file__).resolve().parent
SERVER_DIR = BASE_DIR / "server"
if str(SERVER_DIR) not in sys.path:
    sys.path.insert(0, str(SERVER_DIR))
if str(BASE_DIR) not in sys.path:
    sys.path.insert(0, str(BASE_DIR))


# --- mDNS сервис ---
_mdns_service = None


def _start_mdns(settings):
    """Запуск mDNS для автообнаружения сервера в локальной сети"""
    global _mdns_service
    try:
        import socket
        from zeroconf import Zeroconf, ServiceInfo

        # Определяем локальный IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()

        zeroconf = Zeroconf()
        service_info = ServiceInfo(
            "_http._tcp.local.",
            f"{settings.MDNS_SERVICE_NAME}._http._tcp.local.",
            addresses=[socket.inet_aton(local_ip)],
            port=settings.PORT,
            properties={
                "path": "/api/",
                "version": "1.0.0",
                "name": settings.MDNS_SERVICE_NAME
            },
            server=f"{settings.MDNS_SERVICE_NAME}.local."
        )

        zeroconf.register_service(service_info)
        _mdns_service = (zeroconf, service_info)
        logger.info(f"mDNS зарегистрирован: {settings.MDNS_SERVICE_NAME} → {local_ip}:{settings.PORT}")

    except ImportError:
        logger.warning("zeroconf не установлен, mDNS недоступен")
    except Exception as e:
        logger.warning(f"Не удалось запустить mDNS: {e}")


def _stop_mdns():
    """Остановка mDNS"""
    global _mdns_service
    if _mdns_service:
        try:
            zeroconf, service_info = _mdns_service
            zeroconf.unregister_service(service_info)
            zeroconf.close()
            logger.info("mDNS остановлен")
        except Exception as e:
            logger.warning(f"Ошибка при остановке mDNS: {e}")
        _mdns_service = None


# --- Жизненный цикл приложения ---

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Управление жизненным циклом приложения.
    Startup: загрузка моделей, запуск mDNS
    Shutdown: очистка ресурсов
    """
    settings = get_settings()
    logger.info("=" * 60)
    logger.info("🚀 Запуск сервера LectureOCR")
    logger.info("=" * 60)

    # --- Startup ---

    # Предзагрузка EasyOCR модели (при первом запросе она загрузится автоматически,
    # но лучше загрузить заранее, чтобы первый запрос не ждал)
    logger.info("Загрузка OCR модели (это может занять 1-2 минуты)...")
    try:
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(
            None,
            lambda: TextRecognizer(languages=settings.OCR_LANGUAGES, use_gpu=settings.OCR_USE_GPU)
        )
        logger.info("✅ OCR модель загружена")
    except Exception as e:
        logger.error(f"❌ Не удалось загрузить OCR модель: {e}")

    # Запуск mDNS
    if settings.MDNS_ENABLED:
        _start_mdns(settings)

    logger.info(f"Сервер доступен: http://{settings.HOST}:{settings.PORT}")
    logger.info(f"Документация API: http://{settings.HOST}:{settings.PORT}/docs")
    logger.info("=" * 60)

    yield

    # --- Shutdown ---
    logger.info("Остановка сервера...")
    _stop_mdns()
    logger.info("Сервер остановлен")


# --- Создание приложения ---

def create_app() -> FastAPI:
    """Фабрика FastAPI приложения"""
    settings = get_settings()

    app = FastAPI(
        title="LectureOCR — Распознавание лекций",
        description=(
            "API для распознавания рукописного текста и математических формул "
            "с озвучиванием для студентов с нарушениями зрения"
        ),
        version="1.0.0",
        lifespan=lifespan
    )

    # --- CORS ---
    # Разрешаем запросы от мобильных приложений и браузеров
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],  # В продакшене — конкретные домены
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
        expose_headers=["Content-Disposition", "Content-Length"]
    )

    # --- Middleware: логирование запросов ---
    @app.middleware("http")
    async def log_requests(request: Request, call_next):
        start_time = time.time()
        logger.info(f"→ {request.method} {request.url.path}")

        try:
            response = await call_next(request)
            duration = time.time() - start_time
            logger.info(f"← {request.method} {request.url.path} [{response.status_code}] {duration:.3f}s")
            return response
        except Exception as e:
            duration = time.time() - start_time
            logger.error(f"← {request.method} {request.url.path} [ERROR] {duration:.3f}s — {e}")
            return JSONResponse(
                status_code=500,
                content={"detail": "Внутренняя ошибка сервера"}
            )

    # --- Глобальный обработчик ошибок ---
    @app.exception_handler(Exception)
    async def global_exception_handler(request: Request, exc: Exception):
        logger.error(f"Необработанная ошибка: {exc}", exc_info=True)
        return JSONResponse(
            status_code=500,
            content={"detail": f"Внутренняя ошибка: {str(exc)}"}
        )

    # --- Подключение роутов ---
    app.include_router(health.router)
    app.include_router(recognition.router)

    # --- Статические файлы (аудио) ---
    output_dir = str(settings.OUTPUT_DIR)
    app.mount("/static", StaticFiles(directory=output_dir), name="static")

    # --- Корневой эндпоинт ---
    @app.get("/")
    async def root():
        return {
            "service": "LectureOCR",
            "version": "1.0.0",
            "docs": "/docs",
            "health": "/health"
        }

    return app


if __name__ == "__main__":
    settings = get_settings()
    print("=" * 50)
    print("  Запуск сервера LectureOCR...")
    print(f"  Порт: {settings.PORT}")
    print("=" * 50)

    # factory=True означает, что create_app - это функция, которая возвращает приложение
    uvicorn.run(
        "server.app.main:app",
        factory=False,
        host="127.0.0.1",  # На Windows надежнее использовать 127.0.0.1
        port=settings.PORT,
        reload=False,  # Автоперезагрузка при изменении кода
        log_level="info"
    )