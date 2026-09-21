import os
import uuid
from typing import List, Tuple
from pydub import AudioSegment

try:
    from config import settings
except (ImportError, ModuleNotFoundError):
    from ...config import settings

from ..models import TextChunk
from .tts_engine import TTSEngine
from ..utils.logger import get_logger

logger = get_logger(__name__)


class AudioBuilder:
    def __init__(self):
        self.tts = TTSEngine()
        self.output_dir = str(settings.AUDIO_DIR)
        self.temp_dir = str(settings.TEMP_DIR)
        os.makedirs(self.output_dir, exist_ok=True)
        os.makedirs(self.temp_dir, exist_ok=True)

    def generate_full_audio(self, chunks: List[TextChunk]) -> Tuple[str, List[TextChunk]]:
        combined = AudioSegment.empty()
        current_time_ms = 0
        updated_chunks: List[TextChunk] = []

        # Естественная пауза между смысловыми предложениями и формулами
        sentence_pause = AudioSegment.silent(duration=350)

        for chunk in chunks:
            text_to_speak = chunk.spoken_text if chunk.spoken_text else chunk.text
            if not text_to_speak or not text_to_speak.strip():
                continue

            temp_wav = os.path.join(self.temp_dir, f"chunk_{uuid.uuid4().hex[:8]}.wav")

            try:
                # Синтезируем сразу полное предложение — у Silero формируется идеальная интонация
                audio_path = self.tts.synthesize(text=text_to_speak.strip(), output_path=temp_wav)
                if not audio_path or not os.path.exists(audio_path):
                    continue

                segment = AudioSegment.from_file(audio_path)
                seg_len_ms = len(segment)

                start_sec = round(current_time_ms / 1000.0, 3)
                end_sec = round((current_time_ms + seg_len_ms) / 1000.0, 3)

                chunk.start_time = start_sec
                chunk.end_time = end_sec
                chunk.duration = round(seg_len_ms / 1000.0, 3)
                updated_chunks.append(chunk)

                # Склейка дорожки
                combined += segment + sentence_pause
                current_time_ms += seg_len_ms + 350

                if os.path.exists(audio_path):
                    os.remove(audio_path)

            except Exception as e:
                logger.error(f"Ошибка синтеза предложения: {e}")
                continue

        filename = f"lecture_{uuid.uuid4().hex[:10]}.mp3"
        result_path = os.path.join(self.output_dir, filename)

        if len(combined) > 0:
            combined.export(result_path, format="mp3", bitrate="128k")
            audio_url = f"/audio/{filename}"
            logger.info(f"Аудиокнига собрана: {result_path}, длительность: {len(combined)/1000.0:.2f} с.")
        else:
            audio_url = None

        return audio_url, updated_chunks