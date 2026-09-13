"""
Сервис распознавания математических формул.

Для ВКР используется упрощённый подход:
- Основной метод: обнаружение формул через паттерны в тексте EasyOCR
- Опциональный метод: pix2tex (LaTeX-OCR) для отдельных регионов с формулами

Если pix2tex не установлен — используем только эвристики.
"""

import re
from typing import Optional

from server.app.utils.logger import logger


class FormulaRecognizer:
    """
    Распознаватель математических формул.

    Стратегия:
    1. Ищем паттерны формул в тексте (после EasyOCR)
    2. Пытаемся конвертировать в LaTeX
    3. Помечаем сегменты как "формула" для дальнейшей озвучки
    """

    def __init__(self):
        """Инициализация. Пытаемся загрузить pix2tex."""
        self._latex_ocr = None
        self._load_latex_ocr()

        # Паттерны для определения формул в тексте
        self._formula_patterns = [
            # Степени: x^2, x^n, x^{10}
            re.compile(r'[a-zA-Zа-яА-Я]\s*[\^]\s*[\{\(]?\s*\d+\s*[\}\)]?'),
            # Индексы: x_1, a_n, y_{ij}
            re.compile(r'[a-zA-Zа-яА-Я]\s*[_]\s*[\{\(]?\s*\w+\s*[\}\)]?'),
            # Дроби и операторы
            re.compile(r'[a-zA-Z]\s*/\s*[a-zA-Z]'),
            # Корни
            re.compile(r'[√V]\s*[\(\[{]?\s*\w+\s*[\)\]}]?'),
            # Простые уравнения: a + b = c
            re.compile(r'[a-zA-Zа-яА-Я]\s*[+\-*/=<>≤≥≠±×÷]\s*[a-zA-Zа-яА-Я0-9]'),
            # Выражения с скобками типа f(x)
            re.compile(r'[a-zA-Z]\s*\(\s*[a-zA-Z]\s*\)'),
            # Числовые выражения: 2*x + 3
            re.compile(r'\d+\s*[*×·]\s*[a-zA-Z]'),
            # Суммы, интегралы (если OCR распознал символы)
            re.compile(r'[ΣΠ∫∑∏]\s*'),
            # LaTeX-подобные конструкции (если пользователь пишет LaTeX)
            re.compile(r'\\(frac|sqrt|sum|int|prod|lim|log|sin|cos|tan|alpha|beta|gamma|delta)\b'),
        ]

    def _load_latex_ocr(self):
        """Пытаемся загрузить pix2tex для распознавания формул из изображений"""
        try:
            from pix2tex.cli import LatexOCR
            self._latex_ocr = LatexOCR()
            logger.info("pix2tex (LaTeX-OCR) загружен успешно")
        except ImportError:
            logger.warning("pix2tex не установлен. Распознавание формул — только через эвристики")
        except Exception as e:
            logger.warning(f"Не удалось загрузить pix2tex: {e}. Используем эвристики")

    @property
    def has_latex_ocr(self) -> bool:
        """Доступен ли LaTeX-OCR"""
        return self._latex_ocr is not None

    def is_formula(self, text: str) -> bool:
        """
        Определяет, является ли текст математической формулой.

        Args:
            text: текст для проверки

        Returns:
            True если текст похож на формулу
        """
        text = text.strip()

        if not text:
            return False

        # Если текст слишком длинный — скорее всего обычный текст
        if len(text) > 100:
            return False

        # Подсчитываем "математические" символы
        math_chars = set("+-*/=^_√∫∑∏≤≥≠±×÷∞∂∇()[]{}|<>")
        math_count = sum(1 for c in text if c in math_chars)

        # Подсчитываем буквенные символы
        alpha_count = sum(1 for c in text if c.isalpha())

        # Если много мат.символов относительно длины текста
        total = len(text.replace(" ", ""))
        if total > 0 and math_count / total > 0.3:
            return True

        # Проверяем паттерны
        for pattern in self._formula_patterns:
            if pattern.search(text):
                return True

        # Если однобуквенные переменные через операторы
        if re.match(r'^[a-zA-Z]\s*[=<>≤≥]\s*.+$', text):
            return True

        return False

    def extract_formulas(self, text: str) -> list[dict]:
        """
        Извлекает формулы из текста.

        Args:
            text: полный текст

        Returns:
            список словарей: {start, end, formula, latex}
            start/end — позиции в тексте
        """
        formulas = []

        # Разбиваем на строки и проверяем каждую
        lines = text.split("\n")
        pos = 0

        for line in lines:
            if self.is_formula(line.strip()):
                latex = self._text_to_latex(line.strip())
                formulas.append({
                    "start": pos,
                    "end": pos + len(line),
                    "formula": line.strip(),
                    "latex": latex
                })
            pos += len(line) + 1  # +1 для \n

        return formulas

    def _text_to_latex(self, text: str) -> str:
        """
        Пытается преобразовать распознанный текст в LaTeX.
        Упрощённый подход через замены.

        Args:
            text: распознанный текст формулы

        Returns:
            LaTeX строка
        """
        latex = text.strip()

        # Замены символов на LaTeX
        replacements = [
            # Греческие буквы (если OCR распознал Unicode)
            ("α", r"\alpha"),
            ("β", r"\beta"),
            ("γ", r"\gamma"),
            ("δ", r"\delta"),
            ("ε", r"\epsilon"),
            ("θ", r"\theta"),
            ("λ", r"\lambda"),
            ("μ", r"\mu"),
            ("π", r"\pi"),
            ("σ", r"\sigma"),
            ("φ", r"\phi"),
            ("ω", r"\omega"),
            ("Σ", r"\sum"),
            ("∑", r"\sum"),
            ("Π", r"\prod"),
            ("∏", r"\prod"),
            ("∫", r"\int"),
            ("∞", r"\infty"),
            ("∂", r"\partial"),
            ("√", r"\sqrt"),
            ("≤", r"\leq"),
            ("≥", r"\geq"),
            ("≠", r"\neq"),
            ("±", r"\pm"),
            ("×", r"\times"),
            ("÷", r"\div"),
            ("·", r"\cdot"),
            ("→", r"\rightarrow"),
            ("←", r"\leftarrow"),
            ("∈", r"\in"),
            ("∉", r"\notin"),
            ("⊂", r"\subset"),
            ("⊃", r"\supset"),
            ("∪", r"\cup"),
            ("∩", r"\cap"),
        ]

        for old, new in replacements:
            latex = latex.replace(old, new)

        # Обработка степеней: x2 → x^{2}
        latex = re.sub(r'([a-zA-Z])\s*(\d+)\s*$', r'\1^{\2}', latex)

        # Обработка дробей: a/b → \frac{a}{b}
        latex = re.sub(
            r'([a-zA-Z0-9]+)\s*/\s*([a-zA-Z0-9]+)',
            r'\\frac{\1}{\2}',
            latex
        )

        return latex

    def recognize_from_image(self, image) -> Optional[str]:
        """
        Распознаёт формулу из изображения с помощью pix2tex.

        Args:
            image: PIL Image или numpy array

        Returns:
            LaTeX строка или None
        """
        if self._latex_ocr is None:
            logger.debug("pix2tex недоступен, пропускаем распознавание формулы из изображения")
            return None

        try:
            from PIL import Image
            import numpy as np

            # Конвертируем numpy в PIL если нужно
            if isinstance(image, np.ndarray):
                image = Image.fromarray(image)

            latex = self._latex_ocr(image)
            logger.debug(f"pix2tex распознал: {latex}")
            return latex

        except Exception as e:
            logger.warning(f"Ошибка pix2tex: {e}")
            return None