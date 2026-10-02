import re


class ContentClassifier:
    """Определяет тип контента, исключая ложную классификацию зашумленного текста."""

    @classmethod
    def is_math_block(cls, text: str, is_merged_candidate: bool = False) -> bool:
        if is_merged_candidate:
            return True

        if not text or not text.strip():
            return False

        t = text.strip().lower()

        # OCR курсивного текста часто смешивает латиницу и кириллицу внутри
        # одного слова. Несколько таких слов в строке — признак шума,
        # даже если модель случайно вставила ^, / или =.
        tokens = re.findall(r"[a-zа-яё0-9]+", t)
        mixed = sum(bool(re.search(r"[a-z]", token)) and bool(re.search(r"[а-яё]", token))
                    for token in tokens)
        if len(t) > 20 and mixed >= 2:
            return False

        # Структурные маркеры существеннее числа слов в подписи к формуле.
        if re.search(r"\\[a-z]+\b", t):
            return True
        if any(op in t for op in ("=", "≠", "≈", "≤", "≥", "<", ">", "√", "∫", "∑", "∞", "^")):
            return True
        if re.search(r"\b(?:lim|sqrt|sin|cos|tg|ctg|log|ln|int|sum)\b", t):
            return True
        if re.fullmatch(r"\s*f\s*\([^)]*\)\s*", t):
            return True
        if re.fullmatch(r"\s*[a-zху]_?[0-9]\s*", t):
            return True
        # Один слеш внутри длинной строки OCR часто означает шум, а не дробь.
        if re.fullmatch(r"\s*[a-zа-яα-ω\d()+*\s-]+\s*/\s*[a-zа-яα-ω\d()+*\s-]+\s*", t):
            return True
        if re.fullmatch(r"\s*[a-zа-яα-ω]\s*[-+*×·]\s*[a-zа-яα-ω\d]+\s*", t):
            return True
        return False
