"""
TTS через Silero — нейросетевой синтез речи.
Модель весит ~50 МБ, скачивается автоматически при первом запуске.
Работает офлайн, качество близко к естественной речи.
"""

import os
import torch
import numpy as np
import soundfile as sf
from pathlib import Path
from typing import Optional

from server.app.utils.logger import logger


class SileroTTS:
    """
    Обёртка над Silero TTS.
    Использует модель v4_ru с 4 голосами: aidar, baya, kseniya, xenia, eugene.
    """

    _instance: Optional["SileroTTS"] = None
    _model = None
    _sample_rate = 48000

    # Доступные голоса
    AVAILABLE_SPEAKERS = ["aidar", "baya", "kseniya", "xenia", "eugene", "random"]

    def __new__(cls, *args, **kwargs):
        """Singleton"""
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self, speaker: str = "xenia", sample_rate: int = 48000):
        """
        Args:
            speaker: голос из AVAILABLE_SPEAKERS
                     - aidar: мужской, взрослый
                     - baya: женский, спокойный
                     - kseniya: женский, чёткий
                     - xenia: женский, приятный (рекомендуется)
                     - eugene: мужской, глубокий
            sample_rate: частота дискретизации (8000, 24000, 48000)
        """
        if self._model is not None:
            self.speaker = speaker
            return

        self.speaker = speaker if speaker in self.AVAILABLE_SPEAKERS else "xenia"
        self._sample_rate = sample_rate

        logger.info(f"Загрузка Silero TTS (голос: {self.speaker})...")
        self._load_model()

    def _load_model(self):
        """Загрузка модели Silero"""
        try:
            # Директория для кэша модели
            models_dir = Path(__file__).parent.parent.parent / "models"
            models_dir.mkdir(exist_ok=True)
            model_path = models_dir / "silero_v4_ru.pt"

            # Скачиваем модель если её нет
            if not model_path.exists():
                logger.info("Скачивание модели Silero (~50 МБ, только один раз)...")
                torch.hub.download_url_to_file(
                    "https://models.silero.ai/models/tts/ru/v4_ru.pt",
                    str(model_path)
                )
                logger.info("Модель скачана")

            # Загружаем модель
            device = torch.device("cpu")
            self._model = torch.package.PackageImporter(str(model_path)).load_pickle("tts_models", "model")
            self._model.to(device)

            logger.info(f"✅ Silero TTS загружен (голос: {self.speaker})")

        except Exception as e:
            logger.error(f"❌ Ошибка загрузки Silero: {e}")
            raise RuntimeError(f"Не удалось загрузить Silero TTS: {e}")

    @property
    def is_initialized(self) -> bool:
        return self._model is not None

    def synthesize(self, text: str, output_path: str) -> bool:
        """
        Синтезирует речь и сохраняет в WAV/MP3.

        Args:
            text: текст для озвучки (макс. ~1000 символов за раз)
            output_path: путь для сохранения (.wav или .mp3)

        Returns:
            True если успешно
        """
        if self._model is None:
            raise RuntimeError("Silero TTS не инициализирован")

        text = text.strip()
        if not text:
            return False

        # Silero требует непустой текст, добавляем точку если её нет
        if text[-1] not in ".!?":
            text += "."

        try:
            logger.debug(f"Silero синтез: '{text[:80]}...'")

            # Ограничение Silero — 1000 символов за раз
            # Если текст длиннее — разбиваем на предложения
            if len(text) > 900:
                chunks = self._split_text(text, max_len=900)
                audio_chunks = []
                for chunk in chunks:
                    audio = self._model.apply_tts(
                        text=chunk,
                        speaker=self.speaker,
                        sample_rate=self._sample_rate,
                        put_accent=True,
                        put_yo=True
                    )
                    audio_chunks.append(audio.numpy())
                    # Небольшая пауза между чанками (0.2 сек)
                    audio_chunks.append(np.zeros(int(self._sample_rate * 0.2), dtype=np.float32))
                audio_np = np.concatenate(audio_chunks)
            else:
                audio = self._model.apply_tts(
                    text=text,
                    speaker=self.speaker,
                    sample_rate=self._sample_rate,
                    put_accent=True,
                    put_yo=True
                )
                audio_np = audio.numpy()

            # Сохраняем как WAV
            wav_path = output_path.replace('.mp3', '.wav') if output_path.endswith('.mp3') else output_path
            sf.write(wav_path, audio_np, self._sample_rate)

            # Конвертируем в MP3 если нужно
            if output_path.endswith('.mp3') and wav_path != output_path:
                try:
                    from pydub import AudioSegment
                    audio_seg = AudioSegment.from_wav(wav_path)
                    audio_seg.export(output_path, format="mp3", bitrate="128k")
                    os.remove(wav_path)
                except Exception as e:
                    logger.warning(f"Не удалось конвертировать в MP3: {e}")
                    os.rename(wav_path, output_path)

            return True

        except Exception as e:
            logger.error(f"Ошибка Silero синтеза: {e}")
            return False

    def synthesize_segment(self, text: str, segment_index: int, output_dir: str) -> Optional[str]:
        """Синтез одного сегмента (совместимость с TTSEngine)"""
        Path(output_dir).mkdir(parents=True, exist_ok=True)
        filename = f"segment_{segment_index:04d}.mp3"
        filepath = os.path.join(output_dir, filename)
        success = self.synthesize(text, filepath)
        return filepath if success else None

    def _split_text(self, text: str, max_len: int = 900) -> list[str]:
        """Разбивает текст на чанки по предложениям"""
        import re
        sentences = re.split(r'(?<=[.!?])\s+', text)

        chunks = []
        current = ""
        for sent in sentences:
            if len(current) + len(sent) < max_len:
                current += " " + sent if current else sent
            else:
                if current:
                    chunks.append(current)
                current = sent
        if current:
            chunks.append(current)
        return chunks

    def get_available_voices(self) -> list[dict]:
        """Список доступных голосов"""
        return [
            {"id": "aidar", "name": "Айдар (мужской)", "gender": "male"},
            {"id": "baya", "name": "Бая (женский)", "gender": "female"},
            {"id": "kseniya", "name": "Ксения (женский)", "gender": "female"},
            {"id": "xenia", "name": "Ксения-2 (женский)", "gender": "female"},
            {"id": "eugene", "name": "Евгений (мужской)", "gender": "male"},
        ]