"""
Сервис синтеза речи (Text-to-Speech).

Поддерживает два движка:
- pyttsx3 — офлайн, работает без интернета
- gTTS — онлайн, лучше качество, требует интернет

Генерирует MP3 файлы для каждого сегмента текста.
"""

import os
from pathlib import Path
from typing import Optional

from server.app.utils.logger import logger


class TTSEngine:
    """
    Движок синтеза речи с поддержкой нескольких бэкендов.
    """

    def __init__(self, engine_type: str = "silero", language: str = "ru",
                 rate: int = 150, volume: float = 0.9, speaker: str = "xenia"):
        self.engine_type = engine_type
        self.language = language
        self.rate = rate
        self.volume = volume
        self.speaker = speaker

        self._pyttsx3_engine = None
        self._silero_engine = None
        self._initialized = False

        self._initialize()

    def _initialize(self):
        if self.engine_type == "silero":
            self._init_silero()
        elif self.engine_type == "pyttsx3":
            self._init_pyttsx3()
        elif self.engine_type == "gtts":
            self._check_gtts()
        else:
            raise ValueError(f"Неизвестный TTS движок: {self.engine_type}")

    def _init_silero(self):
        """Инициализация Silero"""
        try:
            from server.app.services.silero_tts import SileroTTS
            self._silero_engine = SileroTTS(speaker=self.speaker)
            self._initialized = True
            logger.info(f"Silero TTS инициализирован (голос: {self.speaker})")
        except Exception as e:
            logger.error(f"Ошибка инициализации Silero: {e}")
            logger.info("Переключаемся на pyttsx3...")
            self.engine_type = "pyttsx3"
            self._init_pyttsx3()


    def _init_pyttsx3(self):
        """Инициализация pyttsx3"""
        try:
            import pyttsx3

            self._pyttsx3_engine = pyttsx3.init()

            # Настраиваем скорость
            self._pyttsx3_engine.setProperty('rate', self.rate)

            # Настраиваем громкость
            self._pyttsx3_engine.setProperty('volume', self.volume)

            # Выбираем русский голос
            voices = self._pyttsx3_engine.getProperty('voices')
            russian_voice = None

            for voice in voices:
                voice_langs = voice.languages
                voice_name = voice.name.lower()

                # Ищем русский голос
                if 'russian' in voice_name or 'ru' in voice_name:
                    russian_voice = voice
                    break

                # Проверяем по языковым тегам
                if voice_langs:
                    for lang in voice_langs:
                        lang_str = lang if isinstance(lang, str) else lang.decode('utf-8', errors='ignore')
                        if 'ru' in lang_str.lower():
                            russian_voice = voice
                            break

            if russian_voice:
                self._pyttsx3_engine.setProperty('voice', russian_voice.id)
                logger.info(f"pyttsx3: выбран голос '{russian_voice.name}'")
            else:
                logger.warning("pyttsx3: русский голос не найден, используется голос по умолчанию")
                # Используем первый доступный
                if voices:
                    self._pyttsx3_engine.setProperty('voice', voices[0].id)

            self._initialized = True
            logger.info(f"pyttsx3 инициализирован (скорость={self.rate}, громкость={self.volume})")

        except Exception as e:
            logger.error(f"Ошибка инициализации pyttsx3: {e}")
            logger.info("Переключаемся на gTTS...")
            self.engine_type = "gtts"
            self._check_gtts()

    def _check_gtts(self):
        """Проверка доступности gTTS"""
        try:
            from gtts import gTTS
            self._initialized = True
            logger.info("gTTS доступен")
        except ImportError:
            logger.error("gTTS не установлен. Установите: pip install gTTS")
            raise RuntimeError("Ни один TTS движок недоступен")

    @property
    def is_initialized(self) -> bool:
        return self._initialized

    def synthesize(self, text: str, output_path: str) -> bool:
        """
        Синтезирует речь из текста и сохраняет в файл.

        Args:
            text: текст для озвучки
            output_path: путь для сохранения аудиофайла (WAV для pyttsx3, MP3 для gTTS)

        Returns:
            True если успешно

        Raises:
            RuntimeError: если движок не инициализирован
        """
        if not self._initialized:
            raise RuntimeError("TTS движок не инициализирован")

        if not text or not text.strip():
            logger.warning("Пустой текст для синтеза")
            return False

        text = text.strip()
        logger.debug(f"TTS синтез ({self.engine_type}): '{text[:80]}...' → {output_path}")

        try:
            if self.engine_type == "silero":
                return self._silero_engine.synthesize(text, output_path)
            elif self.engine_type == "pyttsx3":
                return self._synthesize_pyttsx3(text, output_path)
            elif self.engine_type == "gtts":
                return self._synthesize_gtts(text, output_path)
            else:
                raise ValueError(f"Неизвестный движок: {self.engine_type}")
        except Exception as e:
            logger.error(f"Ошибка синтеза речи: {e}")
            return False

    def _synthesize_pyttsx3(self, text: str, output_path: str) -> bool:
        """Синтез через pyttsx3 (офлайн)"""
        try:
            # pyttsx3 сохраняет в WAV/AIFF
            # Нам нужно конвертировать в MP3 через pydub
            wav_path = output_path.replace('.mp3', '.wav')

            self._pyttsx3_engine.save_to_file(text, wav_path)
            self._pyttsx3_engine.runAndWait()

            if not os.path.exists(wav_path):
                logger.error(f"pyttsx3 не создал файл: {wav_path}")
                return False

            # Конвертируем WAV → MP3 через pydub
            if output_path.endswith('.mp3'):
                try:
                    from pydub import AudioSegment
                    audio = AudioSegment.from_wav(wav_path)
                    audio.export(output_path, format="mp3", bitrate="128k")
                    # Удаляем промежуточный WAV
                    os.remove(wav_path)
                except Exception as conv_err:
                    logger.warning(f"Не удалось конвертировать в MP3: {conv_err}. Оставляем WAV.")
                    # Переименовываем WAV в целевой файл
                    os.rename(wav_path, output_path)

            logger.debug(f"pyttsx3: файл сохранён {output_path}")
            return True

        except Exception as e:
            logger.error(f"Ошибка pyttsx3: {e}")
            # Пробуем gTTS как fallback
            logger.info("Пробуем gTTS как fallback...")
            try:
                return self._synthesize_gtts(text, output_path)
            except Exception:
                return False

    def _synthesize_gtts(self, text: str, output_path: str) -> bool:
        """Синтез через gTTS (онлайн, Google)"""
        try:
            from gtts import gTTS

            tts = gTTS(text=text, lang=self.language, slow=False)
            tts.save(output_path)

            logger.debug(f"gTTS: файл сохранён {output_path}")
            return True

        except Exception as e:
            logger.error(f"Ошибка gTTS: {e}")
            return False

    def synthesize_segment(self, text: str, segment_index: int, output_dir: str) -> Optional[str]:
        """
        Синтезирует один сегмент текста.

        Args:
            text: текст сегмента
            segment_index: порядковый номер
            output_dir: директория для сохранения

        Returns:
            путь к аудиофайлу или None
        """
        Path(output_dir).mkdir(parents=True, exist_ok=True)

        filename = f"segment_{segment_index:04d}.mp3"
        filepath = os.path.join(output_dir, filename)

        success = self.synthesize(text, filepath)
        return filepath if success else None

    def get_available_voices(self) -> list[dict]:
        """Возвращает список доступных голосов (для pyttsx3)"""
        if self._pyttsx3_engine is None:
            return []

        voices = self._pyttsx3_engine.getProperty('voices')
        return [
            {
                "id": voice.id,
                "name": voice.name,
                "languages": [
                    (l if isinstance(l, str) else l.decode('utf-8', errors='ignore'))
                    for l in (voice.languages or [])
                ],
                "gender": voice.gender
            }
            for voice in voices
        ]