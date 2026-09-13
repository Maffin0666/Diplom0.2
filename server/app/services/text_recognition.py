"""
Сервис распознавания текста с помощью EasyOCR.
Модель загружается один раз при инициализации и переиспользуется.
"""

import easyocr
import numpy as np
from pathlib import Path
from typing import Optional

from server.app.utils.logger import logger


class TextRecognizer:
    """
    Обёртка над EasyOCR для распознавания рукописного и печатного текста.

    Поддерживает русский и английский языки.
    Модель загружается при первом вызове и кэшируется.
    """

    _instance: Optional["TextRecognizer"] = None
    _reader: Optional[easyocr.Reader] = None

    def __new__(cls, *args, **kwargs):
        """Singleton — одна модель на всё приложение"""
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self, languages: list[str] = None, use_gpu: bool = False):
        """
        Args:
            languages: список языков для распознавания
            use_gpu: использовать GPU (CUDA)
        """
        if self._reader is not None:
            return  # Уже инициализирован

        self.languages = languages or ["ru", "en"]
        self.use_gpu = use_gpu

        logger.info(f"Загрузка EasyOCR модели (языки: {self.languages}, GPU: {use_gpu})...")
        try:
            self._reader = easyocr.Reader(
                self.languages,
                gpu=use_gpu,
                model_storage_directory=str(Path(__file__).parent.parent.parent / "models"),
                download_enabled=True
            )
            logger.info("EasyOCR модель загружена успешно")
        except Exception as e:
            logger.error(f"Ошибка загрузки EasyOCR: {e}")
            raise RuntimeError(f"Не удалось загрузить EasyOCR: {e}")

    @property
    def is_loaded(self) -> bool:
        """Загружена ли модель"""
        return self._reader is not None

    def recognize(self, image: np.ndarray, detail: int = 1) -> list[dict]:
        """
        Распознаёт текст на изображении.

        Args:
            image: изображение как numpy array (BGR или RGB)
            detail: уровень детализации (0 — только текст, 1 — с координатами)

        Returns:
            список словарей с ключами:
                - text: распознанный текст
                - confidence: уверенность (0-1)
                - bbox: координаты [[x1,y1],[x2,y2],[x3,y3],[x4,y4]]

        Raises:
            RuntimeError: если модель не загружена
        """
        if self._reader is None:
            raise RuntimeError("EasyOCR модель не загружена")

        logger.debug(f"Распознавание текста, размер изображения: {image.shape}")

        try:
            # EasyOCR возвращает список кортежей: (bbox, text, confidence)
            results = self._reader.readtext(
                image,
                detail=detail,
                paragraph=False,  # не объединять в параграфы — нам нужны отдельные строки
                min_size=10,  # минимальный размер текстового блока
                text_threshold=0.5,  # порог уверенности для текста
                low_text=0.3,  # порог для слабо выраженного текста
                link_threshold=0.3,  # порог связи между символами
                width_ths=0.7,  # порог ширины для объединения
                decoder="greedy"
            )

            recognized = []
            for item in results:
                if detail == 0:
                    # Только текст
                    recognized.append({
                        "text": item,
                        "confidence": 1.0,
                        "bbox": None
                    })
                else:
                    bbox, text, confidence = item
                    recognized.append({
                        "text": text.strip(),
                        "confidence": float(confidence),
                        "bbox": bbox
                    })

            # Фильтруем пустые результаты и с низкой уверенностью
            recognized = [
                r for r in recognized
                if r["text"] and len(r["text"].strip()) > 0 and r["confidence"] > 0.2
            ]

            # Сортируем по позиции: сверху вниз, слева направо
            if detail == 1 and recognized:
                recognized = self._sort_by_position(recognized)

            logger.info(f"Распознано {len(recognized)} текстовых блоков")
            for i, r in enumerate(recognized):
                logger.debug(f"  [{i}] ({r['confidence']:.2f}) {r['text']}")

            return recognized

        except Exception as e:
            logger.error(f"Ошибка распознавания текста: {e}")
            raise

    def recognize_from_file(self, image_path: str) -> list[dict]:
        """
        Распознаёт текст из файла изображения.

        Args:
            image_path: путь к файлу

        Returns:
            список распознанных блоков
        """
        import cv2

        path = Path(image_path)
        if not path.exists():
            raise FileNotFoundError(f"Файл не найден: {image_path}")

        image = cv2.imread(str(path))
        if image is None:
            raise ValueError(f"Не удалось прочитать изображение: {image_path}")

        return self.recognize(image)

    def _sort_by_position(self, results: list[dict]) -> list[dict]:
        """
        Сортировка результатов по позиции на странице.
        Группирует строки и сортирует сверху вниз, слева направо.
        """

        def get_top_left(item):
            bbox = item.get("bbox")
            if bbox is None:
                return (0, 0)
            # bbox — список из 4 точек [[x,y], ...]
            # Берём верхний левый угол
            y = min(point[1] for point in bbox)
            x = min(point[0] for point in bbox)
            return (y, x)

        return sorted(results, key=get_top_left)

    def get_full_text(self, results: list[dict]) -> str:
        """
        Собирает полный текст из результатов распознавания.
        Группирует по строкам на основе вертикальной позиции.

        Args:
            results: результаты recognize()

        Returns:
            полный текст с переносами строк
        """
        if not results:
            return ""

        # Группировка по строкам
        lines = self._group_into_lines(results)

        # Собираем текст
        text_lines = []
        for line in lines:
            line_text = " ".join(item["text"] for item in line)
            text_lines.append(line_text)

        return "\n".join(text_lines)

    def _group_into_lines(self, results: list[dict]) -> list[list[dict]]:
        """
        Группирует текстовые блоки по строкам.
        Блоки с близкой вертикальной позицией считаются одной строкой.
        """
        if not results:
            return []

        # Определяем среднюю высоту символов
        heights = []
        for r in results:
            if r["bbox"]:
                bbox = r["bbox"]
                h = max(p[1] for p in bbox) - min(p[1] for p in bbox)
                heights.append(h)

        avg_height = np.median(heights) if heights else 30
        line_threshold = avg_height * 0.5  # порог для отнесения к одной строке

        # Сортируем по Y-координате
        sorted_results = sorted(results, key=lambda r: min(p[1] for p in r["bbox"]) if r["bbox"] else 0)

        lines = []
        current_line = [sorted_results[0]]
        current_y = min(p[1] for p in sorted_results[0]["bbox"]) if sorted_results[0]["bbox"] else 0

        for item in sorted_results[1:]:
            if item["bbox"] is None:
                current_line.append(item)
                continue

            item_y = min(p[1] for p in item["bbox"])

            if abs(item_y - current_y) < line_threshold:
                # Та же строка
                current_line.append(item)
            else:
                # Новая строка
                # Сортируем текущую строку по X
                current_line.sort(key=lambda r: min(p[0] for p in r["bbox"]) if r["bbox"] else 0)
                lines.append(current_line)
                current_line = [item]
                current_y = item_y

        # Последняя строка
        if current_line:
            current_line.sort(key=lambda r: min(p[0] for p in r["bbox"]) if r["bbox"] else 0)
            lines.append(current_line)

        return lines