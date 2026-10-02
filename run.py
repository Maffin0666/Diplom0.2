"""Единая точка запуска: python run.py."""

import uvicorn

from server.app.main import app
from server.config import settings


def create_app():
    """Совместимость с прежними вызовами фабрики приложения."""
    return app


if __name__ == "__main__":
    uvicorn.run(
        "server.app.main:app",
        host=settings.HOST,
        port=settings.PORT,
        workers=1,
        reload=False,
        log_level="debug" if settings.DEBUG else "info",
    )
