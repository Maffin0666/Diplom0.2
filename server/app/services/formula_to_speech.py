import re


class FormulaToSpeech:
    """Детерминированный конвертер формул, встроенных математических выражений и индексов в русскую речь."""

    LATIN_TO_RU = {
        "x": "икс", "х": "икс",
        "y": "игрек", "у": "игрек",
        "z": "зет",
        "a": "а", "b": "бэ", "c": "цэ", "d": "дэ", "e": "е",
        "f": "эф", "k": "ка", "m": "эм", "n": "эн", "p": "пэ",
        "t": "тэ", "r": "эр", "s": "эс", "i": "и", "j": "жи",
        "u": "у", "v": "вэ", "w": "дубль-вэ"
    }

    INDEX_ORDINAL = {
        "0": "нулевое", "1": "первое", "2": "второе", "3": "третье",
        "4": "четвертое", "5": "пятое", "6": "шестое", "7": "седьмое",
        "8": "восьмое", "9": "девятое", "i": "и-тое", "n": "эн-ное", "k": "ка-тое"
    }

    NUMBERS_DICT = {
        "0": "ноль", "1": "один", "2": "два", "3": "три", "4": "четыре",
        "5": "пять", "6": "шесть", "7": "семь", "8": "восемь", "9": "девять", "10": "десять"
    }

    @classmethod
    def convert(cls, text: str) -> str:
        if not text:
            return ""

        res = text.replace("\ufffd", "").strip()

        # 1. Пределы (обрабатываем ДО дробей, чтобы исключить коллизии с lim)
        res = re.sub(r"(?i)\blim\s*_?\{?([a-zA-Zа-яА-Я0-9\-\>\s]+)\}?", r" предел при \1 ", res)
        res = re.sub(r"(?i)\blim\b", " предел ", res)
        res = re.sub(r"\bйт\b", " предел ", res)
        res = res.replace("->", " стремящемся к ")

        # 2. Дроби вида alb, a|b, a/b -> дробь a на b
        def _replace_slash(m):
            v1 = cls.LATIN_TO_RU.get(m.group(1).lower(), m.group(1))
            v2 = cls.LATIN_TO_RU.get(m.group(2).lower(), m.group(2))
            return f" дробь {v1} на {v2} "

        res = re.sub(r"\b([a-zA-Z0-9])[/\|]([a-zA-Z0-9])\b", _replace_slash, res)
        res = re.sub(r"\b([a-zA-Z0-9])l([a-zA-Z0-9])\b", _replace_slash, res)

        # 3. Интегралы и $
        res = re.sub(r"\$\s*=", " интеграл равен ", res)
        res = res.replace("$", " ")

        # 4. Корни: sqrt(x), \sqrt{x}, √x
        res = re.sub(r"(?i)\\sqrt\{([^}]+)\}", r" корень из \1 ", res)
        res = re.sub(r"(?i)\bsqrt\s*\(\s*([^)]+?)\s*\)", r" корень из \1 ", res)
        res = re.sub(r"√\s*\(?([^\)\+\-\=\s]+|\([^\)]+\))\)?", r" корень из \1 ", res)

        # 5. Функции f(x)
        def _fmt_f(m):
            prefix = m.group(1) or ""
            arg = m.group(2)
            arg_sp = cls.convert(arg)
            return f"{prefix} эф от {arg_sp} "

        res = re.sub(r"(?i)(\bфункция\s+)?[fFГг]\(([^\)]+)\)", _fmt_f, res)

        # 6. Индексы: x0, y0, х0, у1, x_0, y_1
        def _fmt_index(m):
            letter = m.group(1).lower()
            idx = m.group(2).lower()
            name = cls.LATIN_TO_RU.get(letter, letter)
            idx_name = cls.INDEX_ORDINAL.get(idx, f"с индексом {idx}")
            return f" {name} {idx_name} "

        res = re.sub(r"(?i)\b([a-zA-ZхуХУ])_?([0-9]|i|n|k)\b", _fmt_index, res)

        # 7. Степени: x^2, x^3
        res = re.sub(
            r"(?i)\b([a-zA-ZхуХУ])\^2\b",
            lambda m: f" {cls.LATIN_TO_RU.get(m.group(1).lower(), m.group(1))} в квадрате ",
            res
        )
        res = re.sub(
            r"(?i)\b([a-zA-ZхуХУ])\^3\b",
            lambda m: f" {cls.LATIN_TO_RU.get(m.group(1).lower(), m.group(1))} в кубе ",
            res
        )
        res = re.sub(
            r"(?i)\b([a-zA-ZхуХУ])\^([0-9a-zA-Z]+)\b",
            lambda m: f" {cls.LATIN_TO_RU.get(m.group(1).lower(), m.group(1))} в степени {m.group(2)} ",
            res
        )

        # 8. Коэффициенты перед переменными: Зх -> 3 икс, 2x -> 2 икс
        res = re.sub(r"\b[Зз]\s*([a-zA-ZхуХУ])\b", lambda m: f" 3 {cls.LATIN_TO_RU.get(m.group(1).lower(), m.group(1))} ", res)
        res = re.sub(r"(\d+)\s*([a-zA-ZхуХУ])\b", lambda m: f" {m.group(1)} {cls.LATIN_TO_RU.get(m.group(2).lower(), m.group(2))} ", res)

        # 9. Двоеточие: только между цифрами заменять на 'делить на'
        res = re.sub(r"(\d+)\s*:\s*(\d+)", r"\1 делить на \2", res)
        res = re.sub(r"([а-яА-Яa-zA-Z]+)\s*:", r"\1:", res)

        # 10. Математические знаки
        res = res.replace("<=", " меньше либо равно ")
        res = res.replace(">=", " больше либо равно ")
        res = res.replace("!=", " не равно ")
        res = res.replace("=", " равно ")
        res = res.replace("+", " плюс ")
        res = res.replace("*", " умножить на ")
        res = res.replace("·", " умножить на ")

        # Знак минус: НЕ трогать дефисы между кириллическими буквами (что-то, что-таким, из-за)
        # Заменять только между цифрами или переменными
        res = re.sub(r"(?<=[\d\w\)])\s+-\s+(?=[\d\w\(])", " минус ", res)
        res = re.sub(r"(\d+)\s*-\s*(\d+)", r"\1 минус \2", res)
        res = re.sub(r"\b([a-zA-Zху])\s*-\s*([a-zA-Zху\d])\b", r"\1 минус \2", res)

        # 11. Одиночные переменные
        res = re.sub(r"\b([a-zA-Z])\b", lambda m: f" {cls.LATIN_TO_RU.get(m.group(1).lower(), m.group(1))} ", res)
        res = re.sub(r"(?i)\b[хХ]\b", " икс ", res)
        res = re.sub(r"(?i)\b[уУ]\s+равно\b", " игрек равно ", res)
        res = re.sub(r"(?i)\bравно\s+[уУ]\b", " равно игрек ", res)

        # 12. Преобразование цифр в слова для Silero
        res = re.sub(r"\b([0-9]|10)\b", lambda m: f" {cls.NUMBERS_DICT.get(m.group(0), m.group(0))} ", res)

        # Очистка
        res = re.sub(r"[{}\[\]\\_^~|@]", " ", res)
        res = re.sub(r"\s+", " ", res).strip()

        return res