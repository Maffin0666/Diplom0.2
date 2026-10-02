from pathlib import Path
from typing import Optional
import torch

from server.config import settings

from ..utils.logger import logger


class SileroTTS:
    def __init__(self, speaker: Optional[str] = None):
        self.device = torch.device("cpu")
        self.model = None
        self.sample_rate = getattr(settings, "SILERO_SAMPLE_RATE", 48000)
        self.speaker = speaker or getattr(settings, "SILERO_SPEAKER", "xenia")
        self._init_model()

    def _find_model_file(self) -> Optional[Path]:
        """Использует именно заданную модель, без скрытого выбора других весов."""
        path = Path(settings.SILERO_MODEL_PATH)
        return path if path.is_file() else None

    def _init_model(self):
        model_path = self._find_model_file()
        if not model_path:
            raise RuntimeError(f"Модель Silero не найдена: {settings.SILERO_MODEL_PATH}")

        try:
            logger.info(f"Загрузка Silero TTS из {model_path} (голос: {self.speaker})...")
            self.model = torch.package.PackageImporter(str(model_path)).load_pickle("tts_models", "model")
            self.model.to(self.device)
            speakers = getattr(self.model, "speakers", None)
            if speakers is not None and self.speaker not in speakers:
                raise ValueError(f"Голос {self.speaker!r} не поддерживается моделью Silero")
            logger.info(f"✅ Silero TTS успешно загружен (голос: {self.speaker})")
        except Exception as e:
            self.model = None
            raise RuntimeError(f"Не удалось загрузить модель Silero: {model_path}") from e

    def synthesize(self, text: str, output_path: str) -> str:
        if self.model is None:
            raise RuntimeError("Модель Silero не загружена")
        if not text.strip():
            raise ValueError("Текст для озвучивания пуст")
        try:
            Path(output_path).parent.mkdir(parents=True, exist_ok=True)
            self.model.save_wav(
                text=text,
                speaker=self.speaker,
                sample_rate=self.sample_rate,
                audio_path=output_path
            )
            return output_path
        except Exception as e:
            raise RuntimeError("Silero не смог озвучить фрагмент") from e
