import re


class ContentClassifier:
    """Определяет тип контента, исключая ложную классификацию зашумленного текста."""

    @classmethod
    def is_math_block(cls, text: str, is_merged_candidate: bool = False) -> bool:
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

        # Only known LaTeX commands count; OCR noise often contains a stray \.
        if re.search(r"\\(?:frac|sqrt|sum|int|lim|alpha|beta|pi)\b", t):
            return True
        if any(op in t for op in ("√", "∫", "∑", "∞")):
            return True
        if re.search(r"\b(?:lim|sqrt|sin|cos|tg|ctg|log|ln|int|sum)\b", t) and len(tokens) <= 8:
            return True
        if re.fullmatch(r"\s*f\s*\([^)]*\)\s*", t):
            return True
        if re.fullmatch(r"\s*[a-zху]_?[0-9]\s*", t):
            return True
        # An isolated slash/caret or comparison sign inside a sentence is more
        # likely OCR noise than a mathematical expression.
        words = re.findall(r"[а-яё]{3,}", t)
        equation = re.search(
            r"(?<![a-zа-яё])(?:[a-zа-яё]|\d+(?:[.,]\d+)?|f\([^)]{1,20}\))\s*(?:=|≠|≈|≤|≥)",
            t,
        )
        if equation and len(words) <= 4 and (len(t) <= 65 or len(words) <= 2):
            return True
        if "^" in t and len(words) <= 2 and re.search(r"[a-zа-яё0-9)]\s*\^\s*[-+a-zа-яё0-9({]", t):
            return True
        if re.fullmatch(r"\s*[a-zα-ω0-9()]{1,5}\s*/\s*[a-zα-ω0-9()]{1,5}\s*", t):
            return True
        if re.fullmatch(r"\s*[a-zхуα-ω]\s*[-+*×·]\s*[a-zхуα-ω\d]{1,5}\s*", t):
            return True
        if is_merged_candidate and not words and re.search(r"[=+×÷/∫∑√]", t):
            return True
        return False
