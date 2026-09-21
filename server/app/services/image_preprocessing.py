import cv2
import numpy as np
from ..utils.logger import get_logger

logger = get_logger(__name__)


class ImagePreprocessor:
    """Модуль нормализации и пространственной подготовки страницы без потери полутонов."""

    @staticmethod
    def deskew_page(image: np.ndarray) -> np.ndarray:
        """Компенсация геометрического наклона листа конспекта."""
        try:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if len(image.shape) == 3 else image
            # Находим координаты темных пикселей (ручка/карандаш)
            coords = np.column_stack(np.where(gray < 190))
            if len(coords) < 150:
                return image

            angle = cv2.minAreaRect(coords)[-1]
            if angle < -45:
                angle = -(90 + angle)
            elif angle > 45:
                angle = 90 - angle
            else:
                angle = -angle

            # Корректируем только реальный наклон страницы (от 1 до 20 градусов),
            # чтобы не деформировать естественный наклон почерка
            if 1.0 <= abs(angle) <= 20.0:
                h, w = image.shape[:2]
                center = (w // 2, h // 2)
                matrix = cv2.getRotationMatrix2D(center, angle, 1.0)
                rotated = cv2.warpAffine(
                    image, matrix, (w, h),
                    flags=cv2.INTER_LINEAR,
                    borderMode=cv2.BORDER_REPLICATE
                )
                return rotated
        except Exception as e:
            logger.warning(f"Ошибка выравнивания наклона: {e}")
        return image

    @classmethod
    def preprocess_for_ocr(cls, image_bytes: bytes) -> np.ndarray:
        """
        Основной конвейер: сохранение микроструктуры рукописных штрихов,
        подавление теней и подготовка контрастного полутонового массива.
        """
        nparr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if img is None:
            raise ValueError("Не удалось декодировать входящее изображение")

        # 1. Приведение к рабочему разрешению с сохранением соотношения сторон
        h, w = img.shape[:2]
        max_dimension = 1920
        if max(h, w) > max_dimension:
            scale = max_dimension / float(max(h, w))
            img = cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)

        # 2. Выравнивание угла перекоса страницы
        deskewed = cls.deskew_page(img)

        # 3. Перевод в градации серого
        gray = cv2.cvtColor(deskewed, cv2.COLOR_BGR2GRAY)

        # 4. Адаптивное выравнивание гистограммы (CLAHE)
        # Устраняет неравномерность освещения и градиентные тени от руки/камеры
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        contrast_enhanced = clahe.apply(gray)

        # 5. Билатеральная фильтрация: убирает шум зернистости бумаги, сохраняя границы штрихов
        filtered = cv2.bilateralFilter(contrast_enhanced, d=5, sigmaColor=40, sigmaSpace=40)

        # Возвращаем 3-канальное изображение (требуется для нейросетевых энкодеров)
        return cv2.cvtColor(filtered, cv2.COLOR_GRAY2BGR)