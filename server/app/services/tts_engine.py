"""Локальный синтез речи; каждый движок возвращает путь к готовому файлу."""

from pathlib import Path

from server.config import settings
from server.app.utils.logger import get_logger

logger = get_logger(__name__)


class TTSEngine:
    """Silero или явно выбранный резервный движок с единым контрактом."""

    def __init__(
        self,
        engine_type: str | None = None,
        language: str = "ru",
        rate: int = 150,
        volume: float = 0.9,
        speaker: str | None = None,
        allow_online: bool | None = None,
        use_fallback: bool | None = None,
    ):
        self.engine_type = engine_type or settings.TTS_ENGINE
        self.language = language
        self.rate = rate
        self.volume = volume
        self.speaker = speaker or settings.SILERO_SPEAKER
        self.allow_online = settings.ALLOW_ONLINE_TTS if allow_online is None else allow_online
        self.use_fallback = settings.USE_FALLBACK_TTS if use_fallback is None else use_fallback
        self._silero_engine = None
        self._pyttsx3_engine = None
        self._initialized = False
        self._initialize()

    def _initialize(self) -> None:
        if self.engine_type == "silero":
            try:
                from server.app.services.silero_tts import SileroTTS
                self._silero_engine = SileroTTS(speaker=self.speaker)
            except Exception:
                if not self.use_fallback:
                    raise
                logger.warning("Silero недоступен; проверяем локальный резервный голос")
                self.engine_type = "pyttsx3"
                self._init_pyttsx3()
                return
        elif self.engine_type == "pyttsx3":
            self._init_pyttsx3()
            return
        elif self.engine_type == "gtts":
            if not self.allow_online:
                raise RuntimeError("Сетевой TTS выключен настройкой ALLOW_ONLINE_TTS")
            from gtts import gTTS  # Проверяем зависимость до приёма запросов.
        else:
            raise ValueError(f"Неизвестный TTS-движок: {self.engine_type}")
        self._initialized = True
        logger.info("TTS-движок готов: %s", self.engine_type)

    def _init_pyttsx3(self) -> None:
        import pyttsx3

        engine = pyttsx3.init()
        engine.setProperty("rate", self.rate)
        engine.setProperty("volume", self.volume)
        voices = engine.getProperty("voices") or []
        russian_voice = None
        for voice in voices:
            tags = [
                tag if isinstance(tag, str) else tag.decode("utf-8", errors="ignore")
                for tag in (voice.languages or [])
            ]
            if "russian" in voice.name.lower() or any("ru" in tag.lower() for tag in tags):
                russian_voice = voice
                break
        if russian_voice is None:
            raise RuntimeError("В pyttsx3 не найден русский голос")
        engine.setProperty("voice", russian_voice.id)
        self._pyttsx3_engine = engine
        self._initialized = True
        logger.info("TTS-движок готов: pyttsx3, голос %s", russian_voice.name)

    @property
    def is_initialized(self) -> bool:
        return self._initialized

    def synthesize(self, text: str, output_path: str) -> str:
        """Сохраняет фрагмент и возвращает существующий WAV- или MP3-файл.

        Ошибка синтеза передаётся конвейеру: терять фрагмент лекции нельзя.
        """
        if not self._initialized:
            raise RuntimeError("TTS-движок не готов")
        if not text or not text.strip():
            raise ValueError("Текст для озвучивания пуст")

        destination = Path(output_path)
        destination.parent.mkdir(parents=True, exist_ok=True)
        if self.engine_type == "silero":
            result = Path(self._silero_engine.synthesize(text.strip(), str(destination.with_suffix(".wav"))))
        elif self.engine_type == "pyttsx3":
            result = destination.with_suffix(".wav")
            self._pyttsx3_engine.save_to_file(text.strip(), str(result))
            self._pyttsx3_engine.runAndWait()
        elif self.engine_type == "gtts":
            from gtts import gTTS
            result = destination.with_suffix(".mp3")
            gTTS(text=text.strip(), lang=self.language, slow=False).save(str(result))
        else:
            raise RuntimeError(f"Неподдерживаемый TTS-движок: {self.engine_type}")

        if not result.is_file() or result.stat().st_size == 0:
            raise RuntimeError(f"TTS не создал аудиофайл для фрагмента: {result}")
        return str(result)

    def synthesize_segment(self, text: str, segment_index: int, output_dir: str) -> str:
        path = Path(output_dir) / f"segment_{segment_index:04d}.wav"
        return self.synthesize(text, str(path))

    def get_available_voices(self) -> list[dict]:
        if self._pyttsx3_engine is None:
            return []
        return [
            {
                "id": voice.id,
                "name": voice.name,
                "languages": [
                    tag if isinstance(tag, str) else tag.decode("utf-8", errors="ignore")
                    for tag in (voice.languages or [])
                ],
                "gender": voice.gender,
            }
            for voice in self._pyttsx3_engine.getProperty("voices")
        ]
