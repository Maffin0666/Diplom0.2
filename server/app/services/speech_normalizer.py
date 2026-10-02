"""Подготовка обычного текста к русскому TTS без потери цифр и латиницы."""

import re


ONES = ("ноль", "один", "два", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять")
TEENS = ("десять", "одиннадцать", "двенадцать", "тринадцать", "четырнадцать", "пятнадцать", "шестнадцать", "семнадцать", "восемнадцать", "девятнадцать")
TENS = ("", "", "двадцать", "тридцать", "сорок", "пятьдесят", "шестьдесят", "семьдесят", "восемьдесят", "девяносто")
HUNDREDS = ("", "сто", "двести", "триста", "четыреста", "пятьсот", "шестьсот", "семьсот", "восемьсот", "девятьсот")
LATIN_NAMES = {"a": "эй", "b": "би", "c": "си", "d": "ди", "e": "и", "f": "эф", "g": "джи", "h": "эйч", "i": "ай", "j": "джей", "k": "кей", "l": "эл", "m": "эм", "n": "эн", "o": "оу", "p": "пи", "q": "кью", "r": "ар", "s": "эс", "t": "ти", "u": "ю", "v": "ви", "w": "дабл ю", "x": "икс", "y": "игрек", "z": "зет"}
KNOWN_WORDS = {"python": "пайтон", "api": "эй пи ай", "cpu": "си пи ю", "gpu": "джи пи ю", "ocr": "оу си ар", "wi-fi": "вай фай"}


def _under_thousand(value: int, feminine: bool = False) -> str:
    parts = []
    if value >= 100:
        parts.append(HUNDREDS[value // 100])
        value %= 100
    if value >= 20:
        parts.append(TENS[value // 10])
        value %= 10
    elif value >= 10:
        parts.append(TEENS[value - 10])
        value = 0
    if value:
        parts.append(("одна", "две")[value - 1] if feminine and value in (1, 2) else ONES[value])
    return " ".join(parts)


def number_to_words(value: int) -> str:
    """Читает целые числа до миллиарда; большие числа читает по цифрам."""
    if value < 0:
        return "минус " + number_to_words(-value)
    if value == 0:
        return ONES[0]
    if value >= 1_000_000_000:
        return " ".join(ONES[int(digit)] for digit in str(value))
    parts = []
    millions, remainder = divmod(value, 1_000_000)
    thousands, units = divmod(remainder, 1_000)
    if millions:
        suffix = "миллион" if millions % 10 == 1 and millions % 100 != 11 else "миллиона" if millions % 10 in (2, 3, 4) and millions % 100 not in (12, 13, 14) else "миллионов"
        parts.extend((_under_thousand(millions), suffix))
    if thousands:
        suffix = "тысяча" if thousands % 10 == 1 and thousands % 100 != 11 else "тысячи" if thousands % 10 in (2, 3, 4) and thousands % 100 not in (12, 13, 14) else "тысяч"
        parts.extend((_under_thousand(thousands, feminine=True), suffix))
    if units:
        parts.append(_under_thousand(units))
    return " ".join(parts)


def normalize_prose(text: str) -> str:
    """Сохраняет исходное значение текста в доступном для Silero виде."""
    value = text.replace("\ufffd", " ")
    # Частая математическая вставка внутри определения остаётся связной речью.
    value = re.sub(r"\bf\s*\(\s*([xyху])\s*\)",
                   lambda m: "эф от " + ("икс" if m.group(1).lower() in ("x", "х") else "игрек"),
                   value, flags=re.IGNORECASE)
    value = re.sub(r"(?<!\w)([xyху])_?([0-9])(?!\w)",
                   lambda m: ("икс" if m.group(1).lower() in ("x", "х") else "игрек") +
                   " с индексом " + ONES[int(m.group(2))], value, flags=re.IGNORECASE)

    def replace_latin(match: re.Match[str]) -> str:
        word = match.group(0)
        spoken = KNOWN_WORDS.get(word.lower(), " ".join(LATIN_NAMES[letter.lower()] for letter in word))
        return " " + spoken + " "

    value = re.sub(r"[A-Za-z]+", replace_latin, value)

    def replace_number(match: re.Match[str]) -> str:
        raw = match.group(0)
        if "," in raw or "." in raw:
            whole, fraction = re.split(r"[,.]", raw, maxsplit=1)
            return number_to_words(int(whole)) + " запятая " + " ".join(ONES[int(digit)] for digit in fraction)
        return number_to_words(int(raw))

    value = re.sub(r"(?<![\w])\d+(?:[,.]\d+)?(?![\w])", replace_number, value)
    # Символы, которые Silero не умеет произносить, называем вместо удаления.
    symbols = {"=": "равно", "+": "плюс", "/": "дробь", "%": "процентов",
               "№": "номер", "&": "и", "@": "собака", "×": "умножить на",
               "÷": "делить на", "<": "меньше", ">": "больше", "\\": "обратная косая черта"}
    value = re.sub(r"[=+/%№&@×÷<>\\]", lambda m: " " + symbols[m.group()] + " ", value)
    # Пунктуационный шум OCR сохраняется в исходном text, но не читается голосом.
    value = re.sub(r"[^а-яА-ЯёЁ\s.,!?;:()\-«»\"'—]", " ", value)
    value = re.sub(r"\s+", " ", value).strip()
    return value or "пауза"
