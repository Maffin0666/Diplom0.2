"""
Предобработка изображений перед OCR.
Улучшает качество распознавания за счёт фильтрации,
бинаризации и коррекции перспективы.
"""

import cv2
import numpy as np
from pathlib import Path
from typing import Optional

from server.app.utils.logger import logger


class ImagePreprocessor:
    """
    Препроцессор изображений для улучшения качества OCR.

    Этапы обработки:
    1. Ресайз до допустимого размера
    2. Конвертация в градации серого
    3. Удаление шума (bilateral filter)
    4. Адаптивная бинаризация
    5. Коррекция наклона (deskew)
    6. Морфологические операции для очистки
    """

    def __init__(self, max_side: int = 2048):
        """
        Args:
            max_side: максимальный размер длинной стороны изображения
        """
        self.max_side = max_side
        logger.info(f"ImagePreprocessor инициализирован (max_side={max_side})")

    def preprocess(self, image_path: str, save_path: Optional[str] = None) -> np.ndarray:
        """
        Полный пайплайн предобработки изображения.

        Args:
            image_path: путь к исходному изображению
            save_path: путь для сохранения обработанного (опционально)

        Returns:
            обработанное изображение как numpy array (BGR)

        Raises:
            FileNotFoundError: если файл не найден
            ValueError: если файл не является изображением
        """
        path = Path(image_path)
        if not path.exists():
            raise FileNotFoundError(f"Изображение не найдено: {image_path}")

        logger.info(f"Начало предобработки: {image_path}")

        # Загрузка изображения
        image = cv2.imread(str(path))
        if image is None:
            raise ValueError(f"Не удалось прочитать изображение: {image_path}")

        original_shape = image.shape[:2]
        logger.debug(f"Исходный размер: {original_shape[1]}x{original_shape[0]}")

        # 1. Ресайз
        image = self._resize(image)

        # 2. Градации серого
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

        # 3. Удаление шума
        denoised = self._denoise(gray)

        # 4. Улучшение контраста (CLAHE)
        enhanced = self._enhance_contrast(denoised)

        # 5. Адаптивная бинаризация
        binary = self._binarize(enhanced)

        # 6. Коррекция наклона
        deskewed = self._deskew(binary)

        # 7. Морфологическая очистка
        cleaned = self._morphological_clean(deskewed)

        # Конвертируем обратно в BGR для EasyOCR
        result = cv2.cvtColor(cleaned, cv2.COLOR_GRAY2BGR)

        if save_path:
            cv2.imwrite(str(save_path), result)
            logger.debug(f"Обработанное изображение сохранено: {save_path}")

        logger.info(f"Предобработка завершена. Результат: {result.shape[1]}x{result.shape[0]}")
        return result

    def preprocess_for_formulas(self, image_path: str) -> np.ndarray:
        """
        Специальная предобработка для распознавания формул.
        Более агрессивная бинаризация и очистка.

        Args:
            image_path: путь к изображению

        Returns:
            обработанное изображение
        """
        path = Path(image_path)
        if not path.exists():
            raise FileNotFoundError(f"Изображение не найдено: {image_path}")

        image = cv2.imread(str(path))
        if image is None:
            raise ValueError(f"Не удалось прочитать изображение: {image_path}")

        image = self._resize(image)
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

        # Более сильное шумоподавление
        denoised = cv2.bilateralFilter(gray, 11, 85, 85)

        # Бинаризация Оцу
        _, binary = cv2.threshold(denoised, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)

        # Инверсия если фон тёмный
        if np.mean(binary) < 127:
            binary = cv2.bitwise_not(binary)

        return cv2.cvtColor(binary, cv2.COLOR_GRAY2BGR)

    def _resize(self, image: np.ndarray) -> np.ndarray:
        """Ресайз с сохранением пропорций"""
        h, w = image.shape[:2]
        max_dim = max(h, w)

        if max_dim <= self.max_side:
            return image

        scale = self.max_side / max_dim
        new_w = int(w * scale)
        new_h = int(h * scale)

        resized = cv2.resize(image, (new_w, new_h), interpolation=cv2.INTER_AREA)
        logger.debug(f"Ресайз: {w}x{h} → {new_w}x{new_h}")
        return resized

    def _denoise(self, gray: np.ndarray) -> np.ndarray:
        """Удаление шума с помощью bilateral filter (сохраняет края)"""
        return cv2.bilateralFilter(gray, 9, 75, 75)

    def _enhance_contrast(self, gray: np.ndarray) -> np.ndarray:
        """Улучшение контраста с помощью CLAHE"""
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        return clahe.apply(gray)

    def _binarize(self, gray: np.ndarray) -> np.ndarray:
        """
        Адаптивная бинаризация.
        Используем метод Гаусса — хорошо работает с рукописным текстом.
        """
        binary = cv2.adaptiveThreshold(
            gray, 255,
            cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
            cv2.THRESH_BINARY,
            blockSize=15,  # размер окна (нечётное число)
            C=10  # константа вычитания
        )
        return binary

    def _deskew(self, binary: np.ndarray) -> np.ndarray:
        """
        Коррекция наклона текста.
        Определяет угол через преобразование Хафа и поворачивает.
        """
        # Инвертируем для поиска линий
        inverted = cv2.bitwise_not(binary)

        # Ищем линии через Hough Transform
        lines = cv2.HoughLinesP(
            inverted, 1, np.pi / 180,
            threshold=100, minLineLength=100, maxLineGap=10
        )

        if lines is None or len(lines) == 0:
            return binary

        # Вычисляем средний угол наклона
        angles = []
        for line in lines:
            x1, y1, x2, y2 = line[0]
            if x2 - x1 == 0:
                continue
            angle = np.degrees(np.arctan2(y2 - y1, x2 - x1))
            # Учитываем только небольшие наклоны (±15°)
            if abs(angle) < 15:
                angles.append(angle)

        if not angles:
            return binary

        median_angle = np.median(angles)

        # Не поворачиваем если наклон минимальный
        if abs(median_angle) < 0.5:
            return binary

        logger.debug(f"Коррекция наклона: {median_angle:.2f}°")

        # Поворот
        h, w = binary.shape
        center = (w // 2, h // 2)
        rotation_matrix = cv2.getRotationMatrix2D(center, median_angle, 1.0)
        rotated = cv2.warpAffine(
            binary, rotation_matrix, (w, h),
            flags=cv2.INTER_CUBIC,
            borderMode=cv2.BORDER_REPLICATE
        )

        return rotated

    def _morphological_clean(self, binary: np.ndarray) -> np.ndarray:
        """
        Морфологическая очистка — удаление мелкого мусора.
        """
        # Ядро для морфологических операций
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (2, 2))

        # Закрытие — заполняет мелкие разрывы в символах
        closed = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel, iterations=1)

        # Открытие — удаляет мелкий шум
        opened = cv2.morphologyEx(closed, cv2.MORPH_OPEN, kernel, iterations=1)

        return opened

    def extract_regions(self, image: np.ndarray) -> list[dict]:
        """
        Выделяет области текста и формул на изображении.
        Возвращает список регионов с координатами и типом.

        Args:
            image: предобработанное изображение (BGR)

        Returns:
            список словарей с ключами: bbox, type, image
        """
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)

        # Ищем контуры
        contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        regions = []
        h_img, w_img = image.shape[:2]

        for contour in contours:
            x, y, w, h = cv2.boundingRect(contour)

            # Фильтруем слишком мелкие области
            if w < 20 or h < 10:
                continue

            # Фильтруем слишком большие (весь кадр)
            if w > w_img * 0.95 and h > h_img * 0.95:
                continue

            # Вырезаем регион с отступами
            pad = 5
            x1 = max(0, x - pad)
            y1 = max(0, y - pad)
            x2 = min(w_img, x + w + pad)
            y2 = min(h_img, y + h + pad)

            region_image = image[y1:y2, x1:x2]

            # Эвристика: формулы обычно имеют большее соотношение сторон
            # и содержат больше мелких элементов
            aspect_ratio = w / max(h, 1)
            region_type = "text"  # по умолчанию текст

            regions.append({
                "bbox": (x1, y1, x2, y2),
                "type": region_type,
                "image": region_image,
                "aspect_ratio": aspect_ratio
            })

        # Сортируем сверху вниз, слева направо
        regions.sort(key=lambda r: (r["bbox"][1], r["bbox"][0]))

        logger.debug(f"Найдено регионов: {len(regions)}")
        return regions