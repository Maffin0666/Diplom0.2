"""Short, cached help narration using the lecture's loaded TTS engine."""

import asyncio
import hashlib
import os
from pathlib import Path

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field
from pydub import AudioSegment

from server.config import settings
from server.app.utils.logger import get_logger

router = APIRouter(prefix="/api/v1/help", tags=["Help"])
logger = get_logger(__name__)


class HelpSpeechRequest(BaseModel):
    text: str = Field(min_length=1, max_length=3500)


def _render_help(text: str, destination: Path, tts) -> None:
    temporary = Path(settings.TEMP_DIR) / f"{destination.stem}.wav"
    partial = Path(settings.TEMP_DIR) / f"{destination.stem}.partial.mp3"
    generated = temporary
    try:
        generated = Path(tts.synthesize(text, str(temporary)))
        AudioSegment.from_file(generated).export(partial, format="mp3", bitrate="96k")
        if partial.stat().st_size == 0:
            raise RuntimeError("Пустая аудиозапись справки")
        os.replace(partial, destination)
    finally:
        for path in {temporary, generated, partial}:
            if path.parent.resolve() == Path(settings.TEMP_DIR).resolve():
                path.unlink(missing_ok=True)


@router.post("/speech")
async def speech(request: Request, body: HelpSpeechRequest) -> dict[str, str]:
    if not request.app.state.models_ready:
        raise HTTPException(503, "Сервер ещё загружает голос")
    text = " ".join(body.text.split())
    if not text:
        raise HTTPException(422, "Текст справки пуст")
    key = hashlib.sha256(text.encode("utf-8")).hexdigest()[:24]
    destination = Path(settings.AUDIO_DIR) / f"help_{key}.mp3"
    if not destination.is_file():
        async with request.app.state.audio_lock:
            if not destination.is_file():
                try:
                    await asyncio.to_thread(
                        _render_help, text, destination, request.app.state.audio_builder.tts
                    )
                except Exception:
                    logger.exception("stage=help_speech_failed key=%s", key)
                    raise HTTPException(503, "Не удалось озвучить справку") from None
    logger.info("stage=help_speech key=%s chars=%d", key, len(text))
    return {"audio_url": f"/audio/{destination.name}"}
