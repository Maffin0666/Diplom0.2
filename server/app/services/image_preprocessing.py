import cv2
import numpy as np
from scipy.ndimage import maximum_filter1d
from scipy.signal import find_peaks
from ..utils.logger import get_logger

logger = get_logger(__name__)


class ImagePreprocessor:
    """Модуль нормализации и пространственной подготовки страницы без потери полутонов."""

    @staticmethod
    def _prefer_local_lines(previous: list[tuple[int, int]],
                            local: list[tuple[int, int]], height: int) -> bool:
        """Включает чувствительный поиск только при заметном пропуске строк.

        На высокой плотной странице одна дополнительная строка тоже бывает
        существенна. На коротких страницах такая разница часто означает шум.
        """
        gain = len(local) - len(previous)
        return (len(previous) >= 3 and
                (gain >= 3 or (height >= 1600 and len(previous) >= 15 and gain == 1)))

    @staticmethod
    def _local_line_spans(gray: np.ndarray, threshold: int) -> list[tuple[int, int]]:
        """Ищет слабые строки по высоте пика относительно соседнего участка.

        Глобальный максимум плотной страницы может быть во много раз выше
        коротких строк; локальная нормировка сохраняет их без снижения
        порога для всего листа.
        """
        height, width = gray.shape
        central = gray[:, width // 12:width - width // 12]
        profile = np.count_nonzero(central < min(100, threshold), axis=1).astype(float)
        smooth = np.convolve(profile, np.ones(9) / 9, mode="same")
        if smooth.max() < 5:
            return []
        local_max = maximum_filter1d(smooth, size=181, mode="nearest")
        peaks, properties = find_peaks(
            smooth, distance=max(16, height // 50), prominence=3,
        )
        centers = [int(y) for y, prominence in zip(peaks, properties["prominences"])
                   if smooth[y] >= local_max[y] * 0.24
                   and prominence >= local_max[y] * 0.035
                   and height * 0.015 < y < height * 0.985]
        if not 3 <= len(centers) <= 45:
            return []
        typical_gap = float(np.median(np.diff(centers)))
        boundaries = [max(0, round(centers[0] - typical_gap * 0.6))]
        boundaries += [(left + right) // 2 for left, right in
                       zip(centers, centers[1:])]
        boundaries.append(min(height, round(centers[-1] + typical_gap * 0.6)))
        return [(max(0, top - 8), min(height, bottom + 8))
                for top, bottom in zip(boundaries, boundaries[1:])]

    @staticmethod
    def _contrast_line_spans(gray: np.ndarray) -> list[tuple[int, int]]:
        """Find dark ink relative to local paper brightness, ignoring shadows.

        A darkened lower half can pass an absolute gray threshold on every
        grid line and produce many phantom rows. This candidate is only used
        when it removes a long tail of such rows below the last clear ink.
        """
        height, width = gray.shape
        background = cv2.GaussianBlur(gray, (101, 101), 0)
        contrast = background.astype(np.int16) - gray.astype(np.int16)
        central = contrast[:, width // 12:width - width // 12]
        profile = np.count_nonzero(central > 55, axis=1).astype(float)
        smooth = np.convolve(profile, np.ones(9) / 9, mode="same")
        if smooth.max() < 5:
            return []
        local_max = maximum_filter1d(smooth, size=181, mode="nearest")
        peaks, properties = find_peaks(
            smooth, distance=max(16, height // 50), prominence=3,
        )
        centers = [int(y) for y, prominence in zip(peaks, properties["prominences"])
                   if smooth[y] >= local_max[y] * 0.24
                   and prominence >= local_max[y] * 0.035
                   and height * 0.015 < y < height * 0.985]
        if not 3 <= len(centers) <= 45:
            return []
        typical_gap = float(np.median(np.diff(centers)))
        boundaries = [max(0, round(centers[0] - typical_gap * 0.6))]
        boundaries += [(left + right) // 2 for left, right in zip(centers, centers[1:])]
        boundaries.append(min(height, round(centers[-1] + typical_gap * 0.6)))
        return [(max(0, top - 8), min(height, bottom + 8))
                for top, bottom in zip(boundaries, boundaries[1:])]

    @staticmethod
    def _dense_line_spans(gray: np.ndarray, threshold: int) -> list[tuple[int, int]]:
        """Дополнительные строки на плотной странице, где общий профиль их склеил.

        Поля тетради и просвечивающий текст с оборота искажают общую
        гистограмму. Считаем только центральную часть и тёмные штрихи.
        """
        height, width = gray.shape
        central = gray[:, width // 12:width - width // 12]
        profile = np.count_nonzero(central < min(100, threshold), axis=1).astype(float)
        smooth = np.convolve(profile, np.ones(9) / 9, mode="same")
        maximum = float(smooth.max())
        if maximum < 5:
            return []
        peaks, _ = find_peaks(
            smooth, distance=max(16, height // 50),
            prominence=max(3, maximum * 0.04),
        )
        centers = [int(y) for y in peaks
                   if smooth[y] >= maximum * 0.15
                   and height * 0.015 < y < height * 0.985]
        if not 3 <= len(centers) <= 45:
            return []
        typical_gap = float(np.median(np.diff(centers)))
        top = max(0, int(centers[0] - typical_gap * 0.6))
        bottom = min(height, int(centers[-1] + typical_gap * 0.6))
        boundaries = [top] + [(left + right) // 2 for left, right in
                              zip(centers, centers[1:])] + [bottom]
        return [(max(0, boundaries[i] - 8), min(height, boundaries[i + 1] + 8))
                for i in range(len(centers))]

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

            # Малый угол часто вызван длинными росчерками почерка, а поворот
            # размывает тонкие штрихи. Корректируем только заметный перекос.
            if 2.0 <= abs(angle) <= 20.0:
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

    @staticmethod
    def detect_line_spans(image: np.ndarray) -> list[tuple[int, int]]:
        """Находит строки по горизонтальной плотности чернил без тяжёлой модели.

        Используется только если детектор EasyOCR пропустил строки. Границы
        соседних полос немного перекрываются, чтобы не обрезать петли букв.
        """
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if image.ndim == 3 else image
        height, width = gray.shape[:2]
        if height < 60:
            return []
        # На небольших снимках прежние широкие интервалы защищают от
        # повторного считывания длинных петель одной и той же строки.
        if width < 1200 or height < 900:
            _, ink = cv2.threshold(gray, 0, 255,
                                   cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
            profile = np.count_nonzero(ink, axis=1).astype(float)
            smooth = np.convolve(profile, np.ones(11) / 11, mode="same")
            maximum = float(smooth.max())
            if maximum < 5:
                return []
            peaks, properties = find_peaks(
                smooth, distance=max(16, height // 18),
                prominence=max(3, maximum * 0.09))
            if len(peaks) == 0:
                return []
            strongest = float(properties["prominences"].max())
            centers = [int(y) for y, prominence in zip(peaks, properties["prominences"])
                       if smooth[y] >= maximum * 0.35 and prominence >= strongest * 0.25]
            if not 2 <= len(centers) <= 30:
                return []
            boundaries = ([0] + [(left + right) // 2 for left, right in
                                   zip(centers, centers[1:])] + [height])
            return [(max(0, boundaries[i] - 8),
                     min(height, boundaries[i + 1] + 8)) for i in range(len(centers))]
        otsu, _ = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        otsu_level = max(1, int(otsu))
        margin = max(1, gray.shape[1] // 20)
        left_dark = np.count_nonzero(gray[:, :margin] < min(otsu_level, 100))
        next_dark = np.count_nonzero(gray[:, margin:2 * margin] < min(otsu_level, 100))
        projection_gray = gray[:, margin:] if left_dark > next_dark * 1.5 else gray

        def find_centers(threshold: int) -> list[int]:
            profile = np.count_nonzero(projection_gray < threshold, axis=1).astype(float)
            smooth = np.convolve(profile, np.ones(11) / 11, mode="same")
            maximum = float(smooth.max())
            if maximum < 5:
                return []
            # Плотные строки могут идти через 4–5 % высоты страницы.
            peaks, _ = find_peaks(smooth, distance=max(16, height // 45),
                                  prominence=max(3, maximum * 0.05))
            return [int(y) for y in peaks if smooth[y] >= maximum * 0.20]

        centers = find_centers(otsu_level)
        # Убираем светлые следы текста с оборота листа, если сильных тёмных
        # штрихов достаточно для сохранения почти всех настоящих строк.
        dark_centers = find_centers(min(otsu_level, 100))
        if len(dark_centers) >= 2 and len(dark_centers) >= len(centers) * 0.70:
            centers = dark_centers
        if not 2 <= len(centers) <= 45:
            centers = []
        bottom = height
        if len(centers) >= 3:
            typical_gap = float(np.median(np.diff(centers)))
            # Пик почти у границы кадра означает обрезанную строку. Не
            # озвучиваем догадки по нескольким видимым нижним штрихам.
            if height - centers[-1] < typical_gap * 0.20:
                bottom = (centers[-2] + centers[-1]) // 2
                centers = centers[:-1]
        boundaries = [0] + [(left + right) // 2 for left, right in zip(centers, centers[1:])] + [bottom]
        spans = [(max(0, boundaries[i] - 8), min(height, boundaries[i + 1] + 8))
                 for i in range(len(centers))]
        dense_spans = ImagePreprocessor._dense_line_spans(gray, otsu_level)
        # Небольшая разница может быть отражением текста с оборота листа.
        # Дополнительное разделение включаем лишь при явном пропуске строк.
        if len(dense_spans) >= len(spans) + 3:
            logger.info("OCR: уточнены границы плотных строк, обычных=%d, уточнённых=%d",
                        len(spans), len(dense_spans))
            spans = dense_spans
        local_spans = ImagePreprocessor._local_line_spans(gray, otsu_level)
        # Переключаемся лишь при явном пропуске нескольких строк. На обычных
        # страницах сохранён прежний кроп, который лучше читает TrOCR.
        if ImagePreprocessor._prefer_local_lines(spans, local_spans, height):
            logger.info("OCR: локальный поиск строк, прежних=%d, найдено=%d",
                        len(spans), len(local_spans))
            spans = local_spans
        # The contrast candidate may be shorter because it ignores grid lines
        # on a shadowed page. Accept it only for a large spurious tail; normal
        # close-spaced lines keep their existing detector and crop boundaries.
        contrast_spans = ImagePreprocessor._contrast_line_spans(gray)
        if (len(contrast_spans) >= 3 and len(spans) - len(contrast_spans) >= 5
                and spans[-1][1] - contrast_spans[-1][1] >= height * 0.15):
            logger.info("OCR: удалены ложные строки в тени, прежних=%d, осталось=%d",
                        len(spans), len(contrast_spans))
            return contrast_spans
        return spans

    @staticmethod
    def detect_ink_bounds(row: np.ndarray) -> tuple[int, int, int, int] | None:
        """Обрезает пустые поля строки, сохраняя петли и росчерки букв."""
        height, width = row.shape[:2]
        if height < 12 or width < 40:
            return None
        gray = cv2.cvtColor(row, cv2.COLOR_BGR2GRAY) if row.ndim == 3 else row
        otsu, _ = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        ink = gray < min(120, max(1, int(otsu)))
        # Исключаем переплёт лишь когда край заметно темнее соседней полосы.
        edge = max(1, width // 20)
        binding = (np.count_nonzero(ink[:, :edge]) >
                   np.count_nonzero(ink[:, edge:2 * edge]) * 1.5)
        if binding:
            ink[:, :int(width * 0.08)] = False
        # Some notebook photos have the binding or a dark camera border on
        # the right. A nearly solid last column cannot be handwriting.
        right_edge = ink[:, -edge:]
        right_inner = ink[:, -2 * edge:-edge]
        right_artifact = (np.mean(ink[:, -8:]) >= 0.8
                          and np.count_nonzero(right_edge) >
                          np.count_nonzero(right_inner) * 1.5)
        if right_artifact:
            ink[:, -max(8, int(width * 0.06)):] = False
        counts = np.count_nonzero(ink, axis=0).astype(np.float32)
        smooth = np.convolve(counts, np.ones(21) / 21, mode="same")
        if smooth.max() < 2:
            return None
        strong = (smooth >= max(2, float(smooth.max()) * 0.18)).astype(np.uint8)[None, :]
        # Слова отделены пробелами, а просвечивающий текст справа — широкой
        # светлой областью. Склеиваем только обычные межсловные пробелы.
        strong = cv2.morphologyEx(strong, cv2.MORPH_CLOSE,
                                  np.ones((1, max(25, width // 24)), np.uint8))[0]
        edges = np.diff(np.r_[0, strong, 0].astype(np.int8))
        starts, ends = np.flatnonzero(edges == 1), np.flatnonzero(edges == -1)
        groups = [(int(start), int(end), float(counts[start:end].sum()))
                  for start, end in zip(starts, ends) if end - start >= 25]
        if not groups:
            return None
        # A disconnected, narrow region touching the right boundary is often
        # the spiral binding. Prefer the text group farther inside the page.
        inner_groups = [group for group in groups
                        if not (group[0] >= width * 0.90 and group[1] >= width - 1
                                and group[1] - group[0] <= width * 0.11)]
        if inner_groups:
            right_artifact = right_artifact or len(inner_groups) < len(groups)
            groups = inner_groups
        # У длинной строки короткое первое слово может образовать отдельную
        # группу: выбор только самой плотной обрезал «Виды» или «Тестирование».
        # Добавляем только группы слева с заметным количеством тёмных штрихов.
        # Группы справа на реальных фото нередко оказываются просвечивающим
        # текстом или началом соседней строки и ухудшают распознавание.
        strongest = max(groups, key=lambda group: group[2])
        left, right = strongest[:2]
        max_gap = max(140, int(width * (0.35 if right_artifact else 0.075)))
        for start, end, mass in sorted(groups, key=lambda group: group[2], reverse=True):
            if end > left:
                continue
            gap = left - end
            min_mass = strongest[2] * (0.05 if right_artifact and end - start >= 80 else 0.12)
            min_width = 25 if right_artifact else max(60, width // 32)
            if (mass >= min_mass
                    and end - start >= min_width
                    and gap <= max_gap):
                left = start
        left = max(0, left - 14)
        right = min(width, right + 14)
        rows = np.flatnonzero(np.count_nonzero(ink[:, left:right], axis=1)
                             >= max(3, (right - left) // 250))
        if len(rows) < 3:
            return None
        return (left, max(0, int(rows[0]) - 8),
                right, min(height, int(rows[-1]) + 9))

    @staticmethod
    def detect_centered_text_span(row: np.ndarray) -> tuple[int, int] | None:
        """Ограничивает крупные боковые росчерки вокруг короткой строки.

        Применяется только если несколько букв имеют общую высоту начала и
        образуют узкую центральную группу. Запас по краям сохраняет первые
        буквы с длинными соединениями и завершающие штрихи.
        """
        height, width = row.shape[:2]
        if width < 700 or height < 80:
            return None
        gray = cv2.cvtColor(row, cv2.COLOR_BGR2GRAY) if row.ndim == 3 else row
        _, ink = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
        _, _, stats, _ = cv2.connectedComponentsWithStats(ink, 8)
        components = [part for part in stats[1:]
                      if part[4] >= 30 and 5 <= part[3] <= height * 0.55]
        if len(components) < 8:
            return None
        starts = np.array([int(part[1]) for part in components])
        mode = int(np.argmax(np.bincount(starts // 5))) * 5
        core = [part for part in components if abs(int(part[1]) - mode) <= 7]
        if len(core) < 5:
            return None
        left = min(int(part[0]) for part in core)
        right = max(int(part[0] + part[2]) for part in core)
        if not (left >= width * 0.30 and right <= width * 0.80
                and width * 0.30 <= right - left <= width * 0.60):
            return None
        return max(0, left - int(width * 0.16)), min(width, right + int(width * 0.06))

    @classmethod
    def preprocess_for_ocr(cls, image_bytes: bytes, deskew: bool = True) -> np.ndarray:
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
        deskewed = cls.deskew_page(img) if deskew else img

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
