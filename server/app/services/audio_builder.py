"""
Сервис сборки финального аудиофайла из сегментов.

Склеивает отдельные MP3-файлы сегментов в один,
генерирует временные метки для синхронизации текста с аудио.
"""

import os
from pathlib import Path
from typing import Optional

from pydub import AudioSegment

from server.app.models import TimestampedSegment
from server.app.utils.logger import logger


class AudioBuilder:
    """
    Сборщик аудио из сегментов с генерацией временных меток.

    Процесс:
    1. Получает список текстовых сегментов
    2. Для каждого генерирует аудио через TTS
    3. Склеивает всё в один MP3 с паузами между сегментами
    4. Генерирует массив TimestampedSegment с точными временными метками
    """

    def __init__(self, pause_duration_ms: int = 500):
        """
        Args:
            pause_duration_ms: длительность паузы между сегментами (мс)
        """
        self.pause_duration_ms = pause_duration_ms
        logger.info(f"AudioBuilder инициализирован (пауза={pause_duration_ms}мс)")

    def build(
        self,
        segments_data: list[dict],
        tts_engine,
        output_dir: str,
        task_id: str
    ) -> tuple[str, list[TimestampedSegment], float]:
        """
        Собирает финальный аудиофайл.
        Новая логика: синтезируем каждый сегмент, но с МЕНЬШЕЙ паузой
        и с плавным соединением, чтобы звучало естественно.
        """
        logger.info(f"Сборка аудио: {len(segments_data)} сегментов, task_id={task_id}")

        segments_dir = os.path.join(output_dir, f"segments_{task_id}")
        Path(segments_dir).mkdir(parents=True, exist_ok=True)

        # Короткая пауза между сегментами (100мс вместо 500мс)
        # — делает речь более плавной
        short_pause = AudioSegment.silent(duration=100)
        # Длинная пауза после формул (для восприятия)
        formula_pause = AudioSegment.silent(duration=400)

        # Стартовая пауза
        combined = AudioSegment.silent(duration=200)
        current_time_ms = 200

        timestamped_segments = []
        successful_count = 0

        for i, seg_data in enumerate(segments_data):
            text = seg_data.get("text", "").strip()
            display_text = seg_data.get("display_text", text)
            is_formula = seg_data.get("is_formula", False)
            original = seg_data.get("original", None)

            if not text:
                continue

            tts_text = text

            segment_path = tts_engine.synthesize_segment(tts_text, i, segments_dir)

            if segment_path and os.path.exists(segment_path):
                try:
                    segment_audio = AudioSegment.from_file(segment_path)
                    segment_audio = self._normalize_volume(segment_audio)

                    # Обрезаем тишину в начале и в конце (важно для естественности!)
                    segment_audio = self._trim_silence(segment_audio)

                    start_time = current_time_ms / 1000.0
                    duration_ms = len(segment_audio)
                    end_time = (current_time_ms + duration_ms) / 1000.0

                    combined += segment_audio

                    # Выбираем паузу в зависимости от типа сегмента
                    pause = formula_pause if is_formula else short_pause
                    combined += pause

                    current_time_ms += duration_ms + len(pause)

                    ts = TimestampedSegment(
                        start=round(start_time, 3),
                        end=round(end_time, 3),
                        text=display_text,
                        is_formula=is_formula,
                        original=original
                    )
                    timestamped_segments.append(ts)
                    successful_count += 1

                    logger.debug(f"Сегмент {i}: [{start_time:.2f}-{end_time:.2f}] '{display_text[:50]}'")

                except Exception as e:
                    logger.error(f"Ошибка обработки сегмента {i}: {e}")
            else:
                logger.warning(f"Сегмент {i}: TTS не сгенерировал файл")

        combined += AudioSegment.silent(duration=300)
        total_duration = len(combined) / 1000.0

        output_path = os.path.join(output_dir, f"{task_id}.mp3")
        combined.export(output_path, format="mp3", bitrate="192k")

        logger.info(f"✅ Аудио готово: {total_duration:.1f}с, {successful_count}/{len(segments_data)} сегментов")

        self._cleanup_segments(segments_dir)
        return output_path, timestamped_segments, total_duration

    def _trim_silence(self, audio: AudioSegment, silence_threshold: float = -40.0,
                     chunk_size: int = 10) -> AudioSegment:
        """
        Обрезает тишину в начале и в конце аудио.
        Это устраняет ощущение "дёрганности" при склейке.
        """
        # Определяем начало не-тишины
        trim_start = 0
        while trim_start < len(audio) - chunk_size:
            chunk = audio[trim_start:trim_start + chunk_size]
            if chunk.dBFS > silence_threshold:
                break
            trim_start += chunk_size

        # Определяем конец не-тишины
        trim_end = len(audio)
        while trim_end > chunk_size:
            chunk = audio[trim_end - chunk_size:trim_end]
            if chunk.dBFS > silence_threshold:
                break
            trim_end -= chunk_size

        # Оставляем немного тишины по краям для плавности (30мс)
        trim_start = max(0, trim_start - 30)
        trim_end = min(len(audio), trim_end + 30)

        return audio[trim_start:trim_end]

    def _normalize_volume(self, audio: AudioSegment, target_dbfs: float = -20.0) -> AudioSegment:
        """
        Нормализация громкости аудио сегмента.

        Args:
            audio: аудио сегмент
            target_dbfs: целевой уровень в dBFS

        Returns:
            нормализованный аудио сегмент
        """
        if audio.dBFS == float('-inf'):
            return audio

        change_in_dbfs = target_dbfs - audio.dBFS
        return audio.apply_gain(change_in_dbfs)

    def _cleanup_segments(self, segments_dir: str):
        """Удаление временных файлов сегментов"""
        try:
            import shutil
            if os.path.exists(segments_dir):
                shutil.rmtree(segments_dir)
                logger.debug(f"Удалена временная директория: {segments_dir}")
        except Exception as e:
            logger.warning(f"Не удалось очистить {segments_dir}: {e}")

    def get_segment_at_time(
        self,
        segments: list[TimestampedSegment],
        time_seconds: float
    ) -> Optional[TimestampedSegment]:
        """
        Находит сегмент по времени (для синхронизации на клиенте).

        Args:
            segments: список сегментов с метками
            time_seconds: время в секундах

        Returns:
            сегмент или None
        """
        for segment in segments:
            if segment.start <= time_seconds <= segment.end:
                return segment
        return None