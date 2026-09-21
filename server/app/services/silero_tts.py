import os
import torch
from pathlib import Path
from typing import Optional

try:
    from config import settings
except (ImportError, ModuleNotFoundError):
    from ...config import settings

from ..utils.logger import logger


class SileroTTS:
    def __init__(self, speaker: Optional[str] = None):
        self.device = torch.device("cpu")
        self.model = None
        self.sample_rate = getattr(settings, "SILERO_SAMPLE_RATE", 48000)
        self.speaker = speaker or getattr(settings, "SILERO_SPEAKER", "xenia")
        self._init_model()

    def _find_model_file(self) -> Optional[Path]:
        """Ищет файл весов silero по всем возможным путям."""
        candidates = [
            Path(settings.SILERO_MODEL_PATH),
            Path("server/models/silero_v4_ru.pt"),
            Path("models/silero_v4_ru.pt"),
            Path(__file__).resolve().parent.parent.parent / "models" / "silero_v4_ru.pt"
        ]
        for p in candidates:
            if p.exists():
                return p
        return None

    def _init_model(self):
        model_path = self._find_model_file()
        if not model_path:
            logger.error(f"Файл модели Silero не найден ни по одному из путей! Проверьте папку server/models/")
            return

        try:
            logger.info(f"Загрузка Silero TTS из {model_path} (голос: {self.speaker})...")
            self.model = torch.package.PackageImporter(str(model_path)).load_pickle("tts_models", "model")
            self.model.to(self.device)
            logger.info(f"✅ Silero TTS успешно загружен (голос: {self.speaker})")
        except Exception as e:
            logger.error(f"Ошибка загрузки Silero: {e}")
            self.model = None

    def synthesize(self, text: str, output_path: str) -> Optional[str]:
        if self.model is None or not text.strip():
            return None
        try:
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            self.model.save_wav(
                text=text,
                speaker=self.speaker,
                sample_rate=self.sample_rate,
                audio_path=output_path
            )
            return output_path
        except Exception as e:
            logger.error(f"Ошибка Silero синтеза для '{text}': {e}")
            return None