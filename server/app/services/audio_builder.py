"""Поблочная сборка MP3 с обязательным озвучиванием каждого фрагмента."""

from pathlib import Path
import os
import uuid

from pydub import AudioSegment

from server.config import settings
from server.app.models import TextChunk
from server.app.services.tts_engine import TTSEngine
from server.app.utils.logger import get_logger

logger = get_logger(__name__)


class AudioBuilder:
    def __init__(self):
        self.tts = TTSEngine(
            engine_type=settings.TTS_ENGINE,
            speaker=settings.SILERO_SPEAKER,
            allow_online=settings.ALLOW_ONLINE_TTS,
            use_fallback=settings.USE_FALLBACK_TTS,
        )
        self.output_dir = Path(settings.AUDIO_DIR)
        self.temp_dir = Path(settings.TEMP_DIR)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.temp_dir.mkdir(parents=True, exist_ok=True)

    def generate_full_audio(self, chunks: list[TextChunk]) -> tuple[str | None, list[TextChunk]]:
        """Возвращает аудио и чанки только при успехе всех фрагментов.

        Во время сборки изменяются только локальные копии чанков. Результат
        публикуется по конечному URL после успешного кодирования всего MP3.
        """
        combined = AudioSegment.empty()
        timed_chunks: list[TextChunk] = []
        for chunk in chunks:
            text = (chunk.spoken_text or chunk.text).strip()
            if not text:
                raise RuntimeError(f"У фрагмента {chunk.index} нет текста для озвучивания")

            temporary = self.temp_dir / f"chunk_{uuid.uuid4().hex}.wav"
            generated = temporary
            try:
                generated = Path(self.tts.synthesize(text, str(temporary)))
                with generated.open("rb") as source:
                    segment = AudioSegment.from_file(source, format=generated.suffix.lstrip("."))
                if len(segment) == 0:
                    raise RuntimeError("TTS создал пустое аудио")

                # Пауза нужна между фрагментами, но не после последнего.
                if timed_chunks:
                    combined += AudioSegment.silent(duration=350, frame_rate=segment.frame_rate)
                start_ms = len(combined)
                combined += segment
                end_ms = len(combined)
                timed_chunks.append(chunk.model_copy(update={
                    "start_time": round(start_ms / 1000, 3),
                    "end_time": round(end_ms / 1000, 3),
                    "duration": round((end_ms - start_ms) / 1000, 3),
                }))
            except Exception as exc:
                raise RuntimeError(f"Не удалось озвучить фрагмент {chunk.index}") from exc
            finally:
                # Удаляются только файлы, созданные этим вызовом в каталоге temp.
                for path in {temporary, temporary.with_suffix(".mp3"), generated}:
                    if path.parent.resolve() == self.temp_dir.resolve():
                        path.unlink(missing_ok=True)

        if not timed_chunks:
            return None, []

        filename = f"lecture_{uuid.uuid4().hex}.mp3"
        final_path = self.output_dir / filename
        partial_path = self.temp_dir / f"{filename}.partial.mp3"
        try:
            combined.export(str(partial_path), format="mp3", bitrate="128k")
            if not partial_path.is_file() or partial_path.stat().st_size == 0:
                raise RuntimeError("Кодирование MP3 не создало файл")
            os.replace(partial_path, final_path)
        finally:
            partial_path.unlink(missing_ok=True)

        logger.info("Собрана аудиозапись %s, длительность %.3f с", filename, len(combined) / 1000)
        return f"/audio/{filename}", timed_chunks
