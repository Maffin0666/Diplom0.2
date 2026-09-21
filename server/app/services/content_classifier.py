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

        # Строгие критерии наличия формулы
        has_equation = any(op in t for op in ["=", "≠", "≈", "≤", "≥"])
        has_math_func = bool(re.search(r"\b(lim|sqrt|sin|cos|tg|ctg|log|ln|int|sum)\b", t))
        has_math_struct = bool(re.search(r"[a-zа-я0-9]\^[0-9a-z]", t)) or bool(re.search(r"\b\d+/\d+\b", t))

        # Если в строке 3 и более осмысленных русских слова — это связный текст
        words = re.findall(r"[а-яё]{3,}", t)
        if len(words) >= 3 and not has_equation:
            return False

        return has_equation or has_math_func or has_math_struct