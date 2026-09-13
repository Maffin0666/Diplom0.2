"""
Преобразование математических формул (LaTeX и текстовых) в русскую речь.

Модуль содержит обширный словарь замен и правила для
преобразования LaTeX-нотации в текст, пригодный для синтеза речи.
"""

import re

from server.app.utils.logger import logger


class FormulaToSpeech:
    """
    Конвертер формул в текст для озвучки.

    Поддерживает:
    - Степени: x^2 → «икс квадрат», x^3 → «икс куб», x^n → «икс в степени эн»
    - Дроби: \\frac{a}{b} → «дробь а на бэ»
    - Корни: \\sqrt{x} → «корень из икс», \\sqrt[3]{x} → «кубический корень из икс»
    - Суммы: \\sum_{i=1}^{n} → «сумма от и равно один до эн»
    - Интегралы: \\int_{a}^{b} → «интеграл от а до бэ»
    - Логарифмы, тригонометрию, пределы
    - Греческие буквы
    - Индексы, операторы, скобки
    """

    def __init__(self):
        """Инициализация словарей замен"""

        # Названия букв латинского алфавита на русском
        self._latin_letters = {
            'a': 'а', 'b': 'бэ', 'c': 'цэ', 'd': 'дэ', 'e': 'е',
            'f': 'эф', 'g': 'жэ', 'h': 'аш', 'i': 'и', 'j': 'жи',
            'k': 'ка', 'l': 'эль', 'm': 'эм', 'n': 'эн', 'o': 'о',
            'p': 'пэ', 'q': 'ку', 'r': 'эр', 's': 'эс', 't': 'тэ',
            'u': 'у', 'v': 'вэ', 'w': 'дубль-вэ', 'x': 'икс', 'y': 'игрек',
            'z': 'зэт',
            'G': 'жэ', 'H': 'аш', 'I': 'и', 'J': 'йот',
            'K': 'ка', 'L': 'эль', 'O': 'о',
            'P': 'пэ', 'Q': 'ку',
            'U': 'у', 'V': 'вэ', 'W': 'дубль-вэ', 'Y': 'игрек',
            'Z': 'зэт',
            'A': 'большое а', 'B': 'большое бэ', 'C': 'большое цэ',
            'D': 'большое дэ', 'E': 'большое е', 'F': 'большое эф',
            'N': 'большое эн', 'M': 'большое эм', 'R': 'большое эр',
            'S': 'большое эс', 'T': 'большое тэ', 'X': 'большое икс',

        }

        # Греческие буквы
        self._greek_letters = {
            r'\alpha': 'альфа', r'\beta': 'бета', r'\gamma': 'гамма',
            r'\delta': 'дельта', r'\epsilon': 'эпсилон', r'\varepsilon': 'эпсилон',
            r'\zeta': 'дзета', r'\eta': 'эта', r'\theta': 'тета',
            r'\iota': 'йота', r'\kappa': 'каппа', r'\lambda': 'лямбда',
            r'\mu': 'мю', r'\nu': 'ню', r'\xi': 'кси',
            r'\pi': 'пи', r'\rho': 'ро', r'\sigma': 'сигма',
            r'\tau': 'тау', r'\upsilon': 'ипсилон', r'\phi': 'фи',
            r'\varphi': 'фи', r'\chi': 'хи', r'\psi': 'пси',
            r'\omega': 'омега',
            r'\Gamma': 'большая гамма', r'\Delta': 'большая дельта',
            r'\Theta': 'большая тета', r'\Lambda': 'большая лямбда',
            r'\Sigma': 'большая сигма', r'\Phi': 'большая фи',
            r'\Psi': 'большая пси', r'\Omega': 'большая омега',
        }

        # Операторы и символы
        self._operators = {
            '+': 'плюс', '-': 'минус', '=': 'равно',
            r'\neq': 'не равно', r'\approx': 'приближённо равно',
            r'\equiv': 'тождественно равно',
            r'\leq': 'меньше или равно', r'\geq': 'больше или равно',
            '<': 'меньше', '>': 'больше',
            r'\pm': 'плюс-минус', r'\mp': 'минус-плюс',
            r'\times': 'умножить на', r'\cdot': 'умножить на',
            r'\div': 'разделить на',
            r'\infty': 'бесконечность',
            r'\partial': 'частная производная',
            r'\nabla': 'набла',
            r'\forall': 'для всех', r'\exists': 'существует',
            r'\in': 'принадлежит', r'\notin': 'не принадлежит',
            r'\subset': 'подмножество', r'\supset': 'надмножество',
            r'\cup': 'объединение', r'\cap': 'пересечение',
            r'\emptyset': 'пустое множество',
            r'\rightarrow': 'стрелка вправо',
            r'\leftarrow': 'стрелка влево',
            r'\Rightarrow': 'следует',
            r'\Leftrightarrow': 'тогда и только тогда',
            r'\ldots': 'многоточие', r'\dots': 'многоточие',
            r'\to': 'стремится к',
        }

        # Функции
        self._functions = {
            r'\sin': 'синус', r'\cos': 'косинус', r'\tan': 'тангенс',
            r'\cot': 'котангенс', r'\sec': 'секанс', r'\csc': 'косеканс',
            r'\arcsin': 'арксинус', r'\arccos': 'арккосинус', r'\arctan': 'арктангенс',
            r'\sinh': 'гиперболический синус', r'\cosh': 'гиперболический косинус',
            r'\ln': 'натуральный логарифм', r'\lg': 'десятичный логарифм',
            r'\exp': 'экспонента', r'\det': 'определитель',
            r'\dim': 'размерность', r'\ker': 'ядро',
            r'\max': 'максимум', r'\min': 'минимум',
            r'\sup': 'супремум', r'\inf': 'инфимум',
        }

        logger.info("FormulaToSpeech инициализирован")

    def convert(self, formula: str) -> str:
        """
        Основной метод: конвертирует формулу в текст для озвучки.
        ВАЖЕН ПОРЯДОК ОБРАБОТКИ!
        """
        if not formula or not formula.strip():
            return ""

        text = formula.strip()
        text = re.sub(r'^\$+|\$+$', '', text).strip()

        logger.debug(f"Конвертация формулы (исходник): '{text}'")

        # 1. Нормализация артефактов OCR (аккуратная)
        text = self._normalize_ocr_artifacts(text)
        logger.debug(f"  после normalize: '{text}'")

        # 2. Сложные конструкции (вложенные) — ДО обработки букв
        text = self._process_fractions(text)
        text = self._process_sqrt(text)
        text = self._process_sum_prod(text)
        text = self._process_integrals(text)
        text = self._process_limits(text)
        text = self._process_logarithms(text)
        logger.debug(f"  после сложных: '{text}'")

        # 3. Степени и индексы — ПЕРЕД обработкой букв, чтобы паттерны сработали
        text = self._process_powers(text)
        text = self._process_subscripts(text)
        logger.debug(f"  после степеней: '{text}'")

        # 4. Функции (sin, cos, log и т.д.)
        text = self._process_functions(text)

        # 5. Скобки (функциональные и группирующие)
        text = self._process_brackets(text)
        logger.debug(f"  после скобок: '{text}'")

        # 6. Греческие буквы
        text = self._process_greek(text)

        # 7. Числа — заменяем на слова ДО букв
        text = self._process_numbers(text)

        # 8. Операторы (+, -, =, и т.д.)
        text = self._process_operators(text)

        # 9. Одиночные латинские буквы — В САМОМ КОНЦЕ
        text = self._process_letters(text)

        # 10. Финальная очистка
        text = self._cleanup(text)

        logger.debug(f"Результат: '{text}'")
        return text

    def _process_fractions(self, text: str) -> str:
        """Обработка дробей: \\frac{a}{b} → дробь а на бэ"""
        # Рекурсивная обработка вложенных дробей
        max_iterations = 10
        for _ in range(max_iterations):
            # Паттерн для \frac{...}{...} с вложенными скобками
            match = re.search(r'\\frac\s*\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}\s*\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}', text)
            if not match:
                break

            numerator = match.group(1).strip()
            denominator = match.group(2).strip()

            # Рекурсивно обрабатываем числитель и знаменатель
            num_speech = self.convert(numerator) if self._has_latex(numerator) else self._letter_or_word(numerator)
            den_speech = self.convert(denominator) if self._has_latex(denominator) else self._letter_or_word(denominator)

            replacement = f"дробь {num_speech} на {den_speech}"
            text = text[:match.start()] + replacement + text[match.end():]

        # Простые дроби через /: a/b
        text = re.sub(
            r'(\w)\s*/\s*(\w)',
            lambda m: f"{self._letter_or_word(m.group(1))} делить на {self._letter_or_word(m.group(2))}",
            text
        )

        return text

    def _process_sqrt(self, text: str) -> str:
        """Обработка корней: \\sqrt{x} → корень из икс"""
        # Корень n-й степени: \sqrt[n]{x}
        text = re.sub(
            r'\\sqrt\s*\[(\w+)\]\s*\{([^{}]+)\}',
            lambda m: f"корень {self._ordinal(m.group(1))} степени из {self._letter_or_word(m.group(2))}",
            text
        )

        # Квадратный корень: \sqrt{x}
        text = re.sub(
            r'\\sqrt\s*\{([^{}]+)\}',
            lambda m: f"корень из {self._letter_or_word(m.group(1))}",
            text
        )

        # Символ √
        text = re.sub(
            r'√\s*[\(\[{]?\s*(\w+)\s*[\)\]}]?',
            lambda m: f"корень из {self._letter_or_word(m.group(1))}",
            text
        )

        return text


    def _process_powers(self, text: str) -> str:
        """Обработка степеней с человеческим чтением"""
        def power_replace(match):
            base = match.group(1)
            exponent = match.group(2).strip('{}').strip()
            base_speech = self._letter_or_word(base)

            # Специальные случаи
            if exponent == '2':
                return f"{base_speech} в квадрате"
            elif exponent == '3':
                return f"{base_speech} в кубе"
            elif exponent == '-1':
                return f"{base_speech} в минус первой степени"
            elif exponent == 'n':
                return f"{base_speech} в степени эн"
            elif exponent.isdigit():
                num_word = self._number_to_words(exponent)
                return f"{base_speech} в {num_word} степени"
            else:
                exp_speech = self.convert(exponent) if self._has_latex(exponent) else self._letter_or_word(exponent)
                return f"{base_speech} в степени {exp_speech}"

        # Степень в фигурных скобках: x^{...}
        text = re.sub(r'(\w)\s*\^\s*\{([^{}]+)\}', power_replace, text)
        # Простая степень: x^2, x^n
        text = re.sub(r'(\w)\s*\^\s*(-?\w+)', power_replace, text)

        return text

    def _process_subscripts(self, text: str) -> str:
        """Обработка индексов: x_1 → икс индекс один"""
        # Индекс в фигурных скобках: x_{ij}
        text = re.sub(
            r'(\w)\s*_\s*\{([^{}]+)\}',
            lambda m: f"{self._letter_or_word(m.group(1))} индекс {self._letter_or_word(m.group(2))}",
            text
        )

        # Простой индекс: x_1
        text = re.sub(
            r'(\w)\s*_\s*(\w)',
            lambda m: f"{self._letter_or_word(m.group(1))} индекс {self._letter_or_word(m.group(2))}",
            text
        )

        return text

    def _process_sum_prod(self, text: str) -> str:
        """Обработка сумм и произведений"""
        # \sum_{i=1}^{n} или \sum_{i=1}^n
        text = re.sub(
            r'\\sum\s*_\s*\{([^{}]+)\}\s*\^\s*\{([^{}]+)\}',
            lambda m: f"сумма от {self._letter_or_word(m.group(1))} до {self._letter_or_word(m.group(2))}",
            text
        )
        text = re.sub(
            r'\\sum\s*_\s*\{([^{}]+)\}\s*\^\s*(\w)',
            lambda m: f"сумма от {self._letter_or_word(m.group(1))} до {self._letter_or_word(m.group(2))}",
            text
        )
        text = re.sub(r'\\sum', 'сумма', text)

        # \prod
        text = re.sub(
            r'\\prod\s*_\s*\{([^{}]+)\}\s*\^\s*\{([^{}]+)\}',
            lambda m: f"произведение от {self._letter_or_word(m.group(1))} до {self._letter_or_word(m.group(2))}",
            text
        )
        text = re.sub(r'\\prod', 'произведение', text)

        return text

    def _process_integrals(self, text: str) -> str:
        """Обработка интегралов"""
        # Определённый интеграл: \int_{a}^{b}
        text = re.sub(
            r'\\int\s*_\s*\{([^{}]+)\}\s*\^\s*\{([^{}]+)\}',
            lambda m: f"интеграл от {self._letter_or_word(m.group(1))} до {self._letter_or_word(m.group(2))}",
            text
        )

        # Неопределённый интеграл
        text = re.sub(r'\\int', 'интеграл', text)

        # Двойной, тройной интеграл
        text = re.sub(r'\\iint', 'двойной интеграл', text)
        text = re.sub(r'\\iiint', 'тройной интеграл', text)
        text = re.sub(r'\\oint', 'контурный интеграл', text)

        return text

    def _process_limits(self, text: str) -> str:
        """Обработка пределов"""
        # \lim_{x \to a}
        text = re.sub(
            r'\\lim\s*_\s*\{([^{}]+)\\to\s*([^{}]+)\}',
            lambda m: f"предел при {self._letter_or_word(m.group(1).strip())} стремящемся к {self._letter_or_word(m.group(2).strip())}",
            text
        )
        text = re.sub(
            r'\\lim\s*_\s*\{([^{}]+)\s*→\s*([^{}]+)\}',
            lambda m: f"предел при {self._letter_or_word(m.group(1).strip())} стремящемся к {self._letter_or_word(m.group(2).strip())}",
            text
        )
        text = re.sub(r'\\lim', 'предел', text)

        return text

    def _process_logarithms(self, text: str) -> str:
        """Обработка логарифмов"""
        # \log_{base}(arg)
        text = re.sub(
            r'\\log\s*_\s*\{([^{}]+)\}\s*[\(\{]([^(){}]+)[\)\}]',
            lambda m: f"логарифм по основанию {self._letter_or_word(m.group(1))} от {self._letter_or_word(m.group(2))}",
            text
        )
        text = re.sub(
            r'\\log\s*_\s*(\w)\s*[\(\{]([^(){}]+)[\)\}]',
            lambda m: f"логарифм по основанию {self._letter_or_word(m.group(1))} от {self._letter_or_word(m.group(2))}",
            text
        )
        text = re.sub(r'\\log', 'логарифм', text)

        return text

    def _process_functions(self, text: str) -> str:
        """Обработка математических функций"""
        for latex_cmd, speech in self._functions.items():
            # Функция с аргументом: \sin(x) или \sin{x}
            pattern = re.escape(latex_cmd) + r'\s*[\(\{]([^(){}]+)[\)\}]'
            text = re.sub(
                pattern,
                lambda m, s=speech: f"{s} {self._letter_or_word(m.group(1))}",
                text
            )
            # Функция без явного аргумента
            text = text.replace(latex_cmd, speech)

        return text

    def _process_greek(self, text: str) -> str:
        """Замена греческих букв на русские названия"""
        # Сначала длинные команды (чтобы \varepsilon не перехватил \epsilon)
        sorted_greek = sorted(self._greek_letters.items(), key=lambda x: -len(x[0]))
        for latex_cmd, speech in sorted_greek:
            text = text.replace(latex_cmd, f" {speech} ")
        return text

    def _process_operators(self, text: str) -> str:
        """
        Замена операторов на слова.
        Использует регулярки с границами, чтобы не ломать другие символы.
        """
        # LaTeX-команды операторов (обрабатываем первыми)
        latex_ops = {
            r'\neq': 'не равно',
            r'\approx': 'приближённо равно',
            r'\equiv': 'тождественно равно',
            r'\leq': 'меньше или равно',
            r'\geq': 'больше или равно',
            r'\pm': 'плюс-минус',
            r'\mp': 'минус-плюс',
            r'\times': 'умножить на',
            r'\cdot': 'умножить на',
            r'\div': 'разделить на',
            r'\infty': 'бесконечность',
            r'\partial': 'частная производная',
            r'\nabla': 'набла',
            r'\forall': 'для всех',
            r'\exists': 'существует',
            r'\in': 'принадлежит',
            r'\notin': 'не принадлежит',
            r'\subset': 'подмножество',
            r'\supset': 'надмножество',
            r'\cup': 'объединение',
            r'\cap': 'пересечение',
            r'\emptyset': 'пустое множество',
            r'\rightarrow': 'стремится к',
            r'\leftarrow': 'следует из',
            r'\Rightarrow': 'следует',
            r'\Leftrightarrow': 'тогда и только тогда',
            r'\to': 'стремится к',
        }
        # Сортируем по убыванию длины, чтобы \leq не был перехвачен \l
        sorted_ops = sorted(latex_ops.items(), key=lambda x: -len(x[0]))
        for latex_cmd, speech in sorted_ops:
            text = text.replace(latex_cmd, f' {speech} ')

        # Одиночные символы-операторы (с пробелами вокруг для безопасности)
        symbol_ops = [
            ('+', ' плюс '),
            ('=', ' равно '),
            ('<', ' меньше '),
            ('>', ' больше '),
            ('≤', ' меньше или равно '),
            ('≥', ' больше или равно '),
            ('≠', ' не равно '),
            ('±', ' плюс-минус '),
            ('×', ' умножить на '),
            ('·', ' умножить на '),
            ('*', ' умножить на '),
            ('÷', ' разделить на '),
            ('∞', ' бесконечность '),
        ]
        for symbol, speech in symbol_ops:
            text = text.replace(symbol, speech)

        # Минус — особый случай! Не путать с дефисом внутри слов
        # Заменяем только если минус окружён пробелами или стоит между числами/буквами
        text = re.sub(r'\s-\s', ' минус ', text)
        text = re.sub(r'(\w)-(\w)', r'\1 минус \2', text)

        return text

    def _process_brackets(self, text: str) -> str:
        """
        Умная обработка скобок.
        - f(x) → "эф от икс"  (функция с аргументом)
        - (a + b) → пауза + содержимое + пауза  (группирующие скобки)
        - [a, b] → "от а до бэ"
        """
        # 1. LaTeX-скобки \left( \right) — просто убираем разметку
        text = re.sub(r'\\left\s*', '', text)
        text = re.sub(r'\\right\s*', '', text)

        # 2. Функциональные скобки: буква(аргумент) → "буква от аргумента"
        #    Работает для одиночной латинской буквы или греческой команды
        def func_replace(match):
            func_name = match.group(1).strip()
            arg = match.group(2).strip()

            func_speech = self._letter_or_word(func_name)
            arg_speech = self._letter_or_word(arg) if not self._has_latex(arg) else self.convert(arg)

            return f"{func_speech} от {arg_speech}"

        # Паттерн: одна буква + ( ... ) без вложенных скобок
        text = re.sub(
            r'\b([a-zA-Zа-яА-Я])\s*\(([^()]+)\)',
            func_replace,
            text
        )

        # 3. Интервалы: [a, b] → "от а до бэ"
        text = re.sub(
            r'\[\s*([^,\[\]]+)\s*,\s*([^,\[\]]+)\s*\]',
            lambda m: f"от {self._letter_or_word(m.group(1).strip())} до {self._letter_or_word(m.group(2).strip())}",
            text
        )

        # 4. Оставшиеся группирующие круглые скобки — заменяем на паузы (запятые)
        text = re.sub(r'\(\s*', ', ', text)
        text = re.sub(r'\s*\)', ', ', text)

        # 5. Квадратные и фигурные скобки — просто убираем
        text = text.replace('[', ' ').replace(']', ' ')
        text = text.replace('{', ' ').replace('}', ' ')

        return text

    def _process_numbers(self, text: str) -> str:
        """Заменяет отдельные числа на слова"""
        def num_replace(match):
            num = match.group(0)
            # Дробные числа не трогаем
            return self._number_to_words(num)

        # Только целые числа, окружённые не-цифрами
        text = re.sub(r'(?<!\d)\d+(?!\d)(?!\.\d)', num_replace, text)
        return text

    def _process_letters(self, text: str) -> str:
        """
        Замена ВСЕХ одиночных латинских букв на их произношение по-русски.
        Работает агрессивно: если буква не окружена другими латинскими буквами
        (т.е. не часть английского слова) — заменяем.
        """
        def replace_letter(match):
            letter = match.group(0)
            return self._latin_letters.get(letter, letter)

        # Ищем одиночную латинскую букву:
        # - слева: начало строки ИЛИ не-латинский символ
        # - справа: не-латинский символ ИЛИ конец строки
        # (?<=...) — lookbehind, (?=...) — lookahead. Они НЕ захватывают символы.
        text = re.sub(
            r'(?<![a-zA-Z])[a-zA-Z](?![a-zA-Z])',
            replace_letter,
            text
        )

        return text

    def _letter_or_word(self, text: str) -> str:
        """
        Конвертирует одну букву в её название, или возвращает слово/число как есть.
        """
        text = text.strip()

        if not text:
            return ""

        # Число
        if text.isdigit():
            return self._number_to_words(text)

        # Одна латинская буква
        if len(text) == 1 and text.isalpha() and text.isascii():
            return self._latin_letters.get(text, text)

        # Несколько символов — обрабатываем по частям
        # Если это простое выражение типа "i=1"
        match = re.match(r'^(\w)\s*=\s*(\w+)$', text)
        if match:
            left = self._letter_or_word(match.group(1))
            right = self._letter_or_word(match.group(2))
            return f"{left} равно {right}"

        # Если содержит LaTeX — рекурсивно обрабатываем
        if self._has_latex(text):
            return self.convert(text)

        return text

    def _number_to_words(self, num_str: str) -> str:
        """Преобразование числа в текст на русском"""
        try:
            from num2words import num2words
            num = int(num_str)
            return num2words(num, lang='ru')
        except (ValueError, ImportError):
            return num_str

    def _ordinal(self, text: str) -> str:
        """Порядковое числительное"""
        ordinals = {
            '2': 'второй', '3': 'третьей', '4': 'четвёртой',
            '5': 'пятой', '6': 'шестой', 'n': 'эн-ной',
        }
        return ordinals.get(text.strip(), text)

    def _has_latex(self, text: str) -> bool:
        """Проверяет, содержит ли текст LaTeX команды"""
        return bool(re.search(r'\\[a-zA-Z]+|[\^_]|\{.*\}', text))

    def _normalize_ocr_artifacts(self, text: str) -> str:
        """
        Исправляет типичные ошибки OCR в формулах.
        Работает аккуратно — не ломает нормальные записи.
        """
        # Заменяем типичные ошибки распознавания функций
        # Только если это отдельное слово (со словесной границей)
        function_replacements = {
            r'\bsqrt\b': r'\\sqrt',
            r'\bsum\b': r'\\sum',
            r'\bint\b': r'\\int',
            r'\blim\b': r'\\lim',
            r'\bsin\b': r'\\sin',
            r'\bcos\b': r'\\cos',
            r'\btan\b': r'\\tan',
            r'\btg\b': r'\\tan',
            r'\bctg\b': r'\\cot',
            r'\blog\b': r'\\log',
            r'\bln\b': r'\\ln',
        }
        for pattern, repl in function_replacements.items():
            text = re.sub(pattern, repl, text)

        # НЕ трогаем x2 → x^2 автоматически, потому что это ломает индексы
        # Пользователь должен писать x^2 явно, либо OCR распознает символ ^

        return text

    def _cleanup(self, text: str) -> str:
        """Финальная очистка текста"""
        # Убираем оставшиеся LaTeX команды
        text = re.sub(r'\\[a-zA-Z]+', '', text)

        # Убираем двойные пробелы
        text = re.sub(r'\s+', ' ', text)

        # Убираем пробелы перед запятыми и точками
        text = re.sub(r'\s+([,.])', r'\1', text)

        # Убираем обрамляющие пробелы
        text = text.strip()

        return text